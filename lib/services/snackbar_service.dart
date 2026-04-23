import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// 全局 ScaffoldMessenger Key，挂载在 MaterialApp.router 上，
/// 使 SnackBar 跨页面导航持续显示。
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

final snackBarServiceProvider = Provider<SnackBarService>((ref) {
  return SnackBarService(scaffoldMessengerKey);
});

/// 统一 SnackBar 服务
///
/// 通过 [scaffoldMessengerKey] 访问根级 ScaffoldMessenger，
/// 不依赖页面级 BuildContext，确保 SnackBar 在任何导航状态下可用。
class SnackBarService {
  final GlobalKey<ScaffoldMessengerState> _key;

  SnackBarService(this._key);

  ScaffoldMessengerState? get _messenger => _key.currentState;

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
                            status ?? '处理中...',
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
          action: SnackBarAction(label: '取消', onPressed: onCancel),
          duration: duration,
        ),
      );
  }

  /// 结果/信息型 SnackBar：文字消息 + 可选操作按钮
  void showResult({
    required String message,
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
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
          content: Text(message, style: const TextStyle(fontSize: 14)),
          action: action,
          duration: duration,
        ),
      );
  }

  /// 隐藏当前 SnackBar
  void hide() {
    _messenger?.hideCurrentSnackBar();
  }

  /// 以 [ValueListenable] 驱动内容的进度 SnackBar。
  ///
  /// 相比 [showProgress]，本方法**只 show 一次** SnackBar，后续内容更新
  /// 通过 `ValueListenableBuilder` 驱动。适合高频进度更新场景
  /// （例如文档级批量翻译）——进度事件再快也不会被 ScaffoldMessenger
  /// 的 queue 机制吞掉：每帧内 notifier 的最终值必定上屏。
  ///
  /// 返回的 [SnackBarProgressHandle] 用于翻译完成/失败时主动收尾。
  SnackBarProgressHandle showListenableProgress({
    required ValueListenable<ListenableProgress> listenable,
    VoidCallback? onCancel,
    Duration duration = const Duration(hours: 1),
  }) {
    final messenger = _messenger;
    if (messenger == null) {
      return SnackBarProgressHandle._(() {}, (_, _, _) {});
    }

    final mobile = _isMobile;

    messenger.clearSnackBars();
    messenger.showSnackBar(
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
          valueListenable: listenable,
          // 完成态：左侧图标由 spinner 切成对勾，避免"翻译完成但还在转圈"
          // 的视觉 bug——ScaffoldMessenger 的 hide/show 动画有 ~250ms
          // 窗口，这段时间仍在显示当前 SnackBar 的 content。
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
            : SnackBarAction(label: '取消', onPressed: onCancel),
        duration: duration,
      ),
    );

    return SnackBarProgressHandle._(
      () => messenger.hideCurrentSnackBar(),
      (msg, action, duration) {
        // 先 hide 进度 SnackBar，再 show 结果 SnackBar。
        // showResult 内部会 clearSnackBars 把进度 SnackBar 排掉。
        if (msg != null) {
          showResult(
            message: msg,
            action: action,
            duration: duration ?? const Duration(seconds: 4),
          );
        } else {
          messenger.clearSnackBars();
        }
      },
    );
  }
}

/// [SnackBarService.showListenableProgress] 使用的通用进度数据。
class ListenableProgress {
  final int current;
  final int total;
  final String status;

  const ListenableProgress({
    required this.current,
    required this.total,
    required this.status,
  });
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
