import '../core/storage/storage_activity.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import '../core/l10n.dart';
import '../data/models/book/document.dart';
import '../router/app_router.dart';
import '../services/ai_settings_prompt.dart';
import '../core/otter_error_text.dart';
import '../core/rust_backend.dart';
import '../src/rust/api/ocr.dart';
import '../src/rust/error.dart';
import '../src/rust/ocr.dart';
import '../core/rust_ai.dart';
import '../src/rust/ai/summary.dart';
import '../services/snackbar_service.dart';
import '../utils/doc_paths.dart';
import 'agent_api_provider.dart';
import 'doc_extract_api_provider.dart';
import 'task_activity_provider.dart' show taskActivityProvider;
import 'document_lifecycle_provider.dart';
import 'image_generation_config_provider.dart';
import 'task_runner.dart';
import 'translation_config_provider.dart';
import '../core/app_logger.dart';

enum DocumentTaskType { extractDocument, generateSummaryImage, redownloadPdf }

enum DocumentTaskStatus { queued, running, completed, cancelled, failed }

class DocumentTaskKey {
  final DocumentTaskType type;
  final String documentId;

  const DocumentTaskKey({required this.type, required this.documentId});

  @override
  bool operator ==(Object other) {
    return other is DocumentTaskKey &&
        other.type == type &&
        other.documentId == documentId;
  }

  @override
  int get hashCode => Object.hash(type, documentId);
}

class DocumentTaskInfo {
  final DocumentTaskKey key;
  final String title;
  final DocumentTaskStatus status;
  final ListenableProgress progress;
  final CancelToken cancelToken;
  final Object? error;
  final Object? result;

  const DocumentTaskInfo({
    required this.key,
    required this.title,
    required this.status,
    required this.progress,
    required this.cancelToken,
    this.error,
    this.result,
  });

  bool get isActive =>
      status == DocumentTaskStatus.queued ||
      status == DocumentTaskStatus.running;

  DocumentTaskInfo copyWith({
    String? title,
    DocumentTaskStatus? status,
    ListenableProgress? progress,
    Object? error = _sentinel,
    Object? result = _sentinel,
  }) {
    return DocumentTaskInfo(
      key: key,
      title: title ?? this.title,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      cancelToken: cancelToken,
      error: identical(error, _sentinel) ? this.error : error,
      result: identical(result, _sentinel) ? this.result : result,
    );
  }
}

const _sentinel = Object();

