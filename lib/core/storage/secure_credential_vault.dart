import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/app_logger.dart';
import 'storage.dart';
import '../../src/rust/api.dart';
import '../../src/rust/credentials.dart';
import '../../src/rust/error.dart';

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

  // macOS 应用是 ad-hoc 签名、没有 keychain-access-groups，数据保护钥匙串会报
  // -34018；改用登录钥匙串，沙箱应用无需额外权限即可读写。
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  /// 启动时由 [init] 填充的内存缓存——[read] 的同步数据源。
  static final Map<String, String> _cache = {};

  static Backend? _backend;

  /// 已存凭据的键名（不含值）。登录钥匙串不支持批量读取，启动时据此逐个读。
  static const _indexKey = 'credential_keys';

  static Set<String> get _index =>
      {...?(GStorage.setting.get(_indexKey) as List?)?.cast<String>()};

  /// app 启动时调用：读入全部凭据到内存缓存。
  static Future<void> init() async {
    try {
      _cache.addAll(await _storage.readAll());
      return;
    } catch (e) {
      log.d('[SecureCredentialVault] readAll 失败，改为按键读取：$e');
    }
    for (final key in _index) {
      try {
        final value = await _storage.read(key: key);
        if (value != null && value.isNotEmpty) _cache[key] = value;
      } catch (e) {
        log.e('[SecureCredentialVault] 读取凭据失败：$key', error: e);
      }
    }
  }

  /// 设置被备份恢复覆盖后，按内存中的凭据重写键名索引。
  static Future<void> rewriteIndex() =>
      GStorage.setting.put(_indexKey, _cache.keys.toList()..sort());

  static Future<void> _track(String key, {required bool present}) async {
    final index = _index;
    if (present ? index.add(key) : index.remove(key)) {
      await GStorage.setting.put(_indexKey, index.toList()..sort());
    }
  }

  /// 把已有凭据注入 Rust 后端，此后的写入与删除同步注入；Rust 只在内存中持有。
  static Future<void> attach(Backend backend) async {
    _backend = backend;
    for (final e in _cache.entries) {
      await _inject(e.key, e.value);
    }
  }

  static Future<void> _inject(String key, String value) async {
    try {
      await _backend?.injectCredentials(
        entries: [CredentialInput(key: key, value: value)],
      );
    } on OtterError catch (e) {
      // Rust 不使用的凭据键会被拒绝，这些键只留在 Dart 侧。
      if (e.code != ErrorCode.invalidArgument) rethrow;
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
    await _inject(key, value);
    await _storage.write(key: key, value: value);
    await _track(key, present: true);
  }

  /// 删除凭据（内存缓存 + 安全存储）。
  static Future<void> delete(String key) async {
    _cache.remove(key);
    await _inject(key, '');
    await _storage.delete(key: key);
    await _track(key, present: false);
  }
}
