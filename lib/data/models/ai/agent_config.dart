import 'agent_protocol.dart';
import 'agent_model_capability.dart';

export 'agent_protocol.dart';
export 'agent_model_capability.dart';

/// 内置服务商预设条目：常驻实例、不可删除、名字锁定。
/// [baseUrl] 为空表示用协议默认地址；非空（厂商预设）作为该实例的默认地址，
/// 用户在设置页改过后以用户值为准。[keyHint] 为空时用协议默认提示。
class AgentVendorPreset {
  final String id;
  final String label;
  final AgentApiProvider protocol;
  final String baseUrl;
  final String keyHint;
  final String apiKeyUrl;
  const AgentVendorPreset(
    this.id,
    this.label,
    this.protocol, [
    this.baseUrl = '',
    this.keyHint = '',
    this.apiKeyUrl = '',
  ]);
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
/// * OpenAI Responses API：`verbosity` / `parallelToolCalls` / `truncation`
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
        thinkingLevel: ThinkingLevel.fromId(json['thinkingLevel'] as String?),
        verbosity: json['verbosity'] as String?,
        parallelToolCalls: json['parallelToolCalls'] as bool?,
        truncation: json['truncation'] as String?,
        presencePenalty: (json['presencePenalty'] as num?)?.toDouble(),
        frequencyPenalty: (json['frequencyPenalty'] as num?)?.toDouble(),
      );
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

  /// 每模型能力（分类 + 模态 + 工具/推理）。缺失项由服务层查询远程能力表或推断。
  final Map<String, AgentModelCapability> modelCaps;

  const AgentProviderInstance({
    required this.id,
    required this.name,
    required this.protocol,
    this.baseUrl = '',
    this.apiKey = '',
    this.models = const [],
    this.modelParams = const {},
    this.modelCaps = const {},
  });

  /// 当前生效的 Base URL（用户未填时取协议默认值）
  String get effectiveBaseUrl =>
      baseUrl.isNotEmpty ? baseUrl : protocol.defaultBaseUrl;

  AgentModelParams paramsFor(String modelId) =>
      modelParams[modelId] ?? const AgentModelParams();
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
