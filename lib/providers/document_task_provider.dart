import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n.dart';
import '../data/models/book/document.dart';
import '../router/app_router.dart';
import '../router/app_routes.dart';
import '../services/ai_settings_prompt.dart';
import '../services/batch_extract_service.dart';
import '../services/doc_extract_service.dart';
import '../services/document_summary_image_service.dart';
import '../services/image_generation_service.dart';
import '../services/snackbar_service.dart';
import 'api_provider.dart';
import 'document_lifecycle_provider.dart';
import 'image_generation_config_provider.dart';
import 'summary_image_provider.dart';
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
  GoRouter get _router => _ref.read(routerProvider);

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
      }
      _finishTask(key, DocumentTaskStatus.cancelled);
      return;
    }

    if (!task.cancelToken.isCancelled) {
      task.cancelToken.cancel();
    }
  }

  Future<String?> extractDocument({
    required String documentId,
    required String filePath,
    required String title,
    required DocExtractApiState apiState,
    void Function(String mdPath, String markdownContent)? onSuccess,
    bool showProgressSnackBar = true,
    bool showBusySnackBar = true,
    bool showResultSnackBar = true,
  }) async {
    if (!apiState.isConfigured) {
      _snackBar.showResult(
        message: _l10n?.configureExtractToken ?? '请先在设置中配置文档提取 Access Token',
        action: SnackBarAction(
          label: _l10n?.goToSettings ?? '前往设置',
          onPressed: () => _router.push(AppRoutes.settingsExtract),
        ),
      );
      return null;
    }

    final result = await _enqueue<String>(
      key: DocumentTaskKey(
        type: DocumentTaskType.extractDocument,
        documentId: documentId,
      ),
      title: title,
      initialStatus: _l10n?.waitingExtractTitle(title) ?? '等待提取: $title',
      runningStatus: _l10n?.submittingTaskTitle(title) ?? '正在提交任务: $title',
      busyMessage: _l10n?.taskInProgress ?? '该文献已有任务正在进行中',
      showBusySnackBar: showBusySnackBar,
      showProgressSnackBar: showProgressSnackBar,
      showResultSnackBar: showResultSnackBar,
      cancelledMessage: _l10n?.extractionCancelled ?? '已取消提取',
      body: (token, progress) async {
        final extractResult = await _extractAsync(
          filePath: filePath,
          title: title,
          apiState: apiState,
          cancelToken: token,
          progress: progress,
        );
        if (token.isCancelled) {
          throw DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.cancel,
          );
        }
        progress(
          ListenableProgress(
            current: 0,
            total: 0,
            status: _l10n?.savingResult ?? '正在保存结果',
          ),
        );
        final savedMdPath = await DocExtractService.instance
            .saveResult(
              filePath,
              extractResult,
              token: apiState.apiKey,
              title: title,
            )
            .timeout(const Duration(seconds: 30));
        onSuccess?.call(savedMdPath, extractResult.processedMarkdown ?? '');
        return savedMdPath;
      },
      onSuccess: (_) => TaskFinish(
        message: _l10n?.extractionCompleteTitle(title) ?? '文档提取完成：$title',
        duration: const Duration(seconds: 6),
      ),
      onError: (e) {
        if (e is DocExtractException) return TaskFinish.text(e.message);
        if (e is BatchExtractException) return TaskFinish.text(e.message);
        if (e is DioException) {
          return TaskFinish.text(_l10n?.networkError(e.message ?? '') ?? '网络错误: ${e.message}');
        }
        return TaskFinish.text(_l10n?.extractionFailedDetail('$e') ?? '提取失败: $e');
      },
    );
    return result;
  }

  Future<Map<String, String?>> extractBatch({
    required List<BatchExtractItem> items,
    required DocExtractApiState apiState,
  }) async {
    if (!apiState.isConfigured) {
      _snackBar.showResult(message: _l10n?.configureExtractToken ?? '请先在设置中配置文档提取 Access Token');
      return {for (final item in items) item.documentId: null};
    }

    final pendingItems =
        items.where((item) => !hasActiveDocumentTask(item.documentId)).toList();
    if (pendingItems.isEmpty) {
      return {for (final item in items) item.documentId: null};
    }

    final cancelToken = CancelToken();
    for (final item in pendingItems) {
      final key = DocumentTaskKey(
        type: DocumentTaskType.extractDocument,
        documentId: item.documentId,
      );
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

    try {
      final results = await BatchExtractService.instance.extractBatch(
        items: pendingItems,
        token: apiState.apiKey,
        state: apiState,
        cancelToken: cancelToken,
        onJobUpdate: _onBatchJobUpdate,
      );
      for (final item in pendingItems) {
        final key = DocumentTaskKey(
          type: DocumentTaskType.extractDocument,
          documentId: item.documentId,
        );
        if (state[key]?.isActive == true) {
          _finishTask(key, DocumentTaskStatus.cancelled);
        }
      }
      return results;
    } catch (e) {
      for (final item in pendingItems) {
        final key = DocumentTaskKey(
          type: DocumentTaskType.extractDocument,
          documentId: item.documentId,
        );
        if (state[key]?.isActive == true) {
          _finishTask(key, DocumentTaskStatus.failed, error: e);
        }
      }
      return {for (final item in pendingItems) item.documentId: null};
    }
  }

  void _onBatchJobUpdate(BatchJobStatus jobStatus) {
    final key = DocumentTaskKey(
      type: DocumentTaskType.extractDocument,
      documentId: jobStatus.documentId,
    );
    final current = state[key];
    if (current == null || !current.isActive) return;

    switch (jobStatus.state) {
      case BatchJobState.pending:
        _updateTask(
          key,
          progress: ListenableProgress(
            current: 0,
            total: 0,
            status: _l10n?.waitingSubmitTitle(jobStatus.title) ?? '等待提交: ${jobStatus.title}',
          ),
        );

      case BatchJobState.submitted:
        _updateTask(
          key,
          status: DocumentTaskStatus.running,
          progress: ListenableProgress(
            current: 0,
            total: 0,
            status: _l10n?.submittedWaitingTitle(jobStatus.title) ?? '已提交，等待处理: ${jobStatus.title}',
          ),
        );

      case BatchJobState.running:
        _updateTask(
          key,
          status: DocumentTaskStatus.running,
          progress: ListenableProgress(
            current: jobStatus.extractedPages,
            total: jobStatus.totalPages,
            status: _l10n?.extractingTitle(jobStatus.title) ?? '正在提取… · ${jobStatus.title}',
          ),
        );

      case BatchJobState.done:
        if (jobStatus.savedPath != null) {
          _finishTask(
            key,
            DocumentTaskStatus.completed,
            result: jobStatus.savedPath,
          );
        } else {
          _finishTask(
            key,
            DocumentTaskStatus.failed,
            error: jobStatus.error ?? (_l10n?.saveResultFailed ?? '保存结果失败'),
          );
        }

      case BatchJobState.failed:
        _finishTask(
          key,
          DocumentTaskStatus.failed,
          error: jobStatus.error ?? (_l10n?.extractionFailed ?? '提取失败'),
        );

      case BatchJobState.cancelled:
        _finishTask(key, DocumentTaskStatus.cancelled);
    }
  }

  Future<DocumentSummaryImageResult?> generateSummaryImage({
    required Document document,
    required void Function(String imagePath) onSuccess,
  }) async {
    final imageRole = AgentApiNotifier.globalImageRole;
    if (!AiSettingsPrompt.ensureImageModelSelected(
      imageRole: imageRole,
      snackBar: _snackBar,
      onOpenSettings: () => _router.push(AppRoutes.settingsApi),
    )) {
      return null;
    }
    final agentState = AgentApiNotifier.loadInstance(imageRole.id!);
    if (agentState == null) return null; // 角色指向的实例已被删除
    if (!AiSettingsPrompt.ensureImageModelConfigured(
      agentState: agentState,
      snackBar: _snackBar,
      onOpenSettings: () => _router.push(AppRoutes.settingsApi),
    )) {
      return null;
    }

    final summaryNotifier = _ref.read(
      summaryImageProvider(document.id).notifier,
    );
    summaryNotifier.start();

    final result = await _enqueue<DocumentSummaryImageResult>(
      key: DocumentTaskKey(
        type: DocumentTaskType.generateSummaryImage,
        documentId: document.id,
      ),
      title: document.title,
      initialStatus: _l10n?.waitingSummaryTitle(document.title) ?? '等待生成总结图: ${document.title}',
      runningStatus: _l10n?.generatingSummaryTitle(document.title) ?? '正在生成总结图: ${document.title}',
      busyMessage: _l10n?.taskInProgress ?? '该文献已有任务正在进行中',
      showBusySnackBar: false,
      showProgressSnackBar: false,
      cancelledMessage: _l10n?.summaryCancelled ?? '已取消总结图生成',
      body: (token, progress) async {
        progress(
          ListenableProgress(
            current: 0,
            total: 0,
            status: _l10n?.preparingContent ?? '正在整理文献内容',
          ),
        );
        final config = _ref.read(imageGenerationConfigProvider);
        progress(
          ListenableProgress(
            current: 0,
            total: 0,
            status: _l10n?.requestingImageModel ?? '正在请求生图模型',
          ),
        );
        final language = _ref.read(translationConfigProvider).targetLanguage;
        return DocumentSummaryImageService.instance.generate(
          document: document,
          agentState: agentState,
          config: config,
          language: language,
          cancelToken: token,
        );
      },
      onSuccess: (result) {
        unawaited(FileImage(File(result.imagePath)).evict());
        summaryNotifier.generated(result.imagePath);
        onSuccess(result.imagePath);
        return TaskFinish.text(_l10n?.summaryGenerated ?? '总结图已生成');
      },
      onError: (e) {
        summaryNotifier.finishWithoutImage();
        if (e is DocumentSummaryImageException) {
          return TaskFinish.text(e.message);
        }
        if (e is ImageGenerationException) {
          return TaskFinish.text(e.message);
        }
        if (e is DioException) {
          return TaskFinish.text(_l10n?.networkError(e.message ?? '') ?? '网络错误: ${e.message}');
        }
        return TaskFinish.text(_l10n?.summaryGenerationFailed('$e') ?? '总结图生成失败: $e');
      },
    );
    if (result == null &&
        _ref.read(summaryImageProvider(document.id)).generating) {
      summaryNotifier.finishWithoutImage();
    }
    return result;
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
      initialStatus: _l10n?.waitingDownloadTitle(title) ?? '等待下载: $title',
      runningStatus: _l10n?.downloadingTitle(title) ?? '正在下载: $title',
      busyMessage: _l10n?.taskInProgress ?? '该文献已有任务正在进行中',
      showBusySnackBar: showBusySnackBar,
      showProgressSnackBar: showProgressSnackBar,
      showResultSnackBar: showResultSnackBar,
      cancelledMessage: _l10n?.downloadCancelled ?? '已取消下载',
      body: (token, _) => _ref
          .read(documentLifecycleProvider)
          .redownloadPdf(documentId, cancelToken: token),
      onSuccess: (success) =>
          TaskFinish.text(success
              ? (_l10n?.downloadSuccessTitle(title) ?? '下载成功：$title')
              : (_l10n?.downloadFailedNoSource ?? '下载失败，未找到可用的 PDF 源')),
      onError: (e) {
        if (e is DioException) return TaskFinish.text(_l10n?.networkError(e.message ?? '') ?? '网络错误: ${e.message}');
        return TaskFinish.text(_l10n?.downloadFailed('$e') ?? '下载失败: $e');
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
      ListenableProgress(current: 0, total: total, status: _l10n?.downloadingPdf ?? '正在下载 PDF'),
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
      base = _l10n?.downloadCompletePartial(ok, fail) ?? '下载完成：成功 $ok 篇，失败 $fail 篇';
    }
    handle.finish(message: base);
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
    if (hasActiveDocumentTask(key.documentId)) {
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
        log.e('[DocumentTask:${request.key.type}] unexpected', error: e, stackTrace: st);
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

  Future<DocExtractResult> _extractAsync({
    required String filePath,
    required String title,
    required DocExtractApiState apiState,
    required CancelToken cancelToken,
    required void Function(ListenableProgress) progress,
  }) async {
    return await BatchExtractService.instance.extractSingle(
      filePath: filePath,
      token: apiState.apiKey,
      state: apiState,
      onProgress: (status, extracted, total) {
        if (cancelToken.isCancelled) return;
        progress(
          ListenableProgress(
            current: extracted,
            total: total,
            status: '$status · $title',
          ),
        );
      },
      cancelToken: cancelToken,
    );
  }
}

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
