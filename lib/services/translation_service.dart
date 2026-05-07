import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/storage/storage.dart';
import '../providers/api_provider.dart';
import '../providers/translation_config_provider.dart';

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
            modelId, systemPrompt, userPrompt, temperature);
      case AgentApiProvider.anthropic:
        yield* _streamAnthropic(dio, '$url${provider.chatPath}', apiKey,
            modelId, systemPrompt, userPrompt, temperature);
      case AgentApiProvider.gemini:
        yield* _streamGemini(dio, '$url${provider.chatPath}', apiKey,
            modelId, systemPrompt, userPrompt, temperature);
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
  ) async* {
    final resp = await dio.post<ResponseBody>(
      url,
      data: {
        'model': modelId,
        'instructions': systemPrompt,
        'input': userPrompt,
        'stream': true,
        if (temperature != null) 'temperature': temperature,
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
  ) async* {
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

    if (modelParams.thinkingMode != null) {
      body['thinking'] = {
        'type': modelParams.thinkingMode,
        if (modelParams.thinkingMode == 'enabled' &&
            modelParams.reasoningEffort != null)
          'reasoning_effort': modelParams.reasoningEffort,
      };
    }

    return body;
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
            },
            options: Options(headers: {
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
              'Content-Type': 'application/json',
            }),
          );
          return _extractAnthropic(resp.data!);

        case AgentApiProvider.gemini:
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
