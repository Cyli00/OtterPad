import 'storage_activity.dart';
import 'dart:convert';

import '../../src/rust/api.dart';
import 'app_database.dart' as db;
import 'json_data.dart';

/// settings 的同步读缓存（G2/Q4 决策）；有 Rust 后端时以 Rust 设置表为准。
///
/// 对外刻意**模仿 Hive `Box` API**（get/put/containsKey/keys/delete/clear），
/// 让遍布全仓的 `GStorage.setting.get/put` 调用点零改动。缓存存解码后的对象——
/// `as bool?`/`as String?`/`as List?`/`as Map?` 全部继续可用。
///
/// 过渡期 drift 的 settings 表仍同步写入：旧 Dart 备份直接拷贝 drift 库，
/// 恢复直接改写该表后由 [adoptMirror] 推回 Rust。备份迁到 Rust 后移除。
class SettingsStore {
  final db.AppDatabase _db;
  final Backend? _backend;
  final Map<String, Object?> _cache = {};

  SettingsStore(this._db, {this._backend});

  /// 同步读。键存在（即便值为 null）返回其值；不存在返回 [defaultValue]。
  Object? get(String key, {Object? defaultValue}) =>
      _cache.containsKey(key) ? _cache[key] : defaultValue;

  bool containsKey(String key) => _cache.containsKey(key);

  Iterable<String> get keys => _cache.keys;

  /// 持久化成功后更新缓存，避免写入失败却显示新值。
  Future<void> put(String key, Object? value) => StorageActivity.run(() async {
    await _backend?.putSetting(key: key, value: toJsonData(value));
    await _mirrorPut(key, value);
    _cache[key] = value;
  });

  Future<void> delete(String key) => StorageActivity.run(() async {
    await _backend?.deleteSetting(key: key);
    await (_db.delete(
      _db.settings,
    )..where((t) => t.settingKey.equals(key))).go();
    _cache.remove(key);
  });

  Future<void> clear() => StorageActivity.run(() async {
    for (final key in _cache.keys.toList()) {
      await _backend?.deleteSetting(key: key);
    }
    await _db.delete(_db.settings).go();
    _cache.clear();
  });

  /// 启动时一次性加载全部 settings 到缓存；有 Rust 后端时用它刷新 drift 副本。
  Future<void> preload() async {
    final backend = _backend;
    if (backend == null) {
      final rows = await _db.select(_db.settings).get();
      _cache
        ..clear()
        ..addEntries([
          for (final r in rows) MapEntry(r.settingKey, decodeRaw(r.value)),
        ]);
      return;
    }
    final entries = await backend.settings();
    _cache
      ..clear()
      ..addEntries([
        for (final e in entries) MapEntry(e.key, fromJsonData(e.value)),
      ]);
    await _db.transaction(() async {
      await _db.delete(_db.settings).go();
      for (final e in _cache.entries) {
        await _mirrorPut(e.key, e.value);
      }
    });
  }

  /// 旧备份恢复改写 drift 的 settings 表之后，以该表为准替换 Rust 设置与缓存。
  Future<void> adoptMirror() async {
    final rows = await _db.select(_db.settings).get();
    final restored = {for (final r in rows) r.settingKey: decodeRaw(r.value)};
    final backend = _backend;
    if (backend != null) {
      for (final e in await backend.settings()) {
        if (!restored.containsKey(e.key)) {
          await backend.deleteSetting(key: e.key);
        }
      }
      for (final e in restored.entries) {
        await backend.putSetting(key: e.key, value: toJsonData(e.value));
      }
    }
    _cache
      ..clear()
      ..addAll(restored);
  }

  Future<void> _mirrorPut(String key, Object? value) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(
        db.SettingsCompanion.insert(settingKey: key, value: jsonEncode(value)),
      );

  static Object? decodeRaw(String raw) {
    if (raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }
}
