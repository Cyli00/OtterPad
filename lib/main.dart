import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/app_logger.dart';
import 'core/rust_backend.dart';
import 'core/storage/secure_credential_vault.dart';
import 'core/storage/settings_keys.dart';
import 'core/storage/storage.dart';
import 'pages/startup/startup_app.dart';
import 'providers/auto_backup_provider.dart';
import 'providers/proxy_provider.dart';
import 'providers/update_check_scheduler.dart';
import 'services/model_capability_store.dart';
import 'services/back_matter_detector.dart';
import 'services/display_metrics.dart';
import 'services/figure_extract_service.dart';
import 'services/haptics.dart';
import 'services/reader_localhost_server.dart';
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

  // 初始化 pdfrx（注册 loadAsset 回调 + 初始化 PDFium 引擎）
  await pdfrxFlutterInitialize();

  // 并行初始化
  await Future.wait([
    GStorage.init(backend: backend),
    BackMatterDetector.instance.init(),
    // figure 提取的 caption 正则配置预热——避免 saveResult 路径里隐式首次
    // init() 的加载延迟与“忘记初始化 → 运行时断言”隐患（init 内部幂等）。
    FigureExtractService.instance.init(),
  ]);

  // 模型能力规则集（geosite 订阅）：加载本地缓存（依赖 GStorage.dbDirPath），
  // 后台按 TTL 检查远程更新（不阻塞启动）。
  await ModelCapabilityStore.instance.init();
  unawaited(ModelCapabilityStore.instance.checkUpdateIfNeeded());

  // 凭据安全存储：必须在 GStorage.init 之后、任何 provider 读取凭据之前完成——
  // 同步 read() 依赖此处填充的内存缓存。
  await SecureCredentialVault.init();
  await SecureCredentialVault.attach(backend);

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

  // 阅读器本地静态文件服务——必须在 GStorage.init 后启动
  // （依赖 GStorage.appRootPath 作为 documentRoot）。
  // root 用 `<AppSupport>/OtterPad/`（db/ 与 library/ 的共同父），所有
  // 文献子目录与 hive 数据库都在 root 下；HTML 现在自包含到
  // `library/<documentId>/.reader.html`，与同目录 figures/ 共 origin 加载。
  // 单例进程级，整个 app 生命周期共享。
  await ReaderLocalhostServer.instance.start(
    documentRoot: GStorage.appRootPath,
  );

  final container = ProviderContainer();

  // 初始化代理配置
  container.read(proxyProvider.notifier).applyInitial();

  // 自动备份调度：启动 2 分钟后首查，之后每小时检查一次到期与变更
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
