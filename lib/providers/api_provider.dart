import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/storage.dart';

enum AgentApiProvider { openai, anthropic, gemini, openAICompatible }

extension AgentApiProviderExt on AgentApiProvider {
  String get label => switch (this) {
    AgentApiProvider.openai => 'OpenAI',
    AgentApiProvider.anthropic => 'Anthropic',
    AgentApiProvider.gemini => 'Gemini',
    AgentApiProvider.openAICompatible => 'Other',
  };

  /// 纯域名，不含版本路径
  String get defaultBaseUrl => switch (this) {
    AgentApiProvider.openai => 'https://api.openai.com',
    AgentApiProvider.anthropic => 'https://api.anthropic.com',
    AgentApiProvider.gemini => 'https://generativelanguage.googleapis.com',
    AgentApiProvider.openAICompatible => 'https://api.deepseek.com',
  };

  String get apiKeyHint => switch (this) {
    AgentApiProvider.openai => 'sk-...',
    AgentApiProvider.anthropic => 'sk-ant-...',
    AgentApiProvider.gemini => 'AI...',
    AgentApiProvider.openAICompatible => 'sk-...',
  };

  /// 模型列表端点路径
  String get modelsPath => switch (this) {
    AgentApiProvider.openai => '/v1/models',
    AgentApiProvider.anthropic => '/v1/models',
    AgentApiProvider.gemini => '/v1beta/models',
    AgentApiProvider.openAICompatible => '/v1/models',
  };

  /// Chat / 消息端点路径（用于预览和模型检测）
  String get chatPath => switch (this) {
    AgentApiProvider.openai => '/v1/responses',
    AgentApiProvider.anthropic => '/v1/messages',
    AgentApiProvider.gemini => '/v1beta',
    AgentApiProvider.openAICompatible => '/v1/chat/completions',
  };
}

// ─── Agent API ───────────────────────────────────────────────────────────────

/// 单个模型的可调参数。所有字段可空——`null` 表示"不发送，使用服务商默认"。
///
/// 字段按服务商归类：
/// * 通用：`temperature` / `topP` / `maxTokens` / `systemPrompt`
/// * OpenAI Responses API：`reasoningEffort` / `verbosity` / `parallelToolCalls` /
///   `truncation` / `webSearchEnabled` / `webSearchContextSize`
/// * Anthropic Messages API：`thinkingMode` / `thinkingBudget`（+ 共享 `topK`）
/// * Gemini GenerateContent：`presencePenalty` / `frequencyPenalty` /
///   `thinkingBudget`（+ 共享 `topK`）
///
/// 真正发往各服务商的请求体序列化（参数名差异、嵌套结构差异）在请求构造层做，
/// 这里只负责存储用户意图。
class AgentModelParams {
  // ── 通用 ───────────────────────────────────────────
  final double? temperature;
  final double? topP;
  final int? maxTokens;
  final String? systemPrompt;

  // ── Anthropic / Gemini 共享 ────────────────────────
  final int? topK;

  // ── OpenAI 专属 ────────────────────────────────────
  /// OpenAI reasoning models：'minimal' | 'low' | 'medium' | 'high'
  final String? reasoningEffort;

  /// OpenAI Responses API `text.verbosity`：'low' | 'medium' | 'high'
  final String? verbosity;

  /// OpenAI `parallel_tool_calls`
  final bool? parallelToolCalls;

  /// OpenAI `truncation`：'auto' | 'disabled'
  final String? truncation;

  /// 工具调用 —— Web 搜索（OpenAI `web_search` / Gemini `google_search`）
  final bool? webSearchEnabled;

  /// 搜索上下文大小：'low' | 'medium' | 'high'
  final String? webSearchContextSize;

  // ── Anthropic 专属 ─────────────────────────────────
  /// Anthropic `thinking.type`：'disabled' | 'enabled' | 'adaptive'
  final String? thinkingMode;

  // ── Anthropic + Gemini 共享 ────────────────────────
  /// Anthropic：`thinking.budget_tokens`；Gemini：`thinkingConfig.thinkingBudget`
  final int? thinkingBudget;

