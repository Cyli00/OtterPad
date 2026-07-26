import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/secure_credential_vault.dart';
import '../core/storage/storage.dart';
import '../services/agent_model_capability.dart';
import '../services/model_capability_store.dart';

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

  /// 实际线上协议：xAI（Grok）已停用 OpenAI 兼容的 Chat Completions、仅保留
  /// 与 OpenAI Responses 同形的自家 Responses API，按 host 升格为
  /// [AgentApiProvider.openai]；其余原样。不进协议枚举——添加服务商仍只见
  /// 4 种协议。请求构造 / 连通性检测 / 工具支持判定统一先过这一层。
  AgentApiProvider wireProtocol(String baseUrl) =>
      this == AgentApiProvider.openAICompatible && _isXaiHost(baseUrl)
      ? AgentApiProvider.openai
      : this;

  /// chat 端点完整 URL（已按 [wireProtocol] 解析，xAI 返回 `/responses`）。
  /// baseUrl 末尾已带版本段（/v1、/v3、/v4、/v1beta…）时不再追加默认版本、
  /// 直接接资源路径——兼容 Zhipu(/api/paas/v4)、Doubao(/api/v3) 等非 /v1
  /// 版本段的厂商，以及用户填带版本反代地址的场景。
  /// Gemini 返回值不含 `/models/{model}:generateContent`，由调用方追加。
  String chatUrl(String baseUrl) {
    final wire = wireProtocol(baseUrl);
    final base = _trimTrailingSlash(baseUrl);
    if (!_versionTailRe.hasMatch(base)) return '$base${wire.chatPath}';
    return switch (wire) {
      AgentApiProvider.openai => '$base/responses',
      AgentApiProvider.anthropic => '$base/messages',
      AgentApiProvider.gemini => base,
      AgentApiProvider.openAICompatible => '$base/chat/completions',
    };
  }

  /// 模型列表端点完整 URL，版本段处理同 [chatUrl]。
  String modelsUrl(String baseUrl) {
    final base = _trimTrailingSlash(baseUrl);
    if (!_versionTailRe.hasMatch(base)) return '$base$modelsPath';
    return '$base/models';
  }
}

/// URL 末尾版本段（/v1、/v3、/v4、/v1beta、/v1beta2 等）
final _versionTailRe = RegExp(r'/v[\da-z.]+$');

/// xAI 官方域名（api.x.ai 等），接受 baseUrl 或完整 chat URL（host 相同）。
bool _isXaiHost(String url) {
  final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
  return host == 'x.ai' || host.endsWith('.x.ai');
}

String _trimTrailingSlash(String url) =>
    url.endsWith('/') ? url.substring(0, url.length - 1) : url;

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

  /// 每模型能力（分类 + 模态 + 工具/推理）。缺失项由 [capabilityFor] 即时推断兜底。
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

  /// 取模型能力，优先级：用户手动覆写 > 远程能力表(geosite 订阅) > 正则推断。
  AgentModelCapability capabilityFor(String modelId) {
    final manual = modelCaps[modelId];
    if (manual != null) return manual;
    final remote = ModelCapabilityStore.instance.lookup(modelId);
    if (remote != null) return remote;
    return AgentModelCapability.infer(provider: protocol, modelId: modelId);
  }
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

/// Agent 服务商配置的整体状态：有序实例列表 + 全局角色。
///
/// 角色（专家/快速/生图）以 `({String? id, String? modelId})` 存入 state，
/// 支持 `ref.watch(provider.select((s) => s.defaultRole))` 细粒度订阅。
/// 服务层无 `ref` 时仍可用 [AgentApiNotifier] 的静态 getter。
class AgentProvidersState {
  final List<AgentProviderInstance> instances;
  final ({String? id, String? modelId}) defaultRole;
  final ({String? id, String? modelId}) fastRole;
  final ({String? id, String? modelId}) imageRole;

  const AgentProvidersState({
    this.instances = const [],
    this.defaultRole = _noRole,
    this.fastRole = _noRole,
    this.imageRole = _noRole,
  });

  AgentProviderInstance? byId(String? id) {
    if (id == null) return null;
    for (final inst in instances) {
      if (inst.id == id) return inst;
    }
    return null;
  }
}

