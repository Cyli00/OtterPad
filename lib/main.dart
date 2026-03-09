import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/storage/storage.dart';
import 'providers/proxy_provider.dart';
import 'providers/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-Edge 沉浸式
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // 初始化 pdfrx（注册 loadAsset 回调 + 初始化 PDFium 引擎）
  await pdfrxFlutterInitialize();

  // 并行初始化
  final results = await Future.wait([
    SharedPreferences.getInstance(),
    GStorage.init(),
  ]);
  final prefs = results[0] as SharedPreferences;

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ],
  );

  // 初始化代理配置
  container.read(proxyProvider.notifier).applyInitial();

  runApp(UncontrolledProviderScope(
    container: container,
    child: const NightReaderApp(),
  ));
}