  // ── Gemini 专属 ────────────────────────────────────
  /// Gemini `generationConfig.presencePenalty`：-2.0 ~ 2.0
  final double? presencePenalty;

  /// Gemini `generationConfig.frequencyPenalty`：-2.0 ~ 2.0
  final double? frequencyPenalty;

  const AgentModelParams({
    this.temperature,
    this.topP,
    this.maxTokens,
    this.systemPrompt,
    this.topK,
    this.reasoningEffort,
    this.verbosity,
    this.parallelToolCalls,
    this.truncation,
    this.webSearchEnabled,
    this.webSearchContextSize,
    this.thinkingMode,
    this.thinkingBudget,
    this.presencePenalty,
    this.frequencyPenalty,
  });

  /// 全部字段都未设置——意味着完全使用服务商默认值
  bool get isDefault =>
      temperature == null &&
      topP == null &&
      maxTokens == null &&
      (systemPrompt == null || systemPrompt!.isEmpty) &&
      topK == null &&
      reasoningEffort == null &&
      verbosity == null &&
      parallelToolCalls == null &&
      truncation == null &&
      webSearchEnabled == null &&
      webSearchContextSize == null &&
      thinkingMode == null &&
      thinkingBudget == null &&
      presencePenalty == null &&
      frequencyPenalty == null;

  AgentModelParams copyWith({
    Object? temperature = _sentinel,
    Object? topP = _sentinel,
    Object? maxTokens = _sentinel,
    Object? systemPrompt = _sentinel,
    Object? topK = _sentinel,
    Object? reasoningEffort = _sentinel,
    Object? verbosity = _sentinel,
    Object? parallelToolCalls = _sentinel,
    Object? truncation = _sentinel,
    Object? webSearchEnabled = _sentinel,
    Object? webSearchContextSize = _sentinel,
    Object? thinkingMode = _sentinel,
    Object? thinkingBudget = _sentinel,
    Object? presencePenalty = _sentinel,
    Object? frequencyPenalty = _sentinel,
  }) => AgentModelParams(
    temperature: identical(temperature, _sentinel)
        ? this.temperature
        : temperature as double?,
    topP: identical(topP, _sentinel) ? this.topP : topP as double?,
    maxTokens: identical(maxTokens, _sentinel)
        ? this.maxTokens
        : maxTokens as int?,
    systemPrompt: identical(systemPrompt, _sentinel)
        ? this.systemPrompt
        : systemPrompt as String?,
    topK: identical(topK, _sentinel) ? this.topK : topK as int?,
    reasoningEffort: identical(reasoningEffort, _sentinel)
        ? this.reasoningEffort
        : reasoningEffort as String?,
    verbosity: identical(verbosity, _sentinel)
        ? this.verbosity
        : verbosity as String?,
    parallelToolCalls: identical(parallelToolCalls, _sentinel)
        ? this.parallelToolCalls
        : parallelToolCalls as bool?,
    truncation: identical(truncation, _sentinel)
        ? this.truncation
        : truncation as String?,
    webSearchEnabled: identical(webSearchEnabled, _sentinel)
        ? this.webSearchEnabled
        : webSearchEnabled as bool?,
    webSearchContextSize: identical(webSearchContextSize, _sentinel)
        ? this.webSearchContextSize
        : webSearchContextSize as String?,
    thinkingMode: identical(thinkingMode, _sentinel)
        ? this.thinkingMode
        : thinkingMode as String?,
    thinkingBudget: identical(thinkingBudget, _sentinel)
        ? this.thinkingBudget
        : thinkingBudget as int?,
    presencePenalty: identical(presencePenalty, _sentinel)
        ? this.presencePenalty
        : presencePenalty as double?,
    frequencyPenalty: identical(frequencyPenalty, _sentinel)
        ? this.frequencyPenalty
        : frequencyPenalty as double?,
  );

