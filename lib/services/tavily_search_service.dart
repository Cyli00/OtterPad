import 'package:dio/dio.dart';
import 'proxy_adapter.dart';

import '../core/storage/secure_credential_vault.dart';

/// Tavily 联网搜索——为无原生搜索的兼容端模型（DeepSeek / Doubao /
/// 自建端点等）提供客户端搜索回退：模型经标准 function calling 发起
/// `web_search` 调用，本服务执行真实搜索并回填结果，回环逻辑在
/// AgentChatService 兼容端分支（与 Kimi `$web_search` 同构）。
///
/// API Key 存 [SecureCredentialVault]，本服务是其唯一存取接缝。
class TavilySearchService {
  TavilySearchService._();
  static final TavilySearchService instance = TavilySearchService._();

  static const _vaultKey = 'tavily_api_key';
  static const _endpoint = 'https://api.tavily.com/search';
  static const _maxResults = 5;

  static String get apiKey => SecureCredentialVault.read(_vaultKey);
  static bool get isConfigured => apiKey.isNotEmpty;
  static Future<void> setApiKey(String value) =>
      SecureCredentialVault.write(_vaultKey, value.trim());

  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  /// 接入 `ProxyProvider` 代理总线，签名与其他网络服务一致。
  void applyProxy(Enum mode, String host, int port) {
    _dio.httpClientAdapter = buildProxyAdapter(
      mode.name,
      host,
      port,
    );
  }

  /// 执行搜索并把结果排版成模型可读文本。失败返回失败说明而不抛出——
  /// 模型据此告知用户搜索失败，而不是整轮对话报错或凭空臆造结果。
  Future<String> search(String query, {CancelToken? cancelToken}) async {
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        _endpoint,
        data: {'query': query, 'max_results': _maxResults},
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
        cancelToken: cancelToken,
      );
      final results = resp.data?['results'];
      if (results is! List || results.isEmpty) return '（没有搜索到相关结果）';
      final blocks = <String>[];
      for (var i = 0; i < results.length; i++) {
        final r = results[i];
        if (r is! Map<String, dynamic>) continue;
        final published = r['published_date'] as String? ?? '';
        blocks.add(
          [
            '[${i + 1}] ${r['title'] ?? ''}',
            'URL: ${r['url'] ?? ''}',
            if (published.isNotEmpty) '发布时间：$published',
            (r['content'] as String?) ?? '',
          ].join('\n'),
        );
      }
      return blocks.join('\n\n');
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      final reason = e.response != null
          ? 'HTTP ${e.response!.statusCode}'
          : e.type.name;
      return '（搜索失败：$reason）';
    }
  }
}
