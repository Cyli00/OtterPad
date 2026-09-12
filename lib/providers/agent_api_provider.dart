import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/secure_credential_vault.dart';
import '../core/storage/settings_keys.dart';
import '../core/storage/storage.dart';

import '../data/models/ai/agent_config.dart';
export '../data/models/ai/agent_config.dart';

/// Agent 服务商配置的整体状态：有序实例列表 + 全局角色。
///
/// 角色（专家/快速/生图）以 `({String? id, String? modelId})` 存入 state，
/// 支持 `ref.watch(provider.select((s) => s.defaultRole))` 细粒度订阅。
/// 无 `ref` 的配置读取仍可用 [AgentApiNotifier] 的静态 getter。
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
  static String _nameKey(String id) => SettingsKeys.agentApiName(id);
  static String _protocolKey(String id) => SettingsKeys.agentApiProtocol(id);
  static String _baseUrlKey(String id) => SettingsKeys.agentApiBaseUrl(id);
  static String _apiKeyKey(String id) => 'agent_api_key_$id';
  static String _modelsKey(String id) => SettingsKeys.agentApiModels(id);
  static String _modelParamsKey(String id) =>
      SettingsKeys.agentApiModelParams(id);
  static String _modelCapsKey(String id) => SettingsKeys.agentApiModelCaps(id);
  static String _modelToolsKey(String id) =>
      SettingsKeys.agentApiModelTools(id);

  /// 有序实例 id 列表——定义「有哪些实例、什么顺序」。
  static const _idsKey = SettingsKeys.agentApiProviderIds;

  // 专家 / 快速 / 生图模型角色**全局唯一**；存储为 "instanceId:modelId"。
  // 空字符串或缺失均视为未设置。
  static const _globalDefaultKey = SettingsKeys.agentApiDefaultModelGlobal;
  static const _globalFastKey = SettingsKeys.agentApiFastModelGlobal;
  static const _globalImageKey = SettingsKeys.agentApiImageModelGlobal;

  /// 内置服务商——永远常驻列表、不可删除、名字锁定。前三家直连各自协议，
  /// id 固定为协议名（兼容历史数据）；其余为主流 OpenAI 兼容厂商预设
  /// （提供 Chat Completions / Anthropic 双接口的厂商统一走 Chat Completions）。
  /// 各家 base URL 与 key 格式均按官方文档核实；Zhipu / Doubao 无 OpenAI
  /// 兼容的 GET /models 列表端点，模型靠管理弹窗的手动添加行录入。
  static const _builtinPresets = [
    AgentVendorPreset(
      'openai',
      'OpenAI',
      AgentApiProvider.openai,
      '',
      '',
      'https://platform.openai.com/api-keys',
    ),
    AgentVendorPreset(
      'anthropic',
      'Anthropic',
      AgentApiProvider.anthropic,
      '',
      '',
      'https://console.anthropic.com/settings/keys',
    ),
    AgentVendorPreset(
      'gemini',
      'Gemini',
      AgentApiProvider.gemini,
      '',
      '',
      'https://aistudio.google.com/app/api-keys',
    ),
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

  /// 一次性迁移：清除旧 addModel 写入的「全默认值」手动覆写（imageInput/
  /// imageOutput/embedding/tool/reasoning/webSearch 全 false）。这种覆写会把
  /// capabilityFor 锁死在全 false、屏蔽远程表（见 addModel 注释）。迁移后
  /// capabilityFor 重新走远程表 > 正则兜底。用户 deliberate 的手改通常含某
  /// 能力 true，不会被误清。idempotent：标志位 _kCapsMigrationV1 守护。
  static const _kCapsMigrationV1 = 'agent_api_caps_migration_v1';

  static void _migrateCapsV1() {
    final box = GStorage.setting;
    if (box.get(_kCapsMigrationV1) == true) return;
    final ids = <String>[for (final p in _builtinPresets) p.id, ..._loadIds()];
    for (final id in ids) {
      final key = _modelCapsKey(id);
      final raw = box.get(key);
      if (raw is! Map) continue;
      final caps = Map<String, dynamic>.from(raw);
      caps.removeWhere((_, v) {
        if (v is! Map) return false;
        return (v['imageInput'] as bool? ?? false) == false &&
            (v['imageOutput'] as bool? ?? false) == false &&
            (v['embedding'] as bool? ?? false) == false &&
            (v['tool'] as bool? ?? false) == false &&
            (v['reasoning'] as bool? ?? false) == false &&
            (v['webSearch'] as bool? ?? false) == false;
      });
      if (caps.isEmpty) {
        box.delete(key);
      } else {
        box.put(key, caps);
      }
    }
    box.put(_kCapsMigrationV1, true);
  }

  /// 列表 = 内置预设（恒在）+ _idsKey 里的自定义实例（按序）。
  static AgentProvidersState _load() {
    _migrateCapsV1();
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
    // 不在此持久化推断能力：旧逻辑把推断结果当「手动覆写」写进 modelCaps，
    // 而 capabilityFor 中手动覆写优先级最高 → 远程表日更被永久屏蔽（正是
    // 「卡片全无能力 / 专家模型不显示」回归根因）。现在留空，让 capabilityFor
    // 实时走「手动覆写(无) > 远程表 > 正则兜底」。用户手改仍经 setModelCapability。
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
