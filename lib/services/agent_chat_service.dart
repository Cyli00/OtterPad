import 'package:dio/dio.dart';

import '../providers/api_provider.dart';
import 'agent_model_capability.dart';
import 'agent_thinking_payload.dart';

/// Agent 对话请求失败（已含服务商可读文案），调用方可按语境加前缀。
class AgentChatException implements Exception {
  final String message;
  const AgentChatException(this.message);

  @override
  String toString() => message;
}

/// 多模态消息中的一张图片（base64 PNG + 展示给模型的文字标签）。
class AgentChatImage {
  final String base64Png;
  final String label;

  const AgentChatImage({required this.base64Png, required this.label});
}

/// Agent 对话接缝：「provider + system/user (+images, +schema) → 文本」的
/// 唯一出口。各 provider 的请求体形状、headers、结构化输出模式、响应提取
/// 全部封装在此，调用方（翻译 / 排版修复 / 未来功能）只描述意图。
///
/// 结构化输出降级阶梯：传入 [schema] 时各 provider 先尝试原生 JSON Schema
/// 约束（OpenAI strict json_schema / Anthropic output_config / Gemini
/// responseJsonSchema / 兼容端 response_format json_schema），被服务商以
/// 400/422 拒绝时逐级退到 json_object 乃至纯 prompt 约束——兼容端各家支持
/// 差异极大，由阶梯自动适配。
///
/// 瞬时错误（429/5xx/超时/断连）内置重试一次。
class AgentChatService {
  AgentChatService._();

