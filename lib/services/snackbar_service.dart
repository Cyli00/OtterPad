import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    messenger
      ..hideCurrentSnackBar()
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
      ..hideCurrentSnackBar()
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
}
