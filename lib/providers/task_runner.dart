import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../core/l10n.dart';
import '../router/app_router.dart';
import '../services/snackbar_service.dart';
import 'task_types.dart';
import '../core/app_logger.dart';

String _resolvedCancelled(String? message) {
  if (message != null) return message;
  final ctx = rootNavigatorKey.currentContext;
  if (ctx != null) return AppLocalizations.of(ctx)?.cancelled ?? '已取消';
  return '已取消';
}

// ── 共享的任务执行生命周期 ──

/// 核心执行生命周期：运行 [body]，处理 completed/cancelled/failed 三种终态，
/// 通过回调通知调用者。返回 body 的结果；cancelled / failed 返回 null。
///
/// 调用者负责创建 CancelToken、ValueNotifier 和清理（dispose）。
Future<T?> executeTaskBody<T>({
  required CancelToken token,
  required void Function(ListenableProgress) onProgress,
  required Future<T> Function(
    CancelToken token,
    void Function(ListenableProgress) progress,
  ) body,
  required TaskFinish Function(T result) onSuccess,
  TaskFinish Function(Object error)? onError,
  String? cancelledMessage,
  required void Function(TaskFinish finish) onFinished,
  required void Function() onCancelled,
  required void Function(T result) onCompleted,
  required void Function(Object error) onFailed,
  String? debugTag,
}) async {
  try {
    final result = await body(token, (p) {
      if (!token.isCancelled) onProgress(p);
    });

    if (token.isCancelled) {
      onCancelled();
      onFinished(TaskFinish.text(_resolvedCancelled(cancelledMessage)));
      return null;
    }

    onCompleted(result);
    final finish = onSuccess(result);
    onFinished(finish);
    return result;
  } catch (e, st) {
    if (isCancellation(e, token)) {
      onCancelled();
      onFinished(TaskFinish.text(_resolvedCancelled(cancelledMessage)));
    } else {
      onFailed(e);
      final finish = onError?.call(e) ?? TaskFinish(message: '任务失败: $e');
      onFinished(finish);
      if (debugTag != null) log.e('[$debugTag] failed', error: e, stackTrace: st);
    }
    return null;
  }
}

/// 结束进度 SnackBar 或直接展示结果消息。
void finishSnackBar({
  required SnackBarProgressHandle? handle,
  required TaskFinish finish,
  required bool showResultDirectly,
  required SnackBarService snackBar,
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
  snackBar.showResult(
    message: finish.message!,
    action: finish.action,
    duration: finish.duration ?? const Duration(seconds: 4),
  );
}

/// 判断异常是否为取消操作。
bool isCancellation(Object e, CancelToken token) {
  if (token.isCancelled) return true;
  return e is DioException && e.type == DioExceptionType.cancel;
}

/// 后台任务通用骨架 mixin。
///
/// 把"busy 检查 → _startTask → 生成 CancelToken → show 进度 SnackBar →
/// 执行 body → 分支 completed/cancelled/failed → _finishTask → finish 通知"
/// 这套重复流水线抽出来，业务方法只需提供 3 样东西：
/// 1. `body`：真正的异步工作，接 `token` 和 `progress` 回调
/// 2. `onSuccess(result)`：把 body 的产物翻译成用户可见的成功文案
/// 3. `onError(error)`（可选）：把异常翻译成用户可见的失败文案
///
/// 进度通知走 [SnackBarService.showListenableProgress]——一个 SnackBar 通过
/// ValueNotifier 原地刷新，不走 ScaffoldMessenger 的 FIFO 队列，消除堆积延迟。
///
/// 子类必须实现 3 个 hook，把 mixin 和具体 state 形状解耦：
/// - [snackBar]：通知服务
/// - [isTaskRunning]：查询任务是否在跑
/// - [markTaskStarted]/[markTaskFinished]：更新 state
mixin TaskRunner<S> on StateNotifier<S> {
  SnackBarService get snackBar;
  bool isTaskRunning(TaskType type);
  void markTaskStarted(TaskType type, CancelToken token);
  void markTaskFinished(TaskType type, TaskStatus status);

  /// 运行一个后台任务，统一管理进度 SnackBar 生命周期。
  ///
  /// 返回 body 的结果；若 busy / cancelled / failed，返回 null。
  Future<T?> runTask<T>({
    required TaskType type,
    required String initialStatus,
    String busyMessage = '任务正在进行中',
    bool showBusySnackBar = true,
    bool showProgressSnackBar = true,
    required Future<T> Function(
      CancelToken token,
      void Function(ListenableProgress) progress,
    )
    body,
    required TaskFinish Function(T result) onSuccess,
    TaskFinish Function(Object error)? onError,
    String? cancelledMessage,
  }) async {
    if (isTaskRunning(type)) {
      if (showBusySnackBar) {
        snackBar.showResult(message: busyMessage);
      }
      return null;
    }

    final token = CancelToken();
    markTaskStarted(type, token);

    final notifier = ValueNotifier<ListenableProgress>(
      ListenableProgress(current: 0, total: 0, status: initialStatus),
    );

    final handle = showProgressSnackBar
        ? snackBar.showListenableProgress(
            listenable: notifier,
            onCancel: () {
              if (!token.isCancelled) token.cancel();
            },
          )
        : null;

    try {
      return await executeTaskBody<T>(
        token: token,
        onProgress: (p) => notifier.value = p,
        body: body,
        onSuccess: onSuccess,
        onError: onError,
        cancelledMessage: cancelledMessage,
        onFinished: (f) => finishSnackBar(
          handle: handle,
          finish: f,
          showResultDirectly: !showProgressSnackBar,
          snackBar: snackBar,
        ),
        onCancelled: () => markTaskFinished(type, TaskStatus.cancelled),
        onCompleted: (_) => markTaskFinished(type, TaskStatus.completed),
        onFailed: (_) => markTaskFinished(type, TaskStatus.failed),
        debugTag: 'TaskRunner:$type',
      );
    } finally {
      notifier.dispose();
    }
  }
}

/// 任务结束通知的文案 / 按钮 / 持续时间。
///
/// 用一个统一结构取代多个 `String?` + `SnackBarAction?` + `Duration?` 参数，
/// 让业务方法的 `onSuccess` / `onError` 回调签名更自然、可扩展。
class TaskFinish {
  final String? message;
  final SnackBarAction? action;
  final Duration? duration;

  const TaskFinish({this.message, this.action, this.duration});

  /// 纯文本结果。
  const TaskFinish.text(String msg)
    : message = msg,
      action = null,
      duration = null;
}