  /// 发送一次非流式对话请求，返回模型输出文本。
  ///
  /// [schema] 非空时启用结构化输出（含降级阶梯），[schemaName] 为 OpenAI
  /// 系 json_schema 的命名。[anthropicMaxTokens] 是 Anthropic 的输出上限
  /// 基线（thinking budget 更大时自动抬高）。
  /// 失败抛 [Exception]，message 已转为可读文案。
  static Future<String> send({
    required AgentApiProvider provider,
    required String baseUrl,
    required String apiKey,
    required String modelId,
    AgentModelParams modelParams = const AgentModelParams(),
    required String systemPrompt,
    required String userPrompt,
    List<AgentChatImage> images = const [],
    double? temperature,
    Map<String, dynamic>? schema,
    String schemaName = 'response',
    int anthropicMaxTokens = 4096,
    Duration receiveTimeout = const Duration(minutes: 5),
    CancelToken? cancelToken,
  }) async {
    final url = provider.chatUrl(baseUrl);
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(minutes: 2),
      receiveTimeout: receiveTimeout,
    ));

    final modes = schema == null
        ? const ['none']
        : switch (provider) {
            AgentApiProvider.openai => const ['schema', 'json'],
            AgentApiProvider.anthropic => const ['schema', 'none'],
            AgentApiProvider.gemini => const ['schema', 'json'],
            AgentApiProvider.openAICompatible => const [
                'schema',
                'json',
                'none'
              ],
          };

    for (var m = 0; m < modes.length; m++) {
      try {
        return await _withTransientRetry(
          cancelToken,
          () => _postRequest(
            dio: dio,
            url: url,
            provider: provider,
            apiKey: apiKey,
            modelId: modelId,
            modelParams: modelParams,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            images: images,
            temperature: temperature,
            schema: schema,
            schemaName: schemaName,
            anthropicMaxTokens: anthropicMaxTokens,
            mode: modes[m],
            cancelToken: cancelToken,
          ),
        );
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) rethrow;
        final code = e.response?.statusCode;
        final canFallback =
            m < modes.length - 1 && (code == 400 || code == 422);
        if (!canFallback) throw AgentChatException(readableMessage(e));
      }
    }
    throw StateError('unreachable');
  }

  /// 429/5xx/超时/断连重试一次（移动网络抖动常见），其余错误直接抛出。
  static Future<T> _withTransientRetry<T>(
    CancelToken? cancelToken,
    Future<T> Function() run,
  ) async {
    try {
      return await run();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      final code = e.response?.statusCode;
      final transient = code == null
          ? const {
              DioExceptionType.connectionTimeout,
              DioExceptionType.sendTimeout,
              DioExceptionType.receiveTimeout,
              DioExceptionType.connectionError,
            }.contains(e.type)
          : const {429, 500, 502, 503, 529}.contains(code);
      if (!transient) rethrow;
      await Future.delayed(const Duration(seconds: 2));
      if (cancelToken?.isCancelled ?? false) rethrow;
      return run();
    }
  }

  static Future<String> _postRequest({
    required Dio dio,
    required String url,
    required AgentApiProvider provider,
    required String apiKey,
    required String modelId,
    required AgentModelParams modelParams,
    required String systemPrompt,
    required String userPrompt,
    required List<AgentChatImage> images,
    required double? temperature,
    required Map<String, dynamic>? schema,
    required String schemaName,
    required int anthropicMaxTokens,
    required String mode,
    required CancelToken? cancelToken,
  }) async {
    final Response<Map<String, dynamic>> resp;

    switch (provider) {
      case AgentApiProvider.openai:
        // 无图时 input 用纯字符串（与多模态数组等价，更省字节）
        final Object input;
        if (images.isEmpty) {
          input = userPrompt;
        } else {
          input = [
            {
              'role': 'user',
              'content': [
                for (final img in images) ...[
                  {'type': 'input_text', 'text': img.label},
                  {
                    'type': 'input_image',
                    'image_url': 'data:image/png;base64,${img.base64Png}',
                    'detail': 'high',
                  },
                ],
                {'type': 'input_text', 'text': userPrompt},
              ],
            },
          ];
        }
        final text = <String, dynamic>{
          if (mode == 'schema')
            'format': {
              'type': 'json_schema',
              'name': schemaName,
              'strict': true,
              'schema': schema,
            }
          else if (mode == 'json')
            'format': {'type': 'json_object'},
          if (modelParams.verbosity != null)
            'verbosity': modelParams.verbosity,
        };
        resp = await dio.post(
          url,
          data: {
            'model': modelId,
            'instructions': systemPrompt,
            'input': input,
            if (text.isNotEmpty) 'text': text,
            if (temperature != null) 'temperature': temperature,
            ...AgentThinkingPayload.forOpenAI(
                modelId, modelParams.thinkingLevel),
          },
          options: Options(headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          }),
          cancelToken: cancelToken,
        );
        return _extractOpenAI(resp.data!);

      case AgentApiProvider.anthropic:
        final Object content = images.isEmpty
            ? userPrompt
            : [
                for (final img in images) ...[
                  {'type': 'text', 'text': img.label},
                  {
                    'type': 'image',
                    'source': {
                      'type': 'base64',
                      'media_type': 'image/png',
                      'data': img.base64Png,
                    },
                  },
                ],
                {'type': 'text', 'text': userPrompt},
              ];
        final thinking = Map<String, dynamic>.from(
          AgentThinkingPayload.forAnthropic(
              modelId, modelParams.thinkingLevel),
        );
        // adaptive 模型的 effort 也在 output_config 里，与 format 合并发送
        final outputConfig = <String, dynamic>{
          if (mode == 'schema')
            'format': {'type': 'json_schema', 'schema': schema},
          ...?(thinking.remove('output_config') as Map<String, dynamic>?),
        };
        // 旧模型要求 budget_tokens < max_tokens
        var maxTokens = anthropicMaxTokens;
        final t = thinking['thinking'];
        if (t is Map && t['budget_tokens'] is int) {
          final budget = t['budget_tokens'] as int;
          if (budget >= maxTokens) maxTokens = budget + 8192;
        }
        resp = await dio.post(
          url,
          data: {
            'model': modelId,
            'system': systemPrompt,
            'max_tokens': maxTokens,
            'messages': [
              {'role': 'user', 'content': content},
            ],
            if (temperature != null) 'temperature': temperature,
            if (outputConfig.isNotEmpty) 'output_config': outputConfig,
            ...thinking,
          },
          options: Options(headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'Content-Type': 'application/json',
          }),
          cancelToken: cancelToken,
        );
        return _extractAnthropic(resp.data!);

      case AgentApiProvider.gemini:
        final parts = <Map<String, dynamic>>[
          for (final img in images) ...[
            {'text': img.label},
            {
              'inline_data': {
                'mime_type': 'image/png',
                'data': img.base64Png,
              },
            },
          ],
          {'text': userPrompt},
        ];
        final thinkingCfg = AgentThinkingPayload.forGemini(
            modelId, modelParams.thinkingLevel);
        resp = await dio.post(
          '$url/models/$modelId:generateContent',
          queryParameters: {'key': apiKey},
          data: {
            'systemInstruction': {
              'parts': [
                {'text': systemPrompt},
              ],
            },
            'contents': [
              {'parts': parts},
            ],
            'generationConfig': {
              if (temperature != null) 'temperature': temperature,
              if (schema != null) 'responseMimeType': 'application/json',
              if (mode == 'schema') 'responseJsonSchema': schema,
              if (thinkingCfg.isNotEmpty) 'thinkingConfig': thinkingCfg,
            },
          },
          cancelToken: cancelToken,
        );
        return _extractGemini(resp.data!);

      case AgentApiProvider.openAICompatible:
        final Object content = images.isEmpty
            ? userPrompt
            : [
                for (final img in images) ...[
                  {'type': 'text', 'text': img.label},
                  {
                    'type': 'image_url',
                    'image_url': {
                      'url': 'data:image/png;base64,${img.base64Png}',
                      'detail': 'high',
                    },
                  },
                ],
                {'type': 'text', 'text': userPrompt},
              ];
        resp = await dio.post(
          url,
          data: {
            'model': modelId,
            'messages': [
              {'role': 'system', 'content': systemPrompt},
              {'role': 'user', 'content': content},
            ],
            if (temperature != null) 'temperature': temperature,
            if (modelParams.maxTokens != null)
              'max_tokens': modelParams.maxTokens,
            if (modelParams.topP != null) 'top_p': modelParams.topP,
            if (modelParams.frequencyPenalty != null)
              'frequency_penalty': modelParams.frequencyPenalty,
            if (modelParams.presencePenalty != null)
              'presence_penalty': modelParams.presencePenalty,
            if (mode == 'schema')
              'response_format': {
                'type': 'json_schema',
                'json_schema': {
                  'name': schemaName,
                  'strict': true,
                  'schema': schema,
                },
              }
            else if (mode == 'json')
              'response_format': {'type': 'json_object'},
            // DashScope 专属：把单图 token 上限 1280 → 16384，密集文档页必需
            if (images.isNotEmpty && AgentModelCapability.isQwenVl(modelId))
              'vl_high_resolution_images': true,
            ...AgentThinkingPayload.forOpenAICompat(modelParams.thinkingLevel),
          },
          options: Options(headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          }),
          cancelToken: cancelToken,
        );
        return _extractOpenAICompatible(resp.data!);
    }
  }

  /// 从 DioException 提取服务商可读错误文案。
  static String readableMessage(DioException e) {
    final body = e.response?.data;
    String msg = 'HTTP ${e.response?.statusCode ?? "?"}';
    if (body is Map<String, dynamic>) {
      final err = body['error'];
      if (err is Map) msg = err['message'] as String? ?? msg;
      if (err is String) msg = err;
    }
    return msg;
  }

  // ── 响应提取（兼容 thinking 模型）────────────────────────
  //
  // 统一取「最后一个非思考 text」：thinking 模型的思考块在前、正文在后，
  // 取首块会拿到空串或思考内容（此前翻译/排版修复两份副本在此已漂移）。

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
    throw Exception('无法从 OpenAI 响应中提取结果');
  }

  static String _extractAnthropic(Map<String, dynamic> data) {
    final content = data['content'] as List<dynamic>?;
    if (content != null) {
      for (final block in content.reversed) {
        if (block is Map<String, dynamic> && block['type'] == 'text') {
          return (block['text'] as String? ?? '').trim();
        }
      }
    }
    throw Exception('无法从 Anthropic 响应中提取结果');
  }

  static String _extractGemini(Map<String, dynamic> data) {
    final candidates = data['candidates'] as List<dynamic>?;
    if (candidates != null && candidates.isNotEmpty) {
      final parts = ((candidates[0] as Map<String, dynamic>)['content']
              as Map<String, dynamic>?)?['parts'] as List<dynamic>?;
      if (parts != null) {
        for (final part in parts.reversed) {
          if (part is Map<String, dynamic> &&
              part['thought'] != true &&
              part.containsKey('text')) {
            return (part['text'] as String? ?? '').trim();
          }
        }
      }
    }
    throw Exception('无法从 Gemini 响应中提取结果');
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
    throw Exception('无法从 API 响应中提取结果');
  }
}