const ({String? id, String? modelId}) _noRole = (id: null, modelId: null);

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

  /// 内置服务商——永远常驻列表、不可删除、名字锁定。前三家直连各自协议，
  /// id 固定为协议名（兼容历史数据）；其余为主流 OpenAI 兼容厂商预设
  /// （提供 Chat Completions / Anthropic 双接口的厂商统一走 Chat Completions）。
  /// 各家 base URL 与 key 格式均按官方文档核实；Zhipu / Doubao 无 OpenAI
  /// 兼容的 GET /models 列表端点，模型靠管理弹窗的手动添加行录入。
  static const _builtinPresets = [
    AgentVendorPreset('openai', 'OpenAI', AgentApiProvider.openai,
        '', '', 'https://platform.openai.com/api-keys'),
    AgentVendorPreset('anthropic', 'Anthropic', AgentApiProvider.anthropic,
        '', '', 'https://console.anthropic.com/settings/keys'),
    AgentVendorPreset('gemini', 'Gemini', AgentApiProvider.gemini,
        '', '', 'https://aistudio.google.com/app/api-keys'),
    AgentVendorPreset(
      'deepseek',
      'DeepSeek',
      AgentApiProvider.openAICompatible,
      'https://api.deepseek.com',
      'sk-...',
      'https://platform.deepseek.com/api_keys',
    ),
    AgentVendorPreset(
      'qwen',
      'Qwen',
      AgentApiProvider.openAICompatible,
      'https://dashscope.aliyuncs.com/compatible-mode/v1',
      'sk-...',
      'https://bailian.console.aliyun.com/cn-beijing?tab=model#/api-key',
    ),
    AgentVendorPreset(
      'zhipu',
      'Zhipu GLM',
      AgentApiProvider.openAICompatible,
      'https://open.bigmodel.cn/api/paas/v4',
      '{id}.{secret}',
      'https://www.bigmodel.cn/invite?icode=kLOZSS2OB1GRYGoRuFBBh%2F2gad6AKpjZefIo3dVEQyA%3D',
    ),
    AgentVendorPreset(
      'kimi',
      'Kimi',
      AgentApiProvider.openAICompatible,
      'https://api.moonshot.cn/v1',
      'sk-...',
      'https://platform.kimi.com/console/api-keys',
    ),
    AgentVendorPreset(
      'doubao',
      'Doubao',
      AgentApiProvider.openAICompatible,
      'https://ark.cn-beijing.volces.com/api/v3',
      'API Key (UUID)',
      'https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey?apikey=%7B%7D',
    ),
    AgentVendorPreset(
      'mimo',
      'MiMo',
      AgentApiProvider.openAICompatible,
      'https://api.xiaomimimo.com/v1',
      'API Key',
      'https://platform.xiaomimimo.com?ref=MQJS4T',
    ),
    AgentVendorPreset(
      'grok',
      'Grok',
      AgentApiProvider.openAICompatible,
      'https://api.x.ai/v1',
      'xai-...',
      'https://console.x.ai',
    ),
  ];

  /// 该 id 是否为内置预设（内置不进 _idsKey、不可删、名字锁定）。
  static bool isBuiltin(String id) => _builtinPresets.any((p) => p.id == id);

  /// 内置厂商预设的 API key 提示；非预设实例或预设未配置时返回 null
  /// （调用方回落到协议默认提示）。
  static String? presetKeyHint(String id) {
    for (final p in _builtinPresets) {
      if (p.id == id) return p.keyHint.isEmpty ? null : p.keyHint;
    }
    return null;
  }

  /// 内置预设的 API Key 获取页面；非预设或未配置时返回 null。
  static String? presetApiKeyUrl(String id) {
    for (final p in _builtinPresets) {
      if (p.id == id) return p.apiKeyUrl.isEmpty ? null : p.apiKeyUrl;
    }
    return null;
  }

  AgentApiNotifier() : super(_load());

  // ── 加载 ──────────────────────────────────────────────────────────────

  static List<String> _loadIds() {
    final raw = GStorage.setting.get(_idsKey) as List?;
    return raw?.cast<String>().where((e) => e.isNotEmpty).toList() ??
        <String>[];
  }

  /// 列表 = 内置预设（恒在）+ _idsKey 里的自定义实例（按序）。
  static AgentProvidersState _load() {
    final box = GStorage.setting;
    final instances = <AgentProviderInstance>[
      for (final p in _builtinPresets)
        _loadConfig(p.id, p.protocol, p.label, defaultBaseUrl: p.baseUrl),
    ];
    for (final id in _loadIds()) {
      final inst = _loadCustom(id);
      if (inst != null) instances.add(inst);
    }
    final (dId, dModel) = _parseRole(box.get(_globalDefaultKey) as String?);
    final (fId, fModel) = _parseRole(box.get(_globalFastKey) as String?);
    final (iId, iModel) = _parseRole(box.get(_globalImageKey) as String?);
    return AgentProvidersState(
      instances: instances,
      defaultRole: (id: dId, modelId: dModel),
      fastRole: (id: fId, modelId: fModel),
      imageRole: (id: iId, modelId: iModel),
    );
  }

  /// 按 id 加载任意实例（内置或自定义）；自定义协议键缺失返回 null。
  static AgentProviderInstance? _loadAny(String id) {
    for (final p in _builtinPresets) {
      if (p.id == id) {
        return _loadConfig(id, p.protocol, p.label, defaultBaseUrl: p.baseUrl);
      }
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
  /// [defaultBaseUrl]：厂商预设的默认地址，用户未填时生效。
  static AgentProviderInstance _loadConfig(
    String id,
    AgentApiProvider protocol,
    String name, {
    String defaultBaseUrl = '',
  }) {
    final box = GStorage.setting;
    var baseUrl = box.get(_baseUrlKey(id), defaultValue: '') as String;
    if (baseUrl.isEmpty) baseUrl = defaultBaseUrl;
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

    return AgentProviderInstance(
      id: id,
      name: name,
      protocol: protocol,
      baseUrl: baseUrl,
      apiKey: apiKey,
      models: models,
      modelParams: modelParams,
      modelCaps: modelCaps,
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
  /// 内置预设不可删，直接忽略。
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
    // 遗留键：旧版「每模型内置工具」配置（功能已移除），删实例时顺带清理
    await box.delete(_modelToolsKey(id));
    for (final key in [_globalDefaultKey, _globalFastKey, _globalImageKey]) {
      final (rid, _) = _parseRole(box.get(key) as String?);
      if (rid == id) await box.delete(key);
    }
    state = _load();
  }

  /// 在现有名字集合里求唯一名：冲突则追加 " 2"/" 3"…。
  /// 内置预设的固定名与已有自定义名都算占用，避免与「OpenAI」等重名。
  String _uniqueName(String base) {
    final taken = <String>{
      for (final p in _builtinPresets) p.label.toLowerCase(),
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
  final s = ref.watch(agentApiProvider);
  final targetId = s.fastRole.id ?? s.defaultRole.id ?? s.imageRole.id;
  if (targetId == null) return const AgentApiState();
  return AgentApiNotifier.loadInstance(targetId) ?? const AgentApiState();
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
  final bool mergeTables;
  final String layoutShapeMode;
  final double repetitionPenalty;
  final double temperature;

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
    this.mergeTables = true,
    this.layoutShapeMode = 'auto',
    this.repetitionPenalty = 1.0,
    this.temperature = 0.0,
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
    bool? mergeTables,
    String? layoutShapeMode,
    double? repetitionPenalty,
    double? temperature,
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
    mergeTables: mergeTables ?? this.mergeTables,
    layoutShapeMode: layoutShapeMode ?? this.layoutShapeMode,
    repetitionPenalty: repetitionPenalty ?? this.repetitionPenalty,
    temperature: temperature ?? this.temperature,
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
    final mergeTables =
        box.get('${_prefix}mergeTables', defaultValue: true) as bool;
    final layoutShapeMode =
        box.get('${_prefix}layoutShapeMode', defaultValue: 'auto') as String;
    final repetitionPenalty =
        box.get('${_prefix}repetitionPenalty', defaultValue: 1.0) as double;
    final temperature =
        box.get('${_prefix}temperature', defaultValue: 0.0) as double;

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
      mergeTables: mergeTables,
      layoutShapeMode: layoutShapeMode,
      repetitionPenalty: repetitionPenalty,
      temperature: temperature,
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
      case 'mergeTables':
        state = state.copyWith(mergeTables: value);
    }
    await GStorage.setting.put('$_prefix$field', value);
  }

  Future<void> setDouble(String field, double value) async {
    switch (field) {
      case 'repetitionPenalty':
        state = state.copyWith(repetitionPenalty: value);
      case 'temperature':
        state = state.copyWith(temperature: value);
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

  /// 重置除 API Key 外的所有提取配置为默认值（清除持久化键，state 回落到默认构造）。
  Future<void> resetExceptApiKey() async {
    final box = GStorage.setting;
    const fields = [
      'useChartRecognition',
      'useDocOrientationClassify',
      'useDocUnwarping',
      'useSealRecognition',
      'useOcrForImageBlock',
      'restructurePages',
      'layoutNms',
      'mergeTables',
      'layoutShapeMode',
      'repetitionPenalty',
      'temperature',
      'markdownIgnoreLabels',
    ];
    for (final f in fields) {
      await box.delete('$_prefix$f');
    }
    state = DocExtractApiState(apiKey: state.apiKey);
  }

  void reload() {
    state = _load();
  }
}

final docExtractApiProvider =
    StateNotifierProvider<DocExtractApiNotifier, DocExtractApiState>(
      (ref) => DocExtractApiNotifier(),
    );