class DocumentTaskNotifier
    extends StateNotifier<Map<DocumentTaskKey, DocumentTaskInfo>> {
  DocumentTaskNotifier(this._ref) : super({});

  static const maxConcurrent = 5;

  final Ref _ref;
  final Queue<_QueuedDocumentTask<dynamic>> _queue = Queue();
  int _runningCount = 0;

  SnackBarService get _snackBar => _ref.read(snackBarServiceProvider);

  AppLocalizations? get _l10n {
    final ctx = rootNavigatorKey.currentContext;
    return ctx != null ? AppLocalizations.of(ctx) : null;
  }

  bool isActive(DocumentTaskKey key) => state[key]?.isActive == true;

  bool hasActiveDocumentTask(String documentId) {
    return state.values.any(
      (task) => task.key.documentId == documentId && task.isActive,
    );
  }

  void cancelTask(DocumentTaskKey key) {
    final task = state[key];
    if (task == null || !task.isActive) return;

    if (task.status == DocumentTaskStatus.queued) {
      _QueuedDocumentTask<dynamic>? queued;
      for (final entry in _queue) {
        if (entry.key == key) {
          queued = entry;
          break;
        }
      }
      if (queued != null) {
        _queue.remove(queued);
        queued.completeCancelled();
        _finishTask(key, DocumentTaskStatus.cancelled);
        return;
      }
      // 批量上传中的等待项不在单文献队列里，必须取消真实请求后再结束状态。
      task.cancelToken.cancel();
      return;
    }

    if (!task.cancelToken.isCancelled) {
      task.cancelToken.cancel();
    }
  }

  /// 提取单篇文献；成功返回 Rust 发布的 generation，取消或失败返回 null。
  Future<String?> extractDocument({
    required String documentId,
    required String title,
    required DocExtractApiState apiState,
    void Function()? onSuccess,
    bool showProgressSnackBar = true,
    bool showBusySnackBar = true,
    bool showResultSnackBar = true,
  }) async {
    if (!await AiSettingsPrompt.ensureExtractConfigured(apiState: apiState)) {
      return null;
    }
    final file = File(DocPaths.pdf(documentId));
    final maxBytes = apiState.provider.maxFileSizeMB * 1024 * 1024;
    if (!file.existsSync() || file.lengthSync() > maxBytes) {
      _snackBar.showResult(
        message: !file.existsSync()
            ? _l10n?.pdfNotFound ?? 'PDF 文件不存在'
            : _l10n?.extractFileTooLargeSingle(
                    apiState.provider.maxFileSizeMB,
                  ) ??
                  '文件超过 ${apiState.provider.maxFileSizeMB}MB 大小限制',
      );
      return null;
    }

    return _enqueue<String>(
      key: DocumentTaskKey(
        type: DocumentTaskType.extractDocument,
        documentId: documentId,
      ),
      title: title,
      initialStatus: _l10n?.waitingExtractTitle(title) ?? '等待提取 · $title',
      runningStatus: _l10n?.submittingTaskTitle(title) ?? '正在提交任务: $title',
      busyMessage: _l10n?.taskInProgress ?? '该文献已有任务在进行，请稍候',
      showBusySnackBar: showBusySnackBar,
      showProgressSnackBar: showProgressSnackBar,
      showResultSnackBar: showResultSnackBar,
      cancelledMessage: _l10n?.extractionCancelled ?? '已取消提取',
      body: (token, progress) async {
        await for (final event in RustBackend.instance.extractDocument(
          document: documentId,
          provider: _extractionProvider(apiState),
          taskId: rustTaskId('ocr', token),
        )) {
          switch (event) {
            case ExtractionEvent_Progress(progress: final p):
              progress(_extractionProgress(p, title));
            case ExtractionEvent_Published(:final generation):
              _ref.invalidate(extractionUsageProvider);
              onSuccess?.call();
              return generation;
            case ExtractionEvent_Failed(:final error):
              throw error;
          }
        }
        throw const OtterError(
          code: ErrorCode.cancelled,
          detail: 'OCR stream ended',
        );
      },
      onSuccess: (_) => TaskFinish(
        message: _l10n?.extractionCompleteTitle(title) ?? '已提取「$title」',
        duration: const Duration(seconds: 6),
      ),
      onError: (e) {
        final l10n = _l10n;
        if (l10n == null) return TaskFinish.text('$e');
        return TaskFinish.text(l10n.extractionFailedDetail(errorText(l10n, e)));
      },
    );
  }

  /// 批量提取：Rust 最多 4 篇并行，单篇失败不影响其余。
  /// 返回 `documentId → generation`（null 表示未成功）。
  Future<Map<String, String?>> extractBatch({
    required List<BatchExtractItem> items,
    required DocExtractApiState apiState,
  }) async {
    final none = {for (final item in items) item.documentId: null as String?};
    if (!await AiSettingsPrompt.ensureExtractConfigured(apiState: apiState)) {
      return none;
    }
    final pending = items
        .where((item) => !hasActiveDocumentTask(item.documentId))
        .toList();
    if (pending.isEmpty) return none;
    final provider = apiState.provider;
    if (pending.length > provider.maxBatchFiles) {
      _snackBar.showResult(
        message:
            _l10n?.batchExtractTooManyFiles(provider.maxBatchFiles) ??
            '一次最多批量提取 ${provider.maxBatchFiles} 篇',
      );
      return none;
    }

    final maxBytes = provider.maxFileSizeMB * 1024 * 1024;
    final runnable = <BatchExtractItem>[];
    var oversizedCount = 0;
    final cancelToken = CancelToken();
    for (final item in pending) {
      final file = File(item.filePath);
      final missing = !file.existsSync();
      final oversized = !missing && file.lengthSync() > maxBytes;
      if (!missing && !oversized) {
        runnable.add(item);
        continue;
      }
      if (oversized) oversizedCount++;
      final key = _extractKey(item.documentId);
      state = {
        ...state,
        key: DocumentTaskInfo(
          key: key,
          title: item.title,
          status: DocumentTaskStatus.failed,
          progress: const ListenableProgress(current: 0, total: 0, status: ''),
          cancelToken: cancelToken,
          error: missing
              ? _l10n?.pdfNotFound ?? 'PDF 文件不存在'
              : _l10n?.extractFileTooLargeSingle(provider.maxFileSizeMB) ??
                    '文件超过 ${provider.maxFileSizeMB}MB 大小限制',
        ),
      };
    }
    if (oversizedCount > 0) {
      _snackBar.showResult(
        message:
            _l10n?.extractFileTooLarge(
              provider.maxFileSizeMB,
              oversizedCount,
            ) ??
            '$oversizedCount 篇超过 ${provider.maxFileSizeMB}MB 限制，已跳过',
      );
    }
    if (runnable.isEmpty) return none;

    final titles = {for (final item in runnable) item.documentId: item.title};
    for (final item in runnable) {
      final key = _extractKey(item.documentId);
      state = {
        ...state,
        key: DocumentTaskInfo(
          key: key,
          title: item.title,
          status: DocumentTaskStatus.queued,
          progress: ListenableProgress(
            current: 0,
            total: 0,
            status: _l10n?.waitingSubmit ?? '等待提交',
          ),
          cancelToken: cancelToken,
        ),
      };
    }

    final activity = _ref.read(taskActivityProvider.notifier);
    final batchProgress = ValueNotifier(
      ListenableProgress(
        current: 0,
        total: runnable.length,
        status: _l10n?.batchExtracting ?? '正在批量提取',
      ),
    );
    final activityId = activity.report(
      progress: batchProgress,
      title: runnable.first.title,
      onCancel: cancelToken.cancel,
    );
    final results = Map.of(none);
    var settled = 0;
    void settle(
      String id,
      DocumentTaskStatus status, {
      Object? error,
      String? generation,
    }) {
      final key = _extractKey(id);
      if (state[key]?.isActive != true) return;
      _finishTask(key, status, error: error, result: generation);
      settled++;
      batchProgress.value = ListenableProgress(
        current: settled,
        total: runnable.length,
        status: _l10n?.batchExtracting ?? '正在批量提取',
      );
    }

    try {
      await for (final event in RustBackend.instance.extractDocuments(
        documents: [for (final item in runnable) item.documentId],
        provider: _extractionProvider(apiState),
        taskId: rustTaskId('ocr-batch', cancelToken),
      )) {
        switch (event) {
          case ExtractionBatchEvent_Document(:final documentId, event: final e):
            switch (e) {
              case ExtractionEvent_Progress(progress: final p):
                _updateTask(
                  _extractKey(documentId),
                  status: DocumentTaskStatus.running,
                  progress: _extractionProgress(p, titles[documentId] ?? ''),
                );
              case ExtractionEvent_Published(:final generation):
                results[documentId] = generation;
                settle(
                  documentId,
                  DocumentTaskStatus.completed,
                  generation: generation,
                );
              case ExtractionEvent_Failed(:final error):
                settle(documentId, DocumentTaskStatus.failed, error: error);
            }
          case ExtractionBatchEvent_Completed():
            break;
          case ExtractionBatchEvent_Failed(:final error):
            throw error;
        }
      }
    } catch (e) {
      if (!isCancellation(e)) log.w('[DocumentTask] 批量提取失败', error: e);
      for (final item in runnable) {
        settle(
          item.documentId,
          cancelToken.isCancelled || isCancellation(e)
              ? DocumentTaskStatus.cancelled
              : DocumentTaskStatus.failed,
          error: e,
        );
      }
    } finally {
      // Rust 不为取消的文献单独发事件。
      for (final item in runnable) {
        settle(item.documentId, DocumentTaskStatus.cancelled);
      }
      _ref.invalidate(extractionUsageProvider);
      activity.finish(activityId);
      batchProgress.dispose();
    }
    return results;
  }

  DocumentTaskKey _extractKey(String documentId) => DocumentTaskKey(
    type: DocumentTaskType.extractDocument,
    documentId: documentId,
  );

  ListenableProgress _extractionProgress(Progress p, String title) {
    final status = switch (p.stage) {
      OcrStage.requestingUpload || OcrStage.uploading =>
        _l10n?.submittingTaskTitle(title) ?? '正在提交任务 · $title',
      OcrStage.queued => _l10n?.submittedWaitingTitle(title) ?? '等待处理 · $title',
      OcrStage.running => _l10n?.extractingTitle(title) ?? '正在提取 · $title',
      OcrStage.converting ||
      OcrStage.downloading ||
      OcrStage.completed => _l10n?.savingResult ?? '正在保存结果',
    };
    return ListenableProgress(
      current: p.done.toInt(),
      total: p.total.toInt(),
      status: status,
    );
  }

  /// 用生图模型生成文献总结图；成功返回图片路径。
  Future<String?> generateSummaryImage({required Document document}) async {
    final imageRole = AgentApiNotifier.globalImageRole;
    if (!await AiSettingsPrompt.ensureImageModelSelected(
      imageRole: imageRole,
    )) {
      return null;
    }
    final agentState = AgentApiNotifier.loadInstance(imageRole.id!);
    if (agentState == null) return null;
    if (!await AiSettingsPrompt.ensureImageModelConfigured(
      agentState: agentState,
    )) {
      return null;
    }
    final model = modelSelection(
      agentState,
      agentState.imageModelId,
      capability: _ref
          .read(agentApiProvider)
          .byId(agentState.id)
          ?.modelCaps[agentState.imageModelId],
    );
    if (model == null) return null;
    final config = _ref.read(imageGenerationConfigProvider);
    final language = _ref.read(translationConfigProvider).targetLanguage;
    return _enqueue<String>(
      key: DocumentTaskKey(
        type: DocumentTaskType.generateSummaryImage,
        documentId: document.id,
      ),
      title: document.title,
      initialStatus:
          _l10n?.waitingSummaryTitle(document.title) ??
          '等待生成总结图: ${document.title}',
      runningStatus:
          _l10n?.generatingSummaryTitle(document.title) ??
          '正在生成总结图: ${document.title}',
      busyMessage: _l10n?.taskInProgress ?? '该文献已有任务在进行，请稍候',
      showBusySnackBar: false,
      showProgressSnackBar: true,
      cancelledMessage: _l10n?.summaryCancelled ?? '已取消总结图生成',
      body: (token, progress) async {
        final summary = await RustBackend.instance.generateSummary(
          document: document.id,
          model: model,
          config: SummaryConfig(
            prompt: config.prompt,
            aspectRatio: config.aspectRatio,
            fidelity: config.fidelity,
            maxReferenceImages: BigInt.from(config.maxReferenceImages),
            language: language,
          ),
          taskId: rustTaskId('summary', token),
        );
        return summary.imagePath;
      },
      onSuccess: (path) {
        unawaited(FileImage(File(path)).evict());
        return TaskFinish.text(_l10n?.summaryGenerated ?? '已生成总结图');
      },
      onError: (e) {
        final l10n = _l10n;
        if (l10n == null) return TaskFinish.text('$e');
        return TaskFinish.text(
          l10n.summaryGenerationFailed(errorText(l10n, e)),
        );
      },
    );
  }

  /// 重新从公网拉取 PDF（复用「通过标识符添加」的 DOI 下载链路）。
  /// 单篇入口；批量见 [redownloadBatch]。
  Future<bool> redownloadPdf({
    required String documentId,
    required String title,
    bool showProgressSnackBar = true,
    bool showBusySnackBar = true,
    bool showResultSnackBar = true,
  }) async {
    final result = await _enqueue<bool>(
      key: DocumentTaskKey(
        type: DocumentTaskType.redownloadPdf,
        documentId: documentId,
      ),
      title: title,
      initialStatus: _l10n?.waitingDownloadTitle(title) ?? '等待下载 · $title',
      runningStatus: _l10n?.downloadingTitle(title) ?? '正在下载 · $title',
      busyMessage: _l10n?.taskInProgress ?? '该文献已有任务在进行，请稍候',
      showBusySnackBar: showBusySnackBar,
      showProgressSnackBar: showProgressSnackBar,
      showResultSnackBar: showResultSnackBar,
      cancelledMessage: _l10n?.downloadCancelled ?? '已取消下载',
      body: (token, _) => _ref
          .read(documentLifecycleProvider)
          .redownloadPdf(documentId, cancelToken: token),
      onSuccess: (success) => success
          ? TaskFinish.text(_l10n?.downloadSuccessTitle(title) ?? '已下载「$title」')
          : TaskFinish.text(
              _l10n?.downloadFailedNoSource ?? '下载失败，未找到可用的 PDF 源',
              tone: SnackTone.error,
            ),
      onError: (e) {
        if (e is DioException) {
          return TaskFinish.text(
            _l10n?.networkError(e.message ?? '') ?? '网络错误：${e.message}',
          );
        }
        return TaskFinish.text(_l10n?.downloadFailed('$e') ?? '下载失败：$e');
      },
    );
    return result ?? false;
  }

  /// 批量重新下载（无文件条目多选入口）：并发上限由 [_enqueue] 队列控制。
  /// 聚合为单个进度 snackbar（已完成 / 总数 + 取消），与单条 [redownloadPdf]
  /// 同一套 [SnackBarService.showListenableProgress]。返回 `documentId → 是否成功`。
  ///
  /// 无 DOI 的条目会由底层 [redownloadPdf] 先用标题搜索补全。
  Future<Map<String, bool>> redownloadBatch(
    List<({String documentId, String title})> items,
  ) async {
    if (items.isEmpty) return const {};

    final total = items.length;
    var completed = 0;
    var cancelled = false;

    final notifier = ValueNotifier<ListenableProgress>(
      ListenableProgress(
        current: 0,
        total: total,
        status: _l10n?.downloadingPdf ?? '正在下载 PDF',
      ),
    );
    final handle = _snackBar.showListenableProgress(
      listenable: notifier,
      onCancel: () {
        cancelled = true;
        for (final item in items) {
          cancelTask(
            DocumentTaskKey(
              type: DocumentTaskType.redownloadPdf,
              documentId: item.documentId,
            ),
          );
        }
      },
    );

    final results = <String, bool>{};
    final futures = <String, Future<bool>>{};
    for (final item in items) {
      futures[item.documentId] =
          redownloadPdf(
            documentId: item.documentId,
            title: item.title,
            showProgressSnackBar: false,
            showBusySnackBar: false,
            showResultSnackBar: false,
          ).then((success) {
            completed++;
            notifier.value = ListenableProgress(
              current: completed,
              total: total,
              status: _l10n?.downloadingPdf ?? '正在下载 PDF',
            );
            return success;
          });
    }
    for (final entry in futures.entries) {
      results[entry.key] = await entry.value;
    }

    final ok = results.values.where((success) => success).length;
    final fail = results.length - ok;
    final String base;
    if (cancelled) {
      base = _l10n?.downloadCancelledPartial(ok) ?? '已取消下载，已成功 $ok 篇';
    } else if (fail == 0) {
      base = _l10n?.downloadCompleteAll(ok) ?? '下载完成，成功 $ok 篇';
    } else {
      base =
          _l10n?.downloadCompletePartial(ok, fail) ??
          '下载完成，成功 $ok 篇，失败 $fail 篇';
    }
    handle.finish(
      message: base,
      tone: !cancelled && fail == 0 ? SnackTone.success : SnackTone.info,
    );
    notifier.dispose();
    return results;
  }

  Future<T?> _enqueue<T>({
    required DocumentTaskKey key,
    required String title,
    required String initialStatus,
    required String runningStatus,
    required String busyMessage,
    required bool showBusySnackBar,
    required bool showProgressSnackBar,
    bool showResultSnackBar = true,
    required Future<T> Function(
      CancelToken token,
      void Function(ListenableProgress progress) progress,
    )
    body,
    required TaskFinish Function(T result) onSuccess,
    TaskFinish Function(Object error)? onError,
    String? cancelledMessage,
  }) {
    if (StorageActivity.isRestoring || hasActiveDocumentTask(key.documentId)) {
      if (showBusySnackBar) _snackBar.showResult(message: busyMessage);
      return Future.value(null);
    }

    final token = CancelToken();
    final initialProgress = ListenableProgress(
      current: 0,
      total: 0,
      status: initialStatus,
    );
    final notifier = ValueNotifier<ListenableProgress>(initialProgress);
    final handle = showProgressSnackBar
        ? _snackBar.showListenableProgress(
            listenable: notifier,
            onCancel: () => cancelTask(key),
          )
        : null;
    final completer = Completer<T?>();
    final request = _QueuedDocumentTask<T>(
      key: key,
      title: title,
      token: token,
      notifier: notifier,
      handle: handle,
      completer: completer,
      runningStatus: runningStatus,
      body: body,
      onSuccess: onSuccess,
      onError: onError,
      cancelledMessage: cancelledMessage,
      showResultSnackBar: showResultSnackBar,
    );

    state = {
      ...state,
      key: DocumentTaskInfo(
        key: key,
        title: title,
        status: DocumentTaskStatus.queued,
        progress: initialProgress,
        cancelToken: token,
      ),
    };
    _queue.add(request);
    _pumpQueue();
    return completer.future;
  }

  void _pumpQueue() {
    while (_runningCount < maxConcurrent && _queue.isNotEmpty) {
      final request = _queue.removeFirst();
      final current = state[request.key];
      if (current == null || current.status != DocumentTaskStatus.queued) {
        request.dispose();
        continue;
      }
      _start(request);
    }
  }

  void _start<T>(_QueuedDocumentTask<T> request) {
    _runningCount++;
    final runningProgress = ListenableProgress(
      current: 0,
      total: 0,
      status: request.runningStatus,
    );
    request.notifier.value = runningProgress;
    _updateTask(
      request.key,
      status: DocumentTaskStatus.running,
      progress: runningProgress,
      error: null,
      result: null,
    );

    unawaited(() async {
      try {
        final result = await executeTaskBody<T>(
          token: request.token,
          onProgress: (p) {
            request.notifier.value = p;
            _updateTask(request.key, progress: p);
          },
          body: request.body,
          onSuccess: request.onSuccess,
          onError: request.onError,
          cancelledMessage: request.cancelledMessage,
          onFinished: (f) => finishSnackBar(
            handle: request.handle,
            finish: f,
            showResultDirectly:
                request.showResultSnackBar && request.handle == null,
            snackBar: _snackBar,
          ),
          onCancelled: () =>
              _finishTask(request.key, DocumentTaskStatus.cancelled),
          onCompleted: (result) => _finishTask(
            request.key,
            DocumentTaskStatus.completed,
            result: result,
          ),
          onFailed: (e) =>
              _finishTask(request.key, DocumentTaskStatus.failed, error: e),
          debugTag: 'DocumentTask:${request.key.type}',
        );
        request.complete(result);
      } catch (e, st) {
        log.e(
          '[DocumentTask:${request.key.type}] unexpected',
          error: e,
          stackTrace: st,
        );
        request.complete(null);
      } finally {
        _runningCount--;
        request.dispose();
        _pumpQueue();
      }
    }());
  }

  void _updateTask(
    DocumentTaskKey key, {
    DocumentTaskStatus? status,
    ListenableProgress? progress,
    Object? error = _sentinel,
    Object? result = _sentinel,
  }) {
    final current = state[key];
    if (current == null) return;
    state = {
      ...state,
      key: current.copyWith(
        status: status,
        progress: progress,
        error: error,
        result: result,
      ),
    };
  }

  void _finishTask(
    DocumentTaskKey key,
    DocumentTaskStatus status, {
    Object? error = _sentinel,
    Object? result = _sentinel,
  }) {
    _updateTask(key, status: status, error: error, result: result);
  }
}

