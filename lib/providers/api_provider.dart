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
  }) => AgentApiState(
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

  void reload() {
    state = _load();
  }
}

final agentApiProvider = StateNotifierProvider<AgentApiNotifier, AgentApiState>(
  (ref) => AgentApiNotifier(),
);

// ─── 文档提取 API（百度 AI Studio Layout Parsing）─────────────────────────────

/// 所有可选的 Markdown 忽略标签
const kAllIgnoreLabels = [
  'header',
  'header_image',
  'footer',
  'footer_image',
  'number',
  'footnote',
  'aside_text',
];

/// 默认启用的忽略标签
const kDefaultIgnoreLabels = [
  'header',
  'header_image',
  'footer',
  'footer_image',
  'number',
  'footnote',
  'aside_text',
];

class DocExtractApiState {
  final String baseUrl;
  final String apiKey; // Access Token

  // ── 提取选项 ──
  final bool useChartRecognition;
  final bool useDocOrientationClassify;
  final bool useDocUnwarping;
  final bool useSealRecognition;
  final bool useOcrForImageBlock;
  final bool restructurePages;
  final bool layoutNms;
  final String layoutShapeMode;
  final double layoutThreshold;
  final double repetitionPenalty;

  // ── Markdown 忽略标签 ──
  final List<String> markdownIgnoreLabels;

  const DocExtractApiState({
    this.baseUrl = '',
    this.apiKey = '',
    this.useChartRecognition = false,
    this.useDocOrientationClassify = false,
    this.useDocUnwarping = false,
    this.useSealRecognition = false,
    this.useOcrForImageBlock = false,
    this.restructurePages = true,
    this.layoutNms = true,
    this.layoutShapeMode = 'auto',
    this.layoutThreshold = 0.5,
    this.repetitionPenalty = 1.0,
    this.markdownIgnoreLabels = kDefaultIgnoreLabels,
  });

  DocExtractApiState copyWith({
    String? baseUrl,
    String? apiKey,
    bool? useChartRecognition,
    bool? useDocOrientationClassify,
    bool? useDocUnwarping,
    bool? useSealRecognition,
    bool? useOcrForImageBlock,
    bool? restructurePages,
    bool? layoutNms,
    String? layoutShapeMode,
    double? layoutThreshold,
    double? repetitionPenalty,
    List<String>? markdownIgnoreLabels,
  }) => DocExtractApiState(
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    useChartRecognition: useChartRecognition ?? this.useChartRecognition,
    useDocOrientationClassify:
        useDocOrientationClassify ?? this.useDocOrientationClassify,
    useDocUnwarping: useDocUnwarping ?? this.useDocUnwarping,
    useSealRecognition: useSealRecognition ?? this.useSealRecognition,
    useOcrForImageBlock: useOcrForImageBlock ?? this.useOcrForImageBlock,
    restructurePages: restructurePages ?? this.restructurePages,
    layoutNms: layoutNms ?? this.layoutNms,
    layoutShapeMode: layoutShapeMode ?? this.layoutShapeMode,
    layoutThreshold: layoutThreshold ?? this.layoutThreshold,
    repetitionPenalty: repetitionPenalty ?? this.repetitionPenalty,
    markdownIgnoreLabels: markdownIgnoreLabels ?? this.markdownIgnoreLabels,
  );
}

class DocExtractApiNotifier extends StateNotifier<DocExtractApiState> {
  static const _baseUrlKey = 'doc_extract_api_base_url';
  static const _apiKeyKey = 'doc_extract_api_key';
  static const _prefix = 'doc_extract_';

  DocExtractApiNotifier() : super(_load());

