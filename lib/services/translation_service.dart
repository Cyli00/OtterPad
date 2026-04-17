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
  }) async {
    if (text.trim().isEmpty) return '';

    // ── 查缓存 ──
    final cacheKey = _buildCacheKey(text, translationConfig.targetLanguage);
    final cached = _getCache(cacheKey);
    if (cached != null) return cached;

    // ── 选模型 ──
    final modelId = agentState.fastModelId ?? agentState.defaultModelId;
    if (modelId == null || modelId.isEmpty) {
      throw Exception('请先在"模型服务"中添加并设置默认模型或快速模型');
    }
    if (agentState.apiKey.isEmpty) {
      throw Exception('请先在"模型服务"中填写 API Key');
    }

    // ── 构建 prompt ──
    final targetLang = translationConfig.targetLanguage;
    final systemPrompt = translationConfig.systemPrompt
        .replaceAll('{{targetLanguage}}', targetLang);
    final userPrompt = translationConfig.userPrompt
        .replaceAll('{{targetLanguage}}', targetLang)
        .replaceAll('{{input}}', text);

    // ── 调用 API ──
    final result = await _callApi(
      provider: agentState.provider,
      baseUrl: agentState.effectiveBaseUrl,
      apiKey: agentState.apiKey,
      modelId: modelId,
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      temperature: translationConfig.temperature,
    );

    // ── 写缓存 ──
    _putCache(cacheKey, result);

    return result;
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
