import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/storage/storage.dart';
import '../providers/api_provider.dart';
import '../providers/translation_config_provider.dart';
import 'agent_chat_service.dart';
import 'prompts.dart';
import 'translation_protected_spans.dart';

/// 翻译缓存条目
class _CacheEntry {
  final String translation;
  final int timestampMs;

  _CacheEntry({required this.translation, required this.timestampMs});

  Map<String, dynamic> toJson() => {
    'translation': translation,
    'ts': timestampMs,
  };

  factory _CacheEntry.fromJson(Map<String, dynamic> json) => _CacheEntry(
    translation: json['translation'] as String? ?? '',
    timestampMs: json['ts'] as int? ?? 0,
  );

  bool get isExpired {
    const maxAge = Duration(days: 7);
    return DateTime.now().millisecondsSinceEpoch - timestampMs >
        maxAge.inMilliseconds;
  }
}

const _cacheBoxKey = 'translation_cache';

/// 轻量翻译服务——使用用户已配置的 Agent API（快速模型优先）完成文本翻译。
///
/// 缓存策略：以原文 SHA 为 key 存入 GStorage.setting，保留 7 天。
class TranslationService {
  TranslationService._();

  /// 翻译 [text]，返回译文。
  ///
  /// 优先使用快速模型，无快速模型时回退到默认模型。
  /// 翻译结果缓存 7 天。
  ///
  /// [translationThinkingLevel]：翻译专用思考强度。默认 [ThinkingLevel.off]——
  /// 翻译是直译任务，思考开销纯属浪费 token 与延迟。模型若不支持完全关闭
  /// （Gemini 2.5 Pro / Claude adaptive / Gemini 3 Pro 等），由
  /// [AgentThinkingPayload] 内部自动 fallback 到该服务商支持的最低档。
  /// 传 `null` 表示"沿用 modelParams 中用户为该模型配置的 thinkingLevel"。
  static Future<String> translate({
    required String text,
    required AgentApiState agentState,
    required TranslationConfig translationConfig,
    bool useCache = true,
    ThinkingLevel? translationThinkingLevel = ThinkingLevel.off,
  }) async {
    if (text.trim().isEmpty) return '';

    // ── 查缓存 ──
    final cacheKey = _buildCacheKey(text, translationConfig.targetLanguage);
    if (useCache) {
      final cached = _getCache(cacheKey);
      if (cached != null) return cached;
    }

    // ── 选模型 ──
    final modelId = agentState.fastModelId ?? agentState.defaultModelId;
    if (modelId == null || modelId.isEmpty) {
      throw Exception('请先在「AI 设置」中选择快速模型或专家模型');
    }
    if (agentState.apiKey.isEmpty) {
      throw Exception('请先在「AI 设置」中填写 API Key');
    }

    // ── 受保护 span：行内公式/代码抠出占位，译后还原 ──
    final protected = ProtectedSpans.mask(text);

    // ── 构建 prompt ──
    final targetLang = translationConfig.targetLanguage;
    var systemPrompt = renderPrompt(translationConfig.systemPrompt, {
      'targetLanguage': targetLang,
    });
    if (!protected.isEmpty) {
      systemPrompt = '$systemPrompt\n${Prompts.translationPlaceholderGuard}';
    }
    final userPrompt = renderPrompt(translationConfig.userPrompt, {
      'targetLanguage': targetLang,
      'input': protected.masked,
    });

    // ── 调用 API ──
    // 翻译专用 thinking 覆盖：translationThinkingLevel != null 时强制写入到
    // params.thinkingLevel——request 构造层会再按 provider+model 翻译为具体字段。
    // 不能关闭思考的模型 (Gemini 2.5 Pro / Claude adaptive / Gemini 3 Pro) 会
    // 在 AgentThinkingPayload 内被 fallback 到该家最低档。
    final modelParams = _applyTranslationThinking(
      agentState.paramsFor(modelId),
      translationThinkingLevel,
    );
    final result = protected.restore(
      await _callApi(
        provider: agentState.provider,
        baseUrl: agentState.effectiveBaseUrl,
        apiKey: agentState.apiKey,
        modelId: modelId,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        temperature: translationConfig.temperature,
        modelParams: modelParams,
      ),
    );

    // ── 写缓存 ──
    _putCache(cacheKey, result);

    return result;
  }

