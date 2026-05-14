import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

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
import 'image_generation_config_provider.dart';
import 'summary_image_provider.dart';
import 'task_runner.dart';
import 'translation_config_provider.dart';

enum DocumentTaskType { extractDocument, generateSummaryImage }

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
        message: '请先在设置中配置文档提取 Access Token',
        action: SnackBarAction(
          label: '前往设置',
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
      initialStatus: '等待提取: $title',
      runningStatus: '正在提交任务: $title',
      busyMessage: '该文献已有任务正在进行中',
      showBusySnackBar: showBusySnackBar,
      showProgressSnackBar: showProgressSnackBar,
      showResultSnackBar: showResultSnackBar,
      cancelledMessage: '已取消提取',
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
          const ListenableProgress(current: 0, total: 0, status: '正在保存结果'),
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
        message: '文档提取完成：$title',
        duration: const Duration(seconds: 6),
      ),
      onError: (e) {
        if (e is DocExtractException) return TaskFinish.text(e.message);
        if (e is BatchExtractException) return TaskFinish.text(e.message);
        if (e is DioException) {
          return TaskFinish.text('网络错误: ${e.message}');
        }
        return TaskFinish.text('提取失败: $e');
      },
    );
    return result;
  }

  Future<Map<String, String?>> extractBatch({
    required List<BatchExtractItem> items,
    required DocExtractApiState apiState,
  }) async {
    if (!apiState.isConfigured) {
      _snackBar.showResult(message: '请先在设置中配置文档提取 Access Token');
      return {for (final item in items) item.documentId: null};
    }

    final futures = <String, Future<String?>>{};
    for (final item in items) {
      futures[item.documentId] = extractDocument(
        documentId: item.documentId,
        filePath: item.filePath,
        title: item.title,
        apiState: apiState,
        showProgressSnackBar: false,
        showBusySnackBar: false,
        showResultSnackBar: false,
      );
    }

    final results = <String, String?>{};
    for (final entry in futures.entries) {
      results[entry.key] = await entry.value;
    }
    return results;
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
    final agentState = AgentApiNotifier.loadForProvider(imageRole.provider!);
    if (!AiSettingsPrompt.ensureImageModelConfigured(
      agentState: agentState,
      snackBar: _snackBar,
      onOpenSettings: () => _router.push(AppRoutes.settingsApi),
    )) {
      return null;
    }

    final summaryNotifier = _ref.read(
      summaryImageProvider(document.filePath).notifier,
    );
    summaryNotifier.start();

    final result = await _enqueue<DocumentSummaryImageResult>(
      key: DocumentTaskKey(
        type: DocumentTaskType.generateSummaryImage,
        documentId: document.id,
      ),
      title: document.title,
      initialStatus: '等待生成总结图: ${document.title}',
      runningStatus: '正在生成总结图: ${document.title}',
      busyMessage: '该文献已有任务正在进行中',
      showBusySnackBar: false,
      showProgressSnackBar: false,
      cancelledMessage: '已取消总结图生成',
      body: (token, progress) async {
        progress(
          const ListenableProgress(current: 0, total: 0, status: '正在整理文献内容'),
        );
        final config = _ref.read(imageGenerationConfigProvider);
        progress(
          const ListenableProgress(current: 0, total: 0, status: '正在请求生图模型'),
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
        return TaskFinish.text('总结图已生成');
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
          return TaskFinish.text('网络错误: ${e.message}');
        }
        return TaskFinish.text('总结图生成失败: $e');
      },
    );
    if (result == null &&
        _ref.read(summaryImageProvider(document.filePath)).generating) {
      summaryNotifier.finishWithoutImage();
    }
    return result;
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
      if (!isActive(key) && !showBusySnackBar) {
        final progress = ListenableProgress(
          current: 0,
          total: 0,
          status: busyMessage,
        );
        state = {
          ...state,
          key: DocumentTaskInfo(
            key: key,
            title: title,
            status: DocumentTaskStatus.failed,
            progress: progress,
            cancelToken: CancelToken(),
            error: busyMessage,
          ),
        };
      }
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
      finish: _finishSnackBar,
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
        final result = await request.body(request.token, (progress) {
          if (request.token.isCancelled) return;
          request.notifier.value = progress;
          _updateTask(request.key, progress: progress);
        });

        if (request.token.isCancelled) {
          _finishTask(request.key, DocumentTaskStatus.cancelled);
          request.finish(
            request.handle,
            TaskFinish.text(request.cancelledMessage ?? '已取消'),
            showResultDirectly:
                request.showResultSnackBar && request.handle == null,
          );
          request.complete(null);
          return;
        }

        _finishTask(request.key, DocumentTaskStatus.completed, result: result);
        request.finish(
          request.handle,
          request.onSuccess(result),
          showResultDirectly:
              request.showResultSnackBar && request.handle == null,
        );
        request.complete(result);
      } catch (e, st) {
        if (_isCancellation(e, request.token)) {
          _finishTask(request.key, DocumentTaskStatus.cancelled);
          request.finish(
            request.handle,
            TaskFinish.text(request.cancelledMessage ?? '已取消'),
            showResultDirectly:
                request.showResultSnackBar && request.handle == null,
          );
        } else {
          _finishTask(request.key, DocumentTaskStatus.failed, error: e);
          request.finish(
            request.handle,
            request.onError?.call(e) ?? TaskFinish(message: '任务失败: $e'),
            showResultDirectly:
                request.showResultSnackBar && request.handle == null,
          );
          debugPrint('[DocumentTask] ${request.key.type} failed: $e\n$st');
        }
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

  void _finishSnackBar(
    SnackBarProgressHandle? handle,
    TaskFinish finish, {
    required bool showResultDirectly,
  }) {
    if (handle != null) {
      handle.finish(
        message: finish.message,
        action: finish.action,
        duration: finish.duration,
      );
      return;
    }
    if (!showResultDirectly || finish.message == null) return;
    _snackBar.showResult(
      message: finish.message!,
      action: finish.action,
      duration: finish.duration ?? const Duration(seconds: 4),
    );
  }

  bool _isCancellation(Object e, CancelToken token) {
    if (token.isCancelled) return true;
    return e is DioException && e.type == DioExceptionType.cancel;
  }

  Future<DocExtractResult> _extractAsync({
    required String filePath,
    required String title,
    required DocExtractApiState apiState,
    required CancelToken cancelToken,
    required void Function(ListenableProgress) progress,
  }) async {
    try {
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
    } catch (asyncError) {
      if (cancelToken.isCancelled ||
          (asyncError is DioException &&
              asyncError.type == DioExceptionType.cancel)) {
        rethrow;
      }
      if (!apiState.hasSyncFallback) rethrow;

      debugPrint('[DocumentTask] 异步提取失败，回退到同步 API: $asyncError');
      progress(
        ListenableProgress(
          current: 0,
          total: 0,
          status: '异步失败，尝试同步提取 · $title',
        ),
      );

      return DocExtractService.instance.extract(
        filePath: filePath,
        apiUrl: apiState.syncBaseUrl,
        token: apiState.apiKey,
        state: apiState,
        cancelToken: cancelToken,
      );
    }
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
  final TaskFinish Function(T result) onSuccess;
  final TaskFinish Function(Object error)? onError;
  final String? cancelledMessage;
  final bool showResultSnackBar;
  final void Function(
    SnackBarProgressHandle? handle,
    TaskFinish finish, {
    required bool showResultDirectly,
  })
  finish;

  _QueuedDocumentTask({
    required this.key,
    required this.title,
    required this.token,
    required this.notifier,
    required this.handle,
    required this.completer,
    required this.runningStatus,
    required this.body,
    required this.onSuccess,
    required this.onError,
    required this.cancelledMessage,
    required this.showResultSnackBar,
    required this.finish,
  });

  void complete(T? value) {
    if (!completer.isCompleted) completer.complete(value);
  }

  void completeCancelled() {
    if (!token.isCancelled) token.cancel();
    handle?.finish(message: cancelledMessage ?? '已取消');
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