/// 批量提取的一篇文献。
class BatchExtractItem {
  final String documentId;
  final String filePath;
  final String title;

  const BatchExtractItem({
    required this.documentId,
    required this.filePath,
    required this.title,
  });
}

/// 设置中的提供商与选项转为 Rust 的提取参数；密钥由凭据注入，不随参数传递。
ExtractionProvider _extractionProvider(DocExtractApiState s) =>
    switch (s.provider) {
      DocExtractProvider.paddle => ExtractionProvider.paddleJob(
        jobUrl: 'https://paddleocr.aistudio-app.com/api/v2/ocr/jobs',
        options: PaddleOptions(
          markdownIgnoreLabels: s.markdownIgnoreLabels,
          useChartRecognition: s.useChartRecognition,
          useDocOrientationClassify: s.useDocOrientationClassify,
          useDocUnwarping: s.useDocUnwarping,
          useSealRecognition: s.useSealRecognition,
          useOcrForImageBlock: s.useOcrForImageBlock,
          mergeTables: s.mergeTables,
          restructurePages: s.restructurePages,
          layoutNms: s.layoutNms,
          layoutShapeMode: s.layoutShapeMode,
          repetitionPenalty: s.repetitionPenalty,
          temperature: s.temperature,
        ),
      ),
      DocExtractProvider.mineru => ExtractionProvider.mineru(
        baseUrl: 'https://mineru.net/api/v4',
        options: MineruOptions(
          isOcr: s.mineruIsOcr,
          enableFormula: s.mineruEnableFormula,
          enableTable: s.mineruEnableTable,
          language: s.mineruLanguage,
          extraFormats: s.mineruExtraFormats,
        ),
      ),
    };