  /// 流式翻译：按 token 增量累加返回完整译文。
  ///
  /// 每个 emit 是"从开始到当前的完整文本"——消费者直接显示 snapshot.data
  /// 即可，无需自己累加。成功结束后写入缓存；流式失败（含收到部分增量后
  /// 中途断流）时 fallback 到非流式 [translate] 一次性 emit，残缺增量不缓存。
  ///
  /// [translationThinkingLevel] 语义与 [translate] 同：默认 [ThinkingLevel.off]，
  /// 不可关闭的模型自动 fallback 到该服务商最低档；传 `null` 沿用用户配置。
  static Stream<String> translateStream({
    required String text,
    required AgentApiState agentState,
    required TranslationConfig translationConfig,
    String? extraSystemInstruction,
    ThinkingLevel? translationThinkingLevel = ThinkingLevel.off,
    bool useCache = true,
  }) async* {
    if (text.trim().isEmpty) {
      yield '';
      return;
    }

    final cacheKey = _buildCacheKey(text, translationConfig.targetLanguage);
    if (useCache) {
      final cached = _getCache(cacheKey);
      if (cached != null) {
        yield cached;
        return;
      }
    }

    final modelId = agentState.fastModelId ?? agentState.defaultModelId;
    if (modelId == null || modelId.isEmpty) {
      throw Exception('请先在「AI 设置」中选择快速模型或专家模型');
    }
    if (agentState.apiKey.isEmpty) {
      throw Exception('请先在「AI 设置」中填写 API Key');
    }

    final protected = ProtectedSpans.mask(text);

    final targetLang = translationConfig.targetLanguage;
    final baseSystemPrompt = renderPrompt(translationConfig.systemPrompt, {
      'targetLanguage': targetLang,
    });
    var systemPrompt = extraSystemInstruction != null
        ? '$baseSystemPrompt\n$extraSystemInstruction'
        : baseSystemPrompt;
    if (!protected.isEmpty) {
      systemPrompt = '$systemPrompt\n${Prompts.translationPlaceholderGuard}';
    }
    final userPrompt = renderPrompt(translationConfig.userPrompt, {
      'targetLanguage': targetLang,
      'input': protected.masked,
    });

    final modelParams = _applyTranslationThinking(
      agentState.paramsFor(modelId),
      translationThinkingLevel,
    );
    Object? streamErr;
    String accumulated = '';
    try {
      await for (final delta in _callApiStream(
        provider: agentState.provider,
        baseUrl: agentState.effectiveBaseUrl,
        apiKey: agentState.apiKey,
        modelId: modelId,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        temperature: translationConfig.temperature,
        modelParams: modelParams,
      )) {
        accumulated += delta;
        // 还原是纯函数，对部分快照同样安全：已完整出现的占位符立即
        // 还原，半截占位符保持原样等下个 delta。
        yield protected.restore(accumulated);
      }
    } catch (e) {
      streamErr = e;
    }

    // 流式失败（含已收到部分增量的中途断流）→ fallback 非流式一次性返回。
    // 部分增量不可信：断流可能截在句子中间，残缺译文一旦进缓存会在 TTL 内
    // 反复命中——宁可重发一次完整请求，fallback 也失败则把原始错误抛给调用方。
    if (streamErr != null) {
      final err = streamErr;
      try {
        final result = await _callApi(
          provider: agentState.provider,
          baseUrl: agentState.effectiveBaseUrl,
          apiKey: agentState.apiKey,
          modelId: modelId,
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          temperature: translationConfig.temperature,
          modelParams: modelParams,
        );
        accumulated = result;
        streamErr = null;
        yield protected.restore(result);
      } catch (_) {
        throw err;
      }
    }

    // 仅在确认无错误时写缓存——残缺译文不得持久化。
    if (useCache && streamErr == null && accumulated.isNotEmpty) {
      _putCache(cacheKey, protected.restore(accumulated));
    }
  }

  // ── 翻译专用思考强度覆盖 ───────────────────────────────────────────────────

  /// 把翻译入口指定的 [override] thinkingLevel 应用到模型参数上。
  /// 传 `null` 表示"沿用用户在 modelParams 里为该模型配置的 thinkingLevel"。
  ///
  /// 之所以不在此处做"能否关闭"的判断、直接交给 [AgentThinkingPayload]
  /// provider 适配层处理 fallback：能力推断本来就集中在
  /// [AgentModelCapability]，这里再分流会让 5 档语义在两个地方维护。
  static AgentModelParams _applyTranslationThinking(
    AgentModelParams params,
    ThinkingLevel? override,
  ) {
    if (override == null) return params;
    return params.copyWith(thinkingLevel: override);
  }

