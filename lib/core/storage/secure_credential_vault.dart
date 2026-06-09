import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/app_logger.dart';

/// 凭据安全保险库——所有 API key / secret / 密码的唯一存取接缝。
///
/// **同步读、异步写**：现有各 Notifier 在构造里同步 `_load()`（`box.get(...)`），
/// 无法 await，而 [FlutterSecureStorage] 只有异步 API。[init] 在 app 启动时把
/// 全部凭据一次性读进内存缓存，[read] 从缓存同步返回，匹配既有同步加载模式；
/// 写入走异步 [write]/[delete]，匹配既有 async `save()`/`setApiKey()`。
///
/// **平台后端**：Android Keystore / iOS·macOS Keychain / Windows DPAPI /
/// Linux libsecret。
///
/// 禁止任何调用点绕过本模块直接把 secret 写进 [GStorage]。
class SecureCredentialVault {
  SecureCredentialVault._();

  static const _storage = FlutterSecureStorage();

  /// 启动时由 [init] 填充的内存缓存——[read] 的同步数据源。
  static final Map<String, String> _cache = {};

  /// app 启动时调用：读入全部凭据到内存缓存。
  static Future<void> init() async {
    try {
      _cache.addAll(await _storage.readAll());
    } catch (e) {
      log.d('[SecureCredentialVault] readAll 失败：$e');
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