class _QueuedDocumentTask<T> {
  final DocumentTaskKey key;
  final String title;
  final CancelToken token;
  final ValueNotifier<ListenableProgress> notifier;
  final SnackBarProgressHandle? handle;
  final Completer<T?> completer;
  final String runningStatus;
  final Future<T> Function(
    CancelToken token,
    void Function(ListenableProgress progress) progress,
  )
  body;
  // `T` 出现在参数位置（逆变），如果直接暴露 `TaskFinish Function(T)`，
  // 队列 `_QueuedDocumentTask<dynamic>` 读取该字段时会触发运行时类型检查失败。
  // 统一存为 `Function(Object?)`，在 onSuccess() 内部 cast 回 T。
  final TaskFinish Function(Object? result) onSuccess;
  final TaskFinish Function(Object error)? onError;
  final String? cancelledMessage;
  final bool showResultSnackBar;

  _QueuedDocumentTask({
    required this.key,
    required this.title,
    required this.token,
    required this.notifier,
    required this.handle,
    required this.completer,
    required this.runningStatus,
    required this.body,
    required TaskFinish Function(T result) onSuccess,
    required this.onError,
    required this.cancelledMessage,
    required this.showResultSnackBar,
  }) : onSuccess = ((result) => onSuccess(result as T));

  void complete(T? value) {
    if (!completer.isCompleted) completer.complete(value);
  }

  void completeCancelled() {
    if (!token.isCancelled) token.cancel();
    final fallback = rootNavigatorKey.currentContext != null
        ? AppLocalizations.of(rootNavigatorKey.currentContext!)?.cancelled
        : null;
    handle?.finish(message: cancelledMessage ?? fallback ?? '已取消');
    complete(null);
    dispose();
  }

  void dispose() {
    notifier.dispose();
  }
}

final documentTaskProvider =
    StateNotifierProvider<
      DocumentTaskNotifier,
      Map<DocumentTaskKey, DocumentTaskInfo>
    >((ref) {
      return DocumentTaskNotifier(ref);
    });
