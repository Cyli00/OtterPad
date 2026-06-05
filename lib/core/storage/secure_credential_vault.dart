import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'storage.dart';

/// 凭据安全保险库——所有 API key / secret / 密码的唯一存取接缝。
///
/// 设计要点：
/// - **同步读、异步写**：现有各 Notifier 在构造里同步 `_load()`（`box.get(...)`），
///   无法 await，而 [FlutterSecureStorage] 只有异步 API。[init] 在 app 启动时把
///   全部凭据一次性读进内存缓存，[read] 从缓存同步返回，匹配既有同步加载模式；
///   写入走异步 [write]/[delete]，匹配既有 async `save()`/`setApiKey()`。
/// - **明文迁移**：历史版本把凭据明文写在 Hive setting box；[init] 启动时把它们
///   搬进安全存储并从 Hive 删除——之后备份（打包 Hive box）不再含任何明文 secret。
/// - **平台后端**：Android Keystore / iOS·macOS Keychain / Windows DPAPI /
///   Linux libsecret。
///
/// 禁止任何调用点绕过本模块直接把 secret 写进 [GStorage]。
class SecureCredentialVault {
  SecureCredentialVault._();

  static const _storage = FlutterSecureStorage();

  /// 启动时由 [init] 填充的内存缓存——[read] 的同步数据源。
  static final Map<String, String> _cache = {};

  /// 需要从 Hive 明文迁移的固定凭据键。
  static const _legacyFixedKeys = <String>{
    'doc_extract_api_key',
    'backup_s3_secret_access_key',
    'backup_webdav_password',
    'zotero_api_key',
  };

  /// 动态凭据键前缀（Agent 每实例一个 `agent_api_key_<id>`）。
  static const _legacyPrefixes = <String>['agent_api_key_'];

  /// 某个 setting key 是否属于应迁出 Hive 的凭据。供 [BackupMergeService] 复用，
  /// 让旧备份里的明文 key 不被重新导入。
  static bool isCredentialKey(String key) =>
      _legacyFixedKeys.contains(key) ||
      _legacyPrefixes.any((prefix) => key.startsWith(prefix));

  /// app 启动时调用（[GStorage.init] 之后）：读入全部凭据缓存 + 迁移历史明文。
  static Future<void> init() async {
    try {
      _cache.addAll(await _storage.readAll());
    } catch (e) {
      debugPrint('[SecureCredentialVault] readAll 失败：$e');
    }
    await _migrateFromHive();
  }

  /// 一次性把 Hive setting box 里的明文凭据搬进安全存储并删除原值。幂等：
  /// 安全存储已有同名键则不覆盖；单条写失败保留 Hive 原值，下次启动重试。
  static Future<void> _migrateFromHive() async {
    final box = GStorage.setting;
    final keys = box.keys.whereType<String>().where(isCredentialKey).toList();
    for (final key in keys) {
      final value = box.get(key);
      if (value is String && value.isNotEmpty && !_cache.containsKey(key)) {
        try {
          await _storage.write(key: key, value: value);
          _cache[key] = value;
        } catch (e) {
          debugPrint('[SecureCredentialVault] 迁移 $key 失败：$e');
          continue; // 保留 Hive 原值，下次启动再试
        }
      }
      await box.delete(key);
    }
  }

  /// 同步读取凭据（来自启动时填充的内存缓存）。缺失返回 ''。
  static String read(String key) => _cache[key] ?? '';

  /// 写入凭据（内存缓存 + 安全存储）。空串等价于 [delete]。
  static Future<void> write(String key, String value) async {
    if (value.isEmpty) {
      await delete(key);
      return;
    }
    _cache[key] = value;
    await _storage.write(key: key, value: value);
  }

  /// 删除凭据（内存缓存 + 安全存储）。
  static Future<void> delete(String key) async {
    _cache.remove(key);
    await _storage.delete(key: key);
  }
}
