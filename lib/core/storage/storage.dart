import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 全局键值存储单例（Hive）
class GStorage {
  static late Box _settingBox;
  static late Box _favoritesBox;

  static late Box _documentsBox;

  static Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dataDir = Directory(p.join(appDir.path, 'NightReader', 'data'));
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }
    Hive.init(dataDir.path);
    final results = await Future.wait([
      Hive.openBox('settings'),
      Hive.openBox('favorites'),
      Hive.openBox('documents'),
    ]);
    _settingBox = results[0];
    _favoritesBox = results[1];
    _documentsBox = results[2];
  }

  static Box get setting => _settingBox;
  static Box get favorites => _favoritesBox;
  static Box get documents => _documentsBox;
}
