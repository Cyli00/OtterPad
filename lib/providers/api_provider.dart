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

  /// 纯域名，不含版本路径
  String get defaultBaseUrl => switch (this) {
    AgentApiProvider.openai => 'https://api.openai.com',
    AgentApiProvider.anthropic => 'https://api.anthropic.com',
    AgentApiProvider.gemini => 'https://generativelanguage.googleapis.com',
  };

  String get apiKeyHint => switch (this) {
    AgentApiProvider.openai => 'sk-...',
    AgentApiProvider.anthropic => 'sk-ant-...',
    AgentApiProvider.gemini => 'AI...',
  };

  /// 模型列表端点路径
  String get modelsPath => switch (this) {
    AgentApiProvider.openai => '/v1/models',
    AgentApiProvider.anthropic => '',
    AgentApiProvider.gemini => '/v1beta/models',
  };

  /// Chat / 消息端点路径（用于预览和模型检测）
  String get chatPath => switch (this) {
    AgentApiProvider.openai => '/v1/responses',
    AgentApiProvider.anthropic => '/v1/messages',
    AgentApiProvider.gemini => '/v1beta',
  };
}

// ─── Agent API ───────────────────────────────────────────────────────────────

class AgentApiState {
  final AgentApiProvider provider;
  final String baseUrl;
  final String apiKey;
  final List<String> models;

  const AgentApiState({
    this.provider = AgentApiProvider.openai,
    this.baseUrl = '',
    this.apiKey = '',
    this.models = const [],
  });

  /// 当前生效的 Base URL（用户未填时取服务商默认值）
  String get effectiveBaseUrl =>
      baseUrl.isNotEmpty ? baseUrl : provider.defaultBaseUrl;

  AgentApiState copyWith({
    AgentApiProvider? provider,
    String? baseUrl,
    String? apiKey,
    List<String>? models,
  }) => AgentApiState(
    provider: provider ?? this.provider,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    models: models ?? this.models,
  );
}

class AgentApiNotifier extends StateNotifier<AgentApiState> {
  static const _providerKey = 'agent_api_provider';

  // 每个服务商独立存储 key / url / models
  static String _baseUrlKey(String p) => 'agent_api_base_url_$p';
  static String _apiKeyKey(String p) => 'agent_api_key_$p';
  static String _modelsKey(String p) => 'agent_api_models_$p';

  AgentApiNotifier() : super(_load());

  static AgentApiState _load() {
    final box = GStorage.setting;
    final provStr = box.get(_providerKey, defaultValue: 'openai') as String;
    final provider = AgentApiProvider.values.firstWhere(
      (e) => e.name == provStr,
      orElse: () => AgentApiProvider.openai,
    );
    return _loadForProvider(provider);
  }

  /// 旧版默认地址（含版本路径），需要清理
  static const _staleDefaults = {
    'https://api.openai.com/v1',
    'https://generativelanguage.googleapis.com/v1beta',
  };

  /// 加载指定服务商的完整状态
  static AgentApiState _loadForProvider(AgentApiProvider provider) {
    final box = GStorage.setting;
    final p = provider.name;

    var apiKey = box.get(_apiKeyKey(p), defaultValue: '') as String;
    var baseUrl = box.get(_baseUrlKey(p), defaultValue: '') as String;

    // 清理旧版含版本路径的默认地址（避免拼出 /v1/v1/...）
    if (_staleDefaults.contains(baseUrl)) {
      baseUrl = '';
      box.put(_baseUrlKey(p), '');
    }

    final rawModels = box.get(_modelsKey(p)) as List?;
    final models = rawModels?.cast<String>().toList() ?? <String>[];

    return AgentApiState(
      provider: provider,
      baseUrl: baseUrl,
      apiKey: apiKey,
      models: models,
    );
  }

  /// 切换服务商 → 加载该服务商独立存储的 key / url / models
  Future<void> setProvider(AgentApiProvider provider) async {
    state = _loadForProvider(provider);
    await GStorage.setting.put(_providerKey, provider.name);
  }

  Future<void> setBaseUrl(String url) async {
    state = state.copyWith(baseUrl: url);
    await GStorage.setting.put(_baseUrlKey(state.provider.name), url);
  }

  Future<void> setApiKey(String key) async {
    state = state.copyWith(apiKey: key);
    await GStorage.setting.put(_apiKeyKey(state.provider.name), key);
  }

  Future<void> addModel(String modelId) async {
    if (state.models.contains(modelId)) return;
    final updated = [...state.models, modelId];
    state = state.copyWith(models: updated);
    await GStorage.setting.put(_modelsKey(state.provider.name), updated);
  }

  Future<void> removeModel(String modelId) async {
    final updated = state.models.where((m) => m != modelId).toList();
    state = state.copyWith(models: updated);
    await GStorage.setting.put(_modelsKey(state.provider.name), updated);
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
  final String apiKey; // Access Token（异步 Job API 必填）
  final String syncBaseUrl; // 同步 API 地址（可选 fallback）

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

  /// 异步 API 只需 token，是否已配置
  bool get isConfigured => apiKey.isNotEmpty;

  /// 是否配置了同步 API 作为 fallback
  bool get hasSyncFallback => syncBaseUrl.isNotEmpty;

  const DocExtractApiState({
    this.apiKey = '',
    this.syncBaseUrl = '',
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
    String? apiKey,
    String? syncBaseUrl,
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
    apiKey: apiKey ?? this.apiKey,
    syncBaseUrl: syncBaseUrl ?? this.syncBaseUrl,
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
    final apiKey = box.get(_apiKeyKey, defaultValue: '') as String;
    final syncBaseUrl = box.get(_baseUrlKey, defaultValue: '') as String;

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
      apiKey: apiKey,
      syncBaseUrl: syncBaseUrl,
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

  Future<void> setSyncBaseUrl(String url) async {
    state = state.copyWith(syncBaseUrl: url);
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
