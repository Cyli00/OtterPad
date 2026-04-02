import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 全局键值存储单例（Hive）
class GStorage {
  static late Box _settingBox;
  static late Box _favoritesBox;
  static late Box _documentsBox;
  static late Box _highlightsBox;
  static late String _dataDirPath;
  static bool _initialized = false;

  static Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dataDir = Directory(p.join(appDir.path, 'NightReader', 'data'));
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }
    _dataDirPath = dataDir.path;
    if (!_initialized) {
      Hive.init(dataDir.path);
      _initialized = true;
    }
    await _openBoxes();
    // 清空旧版标记数据（功能已移除，待重新设计）
    if (_highlightsBox.isNotEmpty) await _highlightsBox.clear();
  }

  static Future<void> reopen() async {
    if (!_initialized) {
      await init();
      return;
    }
    await _openBoxes();
  }

  static Future<void> _openBoxes() async {
    final results = await Future.wait([
      Hive.isBoxOpen('settings') ? Future.value(Hive.box('settings')) : Hive.openBox('settings'),
      Hive.isBoxOpen('favorites') ? Future.value(Hive.box('favorites')) : Hive.openBox('favorites'),
      Hive.isBoxOpen('documents') ? Future.value(Hive.box('documents')) : Hive.openBox('documents'),
      Hive.isBoxOpen('highlights') ? Future.value(Hive.box('highlights')) : Hive.openBox('highlights'),
    ]);
    _settingBox = results[0];
    _favoritesBox = results[1];
    _documentsBox = results[2];
    _highlightsBox = results[3];
  }

  static Future<void> flush() async {
    final futures = <Future<void>>[];
    if (Hive.isBoxOpen('settings')) futures.add(Hive.box('settings').flush());
    if (Hive.isBoxOpen('favorites')) futures.add(Hive.box('favorites').flush());
    if (Hive.isBoxOpen('documents')) futures.add(Hive.box('documents').flush());
    if (Hive.isBoxOpen('highlights')) futures.add(Hive.box('highlights').flush());
    await Future.wait(futures);
  }

  static Future<void> close() async {
    if (!_initialized) return;
    await Hive.close();
  }

  static Box get setting => _settingBox;
  static Box get favorites => _favoritesBox;
  static Box get documents => _documentsBox;
  static Box get highlights => _highlightsBox;
  static String get dataDirPath => _dataDirPath;
}
