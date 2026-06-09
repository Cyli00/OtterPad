import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../core/l10n.dart';
import '../providers/task_activity_provider.dart';
import '../router/app_router.dart';

export '../providers/task_activity_provider.dart' show ListenableProgress;

/// 全局 ScaffoldMessenger Key，挂载在 MaterialApp.router 上，
/// 使 SnackBar 跨页面导航持续显示。
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

final snackBarServiceProvider = Provider<SnackBarService>((ref) {
  return SnackBarService(scaffoldMessengerKey, ref);
});

/// 统一 SnackBar 服务
///
/// 通过 [scaffoldMessengerKey] 访问根级 ScaffoldMessenger，
/// 不依赖页面级 BuildContext，确保 SnackBar 在任何导航状态下可用。
class SnackBarService {
  final GlobalKey<ScaffoldMessengerState> _key;
  final Ref _ref;

  SnackBarService(this._key, this._ref);

  /// snackbar surface 当前持有的活跃任务集合（由 [renderActiveTasks] 同步）。
  List<ActiveTask> _tasks = const [];

  /// 当前占用单槽的一次性结果（Transient Result）；非空时进度渲染让位，结束后回收。
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _transient;

  ScaffoldMessengerState? get _messenger => _key.currentState;

  AppLocalizations? get _l10n {
    final ctx = rootNavigatorKey.currentContext;
    return ctx != null ? AppLocalizations.of(ctx) : null;
  }

  bool get _isMobile {
    final ctx = _key.currentContext;
    if (ctx == null) return true;
    return MediaQuery.sizeOf(ctx).width < 600;
  }