  Map<String, dynamic> toJson() => {
    if (temperature != null) 'temperature': temperature,
    if (topP != null) 'topP': topP,
    if (maxTokens != null) 'maxTokens': maxTokens,
    if (systemPrompt != null && systemPrompt!.isNotEmpty)
      'systemPrompt': systemPrompt,
    if (topK != null) 'topK': topK,
    if (reasoningEffort != null) 'reasoningEffort': reasoningEffort,
    if (verbosity != null) 'verbosity': verbosity,
    if (parallelToolCalls != null) 'parallelToolCalls': parallelToolCalls,
    if (truncation != null) 'truncation': truncation,
    if (webSearchEnabled != null) 'webSearchEnabled': webSearchEnabled,
    if (webSearchContextSize != null)
      'webSearchContextSize': webSearchContextSize,
    if (thinkingMode != null) 'thinkingMode': thinkingMode,
    if (thinkingBudget != null) 'thinkingBudget': thinkingBudget,
    if (presencePenalty != null) 'presencePenalty': presencePenalty,
    if (frequencyPenalty != null) 'frequencyPenalty': frequencyPenalty,
  };

  factory AgentModelParams.fromJson(Map<String, dynamic> json) =>
      AgentModelParams(
        temperature: (json['temperature'] as num?)?.toDouble(),
        topP: (json['topP'] as num?)?.toDouble(),
        maxTokens: (json['maxTokens'] as num?)?.toInt(),
        systemPrompt: json['systemPrompt'] as String?,
        topK: (json['topK'] as num?)?.toInt(),
        reasoningEffort: json['reasoningEffort'] as String?,
        verbosity: json['verbosity'] as String?,
        parallelToolCalls: json['parallelToolCalls'] as bool?,
        truncation: json['truncation'] as String?,
        webSearchEnabled: json['webSearchEnabled'] as bool?,
        webSearchContextSize: json['webSearchContextSize'] as String?,
        // 向后兼容：老字段 thinkingEnabled 自动升级为 thinkingMode
        thinkingMode:
            json['thinkingMode'] as String? ??
            (json['thinkingEnabled'] == true
                ? 'enabled'
                : json['thinkingEnabled'] == false
                ? 'disabled'
                : null),
        thinkingBudget: (json['thinkingBudget'] as num?)?.toInt(),
        presencePenalty: (json['presencePenalty'] as num?)?.toDouble(),
        frequencyPenalty: (json['frequencyPenalty'] as num?)?.toDouble(),
      );
}

class AgentApiState {
  final AgentApiProvider provider;
  final String baseUrl;
  final String apiKey;
  final List<String> models;

  /// 专家模型 id；**全局唯一**——跨服务商共享；若全局默认属于其他服务商，
  /// 当前加载的 state 此字段为 null。
  final String? defaultModelId;

  /// 快速模型 id；**全局唯一**——跨服务商共享；语义与 [defaultModelId] 相同。
  final String? fastModelId;

  /// 生图模型 id；**全局唯一**——跨服务商共享；语义与 [defaultModelId] 相同。
  final String? imageModelId;

  /// 每个模型独立的可调参数；缺失的 modelId 视为全部使用服务商默认值
  final Map<String, AgentModelParams> modelParams;

  const AgentApiState({
    this.provider = AgentApiProvider.openai,
    this.baseUrl = '',
    this.apiKey = '',
    this.models = const [],
    this.defaultModelId,
    this.fastModelId,
    this.imageModelId,
    this.modelParams = const {},
  });

  /// 当前生效的 Base URL（用户未填时取服务商默认值）
  String get effectiveBaseUrl =>
      baseUrl.isNotEmpty ? baseUrl : provider.defaultBaseUrl;

  /// 取指定模型的参数集；从未配置过则返回 const default
  AgentModelParams paramsFor(String modelId) =>
      modelParams[modelId] ?? const AgentModelParams();

  AgentApiState copyWith({
    AgentApiProvider? provider,
    String? baseUrl,
    String? apiKey,
    List<String>? models,
    // 使用 Object sentinel 以便传 null 清空字段
    Object? defaultModelId = _sentinel,
    Object? fastModelId = _sentinel,
    Object? imageModelId = _sentinel,
    Map<String, AgentModelParams>? modelParams,
  }) => AgentApiState(
    provider: provider ?? this.provider,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    models: models ?? this.models,
    defaultModelId: identical(defaultModelId, _sentinel)
        ? this.defaultModelId
        : defaultModelId as String?,
    fastModelId: identical(fastModelId, _sentinel)
        ? this.fastModelId
        : fastModelId as String?,
    imageModelId: identical(imageModelId, _sentinel)
        ? this.imageModelId
        : imageModelId as String?,
    modelParams: modelParams ?? this.modelParams,
  );
}

