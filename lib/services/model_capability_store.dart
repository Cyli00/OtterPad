import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../core/storage/storage.dart';
import 'agent_http.dart';
import 'agent_model_capability.dart';

/// 模型能力规则集订阅（geosite 模式）：远程 jsdelivr CDN 拉取
/// `Cyli00/modelcaps` 仓库的 `model_capabilities.json`，本地文件缓存 +
/// ETag/Last-Modified 条件请求 + TTL 后台刷新 + 手动强制更新。
///
/// 优先级链在 `AgentProviderInstance.capabilityFor` 内：用户手动覆写 > 本
/// 远程表 > 正则推断。本 Store 只负责远程表的拉取/缓存/查询，不参与优先级。
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
  static const _kLastFetched = 'model_caps_last_fetched_at';
  static const _kEtag = 'model_caps_etag';
  static const _kLastModified = 'model_caps_last_modified';
  static const _kVersion = 'model_caps_version';

  final Map<String, AgentModelCapability> _models = {};
  String? _version;
  DateTime? _fetchedAt;
  bool _loaded = false;

  /// 远程表版本（生成日期，YYYY-MM-DD）。
  String? get version => _version;

  /// 上次成功抓取时间（用于 TTL 判定 + UI 展示）。
  DateTime? get fetchedAt => _fetchedAt;

  /// 启动加载本地缓存。不阻塞网络：读缓存文件 + settings 元数据；
  /// 缓存不存在时 _models 为空，capabilityFor 回退正则。
  Future<void> init() async {
    if (_loaded) return;
    await _loadCache();
    _loaded = true;
    // 首启无本地缓存 → 同步拉一次远程表，确保能力判定有数据（不回退正则）。
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
      _models.clear(); // 缓存损坏 → 视为无缓存，回退正则
    }
  }

  void _replaceModels(Map<String, dynamic> doc) {
    final models = doc['models'] as Map<String, dynamic>? ?? {};
    _models
      ..clear()
      ..addEntries([
        for (final e in models.entries)
          MapEntry(e.key.toLowerCase(), _capFromRemote(e.value)),
      ]);
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

  /// 查询：纯 model id → 能力（远程表命中），未命中返回 null（调用方
  /// 回退正则推断）。key 比较忽略大小写。
  AgentModelCapability? lookup(String modelId) {
    if (!_loaded) return null;
    return _models[modelId.toLowerCase()];
  }

  bool get _dueForUpdate {
    if (_fetchedAt == null) return true;
    final fetchedUtc = _fetchedAt!.toUtc();
    // fetchedAt 所在 UTC 日的次日 0 点 = 下次更新时间（与 modelcaps CI
    // 每日 UTC 0 点 build 对齐——过 UTC 0 点即视为新一天，需拉取）。
    final nextUpdate =
        DateTime.utc(fetchedUtc.year, fetchedUtc.month, fetchedUtc.day)
            .add(const Duration(days: 1));
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
        if (newLastMod != null) GStorage.setting.put(_kLastModified, newLastMod),
        GStorage.setting.put(_kLastFetched, _fetchedAt!.toIso8601String()),
        if (_version != null) GStorage.setting.put(_kVersion, _version!),
      ]);
      return true;
    } catch (_) {
      return false; // 网络失败 → 保留旧缓存
    }
  }
}