  // ── 流式 API 分派 ─────────────────────────────────────────────────────────

  /// 流式调用同样走共享 Agent 对话接缝 [AgentChatService]：sendStream 是
  /// 回调式接口，用 StreamController 桥成 Stream；下游取消订阅（如译文
  /// 弹层提前关闭）时经 CancelToken 中断底层请求。
  static Stream<String> _callApiStream({
    required AgentApiProvider provider,
    required String baseUrl,
    required String apiKey,
    required String modelId,
    required String systemPrompt,
    required String userPrompt,
    double? temperature,
    AgentModelParams modelParams = const AgentModelParams(),
  }) {
    final cancelToken = CancelToken();
    final controller = StreamController<String>(
      onCancel: () {
        if (!cancelToken.isCancelled) cancelToken.cancel();
      },
    );
    AgentChatService.sendStream(
      provider: provider,
      baseUrl: baseUrl,
      apiKey: apiKey,
      modelId: modelId,
      modelParams: modelParams,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      temperature: temperature,
      receiveTimeout: const Duration(minutes: 3),
      cancelToken: cancelToken,
      onDelta: controller.add,
    ).then(
      (_) => controller.close(),
      onError: (Object e) {
        if (controller.hasListener && !controller.isClosed) {
          controller.addError(e);
        }
        controller.close();
      },
    );
    return controller.stream;
  }

  // ── API 调用 ──────────────────────────────────────────────────────────────

  /// 非流式调用走共享 Agent 对话接缝 [AgentChatService]，此处只补翻译语境
  /// 的错误文案前缀。
  static Future<String> _callApi({
    required AgentApiProvider provider,
    required String baseUrl,
    required String apiKey,
    required String modelId,
    required String systemPrompt,
    required String userPrompt,
    double? temperature,
    AgentModelParams modelParams = const AgentModelParams(),
  }) async {
    try {
      return await AgentChatService.send(
        provider: provider,
        baseUrl: baseUrl,
        apiKey: apiKey,
        modelId: modelId,
        modelParams: modelParams,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        temperature: temperature,
        receiveTimeout: const Duration(seconds: 60),
      );
    } on AgentChatException catch (e) {
      throw Exception('翻译请求失败：${e.message}');
    }
  }

  // ── 缓存 ──────────────────────────────────────────────────────────────────

  static String _buildCacheKey(String text, String targetLang) {
    // 简单 hash：取文本前 200 字 + 目标语言
    final normalized = text.trim();
    return 'tr_${targetLang}_${normalized.hashCode}';
  }

  // ── 缓存：内存单一真值 + 防抖落盘 ──
  //
  // 旧实现每次 get/put 都对整个缓存 map（可达数 MB、上千条）全量
  // jsonDecode/jsonEncode——文档翻译 8 worker 高频 put 时主 isolate 反复
  // 同步序列化，表现为翻译进行中 UI 掉帧。改为：首次访问 decode 一次进
  // 内存，读写全打内存 map（O(1)），落盘走 2s 防抖批量。进程被杀最多丢
  // 最近 2s 的新缓存条目——缓存可重建，可接受。过期清理也移到落盘时做。
  static Map<String, dynamic>? _cacheMap;
  static Timer? _cacheSaveDebounce;

  static Map<String, dynamic> _loadCacheMap() {
    final loaded = _cacheMap;
    if (loaded != null) return loaded;
    Map<String, dynamic> map = {};
    final raw = GStorage.setting.get(_cacheBoxKey);
    if (raw is String) {
      try {
        map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }
    return _cacheMap = map;
  }

  static String? _getCache(String key) {
    final entryRaw = _loadCacheMap()[key];
    if (entryRaw is Map<String, dynamic>) {
      final entry = _CacheEntry.fromJson(entryRaw);
      if (!entry.isExpired) return entry.translation;
    }
    return null;
  }

  static void _putCache(String key, String translation) {
    _loadCacheMap()[key] = _CacheEntry(
      translation: translation,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    ).toJson();
    _scheduleCacheSave();
  }

  static void _scheduleCacheSave() {
    _cacheSaveDebounce?.cancel();
    _cacheSaveDebounce = Timer(const Duration(seconds: 2), () {
      final map = _cacheMap;
      if (map == null) return;
      map.removeWhere((_, v) {
        if (v is Map<String, dynamic>) {
          return _CacheEntry.fromJson(v).isExpired;
        }
        return true;
      });
      GStorage.setting.put(_cacheBoxKey, jsonEncode(map));
    });
  }
}
