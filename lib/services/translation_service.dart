import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../core/storage/app_database.dart';
import '../core/storage/storage.dart';
import '../providers/api_provider.dart';
import '../providers/translation_config_provider.dart';
import 'agent_chat_service.dart';
import 'prompts.dart';
import 'translation_protected_spans.dart';

/// 轻量翻译服务——使用用户已配置的 Agent API（快速模型优先）完成文本翻译。
///
/// 缓存策略：以 [TranslationService._buildCacheKey] 为 key 落 Drift `translations`
/// 表，保留 7 天。Drift 行级读写替代旧 GStorage.setting 全量 JSON 序列化。
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
      final cached = await _getCache(cacheKey);
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
    await _putCache(cacheKey, result);

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
      final cached = await _getCache(cacheKey);
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
      await _putCache(cacheKey, protected.restore(accumulated));
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
  // 落 Drift translations 表：key = _buildCacheKey（tr_<lang>_<hashCode>），
  // createdAt 驱动 7 天 TTL。行级读写替代旧 GStorage.setting 全量 JSON
  // 序列化——旧实现的内存 map + 2s 防抖落盘绕路已无必要（Drift 索引插入
  // 不触发主 isolate 反复序列化，8 worker 高频 put 不再掉帧）。

  static const _cacheTtl = Duration(days: 7);

  static String _buildCacheKey(String text, String targetLang) {
    // 简单 hash：取文本 + 目标语言。hashCode 跨 Dart 版本不稳定，但同 build
    // 内稳定——缓存可重建，跨版本升级 miss 重译可接受（与旧实现行为一致）。
    final normalized = text.trim();
    return 'tr_${targetLang}_${normalized.hashCode}';
  }

  /// 命中且未过 7 天 TTL 返回译文，否则 null。过期行不在此清，交给写路径顺带清理。
  static Future<String?> _getCache(String key) async {
    final row = await (GStorage.db.select(GStorage.db.translations)
          ..where((t) => t.cacheKey.equals(key)))
        .getSingleOrNull();
    if (row == null) return null;
    final cutoff =
        DateTime.now().millisecondsSinceEpoch - _cacheTtl.inMilliseconds;
    if (row.createdAt <= cutoff) return null;
    return row.translation;
  }

  /// 写入（PK 冲突即覆盖）并顺带清掉过期行，替代旧的「落盘时清」。
  static Future<void> _putCache(String key, String translation) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await GStorage.db.into(GStorage.db.translations).insertOnConflictUpdate(
      TranslationsCompanion(
        cacheKey: Value(key),
        translation: Value(translation),
        createdAt: Value(now),
      ),
    );
    final cutoff = now - _cacheTtl.inMilliseconds;
    await (GStorage.db.delete(GStorage.db.translations)
          ..where((t) => t.createdAt.isSmallerThanValue(cutoff)))
        .go();
  }

  // ── 测试缝（@visibleForTesting）：脱离 LLM 单测 Drift 缓存 ──
  @visibleForTesting
  static String debugBuildCacheKey(String text, String targetLang) =>
      _buildCacheKey(text, targetLang);

  @visibleForTesting
  static Future<String?> debugGetCacheByKey(String key) => _getCache(key);

  @visibleForTesting
  static Future<void> debugPutCacheByKey(String key, String translation) =>
      _putCache(key, translation);
}
