import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/storage/storage.dart';
import '../providers/api_provider.dart';
import '../providers/translation_config_provider.dart';
import 'agent_model_capability.dart';

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
  static Future<String> translate({
    required String text,
    required AgentApiState agentState,
    required TranslationConfig translationConfig,
    bool useCache = true,
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

    // ── 构建 prompt ──
    final targetLang = translationConfig.targetLanguage;
    final systemPrompt = translationConfig.systemPrompt
        .replaceAll('{{targetLanguage}}', targetLang);
    final userPrompt = translationConfig.userPrompt
        .replaceAll('{{targetLanguage}}', targetLang)
        .replaceAll('{{input}}', text);

    // ── 调用 API ──
    final modelParams = agentState.paramsFor(modelId);
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

    // ── 写缓存 ──
    _putCache(cacheKey, result);

    return result;
  }

  /// 流式翻译：按 token 增量累加返回完整译文。
  ///
  /// 每个 emit 是"从开始到当前的完整文本"——消费者直接显示 snapshot.data
  /// 即可，无需自己累加。流结束后写入缓存；流式 API 失败时 fallback 到
  /// 非流式 [translate] 一次性 emit。
  static Stream<String> translateStream({
    required String text,
    required AgentApiState agentState,
    required TranslationConfig translationConfig,
    String? extraSystemInstruction,
  }) async* {
    if (text.trim().isEmpty) {
      yield '';
      return;
    }

    final cacheKey = _buildCacheKey(text, translationConfig.targetLanguage);
    final cached = _getCache(cacheKey);
    if (cached != null) {
      yield cached;
      return;
    }

    final modelId = agentState.fastModelId ?? agentState.defaultModelId;
    if (modelId == null || modelId.isEmpty) {
      throw Exception('请先在「AI 设置」中选择快速模型或专家模型');
    }
    if (agentState.apiKey.isEmpty) {
      throw Exception('请先在「AI 设置」中填写 API Key');
    }

    final targetLang = translationConfig.targetLanguage;
    final baseSystemPrompt = translationConfig.systemPrompt
        .replaceAll('{{targetLanguage}}', targetLang);
    final systemPrompt = extraSystemInstruction != null
        ? '$baseSystemPrompt\n$extraSystemInstruction'
        : baseSystemPrompt;
    final userPrompt = translationConfig.userPrompt
        .replaceAll('{{targetLanguage}}', targetLang)
        .replaceAll('{{input}}', text);

    final modelParams = agentState.paramsFor(modelId);
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
        yield accumulated;
      }
    } catch (e) {
      streamErr = e;
    }

    // 流式完全失败（无任何增量）→ fallback 非流式一次性返回
    if (streamErr != null && accumulated.isEmpty) {
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
        yield result;
      } catch (_) {
        throw streamErr;
      }
    }

    if (accumulated.isNotEmpty) {
      _putCache(cacheKey, accumulated);
    }
  }

  // ── 流式 API 分派 ─────────────────────────────────────────────────────────

  static Stream<String> _callApiStream({
    required AgentApiProvider provider,
    required String baseUrl,
    required String apiKey,
    required String modelId,
    required String systemPrompt,
    required String userPrompt,
    double? temperature,
    AgentModelParams modelParams = const AgentModelParams(),
  }) async* {
    final url = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 3),
    ));

    switch (provider) {
      case AgentApiProvider.openai:
        yield* _streamOpenAI(dio, '$url${provider.chatPath}', apiKey,
            modelId, systemPrompt, userPrompt, temperature, modelParams);
      case AgentApiProvider.anthropic:
        yield* _streamAnthropic(dio, '$url${provider.chatPath}', apiKey,
            modelId, systemPrompt, userPrompt, temperature, modelParams);
      case AgentApiProvider.gemini:
        yield* _streamGemini(dio, '$url${provider.chatPath}', apiKey,
            modelId, systemPrompt, userPrompt, temperature, modelParams);
      case AgentApiProvider.openAICompatible:
        yield* _streamOpenAICompatible(dio, '$url${provider.chatPath}', apiKey,
            modelId, systemPrompt, userPrompt, temperature, modelParams);
    }
  }

  /// OpenAI Responses API 流式，兼容 Chat Completions fallback 格式：
  /// - Responses: `{"type":"response.output_text.delta","delta":"hi"}`
  /// - Chat:      `{"choices":[{"delta":{"content":"hi"}}]}`
  static Stream<String> _streamOpenAI(
    Dio dio,
    String url,
    String apiKey,
    String modelId,
    String systemPrompt,
    String userPrompt,
    double? temperature,
    AgentModelParams modelParams,
  ) async* {
    final resp = await dio.post<ResponseBody>(
      url,
      data: {
        'model': modelId,
        'instructions': systemPrompt,
        'input': userPrompt,
        'stream': true,
        if (temperature != null) 'temperature': temperature,
        ..._buildThinkingForOpenAI(modelParams.thinkingLevel),
      },
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
        },
        responseType: ResponseType.stream,
      ),
    );

    await for (final event in _sseEventStream(resp.data!.stream)) {
      final data = _extractSseData(event);
      if (data == null || data == '[DONE]') continue;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        if (json['type'] == 'response.output_text.delta') {
          final d = json['delta'];
          if (d is String && d.isNotEmpty) yield d;
          continue;
        }
        final choices = json['choices'] as List<dynamic>?;
        if (choices != null && choices.isNotEmpty) {
          final delta = (choices[0] as Map<String, dynamic>)['delta'];
          if (delta is Map<String, dynamic>) {
            final content = delta['content'];
            if (content is String && content.isNotEmpty) yield content;
          }
        }
      } catch (_) {
        // 单 event 解析失败 → 跳过，其他 event 继续
      }
    }
  }

  /// Anthropic Messages API 流式：`content_block_delta.delta.text`
  static Stream<String> _streamAnthropic(
    Dio dio,
    String url,
    String apiKey,
    String modelId,
    String systemPrompt,
    String userPrompt,
    double? temperature,
    AgentModelParams modelParams,
  ) async* {
    final resp = await dio.post<ResponseBody>(
      url,
      data: {
        'model': modelId,
        'system': systemPrompt,
        'max_tokens': 4096,
        'messages': [
          {'role': 'user', 'content': userPrompt},
        ],
        'stream': true,
        if (temperature != null) 'temperature': temperature,
        ..._buildThinkingForAnthropic(modelId, modelParams.thinkingLevel),
      },
      options: Options(
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
        },
        responseType: ResponseType.stream,
      ),
    );

    await for (final event in _sseEventStream(resp.data!.stream)) {
      final data = _extractSseData(event);
      if (data == null) continue;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        if (json['type'] == 'content_block_delta') {
          final delta = json['delta'] as Map<String, dynamic>?;
          if (delta?['type'] == 'text_delta') {
            final text = delta!['text'];
            if (text is String && text.isNotEmpty) yield text;
          }
        }
      } catch (_) {}
    }
  }

  /// Gemini 流式：`:streamGenerateContent?alt=sse`，累加 parts[*].text
  static Stream<String> _streamGemini(
    Dio dio,
    String baseChatUrl,
    String apiKey,
    String modelId,
    String systemPrompt,
    String userPrompt,
    double? temperature,
    AgentModelParams modelParams,
  ) async* {
    final thinkingCfg =
        _buildThinkingForGemini(modelId, modelParams.thinkingLevel);
    final resp = await dio.post<ResponseBody>(
      '$baseChatUrl/models/$modelId:streamGenerateContent',
      queryParameters: {'key': apiKey, 'alt': 'sse'},
      data: {
        'systemInstruction': {
          'parts': [
            {'text': systemPrompt}
          ]
        },
        'contents': [
          {
            'parts': [
              {'text': userPrompt}
            ]
          }
        ],
        'generationConfig': {
          if (temperature != null) 'temperature': temperature,
          if (thinkingCfg.isNotEmpty) 'thinkingConfig': thinkingCfg,
        },
      },
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
        },
        responseType: ResponseType.stream,
      ),
    );

    await for (final event in _sseEventStream(resp.data!.stream)) {
      final data = _extractSseData(event);
      if (data == null) continue;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final candidates = json['candidates'] as List<dynamic>?;
        if (candidates == null || candidates.isEmpty) continue;
        final content = (candidates[0] as Map<String, dynamic>)['content'];
        if (content is! Map<String, dynamic>) continue;
        final parts = content['parts'] as List<dynamic>?;
        if (parts == null) continue;
        for (final part in parts) {
          if (part is Map<String, dynamic>) {
            final t = part['text'];
            if (t is String && t.isNotEmpty) yield t;
          }
        }
      } catch (_) {}
    }
  }

  /// OpenAI Compatible (Chat Completions) 流式：标准 `choices[].delta.content`
  ///
  /// 兼容 DeepSeek 等第三方服务。过滤 `reasoning_content`，仅提取 `content`。
  static Stream<String> _streamOpenAICompatible(
    Dio dio,
    String url,
    String apiKey,
    String modelId,
    String systemPrompt,
    String userPrompt,
    double? temperature,
    AgentModelParams modelParams,
  ) async* {
    final body = _buildOpenAICompatibleBody(
      modelId: modelId,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      temperature: temperature,
      modelParams: modelParams,
      stream: true,
    );

    final resp = await dio.post<ResponseBody>(
      url,
      data: body,
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
        },
        responseType: ResponseType.stream,
      ),
    );

    await for (final event in _sseEventStream(resp.data!.stream)) {
      final data = _extractSseData(event);
      if (data == null || data == '[DONE]') continue;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final choices = json['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) continue;
        final choice = choices[0] as Map<String, dynamic>;
        final finishReason = choice['finish_reason'] as String?;
        if (finishReason == 'insufficient_system_resource') {
          throw Exception('服务器资源不足，请稍后重试');
        }
        final delta = choice['delta'];
        if (delta is Map<String, dynamic>) {
          final content = delta['content'];
          if (content is String && content.isNotEmpty) yield content;
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('服务器资源不足')) {
          rethrow;
        }
      }
    }
  }

  /// 构建 OpenAI Compatible (Chat Completions) 请求体
  static Map<String, dynamic> _buildOpenAICompatibleBody({
    required String modelId,
    required String systemPrompt,
    required String userPrompt,
    double? temperature,
    required AgentModelParams modelParams,
    bool stream = false,
  }) {
    final body = <String, dynamic>{
      'model': modelId,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      if (stream) 'stream': true,
      if (temperature != null) 'temperature': temperature,
      if (modelParams.maxTokens != null) 'max_tokens': modelParams.maxTokens,
      if (modelParams.topP != null) 'top_p': modelParams.topP,
      if (modelParams.frequencyPenalty != null)
        'frequency_penalty': modelParams.frequencyPenalty,
      if (modelParams.presencePenalty != null)
        'presence_penalty': modelParams.presencePenalty,
    };

    body.addAll(_buildThinkingForOpenAICompat(modelParams.thinkingLevel));
    return body;
  }

  // ─── Thinking payload 构造（按 provider+capability 把统一 ThinkingLevel 翻译） ───
  //
  // 设计：每个函数返回**要直接 merge 进对应 body 的 fragment**。
  // - OpenAI / Anthropic / OpenAI Compat 返回顶层 fragment，调用方 `body.addAll(...)`。
  // - Gemini 返回 `thinkingConfig` 内层 fragment，调用方放入 `generationConfig.thinkingConfig`。
  //
  // `level == null` 时统一返回 `{}`——保留服务商默认（不发送任何 thinking 字段）。

  /// OpenAI Responses API：`reasoning.effort` ∈ none/low/medium/high/xhigh。
  static Map<String, dynamic> _buildThinkingForOpenAI(ThinkingLevel? level) {
    if (level == null) return const {};
    final effort = switch (level) {
      ThinkingLevel.off => 'none',
      ThinkingLevel.low => 'low',
      ThinkingLevel.medium => 'medium',
      ThinkingLevel.high => 'high',
      ThinkingLevel.xhigh => 'xhigh',
    };
    return {
      'reasoning': {'effort': effort},
    };
  }

  /// Anthropic Messages：分 adaptive 模型（Opus 4.7+）vs 旧模型两条路径。
  ///
  /// **Adaptive**：`thinking.type='adaptive'` + `output_config.effort` 控制力度。
  /// medium 不带 `output_config`——按 Anthropic 推荐，让 adaptive 自决。
  /// off 映射到 `effort='low'`（adaptive 不能真正关闭）。
  ///
  /// **旧模型**：`thinking.type='disabled'|'enabled'` + `budget_tokens` 数字。
  static Map<String, dynamic> _buildThinkingForAnthropic(
    String modelId,
    ThinkingLevel? level,
  ) {
    if (level == null) return const {};

    if (AgentModelCapability.isClaudeAdaptive(modelId)) {
      final effort = switch (level) {
        ThinkingLevel.off => 'low',
        ThinkingLevel.low => 'low',
        ThinkingLevel.medium => null, // 不带 effort，adaptive 自决
        ThinkingLevel.high => 'high',
        ThinkingLevel.xhigh => 'max',
      };
      return {
        'thinking': {'type': 'adaptive'},
        if (effort != null)
          'output_config': {'effort': effort},
      };
    }

    if (level == ThinkingLevel.off) {
      return {
        'thinking': {'type': 'disabled'},
      };
    }
    final budget = switch (level) {
      ThinkingLevel.low => 1024,
      ThinkingLevel.medium => 4096,
      ThinkingLevel.high => 16384,
      ThinkingLevel.xhigh => 32000,
      ThinkingLevel.off => 0, // unreachable
    };
    return {
      'thinking': {'type': 'enabled', 'budget_tokens': budget},
    };
  }

  /// Gemini：返回放在 `generationConfig.thinkingConfig` 下的 fragment。
  ///
  /// **3 系列**：用 `thinkingLevel: minimal/low/medium/high`，xhigh 也 fallback
  /// 到 high（3 系列上限即 high）。3.x Pro 不支持 minimal，off 改用 'low'。
  ///
  /// **2.5 系列**：用 `thinkingBudget` 数字。映射 [off=0, low=512, medium=4096,
  /// high=16384, xhigh=模型上限]；2.5 Pro 不能完全关，off clamp 到 128。
  static Map<String, dynamic> _buildThinkingForGemini(
    String modelId,
    ThinkingLevel? level,
  ) {
    if (level == null) return const {};

    if (AgentModelCapability.isGemini3(modelId)) {
      final isPro = modelId.toLowerCase().contains('pro');
      final lv = switch (level) {
        ThinkingLevel.off => isPro ? 'low' : 'minimal',
        ThinkingLevel.low => 'low',
        ThinkingLevel.medium => 'medium',
        ThinkingLevel.high || ThinkingLevel.xhigh => 'high',
      };
      return {'thinkingLevel': lv};
    }

    if (AgentModelCapability.isGemini25(modelId)) {
      final maxB = AgentModelCapability.gemini25MaxBudget(modelId);
      final isPro = AgentModelCapability.isGemini25Pro(modelId);
      final budget = switch (level) {
        ThinkingLevel.off => isPro ? 128 : 0,
        ThinkingLevel.low => 512,
        ThinkingLevel.medium => 4096,
        ThinkingLevel.high => 16384,
        ThinkingLevel.xhigh => maxB,
      };
      return {'thinkingBudget': budget};
    }

    // 既非 2.5 也非 3——可能是更老的 Gemini（1.5 Pro 等），不发 thinking 字段
    return const {};
  }

  /// OpenAI Compatible (DeepSeek 等)：`thinking.type` + 顶层 `reasoning_effort`。
  ///
  /// **Schema 来源**：DeepSeek 官方文档（OpenAI Format 路径）。两个字段独立：
  /// - `{thinking:{type:enabled/disabled}}` 控制是否思考（默认 enabled）
  /// - 顶层 `reasoning_effort` 控制思考力度（low/medium/high/xhigh）
  ///
  /// 5 档 → `reasoning_effort` 直接传原字符串，**不在 client 提前归并**：
  /// - off → 仅 `{thinking:{type:disabled}}`，不发 reasoning_effort
  /// - low / medium / high / xhigh → `{thinking:{type:enabled}}` + 原值
  ///
  /// 字符串选择理由：xhigh 既被 OpenAI Reasoning API 识别，也被 DeepSeek 接受
  /// （服务端自动映射到 max）；low/medium 在 DeepSeek 上会被归类到 high，但
  /// 让 server 端做归类，client 保留用户原意。其他 OpenAI 兼容服务（OpenRouter
  /// /Together/Groq 等）若不识别某档会忽略，行为退化为 thinking-on 默认深度。
  static Map<String, dynamic> _buildThinkingForOpenAICompat(
    ThinkingLevel? level,
  ) {
    if (level == null) return const {};
    if (level == ThinkingLevel.off) {
      return {
        'thinking': {'type': 'disabled'},
      };
    }
    final effort = switch (level) {
      ThinkingLevel.low => 'low',
      ThinkingLevel.medium => 'medium',
      ThinkingLevel.high => 'high',
      ThinkingLevel.xhigh => 'xhigh',
      ThinkingLevel.off => 'low', // unreachable
    };
    return {
      'thinking': {'type': 'enabled'},
      'reasoning_effort': effort,
    };
  }

  // ── SSE 通用解析 ──────────────────────────────────────────────────────────

  /// 把字节流切成 SSE 事件（以 `\n\n` 或 `\r\n\r\n` 分隔）。
  /// UTF-8 边界可能跨 chunk，用 `allowMalformed` 容忍截断的 code unit。
  static Stream<String> _sseEventStream(Stream<List<int>> source) async* {
    String buffer = '';
    const decoder = Utf8Decoder(allowMalformed: true);
    await for (final chunk in source) {
      buffer += decoder.convert(chunk);
      while (true) {
        int delim = buffer.indexOf('\n\n');
        int delimLen = 2;
        if (delim < 0) {
          final alt = buffer.indexOf('\r\n\r\n');
          if (alt < 0) break;
          delim = alt;
          delimLen = 4;
        }
        final event = buffer.substring(0, delim);
        buffer = buffer.substring(delim + delimLen);
        if (event.isNotEmpty) yield event;
      }
    }
    if (buffer.trim().isNotEmpty) yield buffer;
  }

  /// 从单个 SSE event 抽取 `data:` 负载，多行按 SSE 规范用 `\n` 拼接。
  static String? _extractSseData(String event) {
    final dataLines = <String>[];
    for (final line in event.split(RegExp(r'\r?\n'))) {
      if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }
    if (dataLines.isEmpty) return null;
    return dataLines.join('\n');
  }

  // ── API 调用 ──────────────────────────────────────────────────────────────

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
    final url =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
    ));

    try {
      final Response<Map<String, dynamic>> resp;

      switch (provider) {
        case AgentApiProvider.openai:
          resp = await dio.post(
            '$url${provider.chatPath}',
            data: {
              'model': modelId,
              'instructions': systemPrompt,
              'input': userPrompt,
              if (temperature != null) 'temperature': temperature,
              ..._buildThinkingForOpenAI(modelParams.thinkingLevel),
            },
            options: Options(headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            }),
          );
          return _extractOpenAI(resp.data!);

        case AgentApiProvider.anthropic:
          resp = await dio.post(
            '$url${provider.chatPath}',
            data: {
              'model': modelId,
              'system': systemPrompt,
              'max_tokens': 4096,
              'messages': [
                {'role': 'user', 'content': userPrompt},
              ],
              if (temperature != null) 'temperature': temperature,
              ..._buildThinkingForAnthropic(modelId, modelParams.thinkingLevel),
            },
            options: Options(headers: {
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
              'Content-Type': 'application/json',
            }),
          );
          return _extractAnthropic(resp.data!);

        case AgentApiProvider.gemini:
          final thinkingCfg =
              _buildThinkingForGemini(modelId, modelParams.thinkingLevel);
          resp = await dio.post(
            '$url${provider.chatPath}/models/$modelId:generateContent',
            queryParameters: {'key': apiKey},
            data: {
              'systemInstruction': {
                'parts': [
                  {'text': systemPrompt}
                ]
              },
              'contents': [
                {
                  'parts': [
                    {'text': userPrompt}
                  ]
                }
              ],
              'generationConfig': {
                if (temperature != null) 'temperature': temperature,
                if (thinkingCfg.isNotEmpty) 'thinkingConfig': thinkingCfg,
              },
            },
          );
          return _extractGemini(resp.data!);

        case AgentApiProvider.openAICompatible:
          resp = await dio.post(
            '$url${provider.chatPath}',
            data: _buildOpenAICompatibleBody(
              modelId: modelId,
              systemPrompt: systemPrompt,
              userPrompt: userPrompt,
              temperature: temperature,
              modelParams: modelParams,
            ),
            options: Options(headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            }),
          );
          return _extractOpenAICompatible(resp.data!);
      }
    } on DioException catch (e) {
      final body = e.response?.data;
      String msg = 'HTTP ${e.response?.statusCode ?? "?"}';
      if (body is Map<String, dynamic>) {
        final err = body['error'];
        if (err is Map) msg = err['message'] as String? ?? msg;
        if (err is String) msg = err;
      }
      throw Exception('翻译请求失败：$msg');
    }
  }

  // ── 结果提取 ──────────────────────────────────────────────────────────────

  static String _extractOpenAI(Map<String, dynamic> data) {
    // Responses API: output[].content[].text
    final output = data['output'] as List<dynamic>?;
    if (output != null) {
      for (final item in output) {
        if (item is Map<String, dynamic> && item['type'] == 'message') {
          final content = item['content'] as List<dynamic>?;
          if (content != null) {
            for (final c in content) {
              if (c is Map<String, dynamic> && c['type'] == 'output_text') {
                return (c['text'] as String? ?? '').trim();
              }
            }
          }
        }
      }
    }
    // Chat Completions fallback
    final choices = data['choices'] as List<dynamic>?;
    if (choices != null && choices.isNotEmpty) {
      final msg = (choices[0] as Map<String, dynamic>)['message'];
      if (msg is Map<String, dynamic>) {
        return (msg['content'] as String? ?? '').trim();
      }
    }
    throw Exception('无法从 OpenAI 响应中提取翻译结果');
  }

  static String _extractAnthropic(Map<String, dynamic> data) {
    final content = data['content'] as List<dynamic>?;
    if (content != null && content.isNotEmpty) {
      final first = content[0] as Map<String, dynamic>;
      return (first['text'] as String? ?? '').trim();
    }
    throw Exception('无法从 Anthropic 响应中提取翻译结果');
  }

  static String _extractGemini(Map<String, dynamic> data) {
    final candidates = data['candidates'] as List<dynamic>?;
    if (candidates != null && candidates.isNotEmpty) {
      final parts =
          ((candidates[0] as Map<String, dynamic>)['content'] as Map<String, dynamic>?)?['parts']
              as List<dynamic>?;
      if (parts != null && parts.isNotEmpty) {
        return ((parts[0] as Map<String, dynamic>)['text'] as String? ?? '')
            .trim();
      }
    }
    throw Exception('无法从 Gemini 响应中提取翻译结果');
  }

  /// Chat Completions 标准格式，兼容 DeepSeek `insufficient_system_resource`
  static String _extractOpenAICompatible(Map<String, dynamic> data) {
    final choices = data['choices'] as List<dynamic>?;
    if (choices != null && choices.isNotEmpty) {
      final choice = choices[0] as Map<String, dynamic>;
      if (choice['finish_reason'] == 'insufficient_system_resource') {
        throw Exception('服务器资源不足，请稍后重试');
      }
      final msg = choice['message'];
      if (msg is Map<String, dynamic>) {
        return (msg['content'] as String? ?? '').trim();
      }
    }
    throw Exception('无法从 API 响应中提取翻译结果');
  }

  // ── 缓存 ──────────────────────────────────────────────────────────────────

  static String _buildCacheKey(String text, String targetLang) {
    // 简单 hash：取文本前 200 字 + 目标语言
    final normalized = text.trim();
    return 'tr_${targetLang}_${normalized.hashCode}';
  }

  static Map<String, dynamic> _loadCacheMap() {
    final raw = GStorage.setting.get(_cacheBoxKey);
    if (raw is String) {
      try {
        return Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }
    return {};
  }

  static String? _getCache(String key) {
    final map = _loadCacheMap();
    final entryRaw = map[key];
    if (entryRaw is Map<String, dynamic>) {
      final entry = _CacheEntry.fromJson(entryRaw);
      if (!entry.isExpired) return entry.translation;
    }
    return null;
  }

  static void _putCache(String key, String translation) {
    final map = _loadCacheMap();

    // 写入新条目
    map[key] = _CacheEntry(
      translation: translation,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    ).toJson();

    // 顺便清除过期条目
    map.removeWhere((_, v) {
      if (v is Map<String, dynamic>) {
        return _CacheEntry.fromJson(v).isExpired;
      }
      return true;
    });

    GStorage.setting.put(_cacheBoxKey, jsonEncode(map));
  }
}
