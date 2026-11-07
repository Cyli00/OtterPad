import '../../src/rust/api.dart';
import 'json_data.dart';

/// Rust 设置表的同步读缓存。
///
/// 对外沿用 Hive `Box` 风格的 get/put/containsKey/keys/delete/clear，缓存存
/// 解码后的对象，`as bool?`/`as String?`/`as List?`/`as Map?` 都可直接使用。
class SettingsStore {
  SettingsStore(this._backend);

  final Backend _backend;
  final Map<String, Object?> _cache = {};

  /// 同步读。键存在（即便值为 null）返回其值；不存在返回 [defaultValue]。
  Object? get(String key, {Object? defaultValue}) =>
      _cache.containsKey(key) ? _cache[key] : defaultValue;

  bool containsKey(String key) => _cache.containsKey(key);

  Iterable<String> get keys => _cache.keys;

  /// 写入成功后才更新缓存，避免写入失败却显示新值。
  Future<void> put(String key, Object? value) async {
    await _backend.putSetting(key: key, value: toJsonData(value));
    _cache[key] = value;
  }

  Future<void> delete(String key) async {
    await _backend.deleteSetting(key: key);
    _cache.remove(key);
  }

  Future<void> clear() async {
    for (final key in _cache.keys.toList()) {
      await _backend.deleteSetting(key: key);
    }
    _cache.clear();
  }

  /// 从 Rust 重新载入全部设置（启动与恢复备份后）。
  Future<void> preload() async {
    final entries = await _backend.settings();
    _cache
      ..clear()
      ..addEntries([
        for (final e in entries) MapEntry(e.key, fromJsonData(e.value)),
      ]);
  }
}
