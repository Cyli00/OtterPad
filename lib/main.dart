import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/app_logger.dart';
import 'core/rust_backend.dart';
import 'core/storage/credential_vault.dart';
import 'core/storage/settings_keys.dart';
import 'core/storage/storage.dart';
import 'pages/startup/startup_app.dart';
import 'providers/auto_backup_provider.dart';
import 'providers/favorites_provider.dart';
import 'providers/update_check_scheduler.dart';
import 'services/model_capability_store.dart';
import 'services/prompts.dart';
import 'services/display_metrics.dart';
import 'services/haptics.dart';
import 'services/share_receiver_service.dart';
import 'services/storage_usage_service.dart';
import 'src/rust/api.dart';

bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-Edge 沉浸式（仅对移动端生效，桌面是 no-op）
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // 桌面：隐藏原生标题栏，改由 WindowChrome 提供自定义 chrome
  if (_isDesktop) {
    await windowManager.ensureInitialized();
    // 窗口尺寸由主显示器分辨率推导：逻辑分辨率（系统缩放后的分辨率）决定
    // 布局可用宽度，可用工作区（扣任务栏 / Dock）决定上限——避免小屏上初始
    // 窗口超出屏幕、大屏上最小尺寸过小失去约束意义
    final display = await queryPrimaryDisplay();
    final minimumSize = resolveWindowMinimumSize(display);
    final windowOptions = WindowOptions(
      size: resolveInitialWindowSize(display, minimumSize),
      minimumSize: minimumSize,
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: 'OtterPad',
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // Rust 后端最先打开：设置以它为准，首次启动在此迁移 0.1.x 数据。
  final backend = await _startBackend();
  if (backend == null) return;

  await GStorage.init(backend);
  await Prompts.load();

  // 模型能力表：读取 Rust 缓存，后台按日由 Rust 检查更新（不阻塞启动）。
  await ModelCapabilityStore.instance.init();
  unawaited(ModelCapabilityStore.instance.checkUpdateIfNeeded());

  await ensureDefaultFavorite(backend);

  // 凭据：必须在任何 provider 读取凭据之前完成——同步 read() 依赖此处填充的内存缓存。
  await CredentialVault.open(backend);

  // 应用通用设置中的持久化偏好
  final hapticsOn =
      GStorage.setting.get(SettingsKeys.hapticsEnabled) as bool? ?? true;
  Haptics.setEnabled(hapticsOn);

  // 缓存自动清理（fire-and-forget，不阻塞启动）
  final cacheCleanup =
      GStorage.setting.get(SettingsKeys.cacheAutoCleanup) as bool? ?? false;
  if (cacheCleanup) {
    StorageUsageService.clearGroups({StorageGroupKey.cache});
  }

  final container = ProviderContainer();

  // 自动备份：Rust 在启动 2 分钟后首查、之后每小时按周期与文献变更判断。
  container.read(autoBackupSchedulerProvider).start();

  // 检查更新：启动 3 秒后自动检查一次（受"启动时检查更新"设置开关控制）
  container.read(updateCheckSchedulerProvider).start();

  // 移动端：接收分享/打开 PDF 文件的 intent
  ShareReceiverService? shareReceiver;
  if (!_isDesktop) {
    shareReceiver = ShareReceiverService(container);
  }

  runApp(
    UncontrolledProviderScope(container: container, child: const OtterPadApp()),
  );

  // 首帧后查询冷启动时携带的待导入文件
  if (shareReceiver != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      shareReceiver!.checkInitialSharedFiles();
    });
  }
}

/// 打开 Rust 后端。迁移 0.1.x 数据时显示进度；打开失败时停在错误页并返回 null。
Future<Backend?> _startBackend() async {
  final root = p.join(
    (await getApplicationSupportDirectory()).path,
    'OtterPad',
  );
  final status = ValueNotifier(const StartupStatus());
  var shown = false;
  await for (final event in RustBackend.start(root)) {
    switch (event) {
      case InitializationEvent_Migration(:final progress):
        status.value = StartupStatus(
          done: progress.done.toInt(),
          total: progress.total.toInt(),
        );
        if (!shown) {
          shown = true;
          runApp(StartupApp(status));
        }
      case InitializationEvent_Failed(:final error):
        log.e('[Startup] Rust 后端打开失败：${error.code.name} ${error.detail}');
        status.value = StartupStatus(failure: error.code);
        runApp(StartupApp(status));
        return null;
      case InitializationEvent_Ready(:final migrationError):
        // 迁移失败不阻塞启动：已完成的文献可用，下次启动从未完成处继续。
        if (migrationError != null) {
          log.w('[Startup] 0.1.x 数据迁移未完成：${migrationError.name}');
        }
        return RustBackend.instance;
    }
  }
  return null;
}
