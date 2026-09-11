import 'dart:convert';

import 'app_database.dart' as db;

/// settings 的 Drift 后端 + 同步读缓存（G2/Q4 决策）。
///
/// 对外刻意**模仿 Hive `Box` API**（get/put/containsKey/keys/delete/clear），
/// 让遍布全仓的 `GStorage.setting.get/put` 调用点零改动。value 列存 JSON
/// 文本，缓存存解码后的对象——`as bool?`/`as String?`/`as List?`/`as Map?`
/// 全部继续可用。
class SettingsStore {
  final db.AppDatabase _db;
  final Map<String, Object?> _cache = {};

  SettingsStore(this._db);

  /// 同步读。键存在（即便值为 null）返回其值；不存在返回 [defaultValue]。
  Object? get(String key, {Object? defaultValue}) =>
      _cache.containsKey(key) ? _cache[key] : defaultValue;

  bool containsKey(String key) => _cache.containsKey(key);

  Iterable<String> get keys => _cache.keys;

  /// 数据库写成功后更新缓存，避免写入失败却显示新值。
  Future<void> put(String key, Object? value) async {
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          db.SettingsCompanion.insert(
            settingKey: key,
            value: jsonEncode(value),
          ),
        );
    _cache[key] = value;
  }

  Future<void> delete(String key) async {
    await (_db.delete(
      _db.settings,
    )..where((t) => t.settingKey.equals(key))).go();
    _cache.remove(key);
  }

  Future<void> clear() async {
    await _db.delete(_db.settings).go();
    _cache.clear();
  }

  /// 启动时一次性加载全部 settings 到缓存。
  Future<void> preload() async {
    final rows = await _db.select(_db.settings).get();
    _cache
      ..clear()
      ..addEntries([
        for (final r in rows) MapEntry(r.settingKey, _decode(r.value)),
      ]);
  }

  static Object? _decode(String raw) {
    if (raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }
}