  static DocExtractApiState _load() {
    final box = GStorage.setting;
    final baseUrl = box.get(_baseUrlKey, defaultValue: '') as String;
    final apiKey = box.get(_apiKeyKey, defaultValue: '') as String;

    final useChartRecognition =
        box.get('${_prefix}useChartRecognition', defaultValue: false) as bool;
    final useDocOrientationClassify =
        box.get('${_prefix}useDocOrientationClassify', defaultValue: false)
            as bool;
    final useDocUnwarping =
        box.get('${_prefix}useDocUnwarping', defaultValue: false) as bool;
    final useSealRecognition =
        box.get('${_prefix}useSealRecognition', defaultValue: false) as bool;
    final useOcrForImageBlock =
        box.get('${_prefix}useOcrForImageBlock', defaultValue: false) as bool;
    final restructurePages =
        box.get('${_prefix}restructurePages', defaultValue: true) as bool;
    final layoutNms =
        box.get('${_prefix}layoutNms', defaultValue: true) as bool;
    final layoutShapeMode =
        box.get('${_prefix}layoutShapeMode', defaultValue: 'auto') as String;
    final layoutThreshold =
        box.get('${_prefix}layoutThreshold', defaultValue: 0.5) as double;
    final repetitionPenalty =
        box.get('${_prefix}repetitionPenalty', defaultValue: 1.0) as double;

    final rawLabels = box.get('${_prefix}markdownIgnoreLabels') as List?;
    final markdownIgnoreLabels = rawLabels != null
        ? rawLabels.cast<String>().toList()
        : List<String>.from(kDefaultIgnoreLabels);

    return DocExtractApiState(
      baseUrl: baseUrl,
      apiKey: apiKey,
      useChartRecognition: useChartRecognition,
      useDocOrientationClassify: useDocOrientationClassify,
      useDocUnwarping: useDocUnwarping,
      useSealRecognition: useSealRecognition,
      useOcrForImageBlock: useOcrForImageBlock,
      restructurePages: restructurePages,
      layoutNms: layoutNms,
      layoutShapeMode: layoutShapeMode,
      layoutThreshold: layoutThreshold,
      repetitionPenalty: repetitionPenalty,
      markdownIgnoreLabels: markdownIgnoreLabels,
    );
  }

  Future<void> setBaseUrl(String url) async {
    state = state.copyWith(baseUrl: url);
    await GStorage.setting.put(_baseUrlKey, url);
  }

  Future<void> setApiKey(String key) async {
    state = state.copyWith(apiKey: key);
    await GStorage.setting.put(_apiKeyKey, key);
  }

  Future<void> setBool(String field, bool value) async {
    switch (field) {
      case 'useChartRecognition':
        state = state.copyWith(useChartRecognition: value);
      case 'useDocOrientationClassify':
        state = state.copyWith(useDocOrientationClassify: value);
      case 'useDocUnwarping':
        state = state.copyWith(useDocUnwarping: value);
      case 'useSealRecognition':
        state = state.copyWith(useSealRecognition: value);
      case 'useOcrForImageBlock':
        state = state.copyWith(useOcrForImageBlock: value);
      case 'restructurePages':
        state = state.copyWith(restructurePages: value);
      case 'layoutNms':
        state = state.copyWith(layoutNms: value);
    }
    await GStorage.setting.put('$_prefix$field', value);
  }

  Future<void> setDouble(String field, double value) async {
    switch (field) {
      case 'layoutThreshold':
        state = state.copyWith(layoutThreshold: value);
      case 'repetitionPenalty':
        state = state.copyWith(repetitionPenalty: value);
    }
    await GStorage.setting.put('$_prefix$field', value);
  }

  Future<void> setString(String field, String value) async {
    switch (field) {
      case 'layoutShapeMode':
        state = state.copyWith(layoutShapeMode: value);
    }
    await GStorage.setting.put('$_prefix$field', value);
  }

  Future<void> setIgnoreLabels(List<String> labels) async {
    state = state.copyWith(markdownIgnoreLabels: labels);
    await GStorage.setting.put('${_prefix}markdownIgnoreLabels', labels);
  }

  void reload() {
    state = _load();
  }
}

final docExtractApiProvider =
    StateNotifierProvider<DocExtractApiNotifier, DocExtractApiState>(
      (ref) => DocExtractApiNotifier(),
    );