const _sentinel = Object();

class AgentApiNotifier extends StateNotifier<AgentApiState> {
  static const _providerKey = 'agent_api_provider';

  // 每个服务商独立存储 key / url / models / 模型参数
  static String _baseUrlKey(String p) => 'agent_api_base_url_$p';
  static String _apiKeyKey(String p) => 'agent_api_key_$p';
  static String _modelsKey(String p) => 'agent_api_models_$p';
  static String _modelParamsKey(String p) => 'agent_api_model_params_$p';

  // 专家 / 快速 / 生图模型角色**全局唯一**；存储为 "providerName:modelId" 字符串。
  // 例："openai:gpt-4o-mini"。空字符串或缺失均视为未设置。
  static const _globalDefaultKey = 'agent_api_default_model_global';
  static const _globalFastKey = 'agent_api_fast_model_global';
  static const _globalImageKey = 'agent_api_image_model_global';

  // 旧版每服务商独立的角色 key —— 仅用于一次性迁移，之后会被删除。
  static String _legacyDefaultKey(String p) => 'agent_api_default_model_$p';
  static String _legacyFastKey(String p) => 'agent_api_fast_model_$p';

  AgentApiNotifier() : super(_load());

  static AgentApiState _load() {
    final box = GStorage.setting;
    final provStr = box.get(_providerKey, defaultValue: 'openai') as String;
    final provider = AgentApiProvider.values.firstWhere(
      (e) => e.name == provStr,
      orElse: () => AgentApiProvider.openai,
    );
    // 把旧版 per-provider 的 default/fast 迁移到新的全局 key。
    // 迁移只在"尚未存在全局 key"时跑一次；之后 legacy key 被删除，不会再触发。
    _migrateLegacyRolesIfNeeded(provider);
    return _loadForProvider(provider);
  }

  /// 解析 "providerName:modelId" 为 `(provider, modelId)`；
  /// 任一字段缺失或 providerName 无法匹配时返回 `(null, null)`。
  static (AgentApiProvider?, String?) _parseRole(String? raw) {
    if (raw == null || raw.isEmpty) return (null, null);
    final colonIdx = raw.indexOf(':');
    if (colonIdx <= 0 || colonIdx >= raw.length - 1) return (null, null);
    final provStr = raw.substring(0, colonIdx);
    final modelId = raw.substring(colonIdx + 1);
    for (final prov in AgentApiProvider.values) {
      if (prov.name == provStr) return (prov, modelId);
    }
    return (null, null);
  }

  /// 把 `(provider, modelId)` 序列化为 "providerName:modelId"。
  static String _serializeRole(AgentApiProvider provider, String modelId) =>
      '${provider.name}:$modelId';

