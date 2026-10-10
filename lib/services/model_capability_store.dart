import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../core/storage/settings_keys.dart';
import '../core/storage/storage.dart';
import 'agent_http.dart';
import '../data/models/ai/agent_config.dart';

/// 模型能力规则集订阅（geosite 模式）：远程 jsdelivr CDN 拉取
/// `Cyli00/modelcaps` 仓库的 `model_capabilities.json`，本地文件缓存 +
/// ETag/Last-Modified 条件请求 + TTL 后台刷新 + 手动强制更新。
///
/// 优先级链在 `AgentProviderInstance.capabilityFor` 内：用户手动覆写 > 本
/// 远程表 > 兜底（全 false）。本 Store 只负责远程表的拉取/缓存/查询，不参与优先级。
///
/// 缓存文件落 `GStorage.dbDirPath`（app 数据目录，非文献库）；ETag/时间/
/// 版本/间隔走 `GStorage.setting`（SettingsStore 唯一入口）。HTTP 复用
/// `AgentHttp`（接入代理总线）。
class ModelCapabilityStore {
  ModelCapabilityStore._();
  static final ModelCapabilityStore instance = ModelCapabilityStore._();

  static const _remoteUrl =
      'https://cdn.jsdelivr.net/gh/Cyli00/modelcaps@main/model_capabilities.json';
  static const _cacheFileName = 'model_caps_cache.json';

  // ── settings keys ──
  static const _kLastFetched = SettingsKeys.modelCapsLastFetchedAt;
  static const _kEtag = SettingsKeys.modelCapsEtag;
  static const _kLastModified = SettingsKeys.modelCapsLastModified;
  static const _kVersion = SettingsKeys.modelCapsVersion;

  final Map<String, AgentModelCapability> _models = {};
  final Map<String, ThinkingSpec> _thinking = {};
  String? _version;
  DateTime? _fetchedAt;
  bool _loaded = false;

  /// 远程表版本（生成日期，YYYY-MM-DD）。
  String? get version => _version;

  /// 上次成功抓取时间（用于 TTL 判定 + UI 展示）。
  DateTime? get fetchedAt => _fetchedAt;

  /// 启动加载本地缓存。不阻塞网络：读缓存文件 + settings 元数据；
  /// 缓存不存在时 _models 为空，capabilityFor 回退兜底（全 false）。
  Future<void> init() async {
    if (_loaded) return;
    await _loadCache();
    _loaded = true;
    // 首启无本地缓存 → 同步拉一次远程表，确保能力判定有数据（不回退兜底）。
    // 有缓存时由 checkUpdateIfNeeded 按 TTL 后台刷新。
    if (_models.isEmpty) {
      await _fetch();
    }
  }

  Future<void> _loadCache() async {
    final file = File(p.join(GStorage.dbDirPath, _cacheFileName));
    if (!await file.exists()) return;
    try {
      final doc = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _replaceModels(doc);
      _version = doc['version'] as String?;
      final fetched = GStorage.setting.get(_kLastFetched) as String?;
      _fetchedAt = fetched == null ? null : DateTime.tryParse(fetched);
    } catch (_) {
      // 缓存损坏 → 视为无缓存，回退兜底（全 false）
      _models.clear();
      _thinking.clear();
    }
  }

  void _replaceModels(Map<String, dynamic> doc) {
    final models = doc['models'] as Map<String, dynamic>? ?? {};
    _models.clear();
    _thinking.clear();
    for (final e in models.entries) {
      final key = e.key.toLowerCase();
      _models[key] = _capFromRemote(e.value);
      final thinking = (e.value as Map<String, dynamic>)['thinking'];
      if (thinking is Map<String, dynamic>) {
        _thinking[key] = ThinkingSpec.fromJson(thinking);
      }
    }
  }

  /// 远程表条目 → AgentModelCapability。textInput/textOutput 远程表不显式
  /// 标（恒为 true，对话模型固有），此处补齐。
  AgentModelCapability _capFromRemote(dynamic v) {
    final m = v as Map<String, dynamic>;
    return AgentModelCapability(
      textInput: true,
      imageInput: m['imageInput'] as bool? ?? false,
      textOutput: true,
      imageOutput: m['imageOutput'] as bool? ?? false,
      embedding: m['embedding'] as bool? ?? false,
      tool: m['tool'] as bool? ?? false,
      reasoning: m['reasoning'] as bool? ?? false,
      webSearch: m['webSearch'] as bool? ?? false,
    );
  }

  /// 查询：model id → 能力（远程表命中），未命中返回 null。
  ///
  /// 入参可为全 id（如 `xiaomi/mimo-v2.5-pro`）或第三方服务商加了前后缀的
  /// 变体（`deepseek-v4.1-flash-fast`）：按 [modelIdCandidates] 由严到宽逐个
  /// 尝试，命中即停。否则变体 id 永远 miss，被迫回退兜底（全 false）→ 能力漏标。
  AgentModelCapability? lookup(String modelId) {
    final key = _resolveKey(modelId);
    return key == null ? null : _models[key];
  }

  /// 查询：model id → 思考参数规格，与 [lookup] 命中同一条目；该条目无
  /// `thinking` 字段（上游未提供）时返回 null，调用方回退到识别规则。
  ThinkingSpec? thinkingSpec(String modelId) {
    final key = _resolveKey(modelId);
    return key == null ? null : _thinking[key];
  }

  String? _resolveKey(String modelId) {
    if (!_loaded) return null;
    for (final candidate in modelIdCandidates(modelId)) {
      if (_models.containsKey(candidate)) return candidate;
    }
    return null;
  }

