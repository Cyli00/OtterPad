import 'package:dio/dio.dart';

import '../core/storage/secure_credential_vault.dart';
import '../core/storage/settings_keys.dart';
import '../core/storage/storage.dart';
import 'agent_http.dart';
import 'tavily_search_service.dart';

enum WebSearchProvider { tavily, exa, brave }

class WebSearchService {
  static WebSearchProvider get provider => WebSearchProvider.values.firstWhere(
    (p) => p.name == GStorage.setting.get(SettingsKeys.webSearchProvider),
    orElse: () => WebSearchProvider.tavily,
  );

  static Future<void> setProvider(WebSearchProvider value) =>
      GStorage.setting.put(SettingsKeys.webSearchProvider, value.name);

  static String keyFor(WebSearchProvider provider) =>
      provider == WebSearchProvider.tavily
      ? TavilySearchService.apiKey
      : SecureCredentialVault.read('${provider.name}_search_api_key');

  static Future<void> setKey(WebSearchProvider provider, String key) =>
      provider == WebSearchProvider.tavily
      ? TavilySearchService.setApiKey(key)
      : SecureCredentialVault.write(
          '${provider.name}_search_api_key',
          key.trim(),
        );

  static bool get isConfigured => keyFor(provider).isNotEmpty;

  static Future<String> search(String query, {CancelToken? cancelToken}) {
    final selected = provider;
    if (selected == WebSearchProvider.tavily) {
      return TavilySearchService.instance.search(
        query,
        cancelToken: cancelToken,
      );
    }
    return searchWith(
      provider: selected,
      apiKey: keyFor(selected),
      query: query,
      dio: AgentHttp.instance.dio(receiveTimeout: const Duration(seconds: 30)),
      cancelToken: cancelToken,
    );
  }

  static Future<String> searchWith({
    required WebSearchProvider provider,
    required String apiKey,
    required String query,
    required Dio dio,
    CancelToken? cancelToken,
  }) async {
    try {
      final Response<Map<String, dynamic>> response;
      if (provider == WebSearchProvider.brave) {
        response = await dio.get(
          'https://api.search.brave.com/res/v1/web/search',
          queryParameters: {'q': query, 'count': 5},
          options: Options(headers: {'X-Subscription-Token': apiKey}),
          cancelToken: cancelToken,
        );
      } else {
        response = await dio.post(
          'https://api.exa.ai/search',
          data: {
            'query': query,
            'numResults': 5,
            'contents': {
              'text': {'maxCharacters': 2000},
            },
          },
          options: Options(headers: {'x-api-key': apiKey}),
          cancelToken: cancelToken,
        );
      }
      final data = response.data;
      final results = provider == WebSearchProvider.brave
          ? ((data?['web'] as Map?)?['results'])
          : (data?['results']);
      if (results is! List || results.isEmpty) return '（没有搜索到相关结果）';
      return [
        for (final (index, result) in results.indexed)
          if (result is Map)
            '[${index + 1}] ${result['title'] ?? ''}\n'
                'URL: ${result['url'] ?? ''}\n'
                '${result['text'] ?? result['description'] ?? ''}',
      ].join('\n\n');
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      return '（搜索失败：${e.response == null ? e.type.name : 'HTTP ${e.response!.statusCode}'}）';
    }
  }
}