  /// 一次性迁移：把旧版每服务商独立的 default/fast 合并为全局单例。
  /// 偏好当前 provider 的 legacy 值——这通常是用户最近操作的那个。
  static void _migrateLegacyRolesIfNeeded(AgentApiProvider currentProvider) {
    final box = GStorage.setting;

    void migrateOne(String globalKey, String Function(String p) legacyKeyFn) {
      if (!box.containsKey(globalKey)) {
        // 1) 优先取当前 provider 的 legacy 值
        String? pickedId;
        AgentApiProvider? pickedProv;
        final currentLegacy =
            box.get(legacyKeyFn(currentProvider.name)) as String?;
        if (currentLegacy != null && currentLegacy.isNotEmpty) {
          pickedId = currentLegacy;
          pickedProv = currentProvider;
        } else {
          // 2) 回退：按 enum 顺序挑选第一个非空的
          for (final prov in AgentApiProvider.values) {
            final legacy = box.get(legacyKeyFn(prov.name)) as String?;
            if (legacy != null && legacy.isNotEmpty) {
              pickedId = legacy;
              pickedProv = prov;
              break;
            }
          }
        }
        if (pickedId != null && pickedProv != null) {
          box.put(globalKey, _serializeRole(pickedProv, pickedId));
        }
      }
      // 无论是否迁移过，都清理 legacy key，避免下次误读
      for (final prov in AgentApiProvider.values) {
        box.delete(legacyKeyFn(prov.name));
      }
    }

    migrateOne(_globalDefaultKey, _legacyDefaultKey);
    migrateOne(_globalFastKey, _legacyFastKey);
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

    // 读取全局默认 / 快速模型；仅当全局角色指向「当前 provider」时才填充 state，
    // 否则留 null——这正是"跨服务商唯一"的核心：切到别的 provider 时
    // 看不到属于其他 provider 的角色。
    final (defaultProv, defaultId) = _parseRole(
      box.get(_globalDefaultKey) as String?,
    );
    final (fastProv, fastId) = _parseRole(box.get(_globalFastKey) as String?);
    final (imageProv, imageId) = _parseRole(
      box.get(_globalImageKey) as String?,
    );
    String? defaultModelId;
    String? fastModelId;
    String? imageModelId;
    if (defaultProv == provider &&
        defaultId != null &&
        models.contains(defaultId)) {
      defaultModelId = defaultId;
    }
    if (fastProv == provider && fastId != null && models.contains(fastId)) {
      fastModelId = fastId;
    }
    if (imageProv == provider && imageId != null && models.contains(imageId)) {
      imageModelId = imageId;
    }

    // 读取每模型参数；同时丢弃指向已删除模型的孤儿条目
    final modelParams = <String, AgentModelParams>{};
    final rawParams = box.get(_modelParamsKey(p));
    if (rawParams is Map) {
      rawParams.forEach((key, value) {
        if (key is! String || !models.contains(key)) return;
        if (value is! Map) return;
        try {
          final json = value.cast<String, dynamic>();
          modelParams[key] = AgentModelParams.fromJson(json);
        } catch (_) {
          // 单条解析失败不影响其他模型
        }
      });
    }

    return AgentApiState(
      provider: provider,
      baseUrl: baseUrl,
      apiKey: apiKey,
      models: models,
      defaultModelId: defaultModelId,
      fastModelId: fastModelId,
      imageModelId: imageModelId,
      modelParams: modelParams,
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

  /// 添加一个模型；可同时将其设为专家 / 快速 / 生图模型（**全局唯一**——替换任何
  /// 服务商下的旧值）。
  ///
  /// Hive in-memory 更新是同步的，先写 Hive 再更新 state，确保重建时
  /// 静态 getter（globalXxxRole）读到一致的快照。
  Future<void> addModel(
    String modelId, {
    bool setAsDefault = false,
    bool setAsFast = false,
    bool setAsImage = false,
  }) async {
    final box = GStorage.setting;
    final p = state.provider.name;
    final List<String> updated = state.models.contains(modelId)
        ? state.models
        : [...state.models, modelId];

    final f1 = box.put(_modelsKey(p), updated);
    final f2 = setAsDefault
        ? box.put(_globalDefaultKey, _serializeRole(state.provider, modelId))
        : null;
    final f3 = setAsFast
        ? box.put(_globalFastKey, _serializeRole(state.provider, modelId))
        : null;
    final f4 = setAsImage
        ? box.put(_globalImageKey, _serializeRole(state.provider, modelId))
        : null;

    state = state.copyWith(
      models: updated,
      defaultModelId: setAsDefault ? modelId : _sentinel,
      fastModelId: setAsFast ? modelId : _sentinel,
      imageModelId: setAsImage ? modelId : _sentinel,
    );

    await f1;
    if (f2 != null) await f2;
    if (f3 != null) await f3;
    if (f4 != null) await f4;
  }

  Future<void> removeModel(String modelId) async {
    final box = GStorage.setting;
    final p = state.provider.name;
    final updated = state.models.where((m) => m != modelId).toList();

    // 级联清理：只有当全局角色恰好指向「当前 provider + 被删模型」时才清空。
    // 指向其他 provider 的角色不受影响。
    final (defaultProv, defaultId) = _parseRole(
      box.get(_globalDefaultKey) as String?,
    );
    final (fastProv, fastId) = _parseRole(box.get(_globalFastKey) as String?);
    final (imageProv, imageId) = _parseRole(
      box.get(_globalImageKey) as String?,
    );
    final clearedDefault =
        defaultProv == state.provider && defaultId == modelId;
    final clearedFast = fastProv == state.provider && fastId == modelId;
    final clearedImage = imageProv == state.provider && imageId == modelId;

    // 级联清理：被删模型若有自定义参数，一并丢弃，避免孤儿条目长期残留
    final hadParams = state.modelParams.containsKey(modelId);
    final updatedParams = hadParams
        ? (Map<String, AgentModelParams>.from(state.modelParams)
            ..remove(modelId))
        : state.modelParams;

    // Hive 的 in-memory 更新是同步的（返回的 Future 仅代表磁盘刷写）。
    // 先触发所有 in-memory 更新，再更新 Riverpod state，确保重建时读到
    // 一致的 Hive 快照——避免 state 更新触发重建、而 box.delete 尚未执行
    // 导致 _buildGlobalRoles 读到旧的全局角色。
    final raw = hadParams
        ? updatedParams.map((k, v) => MapEntry(k, v.toJson()))
        : null;
    final f1 = box.put(_modelsKey(p), updated);
    final f2 = clearedDefault ? box.delete(_globalDefaultKey) : null;
    final f3 = clearedFast ? box.delete(_globalFastKey) : null;
    final f4 = clearedImage ? box.delete(_globalImageKey) : null;
    final f5 = raw != null ? box.put(_modelParamsKey(p), raw) : null;

    // in-memory 已更新，此时触发重建是安全的
    state = state.copyWith(
      models: updated,
      defaultModelId: clearedDefault ? null : _sentinel,
      fastModelId: clearedFast ? null : _sentinel,
      imageModelId: clearedImage ? null : _sentinel,
      modelParams: updatedParams,
    );

    // 等待磁盘持久化完成
    await f1;
    if (f2 != null) await f2;
    if (f3 != null) await f3;
    if (f4 != null) await f4;
    if (f5 != null) await f5;
  }

  /// 显式切换默认模型；传 null 清空。**全局唯一**——写入时会覆盖任何
  /// 服务商下的旧角色。
  Future<void> setDefaultModel(String? modelId) async {
    final box = GStorage.setting;
    if (modelId != null && !state.models.contains(modelId)) return;
    state = state.copyWith(defaultModelId: modelId);
    if (modelId == null) {
      await box.delete(_globalDefaultKey);
    } else {
      await box.put(_globalDefaultKey, _serializeRole(state.provider, modelId));
    }
  }

  /// 显式切换快速模型；传 null 清空。**全局唯一**——写入时会覆盖任何
  /// 服务商下的旧角色。
  Future<void> setFastModel(String? modelId) async {
    final box = GStorage.setting;
    if (modelId != null && !state.models.contains(modelId)) return;
    state = state.copyWith(fastModelId: modelId);
    if (modelId == null) {
      await box.delete(_globalFastKey);
    } else {
      await box.put(_globalFastKey, _serializeRole(state.provider, modelId));
    }
  }

  /// 写入指定模型的参数；若 [params.isDefault] 为 true 则从 map 中移除条目，
  /// 避免持久化"全 null"的空壳。
  Future<void> setModelParams(String modelId, AgentModelParams params) async {
    if (!state.models.contains(modelId)) return;
    final box = GStorage.setting;
    final p = state.provider.name;
    final updated = Map<String, AgentModelParams>.from(state.modelParams);
    if (params.isDefault) {
      updated.remove(modelId);
    } else {
      updated[modelId] = params;
    }
    state = state.copyWith(modelParams: updated);
    final raw = updated.map((k, v) => MapEntry(k, v.toJson()));
    await box.put(_modelParamsKey(p), raw);
  }

  /// 一键重置指定模型的所有参数为服务商默认值
  Future<void> resetModelParams(String modelId) =>
      setModelParams(modelId, const AgentModelParams());

  /// 全局默认模型角色（跨服务商），供 UI 展示。
  static ({AgentApiProvider? provider, String? modelId}) get globalDefaultRole {
    final (prov, id) = _parseRole(
      GStorage.setting.get(_globalDefaultKey) as String?,
    );
    return (provider: prov, modelId: id);
  }

  /// 全局快速模型角色（跨服务商），供 UI 展示。
  static ({AgentApiProvider? provider, String? modelId}) get globalFastRole {
    final (prov, id) = _parseRole(
      GStorage.setting.get(_globalFastKey) as String?,
    );
    return (provider: prov, modelId: id);
  }

  /// 全局生图模型角色（跨服务商），供 UI 展示。
  static ({AgentApiProvider? provider, String? modelId}) get globalImageRole {
    final (prov, id) = _parseRole(
      GStorage.setting.get(_globalImageKey) as String?,
    );
    return (provider: prov, modelId: id);
  }

  /// 返回所有服务商下已添加的模型，按服务商分组。
  static Map<AgentApiProvider, List<String>> getAllConfiguredModels() {
    final result = <AgentApiProvider, List<String>>{};
    for (final prov in AgentApiProvider.values) {
      final rawModels = GStorage.setting.get(_modelsKey(prov.name)) as List?;
      if (rawModels == null) continue;
      final models = rawModels
          .cast<String>()
          .where((m) => m.isNotEmpty)
          .toList();
      if (models.isNotEmpty) result[prov] = models;
    }
    return result;
  }

  /// 跨服务商设置全局默认模型。传 null 清除。
  Future<void> setGlobalDefaultModel(
    AgentApiProvider? provider,
    String? modelId,
  ) async {
    if (provider != null && modelId != null) {
      await GStorage.setting.put(
        _globalDefaultKey,
        _serializeRole(provider, modelId),
      );
    } else {
      await GStorage.setting.delete(_globalDefaultKey);
    }
    state = _loadForProvider(state.provider);
  }

  /// 跨服务商设置全局快速模型。传 null 清除。
  Future<void> setGlobalFastModel(
    AgentApiProvider? provider,
    String? modelId,
  ) async {
    if (provider != null && modelId != null) {
      await GStorage.setting.put(
        _globalFastKey,
        _serializeRole(provider, modelId),
      );
    } else {
      await GStorage.setting.delete(_globalFastKey);
    }
    state = _loadForProvider(state.provider);
  }

  /// 跨服务商设置全局生图模型。传 null 清除。
  Future<void> setGlobalImageModel(
    AgentApiProvider? provider,
    String? modelId,
  ) async {
    if (provider != null && modelId != null) {
      await GStorage.setting.put(
        _globalImageKey,
        _serializeRole(provider, modelId),
      );
    } else {
      await GStorage.setting.delete(_globalImageKey);
    }
    state = _loadForProvider(state.provider);
  }

  /// 解析全局默认/快速模型角色，加载其所属服务商的完整状态。
  /// 用于当前 UI 服务商没有配置模型角色时回退。
  static AgentApiState? resolveEffectiveState() {
    final box = GStorage.setting;
    final (fastProv, _) = _parseRole(box.get(_globalFastKey) as String?);
    final (defaultProv, _) = _parseRole(box.get(_globalDefaultKey) as String?);
    final (imageProv, _) = _parseRole(box.get(_globalImageKey) as String?);
    final targetProv = fastProv ?? defaultProv ?? imageProv;
    if (targetProv == null) return null;
    return _loadForProvider(targetProv);
  }

  /// 加载指定服务商的完整状态，供跨服务商角色调用层使用。
  static AgentApiState loadForProvider(AgentApiProvider provider) {
    return _loadForProvider(provider);
  }

  void reload() {
    state = _load();
  }
}

final agentApiProvider = StateNotifierProvider<AgentApiNotifier, AgentApiState>(
  (ref) => AgentApiNotifier(),
);

/// 用于 API 调用的有效状态。
///
/// 当前服务商若有默认或快速模型，直接使用当前状态；
/// 否则回退到全局模型角色所属的服务商配置。
/// 设置页应继续使用 [agentApiProvider]（仅管理当前服务商）。
final effectiveAgentApiProvider = Provider<AgentApiState>((ref) {
  final current = ref.watch(agentApiProvider);
  if (current.fastModelId != null ||
      current.defaultModelId != null ||
      current.imageModelId != null) {
    return current;
  }
  return AgentApiNotifier.resolveEffectiveState() ?? current;
});

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