  /// 生图模型判定：查远程表 imageOutput，未命中（modelcaps 未收录/离线）返回
  /// false——这类模型能力置空，由用户在能力卡片手动指定（方案 C）。
  /// lookup 内部已做纯 id 提取。
  bool isImageGenerationModel(String modelId) =>
      lookup(modelId)?.imageOutput ?? false;

  bool get _dueForUpdate {
    if (_fetchedAt == null) return true;
    final fetchedUtc = _fetchedAt!.toUtc();
    // fetchedAt 所在 UTC 日的次日 0 点 = 下次更新时间（与 modelcaps CI
    // 每日 UTC 0 点 build 对齐——过 UTC 0 点即视为新一天，需拉取）。
    final nextUpdate = DateTime.utc(
      fetchedUtc.year,
      fetchedUtc.month,
      fetchedUtc.day,
    ).add(const Duration(days: 1));
    return !DateTime.now().toUtc().isBefore(nextUpdate);
  }

  /// 启动后后台检查：TTL 到了就拉一次。失败静默（保留旧缓存，不抛）。
  Future<void> checkUpdateIfNeeded() async {
    if (!_dueForUpdate) return;
    await _fetch();
  }

  Future<bool> _fetch() async {
    final dio = AgentHttp.instance.dio(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
    );
    final headers = <String, dynamic>{};
    final etag = GStorage.setting.get(_kEtag) as String?;
    if (etag != null && etag.isNotEmpty) headers['If-None-Match'] = etag;
    final lastMod = GStorage.setting.get(_kLastModified) as String?;
    if (lastMod != null && lastMod.isNotEmpty) {
      headers['If-Modified-Since'] = lastMod;
    }
    try {
      final resp = await dio.get<dynamic>(
        _remoteUrl,
        options: Options(headers: headers),
      );
      if (resp.statusCode == 304) return false;
      final doc = resp.data is Map
          ? resp.data as Map<String, dynamic>
          : jsonDecode(resp.data as String) as Map<String, dynamic>;
      _replaceModels(doc);
      _version = doc['version'] as String?;
      _fetchedAt = DateTime.now();
      // 落盘缓存
      final file = File(p.join(GStorage.dbDirPath, _cacheFileName));
      await file.writeAsString(jsonEncode(doc));
      // 元数据存 settings（响应头优先，回退旧值）
      final respHeaders = resp.headers.map;
      final newEtag = respHeaders['etag']?.first ?? etag;
      final newLastMod = respHeaders['last-modified']?.first ?? lastMod;
      await Future.wait([
        if (newEtag != null) GStorage.setting.put(_kEtag, newEtag),
        if (newLastMod != null)
          GStorage.setting.put(_kLastModified, newLastMod),
        GStorage.setting.put(_kLastFetched, _fetchedAt!.toIso8601String()),
        if (_version != null) GStorage.setting.put(_kVersion, _version!),
      ]);
      return true;
    } catch (_) {
      return false; // 网络失败 → 保留旧缓存
    }
  }
}

/// 不改变能力的变体后缀词：第三方服务商常在原厂 id 后追加这些段表示加速线路、
/// 别名或地域。`mini`/`pro`/`flash`/`lite`/`vision`/`nano`/版本号等会改变
/// 能力的段不在此列，永不剥离（否则 `gpt-5-mini` 会被当成 `gpt-5`）。
const _variantSuffixes = {
  'fast',
  'turbo',
  'latest',
  'preview',
  'exp',
  'free',
  'thinking',
  'us',
  'eu',
  'global',
};

/// 日期戳段（`0731`、`20250929`）。
final _dateSegment = RegExp(r'^\d{4,8}$');

/// 点号厂商/地域前缀（`us.anthropic.`、`anthropic.`）：纯字母段 + 点。
/// `gpt-5.1`、`deepseek-v4.1` 的首段含 `-` 或数字，不会被误剥。
final _dottedVendorPrefix = RegExp(r'^(?:[a-z]+\.)+(?=[a-z])');

/// 远程表查询的候选 id，由严到宽：原纯 id → 去 `:xxx`/`@xxx` 尾巴与点号
/// 厂商前缀 → 从末尾逐段剥离变体后缀词/日期戳。原 id 永远排第一，表里有
/// 专门条目的变体（如 `claude-opus-4.8-fast`）不受影响。
List<String> modelIdCandidates(String modelId) {
  final out = <String>[];
  void add(String s) {
    if (s.isNotEmpty && !out.contains(s)) out.add(s);
  }

  var id = modelId.trim().toLowerCase().split('/').last;
  add(id);
  id = id.split(RegExp('[:@]')).first.replaceFirst(_dottedVendorPrefix, '');
  add(id);
  var parts = id.split('-');
  while (parts.length > 1 &&
      (_variantSuffixes.contains(parts.last) ||
          _dateSegment.hasMatch(parts.last))) {
    parts = parts.sublist(0, parts.length - 1);
    add(parts.join('-'));
  }
  return out;
}

extension AgentProviderCapabilities on AgentProviderInstance {
  /// 取模型能力，优先级：用户手动覆写 > 远程能力表(geosite 订阅) > 正则推断。
  AgentModelCapability capabilityFor(String modelId) {
    final manual = modelCaps[modelId];
    if (manual != null) return manual;
    final remote = ModelCapabilityStore.instance.lookup(modelId);
    if (remote != null) return remote;
    return AgentModelCapability.infer(provider: protocol, modelId: modelId);
  }
}
