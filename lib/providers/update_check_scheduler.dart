import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_logger.dart';
import '../router/app_router.dart';
import '../services/update_flow.dart';
import '../services/update_service.dart';

/// 启动时自动检查一次更新（Rust 延迟 3 秒后检查），不做周期性轮询。
class UpdateCheckScheduler {
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    unawaited(_tick());
  }

  /// 开关与已忽略版本由 Rust 判断；需要提示时才返回结果。
  Future<void> _tick() async {
    UpdateInfo? info;
    try {
      info = await UpdateService.checkAfterStartup();
    } catch (e) {
      log.w('[UpdateCheck] 自动检查失败：$e');
      return;
    }
    if (info == null) return;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await presentUpdateDialog(context: ctx, info: info);
  }
}

final updateCheckSchedulerProvider = Provider<UpdateCheckScheduler>((ref) {
  return UpdateCheckScheduler();
});
