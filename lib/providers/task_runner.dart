import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../services/snackbar_service.dart';
import 'task_types.dart';

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
    required Future<T> Function(
      CancelToken token,
      void Function(ListenableProgress) progress,
    ) body,
    required TaskFinish Function(T result) onSuccess,
    TaskFinish Function(Object error)? onError,
    String? cancelledMessage = '已取消',
  }) async {
    if (isTaskRunning(type)) {
      snackBar.showResult(message: busyMessage);
      return null;
    }

    final token = CancelToken();
    markTaskStarted(type, token);

    final notifier = ValueNotifier<ListenableProgress>(
      ListenableProgress(current: 0, total: 0, status: initialStatus),
    );

    final handle = snackBar.showListenableProgress(
      listenable: notifier,
      onCancel: () {
        if (!token.isCancelled) token.cancel();
      },
    );

    try {
      final result = await body(token, (p) {
        // 任务已取消后到达的进度事件直接丢弃，避免"取消后还刷进度"的视觉 bug
        if (!token.isCancelled) notifier.value = p;
      });

      if (token.isCancelled) {
        markTaskFinished(type, TaskStatus.cancelled);
        handle.finish(message: cancelledMessage);
        return null;
      }

      markTaskFinished(type, TaskStatus.completed);
      final finish = onSuccess(result);
      handle.finish(
        message: finish.message,
        action: finish.action,
        duration: finish.duration,
      );
      return result;
    } catch (e, st) {
      if (_isCancellation(e, token)) {
        markTaskFinished(type, TaskStatus.cancelled);
        handle.finish(message: cancelledMessage);
      } else {
        markTaskFinished(type, TaskStatus.failed);
        final finish = onError?.call(e) ?? TaskFinish(message: '任务失败: $e');
        handle.finish(
          message: finish.message,
          action: finish.action,
          duration: finish.duration,
        );
        debugPrint('[TaskRunner] $type failed: $e\n$st');
      }
      return null;
    } finally {
      notifier.dispose();
    }
  }

  bool _isCancellation(Object e, CancelToken token) {
    if (token.isCancelled) return true;
    if (e is DioException && e.type == DioExceptionType.cancel) return true;
    return false;
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
