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
  final bool useLayoutDetection;
  final bool useChartRecognition;
  final bool useDocOrientationClassify;
  final bool useDocUnwarping;
  final bool useSealRecognition;
  final bool useOcrForImageBlock;
  final bool mergeTables;
  final bool relevelTitles;
  final bool restructurePages;
  final bool layoutNms;

  // ── Markdown 忽略标签 ──
  final List<String> markdownIgnoreLabels;

  const DocExtractApiState({
    this.baseUrl = '',
    this.apiKey = '',
    this.useLayoutDetection = true,
    this.useChartRecognition = false,
    this.useDocOrientationClassify = false,
    this.useDocUnwarping = false,
    this.useSealRecognition = false,
    this.useOcrForImageBlock = false,
    this.mergeTables = true,
    this.relevelTitles = true,
    this.restructurePages = true,
    this.layoutNms = true,
    this.markdownIgnoreLabels = kDefaultIgnoreLabels,
  });

  DocExtractApiState copyWith({
    String? baseUrl,
    String? apiKey,
    bool? useLayoutDetection,
    bool? useChartRecognition,
    bool? useDocOrientationClassify,
    bool? useDocUnwarping,
    bool? useSealRecognition,
    bool? useOcrForImageBlock,
    bool? mergeTables,
    bool? relevelTitles,
    bool? restructurePages,
    bool? layoutNms,
    List<String>? markdownIgnoreLabels,
  }) =>
      DocExtractApiState(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        useLayoutDetection: useLayoutDetection ?? this.useLayoutDetection,
        useChartRecognition: useChartRecognition ?? this.useChartRecognition,
        useDocOrientationClassify:
            useDocOrientationClassify ?? this.useDocOrientationClassify,
        useDocUnwarping: useDocUnwarping ?? this.useDocUnwarping,
        useSealRecognition: useSealRecognition ?? this.useSealRecognition,
        useOcrForImageBlock: useOcrForImageBlock ?? this.useOcrForImageBlock,
        mergeTables: mergeTables ?? this.mergeTables,
        relevelTitles: relevelTitles ?? this.relevelTitles,
        restructurePages: restructurePages ?? this.restructurePages,
        layoutNms: layoutNms ?? this.layoutNms,
        markdownIgnoreLabels:
            markdownIgnoreLabels ?? this.markdownIgnoreLabels,
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

    final useLayoutDetection =
        box.get('${_prefix}useLayoutDetection', defaultValue: true) as bool;
    final useChartRecognition =
        box.get('${_prefix}useChartRecognition', defaultValue: false) as bool;
    final useDocOrientationClassify = box.get(
        '${_prefix}useDocOrientationClassify',
        defaultValue: false) as bool;
    final useDocUnwarping =
        box.get('${_prefix}useDocUnwarping', defaultValue: false) as bool;
    final useSealRecognition =
        box.get('${_prefix}useSealRecognition', defaultValue: false) as bool;
    final useOcrForImageBlock =
        box.get('${_prefix}useOcrForImageBlock', defaultValue: false) as bool;
    final mergeTables =
        box.get('${_prefix}mergeTables', defaultValue: true) as bool;
    final relevelTitles =
        box.get('${_prefix}relevelTitles', defaultValue: true) as bool;
    final restructurePages =
        box.get('${_prefix}restructurePages', defaultValue: true) as bool;
    final layoutNms =
        box.get('${_prefix}layoutNms', defaultValue: true) as bool;

    final rawLabels = box.get('${_prefix}markdownIgnoreLabels') as List?;
    final markdownIgnoreLabels = rawLabels != null
        ? rawLabels.cast<String>().toList()
        : List<String>.from(kDefaultIgnoreLabels);

    return DocExtractApiState(
      baseUrl: baseUrl,
      apiKey: apiKey,
      useLayoutDetection: useLayoutDetection,
      useChartRecognition: useChartRecognition,
      useDocOrientationClassify: useDocOrientationClassify,
      useDocUnwarping: useDocUnwarping,
      useSealRecognition: useSealRecognition,
      useOcrForImageBlock: useOcrForImageBlock,
      mergeTables: mergeTables,
      relevelTitles: relevelTitles,
      restructurePages: restructurePages,
      layoutNms: layoutNms,
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
      case 'useLayoutDetection':
        state = state.copyWith(useLayoutDetection: value);
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
      case 'mergeTables':
        state = state.copyWith(mergeTables: value);
      case 'relevelTitles':
        state = state.copyWith(relevelTitles: value);
      case 'restructurePages':
        state = state.copyWith(restructurePages: value);
      case 'layoutNms':
        state = state.copyWith(layoutNms: value);
    }
    await GStorage.setting.put('$_prefix$field', value);
  }

  Future<void> setIgnoreLabels(List<String> labels) async {
    state = state.copyWith(markdownIgnoreLabels: labels);
    await GStorage.setting.put('${_prefix}markdownIgnoreLabels', labels);
  }
}

final docExtractApiProvider =
    StateNotifierProvider<DocExtractApiNotifier, DocExtractApiState>(
  (ref) => DocExtractApiNotifier(),
);
