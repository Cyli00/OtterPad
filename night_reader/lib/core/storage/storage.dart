import 'package:hive_flutter/hive_flutter.dart';

/// 全局键值存储单例（Hive）
class GStorage {
  static late Box _settingBox;

  static Future<void> init() async {
    await Hive.initFlutter();
    _settingBox = await Hive.openBox('settings');
  }

  static Box get setting => _settingBox;
}