  /// 进度型 SnackBar：spinner + 状态文字 + 文件名 + 可选进度计数 + 取消按钮
  void showProgress({
    int? current,
    int? total,
    required String fileName,
    String? status,
    required VoidCallback onCancel,
    Duration duration = const Duration(minutes: 5),
  }) {
    final messenger = _messenger;
    if (messenger == null) return;

    final mobile = _isMobile;

    // clearSnackBars 而非 hideCurrentSnackBar：前者清空整个 FIFO 队列，
    // 避免旧 snack 未 timeout 把新 snack 卡在队尾形成感知延迟。
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          width: mobile ? null : 400,
          margin: mobile
              ? const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0)
              : null,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
          elevation: 6,
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            status ?? (_l10n?.processing ?? '处理中...'),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (current != null && total != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: Text(
                              '$current / $total',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      fileName,
                      style: const TextStyle(fontSize: 12, height: 1.4),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: _l10n?.cancel ?? '取消',
            onPressed: onCancel,
          ),
          duration: duration,
        ),
      );
  }

  /// 结果/信息型 SnackBar（Transient Result）：文字消息 + 可选操作按钮。
  ///
  /// 短暂占用单槽；关闭后由 [_refreshSlot] 回收，重新呈现仍在跑的 Active Task。
  void showResult({
    required String message,
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    final messenger = _messenger;
    if (messenger == null) return;

    final mobile = _isMobile;

    messenger.clearSnackBars();
    final controller = messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: mobile ? null : 400,
        margin: mobile
            ? const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0)
            : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
        elevation: 6,
        content: Text(message, style: const TextStyle(fontSize: 14)),
        action: action,
        duration: duration,
      ),
    );
    _transient = controller;
    controller.closed.then((_) {
      if (identical(_transient, controller)) {
        _transient = null;
        _refreshSlot();
      }
    });
  }

  /// 隐藏当前 SnackBar
  void hide() {
    _messenger?.hideCurrentSnackBar();
  }

  /// 以 [ValueListenable] 驱动的进度任务：登记进 Task Activity，由
  /// [renderActiveTasks] 仲裁呈现（1 个显示完整进度，≥2 聚合）。
  ///
  /// 返回的 [SnackBarProgressHandle] 用于完成/失败时收尾——注销该任务，
  /// 完成消息以 Transient Result 形式短暂呈现。[duration] 仅为兼容旧签名保留。
  SnackBarProgressHandle showListenableProgress({
    required ValueListenable<ListenableProgress> listenable,
    VoidCallback? onCancel,
    Duration duration = const Duration(hours: 1),
    String title = '',
  }) {
    final activity = _ref.read(taskActivityProvider.notifier);
    final id = activity.report(
      progress: listenable,
      title: title,
      onCancel: onCancel,
    );
    return SnackBarProgressHandle._(
      () => activity.finish(id),
      (msg, action, dur) {
        // 先把完成消息作为 Transient Result 占槽，再注销任务——这样后续
        // renderActiveTasks 看到 Transient 占槽会让位，消息不会被进度回收顶掉。
        if (msg != null) {
          showResult(
            message: msg,
            action: action,
            duration: dur ?? const Duration(seconds: 4),
          );
        }
        activity.finish(id);
      },
    );
  }

  /// snackbar surface：观察 Task Activity，把单槽同步到当前活集合。
  /// 0 个 → 清空；1 个 → 完整进度；≥2 个 → 聚合"N 个任务进行中"。
  void renderActiveTasks(List<ActiveTask> tasks) {
    _tasks = tasks;
    _refreshSlot();
  }

  /// 依据当前 [_tasks] 重绘单槽。Transient Result 占槽期间让位，由其关闭回调回收。
  void _refreshSlot() {
    final messenger = _messenger;
    if (messenger == null) return;
    if (_transient != null) return;

    final tasks = _tasks;
    if (tasks.isEmpty) {
      messenger.clearSnackBars();
    } else if (tasks.length == 1) {
      _showProgressSnackBar(tasks.single);
    } else {
      _showAggregateSnackBar(tasks);
    }
  }

  void _showProgressSnackBar(ActiveTask task) {
    final messenger = _messenger;
    if (messenger == null) return;
    final mobile = _isMobile;
    final onCancel = task.onCancel;

    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          width: mobile ? null : 400,
          margin: mobile
              ? const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0)
              : null,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
          elevation: 6,
          content: ValueListenableBuilder<ListenableProgress>(
            valueListenable: task.progress,
            // 完成态：左侧图标由 spinner 切成对勾，避免"完成但还在转圈"的视觉 bug。
            builder: (ctx, info, _) => Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: (info.total > 0 && info.current >= info.total)
                      ? Icon(
                          Symbols.check_circle_rounded,
                          color: Theme.of(ctx).colorScheme.primary,
                          size: 22,
                          fill: 1,
                        )
                      : const CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          info.status,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (info.total > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            '${info.current} / ${info.total}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          action: onCancel == null
              ? null
              : SnackBarAction(
                  label: _l10n?.cancel ?? '取消',
                  onPressed: onCancel,
                ),
          duration: const Duration(hours: 1),
        ),
      );
  }

  void _showAggregateSnackBar(List<ActiveTask> tasks) {
    final messenger = _messenger;
    if (messenger == null) return;
    final mobile = _isMobile;

    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          width: mobile ? null : 400,
          margin: mobile
              ? const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0)
              : null,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
          elevation: 6,
          content: Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  _l10n?.tasksInProgress(tasks.length) ?? '${tasks.length} 个任务进行中',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: _l10n?.cancelAll ?? '取消全部',
            onPressed: () {
              for (final task in tasks) {
                task.onCancel?.call();
              }
            },
          ),
          duration: const Duration(hours: 1),
        ),
      );
  }
}

/// 进度 SnackBar 的生命周期句柄。
class SnackBarProgressHandle {
  final VoidCallback _dismiss;
  final void Function(
    String? finishMessage,
    SnackBarAction? finishAction,
    Duration? finishDuration,
  ) _finish;

  SnackBarProgressHandle._(this._dismiss, this._finish);

  /// 关闭 SnackBar 但不展示结果（例如中途取消）。
  void dismiss() => _dismiss();

  /// 结束进度态。若 [message] 非空，关闭后以结果态展示一条短消息；
  /// [action] 用于给结果 SnackBar 附加按钮（如"前往设置"/"去添加"）。
  void finish({
    String? message,
    SnackBarAction? action,
    Duration? duration,
  }) =>
      _finish(message, action, duration);
}
