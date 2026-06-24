import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/storage/secure_credential_vault.dart';
import 'core/storage/storage.dart';
import 'providers/auto_backup_provider.dart';
import 'providers/proxy_provider.dart';
import 'services/agent_model_capability.dart';
import 'services/back_matter_detector.dart';
import 'services/figure_extract_service.dart';
import 'services/haptics.dart';
import 'services/reader_localhost_server.dart';
import 'services/share_receiver_service.dart';
import 'services/storage_usage_service.dart';

bool get _isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-Edge 沉浸式（仅对移动端生效，桌面是 no-op）
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // 桌面：隐藏原生标题栏，改由 WindowChrome 提供自定义 chrome
  if (_isDesktop) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(720, 480),
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

  // 初始化 pdfrx（注册 loadAsset 回调 + 初始化 PDFium 引擎）
  await pdfrxFlutterInitialize();

  // 并行初始化
  await Future.wait([
    GStorage.init(),
    AgentModelCapability.init(),
    BackMatterDetector.instance.init(),
    // figure 提取的 caption 正则配置预热——避免 saveResult 路径里隐式首次
    // init() 的加载延迟与“忘记初始化 → 运行时断言”隐患（init 内部幂等）。
    FigureExtractService.instance.init(),
  ]);

  // 凭据安全存储：必须在 GStorage.init 之后、任何 provider 读取凭据之前完成——
  // 同步 read() 依赖此处填充的内存缓存。
  await SecureCredentialVault.init();

  // 应用通用设置中的持久化偏好
  final hapticsOn =
      GStorage.setting.get('general_haptics_enabled') as bool? ?? true;
  Haptics.setEnabled(hapticsOn);

  // 缓存自动清理（fire-and-forget，不阻塞启动）
  final cacheCleanup =
      GStorage.setting.get('general_cache_auto_cleanup') as bool? ?? false;
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
