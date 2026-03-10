// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/storage.dart';

enum AgentApiProvider { openai, anthropic, gemini }

extension AgentApiProviderExt on AgentApiProvider {
  String get label => switch (this) {
        AgentApiProvider.openai => 'OpenAI',
        AgentApiProvider.anthropic => 'Anthropic',
        AgentApiProvider.gemini => 'Gemini',
      };

  String get defaultBaseUrl => switch (this) {
        AgentApiProvider.openai => 'https://api.openai.com/v1',
        AgentApiProvider.anthropic => 'https://api.anthropic.com',
        AgentApiProvider.gemini =>
          'https://generativelanguage.googleapis.com/v1beta',
      };

  String get apiKeyHint => switch (this) {
        AgentApiProvider.openai => 'sk-...',
        AgentApiProvider.anthropic => 'sk-ant-...',
        AgentApiProvider.gemini => 'AI...',
      };
}

// ─── Agent API ───────────────────────────────────────────────────────────────

class AgentApiState {
  final AgentApiProvider provider;
  final String baseUrl;
  final String apiKey;

  const AgentApiState({
    this.provider = AgentApiProvider.openai,
    this.baseUrl = '',
    this.apiKey = '',
  });

  AgentApiState copyWith({
    AgentApiProvider? provider,
    String? baseUrl,
    String? apiKey,
  }) =>
      AgentApiState(
        provider: provider ?? this.provider,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
      );
}

class AgentApiNotifier extends StateNotifier<AgentApiState> {
  static const _providerKey = 'agent_api_provider';
  static const _baseUrlKey = 'agent_api_base_url';
  static const _apiKeyKey = 'agent_api_key';

  AgentApiNotifier() : super(_load());

  static AgentApiState _load() {
    final box = GStorage.setting;
    final provStr = box.get(_providerKey, defaultValue: 'openai') as String;
    final baseUrl = box.get(_baseUrlKey, defaultValue: '') as String;
    final apiKey = box.get(_apiKeyKey, defaultValue: '') as String;

    final provider = AgentApiProvider.values.firstWhere(
      (e) => e.name == provStr,
      orElse: () => AgentApiProvider.openai,
    );

    return AgentApiState(provider: provider, baseUrl: baseUrl, apiKey: apiKey);
  }

  Future<void> setProvider(AgentApiProvider provider) async {
    state = state.copyWith(provider: provider);
    await GStorage.setting.put(_providerKey, provider.name);
  }

  Future<void> setBaseUrl(String url) async {
    state = state.copyWith(baseUrl: url);
    await GStorage.setting.put(_baseUrlKey, url);
  }

  Future<void> setApiKey(String key) async {
    state = state.copyWith(apiKey: key);
    await GStorage.setting.put(_apiKeyKey, key);
  }
}

final agentApiProvider =
    StateNotifierProvider<AgentApiNotifier, AgentApiState>(
  (ref) => AgentApiNotifier(),
);

// ─── 文档提取 API ─────────────────────────────────────────────────────────────

class DocExtractApiState {
  final String baseUrl;
  final String apiKey;

  const DocExtractApiState({this.baseUrl = '', this.apiKey = ''});

  DocExtractApiState copyWith({String? baseUrl, String? apiKey}) =>
      DocExtractApiState(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
      );
}

class DocExtractApiNotifier extends StateNotifier<DocExtractApiState> {
  static const _baseUrlKey = 'doc_extract_api_base_url';
  static const _apiKeyKey = 'doc_extract_api_key';

  DocExtractApiNotifier() : super(_load());

  static DocExtractApiState _load() {
    final box = GStorage.setting;
    final baseUrl = box.get(_baseUrlKey, defaultValue: '') as String;
    final apiKey = box.get(_apiKeyKey, defaultValue: '') as String;
    return DocExtractApiState(baseUrl: baseUrl, apiKey: apiKey);
  }

  Future<void> setBaseUrl(String url) async {
    state = state.copyWith(baseUrl: url);
    await GStorage.setting.put(_baseUrlKey, url);
  }

  Future<void> setApiKey(String key) async {
    state = state.copyWith(apiKey: key);
    await GStorage.setting.put(_apiKeyKey, key);
  }
}

final docExtractApiProvider =
    StateNotifierProvider<DocExtractApiNotifier, DocExtractApiState>(
  (ref) => DocExtractApiNotifier(),
);
