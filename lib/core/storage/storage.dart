import 'package:hive_flutter/hive_flutter.dart';

/// 全局键值存储单例（Hive）
class GStorage {
  static late Box _settingBox;
  static late Box _favoritesBox;

  static Future<void> init() async {
    await Hive.initFlutter();
    final results = await Future.wait([
      Hive.openBox('settings'),
      Hive.openBox('favorites'),
    ]);
    _settingBox = results[0];
    _favoritesBox = results[1];
  }

  static Box get setting => _settingBox;
  static Box get favorites => _favoritesBox;
}
