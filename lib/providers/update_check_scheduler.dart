import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_logger.dart';
import '../core/storage/storage.dart';
import '../router/app_router.dart';
import '../services/update_flow.dart';
import '../services/update_service.dart';

/// 启动时自动检查一次更新。只查一次，不做周期性轮询——
/// 与 `AutoBackupScheduler` 同一挂载方式（main 初始化链路调用 [start]）。
class UpdateCheckScheduler {
  Timer? _initial;

  void start() {
    _initial ??= Timer(const Duration(seconds: 3), _tick);
  }

  void dispose() {
    _initial?.cancel();
  }

  Future<void> _tick() async {
    final autoCheck =
        GStorage.setting.get('general_auto_check_update') as bool? ?? true;
    if (!autoCheck) return;

    UpdateInfo info;
    try {
      info = await UpdateService.instance.checkForUpdate();
    } catch (e) {
      log.w('[UpdateCheck] 自动检查失败：$e');
      return;
    }
    if (!info.hasUpdate) return;
    // 用户忽略过的版本不再自动弹（手动检查不受此限制）
    if (UpdateService.getIgnoredVersion() == info.remoteVersion) return;

    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await presentUpdateDialog(context: ctx, info: info);
  }
}

final updateCheckSchedulerProvider = Provider<UpdateCheckScheduler>((ref) {
  final scheduler = UpdateCheckScheduler();
  ref.onDispose(scheduler.dispose);
  return scheduler;
});
