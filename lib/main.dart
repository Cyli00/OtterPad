import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/services/service_locator.dart';
import 'core/storage/storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化键值存储
  await GStorage.init();

  // 注册全局依赖（GetX DI）
  await ServiceLocator.init();

  runApp(const NightReaderApp());
}
