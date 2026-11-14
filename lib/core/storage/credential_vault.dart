import '../../src/rust/api.dart';
import '../../src/rust/credentials.dart';

/// 凭据（API key / secret / 密码）的唯一存取接缝。数据由 Rust 存在数据根的
/// `credentials.json`（0600，与 `v2/` 并列，不进入备份包），不使用系统钥匙串。
///
/// **同步读、异步写**：各 Notifier 在构造里同步加载，[open] 在启动时把凭据读进内存，
/// [read] 从缓存同步返回；[write]/[delete] 先写 Rust，成功后再更新缓存。
///
/// 禁止任何调用点绕过本模块直接把 secret 写进 [GStorage]。
class CredentialVault {
  CredentialVault._();

  static final Map<String, String> _cache = {};
  static Backend? _backend;

  /// app 启动时、任何 provider 读取凭据之前调用。
  static Future<void> open(Backend backend) async {
    _backend = backend;
    final entries = await backend.credentials();
    _cache
      ..clear()
      ..addAll({for (final e in entries) e.key: e.value});
  }

  /// 同步读取凭据。缺失返回 ''。
  static String read(String key) => _cache[key] ?? '';

  /// 写入凭据；空串等价于 [delete]。
  static Future<void> write(String key, String value) async {
    final backend = _backend ?? (throw StateError('CredentialVault.open 尚未调用'));
    await backend.injectCredentials(
      entries: [CredentialInput(key: key, value: value)],
    );
    if (value.isEmpty) {
      _cache.remove(key);
    } else {
      _cache[key] = value;
    }
  }

  static Future<void> delete(String key) => write(key, '');
}
