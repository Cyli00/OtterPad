import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/secure_credential_vault.dart';
import '../core/storage/storage.dart';
import '../services/agent_model_capability.dart';

enum AgentApiProvider { openai, anthropic, gemini, openAICompatible }

extension AgentApiProviderExt on AgentApiProvider {
  String get label => switch (this) {
    AgentApiProvider.openai => 'OpenAI',
    AgentApiProvider.anthropic => 'Anthropic',
    AgentApiProvider.gemini => 'Gemini',
    AgentApiProvider.openAICompatible => 'OpenAI Compatible',
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

/// 跨 provider 统一的"思考力度"分级。
///
/// **5 档语义**（由请求构造层按 provider+model capability 翻译为各家具体字段）：
/// - `off`：完全不思考。OpenAI=`reasoning.effort:none`、Gemini 2.5=`thinkingBudget:0`、
///   Claude 旧=`thinking.type:disabled`、Claude Opus 4.7=映射到 `output_config.effort:low`
///   （adaptive 模型不能真正关闭，最低档即低思考）。
/// - `low`：低思考预算/最小开销，适合简单指令跟随、聊天。
/// - `medium`（默认）：平衡思考与成本，多数任务的合理选择。Claude Opus 4.7
///   下不向请求体写 `output_config`，让 adaptive 自决。
/// - `high`：高深度推理，适合复杂代码/分析。
/// - `xhigh`：模型上限。Claude=`output_config.effort:max`、Gemini=模型 max budget、
///   OpenAI=`xhigh`、DeepSeek=`reasoning_effort:max`。
///
/// 持久化用 string id（`'off'/'low'/'medium'/'high'/'xhigh'`），保证未来插入
/// 新档时旧数据不被破坏（不要换成 enum.index）。
enum ThinkingLevel {
  off('off', '关闭'),
  low('low', '低'),
  medium('medium', '中等'),
  high('high', '高'),
  xhigh('xhigh', '超高');

  final String id;
  final String label;
  const ThinkingLevel(this.id, this.label);

  static ThinkingLevel? fromId(String? id) {
    if (id == null) return null;
    for (final l in ThinkingLevel.values) {
      if (l.id == id) return l;
    }
    return null;
  }
}

/// 单个模型的可调参数。所有字段可空——`null` 表示"不发送，使用服务商默认"。
///
/// 字段按服务商归类：
/// * 通用：`temperature` / `topP` / `maxTokens` / `systemPrompt`
/// * 跨 provider 统一思考力度：`thinkingLevel`（请求构造层按 capability 翻译）
/// * OpenAI Responses API：`verbosity` / `parallelToolCalls` /
///   `truncation` / `webSearchEnabled` / `webSearchContextSize`
/// * Anthropic / Gemini 共享：`topK`
/// * Gemini GenerateContent：`presencePenalty` / `frequencyPenalty`
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

  // ── 跨 provider 统一思考力度 ───────────────────────
  /// 跨 provider 统一思考分级；null 表示"不发送，服务商默认"。
  /// 请求构造层按 [AgentModelCapability] 把它翻译成各家具体字段。
  final ThinkingLevel? thinkingLevel;

  // ── OpenAI 专属 ────────────────────────────────────
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
    this.thinkingLevel,
    this.verbosity,
    this.parallelToolCalls,
    this.truncation,
    this.webSearchEnabled,
    this.webSearchContextSize,
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
      thinkingLevel == null &&
      verbosity == null &&
      parallelToolCalls == null &&
      truncation == null &&
      webSearchEnabled == null &&
      webSearchContextSize == null &&
      presencePenalty == null &&
      frequencyPenalty == null;

  AgentModelParams copyWith({
    Object? temperature = _sentinel,
    Object? topP = _sentinel,
    Object? maxTokens = _sentinel,
    Object? systemPrompt = _sentinel,
    Object? topK = _sentinel,
    Object? thinkingLevel = _sentinel,
    Object? verbosity = _sentinel,
    Object? parallelToolCalls = _sentinel,
    Object? truncation = _sentinel,
    Object? webSearchEnabled = _sentinel,
    Object? webSearchContextSize = _sentinel,
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
    thinkingLevel: identical(thinkingLevel, _sentinel)
        ? this.thinkingLevel
        : thinkingLevel as ThinkingLevel?,
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
    if (thinkingLevel != null) 'thinkingLevel': thinkingLevel!.id,
    if (verbosity != null) 'verbosity': verbosity,
    if (parallelToolCalls != null) 'parallelToolCalls': parallelToolCalls,
    if (truncation != null) 'truncation': truncation,
    if (webSearchEnabled != null) 'webSearchEnabled': webSearchEnabled,
    if (webSearchContextSize != null)
      'webSearchContextSize': webSearchContextSize,
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
        thinkingLevel: _migrateThinkingLevel(json),
        verbosity: json['verbosity'] as String?,
        parallelToolCalls: json['parallelToolCalls'] as bool?,
        truncation: json['truncation'] as String?,
        webSearchEnabled: json['webSearchEnabled'] as bool?,
        webSearchContextSize: json['webSearchContextSize'] as String?,
        presencePenalty: (json['presencePenalty'] as num?)?.toDouble(),
        frequencyPenalty: (json['frequencyPenalty'] as num?)?.toDouble(),
      );

  /// 反序列化时把旧字段自动迁移到 [thinkingLevel]。
  ///
  /// **优先级**：新字段 `thinkingLevel` > 旧 `thinkingMode='disabled'` 直接 off >
  /// 旧 `reasoningEffort` 字符串映射 > 旧 `thinkingBudget` 数字按区间反推 >
  /// 仅有 `thinkingMode='enabled'/'adaptive'` 但无具体值 → 用 medium 兜底。
  ///
  /// 数字反推阈值参考各 provider 默认 budget 取整：1024（low 上限）/ 8192
  /// （medium 上限）/ 16384（high 上限）；阈值不严格对应"原始 budget 的最佳
  /// 还原"，只保证旧高 budget 用户升级后仍落在 high/xhigh 档。
  static ThinkingLevel? _migrateThinkingLevel(Map<String, dynamic> json) {
    final fresh = ThinkingLevel.fromId(json['thinkingLevel'] as String?);
    if (fresh != null) return fresh;

    final mode =
        json['thinkingMode'] as String? ??
        (json['thinkingEnabled'] == true
            ? 'enabled'
            : json['thinkingEnabled'] == false
            ? 'disabled'
            : null);
    if (mode == 'disabled') return ThinkingLevel.off;

    final effort = json['reasoningEffort'] as String?;
    if (effort != null) {
      return switch (effort) {
        'minimal' || 'low' => ThinkingLevel.low,
        'medium' => ThinkingLevel.medium,
        'high' => ThinkingLevel.high,
        'max' || 'xhigh' => ThinkingLevel.xhigh,
        _ => null,
      };
    }

    final budget = (json['thinkingBudget'] as num?)?.toInt();
    if (budget != null) {
      if (budget == 0) return ThinkingLevel.off;
      if (budget < 1024) return ThinkingLevel.low;
      if (budget < 8192) return ThinkingLevel.medium;
      if (budget < 16384) return ThinkingLevel.high;
      return ThinkingLevel.xhigh;
    }

    if (mode == 'enabled' || mode == 'adaptive') return ThinkingLevel.medium;
    return null;
  }
}

/// 单个服务商实例（注册表条目）。
///
/// `protocol` 是 [AgentApiProvider] 之一——决定线格式（请求/解析），由各
/// 协议适配层 `switch` 消费。`id` 创建时用毫秒时间戳生成、之后稳定不变，角色串
/// 与 Hive 存储键都靠它定位。`name` 用户可见、强制唯一。
class AgentProviderInstance {
  final String id;
  final String name;
  final AgentApiProvider protocol;
  final String baseUrl;
  final String apiKey;
  final List<String> models;
  final Map<String, AgentModelParams> modelParams;

  /// 每模型能力（分类 + 模态 + 工具/推理）。缺失项由 [capabilityFor] 即时推断兜底。
  final Map<String, AgentModelCapability> modelCaps;

  /// 每模型启用的内置工具（search / code_execution 等）。缺失 = 全部关闭。
  final Map<String, List<String>> modelBuiltInTools;

  const AgentProviderInstance({
    required this.id,
    required this.name,
    required this.protocol,
    this.baseUrl = '',
    this.apiKey = '',
    this.models = const [],
    this.modelParams = const {},
    this.modelCaps = const {},
    this.modelBuiltInTools = const {},
  });

  /// 当前生效的 Base URL（用户未填时取协议默认值）
  String get effectiveBaseUrl =>
      baseUrl.isNotEmpty ? baseUrl : protocol.defaultBaseUrl;

  AgentModelParams paramsFor(String modelId) =>
      modelParams[modelId] ?? const AgentModelParams();

  /// 取模型能力：优先用户持久化的覆盖值，缺失则按 id 即时推断。
  AgentModelCapability capabilityFor(String modelId) =>
      modelCaps[modelId] ??
      AgentModelCapability.infer(provider: protocol, modelId: modelId);

  /// 取模型已启用的内置工具集合。
  Set<String> builtInToolsFor(String modelId) =>
      Set<String>.from(modelBuiltInTools[modelId] ?? const <String>[]);
}

/// 单实例的「已解析视图」：实例自身字段 + 三个全局角色中**指向本实例**的那部分。
///
/// 调用层（翻译/生图等）读这个对象；`defaultModelId`/`fastModelId`/`imageModelId`
/// 仅当对应全局角色恰好指向本实例时才非空，语义与重构前一致，只是键从「协议」
/// 换成了「实例 id」。
class AgentApiState {
  /// 所属实例 id；空字符串表示「未解析到任何实例」的兜底态。
  final String id;

  /// 所属实例显示名。
  final String name;

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
    this.id = '',
    this.name = '',
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
    String? id,
    String? name,
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
    id: id ?? this.id,
    name: name ?? this.name,
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

/// Agent 服务商配置的整体状态：有序实例列表。
///
/// 全局角色（专家/快速/生图）不放进 state——它们由 [AgentApiNotifier] 的静态
/// getter 直接读 Hive；notifier 在写完任何配置后 `state = _load()` 触发重建，
/// 驱动 UI（build 内读静态 getter）刷新——沿用重构前的同一套刷新机制。
class AgentProvidersState {
  final List<AgentProviderInstance> instances;
  const AgentProvidersState({this.instances = const []});

  AgentProviderInstance? byId(String? id) {
    if (id == null) return null;
    for (final inst in instances) {
      if (inst.id == id) return inst;
    }
    return null;
  }
}

class AgentApiNotifier extends StateNotifier<AgentProvidersState> {
  // per-instance 存储键，均以实例 id 结尾。
  static String _nameKey(String id) => 'agent_api_name_$id';
  static String _protocolKey(String id) => 'agent_api_protocol_$id';
  static String _baseUrlKey(String id) => 'agent_api_base_url_$id';
  static String _apiKeyKey(String id) => 'agent_api_key_$id';
  static String _modelsKey(String id) => 'agent_api_models_$id';
  static String _modelParamsKey(String id) => 'agent_api_model_params_$id';
  static String _modelCapsKey(String id) => 'agent_api_model_caps_$id';
  static String _modelToolsKey(String id) => 'agent_api_model_tools_$id';

  /// 有序实例 id 列表——定义「有哪些实例、什么顺序」。
  static const _idsKey = 'agent_api_provider_ids';

  // 专家 / 快速 / 生图模型角色**全局唯一**；存储为 "instanceId:modelId"。
  // 空字符串或缺失均视为未设置。
  static const _globalDefaultKey = 'agent_api_default_model_global';
  static const _globalFastKey = 'agent_api_fast_model_global';
  static const _globalImageKey = 'agent_api_image_model_global';

  /// 内置三家——永远常驻列表、不可删除、名字锁定，id 固定为协议名。
  static const _builtinProtocols = [
    AgentApiProvider.openai,
    AgentApiProvider.anthropic,
    AgentApiProvider.gemini,
  ];

  /// 该 id 是否为内置三家（内置不进 _idsKey、不可删、名字锁定）。
  static bool isBuiltin(String id) =>
      _builtinProtocols.any((p) => p.name == id);

  AgentApiNotifier() : super(_load());

  // ── 加载 ──────────────────────────────────────────────────────────────

  static List<String> _loadIds() {
    final raw = GStorage.setting.get(_idsKey) as List?;
    return raw?.cast<String>().where((e) => e.isNotEmpty).toList() ??
        <String>[];
  }

  /// 列表 = 内置三家（恒在，id=协议名）+ _idsKey 里的自定义实例（按序）。
  static AgentProvidersState _load() {
    final instances = <AgentProviderInstance>[
      for (final p in _builtinProtocols) _loadConfig(p.name, p, p.label),
    ];
    for (final id in _loadIds()) {
      final inst = _loadCustom(id);
      if (inst != null) instances.add(inst);
    }
    return AgentProvidersState(instances: instances);
  }

  /// 按 id 加载任意实例（内置或自定义）；自定义协议键缺失返回 null。
  static AgentProviderInstance? _loadAny(String id) {
    if (isBuiltin(id)) {
      final p = _builtinProtocols.firstWhere((p) => p.name == id);
      return _loadConfig(id, p, p.label);
    }
    return _loadCustom(id);
  }

  /// 读取自定义实例：协议/名字从 Hive 取；协议键缺失视为「非注册」返回 null。
  static AgentProviderInstance? _loadCustom(String id) {
    final protoStr = GStorage.setting.get(_protocolKey(id)) as String?;
    if (protoStr == null) return null;
    final protocol = AgentApiProvider.values.firstWhere(
      (e) => e.name == protoStr,
      orElse: () => AgentApiProvider.openAICompatible,
    );
    final name =
        GStorage.setting.get(_nameKey(id)) as String? ?? protocol.label;
    return _loadConfig(id, protocol, name);
  }

  /// 读取一个实例的 url/key/models/params（协议与名字由调用方给定）。
  static AgentProviderInstance _loadConfig(
    String id,
    AgentApiProvider protocol,
    String name,
  ) {
    final box = GStorage.setting;
    final baseUrl = box.get(_baseUrlKey(id), defaultValue: '') as String;
    final apiKey = SecureCredentialVault.read(_apiKeyKey(id));
    final models =
        (box.get(_modelsKey(id)) as List?)?.cast<String>().toList() ??
        <String>[];

    // 读取每模型参数；同时丢弃指向已删除模型的孤儿条目
    final modelParams = <String, AgentModelParams>{};
    final rawParams = box.get(_modelParamsKey(id));
    if (rawParams is Map) {
      rawParams.forEach((key, value) {
        if (key is! String || !models.contains(key)) return;
        if (value is! Map) return;
        try {
          modelParams[key] = AgentModelParams.fromJson(
            value.cast<String, dynamic>(),
          );
        } catch (_) {
          // 单条解析失败不影响其他模型
        }
      });
    }

    // 读取每模型能力覆盖；同样丢弃指向已删除模型的孤儿条目
    final modelCaps = <String, AgentModelCapability>{};
    final rawCaps = box.get(_modelCapsKey(id));
    if (rawCaps is Map) {
      rawCaps.forEach((key, value) {
        if (key is! String || !models.contains(key)) return;
        if (value is! Map) return;
        try {
          modelCaps[key] = AgentModelCapability.fromJson(
            value.cast<String, dynamic>(),
          );
        } catch (_) {
          // 单条解析失败不影响其他模型
        }
      });
    }

    // 读取每模型内置工具列表
    final modelBuiltInTools = <String, List<String>>{};
    final rawTools = box.get(_modelToolsKey(id));
    if (rawTools is Map) {
      rawTools.forEach((key, value) {
        if (key is! String || !models.contains(key)) return;
        if (value is! List) return;
        modelBuiltInTools[key] = value.cast<String>().toList();
      });
    }

    return AgentProviderInstance(
      id: id,
      name: name,
      protocol: protocol,
      baseUrl: baseUrl,
      apiKey: apiKey,
      models: models,
      modelParams: modelParams,
      modelCaps: modelCaps,
      modelBuiltInTools: modelBuiltInTools,
    );
  }

  // ── 角色串解析 / 序列化 ────────────────────────────────────────────────

  /// 解析 "instanceId:modelId" → `(id, modelId)`；任一缺失返回 `(null, null)`。
  /// 不再校验枚举——id 是否为有效实例由调用层（loadInstance/byId）判定。
  static (String?, String?) _parseRole(String? raw) {
    if (raw == null || raw.isEmpty) return (null, null);
    final colonIdx = raw.indexOf(':');
    if (colonIdx <= 0 || colonIdx >= raw.length - 1) return (null, null);
    return (raw.substring(0, colonIdx), raw.substring(colonIdx + 1));
  }

  static String _serializeRole(String id, String modelId) => '$id:$modelId';

  // ── 实例增删改 ─────────────────────────────────────────────────────────

  /// 添加一个新实例；返回生成的 id。名字默认取协议 label，重名自动加后缀。
  /// [baseUrl]/[apiKey] 非空时一并写入（创建对话框会预先收齐这些字段）。
  Future<String> addInstance(
    AgentApiProvider protocol, {
    String? name,
    String? baseUrl,
    String? apiKey,
  }) async {
    final box = GStorage.setting;
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final base = (name == null || name.trim().isEmpty)
        ? protocol.label
        : name.trim();
    final finalName = _uniqueName(base);
    await box.put(_protocolKey(id), protocol.name);
    await box.put(_nameKey(id), finalName);
    if (baseUrl != null && baseUrl.isNotEmpty) {
      await box.put(_baseUrlKey(id), baseUrl);
    }
    if (apiKey != null && apiKey.isNotEmpty) {
      await SecureCredentialVault.write(_apiKeyKey(id), apiKey);
    }
    await box.put(_idsKey, [..._loadIds(), id]);
    state = _load();
    return id;
  }

  /// 删除实例：清掉全部 per-id 键 + 从列表移除 + 清空指向它的全局角色。
  /// 内置三家不可删，直接忽略。
  Future<void> removeInstance(String id) async {
    if (isBuiltin(id)) return;
    final box = GStorage.setting;
    await box.put(_idsKey, _loadIds()..remove(id));
    await box.delete(_nameKey(id));
    await box.delete(_protocolKey(id));
    await box.delete(_baseUrlKey(id));
    await SecureCredentialVault.delete(_apiKeyKey(id));
    await box.delete(_modelsKey(id));
    await box.delete(_modelParamsKey(id));
    await box.delete(_modelCapsKey(id));
    await box.delete(_modelToolsKey(id));
    for (final key in [_globalDefaultKey, _globalFastKey, _globalImageKey]) {
      final (rid, _) = _parseRole(box.get(key) as String?);
      if (rid == id) await box.delete(key);
    }
    state = _load();
  }

  /// 在现有名字集合里求唯一名：冲突则追加 " 2"/" 3"…。
  /// 内置三家的固定名与已有自定义名都算占用，避免与「OpenAI」等重名。
  String _uniqueName(String base) {
    final taken = <String>{
      for (final p in _builtinProtocols) p.label.toLowerCase(),
    };
    for (final id in _loadIds()) {
      final n = GStorage.setting.get(_nameKey(id)) as String?;
      if (n != null) taken.add(n.toLowerCase());
    }
    if (!taken.contains(base.toLowerCase())) return base;
    var i = 2;
    while (taken.contains('$base $i'.toLowerCase())) {
      i++;
    }
    return '$base $i';
  }

  Future<void> setBaseUrl(String id, String url) async {
    await GStorage.setting.put(_baseUrlKey(id), url);
    state = _load();
  }

  Future<void> setApiKey(String id, String key) async {
    await SecureCredentialVault.write(_apiKeyKey(id), key);
    state = _load();
  }

  // ── 模型增删改 ─────────────────────────────────────────────────────────

  /// 给实例 [id] 添加模型；可同时设为专家/快速/生图角色（全局唯一，替换旧值）。
  Future<void> addModel(
    String id,
    String modelId, {
    bool setAsDefault = false,
    bool setAsFast = false,
    bool setAsImage = false,
  }) async {
    final box = GStorage.setting;
    final inst = state.byId(id) ?? _loadAny(id);
    if (inst == null) return;
    final updated = inst.models.contains(modelId)
        ? inst.models
        : [...inst.models, modelId];

    await box.put(_modelsKey(id), updated);
    // 新增模型时推断并持久化能力（已存在则不动，保留用户可能的手改）
    if (!inst.models.contains(modelId)) {
      final caps = Map<String, AgentModelCapability>.from(inst.modelCaps);
      caps[modelId] = AgentModelCapability.infer(
        provider: inst.protocol,
        modelId: modelId,
      );
      await box.put(
        _modelCapsKey(id),
        caps.map((k, v) => MapEntry(k, v.toJson())),
      );
    }
    if (setAsDefault) {
      await box.put(_globalDefaultKey, _serializeRole(id, modelId));
    }
    if (setAsFast) {
      await box.put(_globalFastKey, _serializeRole(id, modelId));
    }
    if (setAsImage) {
      await box.put(_globalImageKey, _serializeRole(id, modelId));
    }
    state = _load();
  }

  /// 从实例 [id] 移除模型；级联清空指向它的全局角色与自定义参数。
  Future<void> removeModel(String id, String modelId) async {
    final box = GStorage.setting;
    final inst = state.byId(id) ?? _loadAny(id);
    if (inst == null) return;

    await box.put(
      _modelsKey(id),
      inst.models.where((m) => m != modelId).toList(),
    );
    for (final key in [_globalDefaultKey, _globalFastKey, _globalImageKey]) {
      final (rid, rmodel) = _parseRole(box.get(key) as String?);
      if (rid == id && rmodel == modelId) await box.delete(key);
    }
    if (inst.modelParams.containsKey(modelId)) {
      final params = Map<String, AgentModelParams>.from(inst.modelParams)
        ..remove(modelId);
      await box.put(
        _modelParamsKey(id),
        params.map((k, v) => MapEntry(k, v.toJson())),
      );
    }
    if (inst.modelCaps.containsKey(modelId)) {
      final caps = Map<String, AgentModelCapability>.from(inst.modelCaps)
        ..remove(modelId);
      await box.put(
        _modelCapsKey(id),
        caps.map((k, v) => MapEntry(k, v.toJson())),
      );
    }
    if (inst.modelBuiltInTools.containsKey(modelId)) {
      final tools = Map<String, List<String>>.from(inst.modelBuiltInTools)
        ..remove(modelId);
      await box.put(_modelToolsKey(id), tools);
    }
    state = _load();
  }

  /// 写入指定模型的能力覆盖（手动修正分类/模态/工具/推理）。
  Future<void> setModelCapability(
    String id,
    String modelId,
    AgentModelCapability cap,
  ) async {
    final inst = state.byId(id) ?? _loadAny(id);
    if (inst == null || !inst.models.contains(modelId)) return;
    final caps = Map<String, AgentModelCapability>.from(inst.modelCaps);
    caps[modelId] = cap;
    await GStorage.setting.put(
      _modelCapsKey(id),
      caps.map((k, v) => MapEntry(k, v.toJson())),
    );
    state = _load();
  }

  /// 重置为自动推断：删除该模型的能力覆盖条目，下次读取回落即时推断。
  Future<void> resetModelCapability(String id, String modelId) async {
    final inst = state.byId(id) ?? _loadAny(id);
    if (inst == null || !inst.modelCaps.containsKey(modelId)) return;
    final caps = Map<String, AgentModelCapability>.from(inst.modelCaps)
      ..remove(modelId);
    await GStorage.setting.put(
      _modelCapsKey(id),
      caps.map((k, v) => MapEntry(k, v.toJson())),
    );
    state = _load();
  }

  // ── 模型参数（思考强度）─────────────────────────────────────────────────

  Future<void> setModelThinkingLevel(
    String id,
    String modelId,
    ThinkingLevel? level,
  ) async {
    final inst = state.byId(id) ?? _loadAny(id);
    if (inst == null || !inst.models.contains(modelId)) return;
    final params = Map<String, AgentModelParams>.from(inst.modelParams);
    final current = params[modelId] ?? const AgentModelParams();
    final updated = current.copyWith(thinkingLevel: level);
    if (updated.isDefault) {
      params.remove(modelId);
    } else {
      params[modelId] = updated;
    }
    await GStorage.setting.put(
      _modelParamsKey(id),
      params.map((k, v) => MapEntry(k, v.toJson())),
    );
    state = _load();
  }

  // ── 内置工具 ──────────────────────────────────────────────────────────

  Future<void> setModelBuiltInTools(
    String id,
    String modelId,
    Set<String> tools,
  ) async {
    final inst = state.byId(id) ?? _loadAny(id);
    if (inst == null || !inst.models.contains(modelId)) return;
    final all = Map<String, List<String>>.from(inst.modelBuiltInTools);
    if (tools.isEmpty) {
      all.remove(modelId);
    } else {
      all[modelId] = tools.toList();
    }
    await GStorage.setting.put(_modelToolsKey(id), all);
    state = _load();
  }

  // ── 全局角色（写）──────────────────────────────────────────────────────

  Future<void> setGlobalDefaultModel(String? id, String? modelId) =>
      _setRole(_globalDefaultKey, id, modelId);

  Future<void> setGlobalFastModel(String? id, String? modelId) =>
      _setRole(_globalFastKey, id, modelId);

  Future<void> setGlobalImageModel(String? id, String? modelId) =>
      _setRole(_globalImageKey, id, modelId);

  Future<void> _setRole(String key, String? id, String? modelId) async {
    final box = GStorage.setting;
    if (id != null && modelId != null) {
      await box.put(key, _serializeRole(id, modelId));
    } else {
      await box.delete(key);
    }
    state = _load();
  }

  // ── 全局角色（读，静态）────────────────────────────────────────────────

  static ({String? id, String? modelId}) get globalDefaultRole {
    final (id, m) = _parseRole(
      GStorage.setting.get(_globalDefaultKey) as String?,
    );
    return (id: id, modelId: m);
  }

  static ({String? id, String? modelId}) get globalFastRole {
    final (id, m) = _parseRole(GStorage.setting.get(_globalFastKey) as String?);
    return (id: id, modelId: m);
  }

  static ({String? id, String? modelId}) get globalImageRole {
    final (id, m) = _parseRole(
      GStorage.setting.get(_globalImageKey) as String?,
    );
    return (id: id, modelId: m);
  }

  // ── 调用层解析 ─────────────────────────────────────────────────────────

  /// 加载单实例的「已解析视图」，并把**指向它**的全局角色填进对应模型字段。
  /// 调用层（生图/翻译）据此取 protocol/baseUrl/apiKey/modelId。无此实例返回 null。
  static AgentApiState? loadInstance(String id) {
    final inst = _loadAny(id);
    if (inst == null) return null;
    final box = GStorage.setting;
    final (dId, dModel) = _parseRole(box.get(_globalDefaultKey) as String?);
    final (fId, fModel) = _parseRole(box.get(_globalFastKey) as String?);
    final (iId, iModel) = _parseRole(box.get(_globalImageKey) as String?);
    bool owns(String? rid, String? rmodel) =>
        rid == id && rmodel != null && inst.models.contains(rmodel);
    return AgentApiState(
      id: inst.id,
      name: inst.name,
      provider: inst.protocol,
      baseUrl: inst.baseUrl,
      apiKey: inst.apiKey,
      models: inst.models,
      defaultModelId: owns(dId, dModel) ? dModel : null,
      fastModelId: owns(fId, fModel) ? fModel : null,
      imageModelId: owns(iId, iModel) ? iModel : null,
      modelParams: inst.modelParams,
    );
  }

  /// 解析「文本调用」的有效实例：快速角色 → 专家角色 → 生图角色 所属实例。
  static AgentApiState? resolveEffectiveState() {
    final targetId =
        globalFastRole.id ?? globalDefaultRole.id ?? globalImageRole.id;
    if (targetId == null) return null;
    return loadInstance(targetId);
  }

  void reload() {
    state = _load();
  }
}

final agentApiProvider =
    StateNotifierProvider<AgentApiNotifier, AgentProvidersState>(
      (ref) => AgentApiNotifier(),
    );

/// 用于 API 调用的「文本角色」有效状态。
///
/// 解析顺序：快速角色 → 专家角色 → 生图角色 所属实例。无任何角色时返回空 state，
/// 触发 [AiSettingsPrompt] 的「请先选择模型」提示。设置页不读它（用 [agentApiProvider]）。
final effectiveAgentApiProvider = Provider<AgentApiState>((ref) {
  ref.watch(agentApiProvider); // 实例 / 角色变更时重算
  return AgentApiNotifier.resolveEffectiveState() ?? const AgentApiState();
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

  const DocExtractApiState({
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
  static const _apiKeyKey = 'doc_extract_api_key';
  static const _prefix = 'doc_extract_';

  DocExtractApiNotifier() : super(_load());

  static DocExtractApiState _load() {
    final box = GStorage.setting;

    final apiKey = SecureCredentialVault.read(_apiKeyKey);
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

  Future<void> setApiKey(String key) async {
    state = state.copyWith(apiKey: key);
    await SecureCredentialVault.write(_apiKeyKey, key);
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
