import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/storage/storage.dart';
import 'providers/proxy_provider.dart';
import 'services/agent_model_capability.dart';

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
      title: '獭祭鱼 OtterPad',
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
  ]);

  final container = ProviderContainer();

  // 初始化代理配置
  container.read(proxyProvider.notifier).applyInitial();

  runApp(UncontrolledProviderScope(
    container: container,
    child: const OtterPadApp(),
  ));
}
