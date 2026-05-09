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
  static late Box _historyBox;
  static late String _dataDirPath;
  static bool _initialized = false;

  static Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    final appRoot = Directory(p.join(appDir.path, 'OtterPad'));
    final dataDir = Directory(p.join(appRoot.path, 'data'));
    if (!await dataDir.exists()) {
      await dataDir.create(recursive: true);
    }
    _dataDirPath = dataDir.path;
    if (!_initialized) {
      Hive.init(dataDir.path);
      _initialized = true;
    }
    await _openBoxes();
    await _migrateLegacyAppPaths(appDir.path, appRoot.path);
    // 高亮数据保留（Phase 1 WebView 标注系统已启用）
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
      Hive.isBoxOpen('settings')
          ? Future.value(Hive.box('settings'))
          : Hive.openBox('settings'),
      Hive.isBoxOpen('favorites')
          ? Future.value(Hive.box('favorites'))
          : Hive.openBox('favorites'),
      Hive.isBoxOpen('documents')
          ? Future.value(Hive.box('documents'))
          : Hive.openBox('documents'),
      Hive.isBoxOpen('highlights')
          ? Future.value(Hive.box('highlights'))
          : Hive.openBox('highlights'),
      Hive.isBoxOpen('history')
          ? Future.value(Hive.box('history'))
          : Hive.openBox('history'),
    ]);
    _settingBox = results[0];
    _favoritesBox = results[1];
    _documentsBox = results[2];
    _highlightsBox = results[3];
    _historyBox = results[4];
  }

  static Future<void> _migrateLegacyAppPaths(
    String appDocumentsPath,
    String currentAppRoot,
  ) async {
    final legacyAppRoot = p.join(appDocumentsPath, 'NightReader');
    if (p.equals(legacyAppRoot, currentAppRoot)) return;

    final boxes = [
      _settingBox,
      _favoritesBox,
      _documentsBox,
      _highlightsBox,
      _historyBox,
    ];
    for (final box in boxes) {
      for (final key in box.keys.toList()) {
        final value = box.get(key);
        final migrated = _replaceLegacyPath(
          value,
          legacyAppRoot,
          currentAppRoot,
        );
        if (!identical(migrated, value)) {
          await box.put(key, migrated);
        }
      }
    }
  }

  static dynamic _replaceLegacyPath(
    dynamic value,
    String legacyAppRoot,
    String currentAppRoot,
  ) {
    if (value is String) {
      final migrated = value
          .replaceAll(legacyAppRoot, currentAppRoot)
          .replaceAll(_jsonPath(legacyAppRoot), _jsonPath(currentAppRoot));
      return migrated == value ? value : migrated;
    }

    if (value is List) {
      var changed = false;
      final migrated = value.map((item) {
        final next = _replaceLegacyPath(item, legacyAppRoot, currentAppRoot);
        changed = changed || !identical(next, item);
        return next;
      }).toList();
      return changed ? migrated : value;
    }

    if (value is Map) {
      var changed = false;
      final migrated = <dynamic, dynamic>{};
      value.forEach((key, item) {
        final nextKey = _replaceLegacyPath(key, legacyAppRoot, currentAppRoot);
        final nextValue = _replaceLegacyPath(
          item,
          legacyAppRoot,
          currentAppRoot,
        );
        changed =
            changed || !identical(nextKey, key) || !identical(nextValue, item);
        migrated[nextKey] = nextValue;
      });
      return changed ? migrated : value;
    }

    return value;
  }

  static String _jsonPath(String path) => path.replaceAll(r'\', r'\\');

  static Future<void> flush() async {
    final futures = <Future<void>>[];
    if (Hive.isBoxOpen('settings')) futures.add(Hive.box('settings').flush());
    if (Hive.isBoxOpen('favorites')) futures.add(Hive.box('favorites').flush());
    if (Hive.isBoxOpen('documents')) futures.add(Hive.box('documents').flush());
    if (Hive.isBoxOpen('highlights')) {
      futures.add(Hive.box('highlights').flush());
    }
    if (Hive.isBoxOpen('history')) futures.add(Hive.box('history').flush());
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
  static Box get history => _historyBox;
  static String get dataDirPath => _dataDirPath;
}
