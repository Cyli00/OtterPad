import 'package:dio/dio.dart';

import '../../providers/api_provider.dart';

/// Agent API 的网络端操作合集——连通性检测 + 候选模型拉取。
///
/// 纯函数式：不依赖 BuildContext / State / Riverpod，便于独立测试。

/// 检测单个模型是否可用。
///
/// 返回 `null` 表示连接成功；非空字符串是错误消息（可直接展示给用户）。
Future<String?> testAgentModel({
  required AgentApiProvider provider,
  required String baseUrl,
  required String apiKey,
  required String modelId,
}) async {
  final url = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;

  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  try {
    switch (provider) {
      case AgentApiProvider.openai:
        await dio.post(
          '$url${provider.chatPath}',
          data: {
            'model': modelId,
            'input': 'hi',
            'max_output_tokens': 16,
          },
          options: Options(headers: {
            'Authorization': 'Bearer $apiKey',
          }),
        );
      case AgentApiProvider.anthropic:
        await dio.post(
          '$url${provider.chatPath}',
          data: {
            'model': modelId,
            'max_tokens': 1,
            'messages': [
              {'role': 'user', 'content': 'hi'}
            ],
          },
          options: Options(headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'content-type': 'application/json',
          }),
        );
      case AgentApiProvider.gemini:
        await dio.post(
          '$url${provider.chatPath}/models/$modelId:generateContent',
          queryParameters: {'key': apiKey},
          data: {
            'contents': [
              {
                'parts': [
                  {'text': 'hi'}
                ]
              }
            ],
            'generationConfig': {'maxOutputTokens': 1},
          },
        );
      case AgentApiProvider.openAICompatible:
        await dio.post(
          '$url${provider.chatPath}',
          data: {
            'model': modelId,
            'messages': [
              {'role': 'user', 'content': 'hi'}
            ],
            'max_tokens': 16,
          },
          options: Options(headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          }),
        );
    }
    return null;
  } on DioException catch (e) {
    // anthropic 返回 400 常见是"消息格式问题"而非模型不可用——视为连通
    if (provider == AgentApiProvider.anthropic &&
        e.response?.statusCode == 400) {
      return null;
    }
    return _extractErrorMessage(e);
  } catch (e) {
    return '$e';
  }
}

String _extractErrorMessage(DioException e) {
  final body = e.response?.data;
  if (body is Map<String, dynamic>) {
    final apiErr = body['error'];
    if (apiErr is Map) {
      return apiErr['message'] as String? ?? 'HTTP ${e.response?.statusCode}';
    }
    if (apiErr is String) return apiErr;
    return body['message'] as String? ?? 'HTTP ${e.response?.statusCode}';
  }
  return e.response?.statusCode != null
      ? 'HTTP ${e.response!.statusCode}'
      : (e.message ?? e.type.name);
}

/// 从 provider 的 /models 端点拉取可选模型 ID（已排序）。
///
/// 失败时抛出异常，由调用方决定如何展示错误。
Future<List<String>> fetchAvailableModels({
  required AgentApiProvider provider,
  required String baseUrl,
  required String apiKey,
}) async {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  switch (provider) {
    case AgentApiProvider.openai:
    case AgentApiProvider.openAICompatible:
      final response = await dio.get<Map<String, dynamic>>(
        '$baseUrl${provider.modelsPath}',
        options: Options(
          headers: {'Authorization': 'Bearer $apiKey'},
        ),
      );
      final data = response.data?['data'] as List<dynamic>?;
      if (data == null) return const <String>[];
      return data
          .map((m) => (m as Map<String, dynamic>)['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toList()
        ..sort();

    case AgentApiProvider.anthropic:
      final response = await dio.get<Map<String, dynamic>>(
        '$baseUrl${provider.modelsPath}',
        queryParameters: {'limit': 100},
        options: Options(
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
          },
        ),
      );
      final data = response.data?['data'] as List<dynamic>?;
      if (data == null) return const <String>[];
      return data
          .map((m) => (m as Map<String, dynamic>)['id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toList()
        ..sort();

    case AgentApiProvider.gemini:
      final response = await dio.get<Map<String, dynamic>>(
        '$baseUrl${provider.modelsPath}',
        queryParameters: {'key': apiKey},
      );
      final list = response.data?['models'] as List<dynamic>? ?? [];
      return list
          .map((m) {
            final name = (m as Map<String, dynamic>)['name'] as String? ?? '';
            return name.startsWith('models/') ? name.substring(7) : name;
          })
          .where((id) => id.isNotEmpty)
          .toList()
        ..sort();
  }
}
