import '../core/storage/credential_vault.dart';
import '../core/storage/settings_keys.dart';
import '../core/storage/storage.dart';

enum WebSearchProvider { tavily, exa, brave }

/// 外部联网搜索的服务商与密钥设置；搜索本身由 Rust 在问 AI 时执行。
/// 密钥键名与 Rust 一致（`tavily_api_key`、`exa_search_api_key`、`brave_search_api_key`）。
class WebSearchService {
  static WebSearchProvider get provider => WebSearchProvider.values.firstWhere(
    (p) => p.name == GStorage.setting.get(SettingsKeys.webSearchProvider),
    orElse: () => WebSearchProvider.tavily,
  );

  static Future<void> setProvider(WebSearchProvider value) =>
      GStorage.setting.put(SettingsKeys.webSearchProvider, value.name);

  static String _vaultKey(WebSearchProvider provider) =>
      provider == WebSearchProvider.tavily
      ? 'tavily_api_key'
      : '${provider.name}_search_api_key';

  static String keyFor(WebSearchProvider provider) =>
      CredentialVault.read(_vaultKey(provider));

  static Future<void> setKey(WebSearchProvider provider, String key) =>
      CredentialVault.write(_vaultKey(provider), key.trim());

  static bool get isConfigured => keyFor(provider).isNotEmpty;
}
