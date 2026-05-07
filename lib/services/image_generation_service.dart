import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../providers/api_provider.dart';
import 'agent_model_capability.dart';

class ImageGenerationRequest {
  final AgentApiProvider provider;
  final String baseUrl;
  final String apiKey;
  final String modelId;
  final String prompt;
  final List<String> referenceImagePaths;
  final String aspectRatio;
  final String fidelity;
  final CancelToken? cancelToken;

  const ImageGenerationRequest({
    required this.provider,
    required this.baseUrl,
    required this.apiKey,
    required this.modelId,
    required this.prompt,
    required this.referenceImagePaths,
    required this.aspectRatio,
    required this.fidelity,
    this.cancelToken,
  });
}

class ImageGenerationResult {
  final Uint8List bytes;
  final String mimeType;
  final String? providerText;
  final String? requestId;

  const ImageGenerationResult({
    required this.bytes,
    required this.mimeType,
    this.providerText,
    this.requestId,
  });
}

class ImageGenerationException implements Exception {
  final String message;
  const ImageGenerationException(this.message);

  @override
  String toString() => message;
}

class ImageGenerationService {
  ImageGenerationService._();
  static final ImageGenerationService instance = ImageGenerationService._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 5),
      sendTimeout: const Duration(minutes: 2),
    ),
  );

  Future<ImageGenerationResult> generate(ImageGenerationRequest request) async {
    if (request.apiKey.trim().isEmpty) {
      throw const ImageGenerationException('请先在「AI 设置」中填写生图模型 API Key');
    }
    if (!AgentModelCapability.isImageGenerationModel(
      provider: request.provider,
      modelId: request.modelId,
    )) {
      throw ImageGenerationException('当前模型不支持图片生成：${request.modelId}');
    }

    switch (request.provider) {
      case AgentApiProvider.openai:
        return _generateOpenAI(request);
      case AgentApiProvider.gemini:
        return _generateGemini(request);
      case AgentApiProvider.openAICompatible:
        return _generateOpenAI(request);
      case AgentApiProvider.anthropic:
        throw const ImageGenerationException('当前暂不支持 Anthropic 生图接口');
    }
  }

  Future<ImageGenerationResult> _generateOpenAI(
    ImageGenerationRequest request,
  ) async {
    final base = _trimTrailingSlash(request.baseUrl);
    final hasReferenceImages = request.referenceImagePaths.isNotEmpty;
    final endpoint = hasReferenceImages
        ? '$base/v1/images/edits'
        : '$base/v1/images/generations';
    final headers = {'Authorization': 'Bearer ${request.apiKey}'};
    final size = _openAIImageSize(request.aspectRatio);
    final quality = _openAIQuality(request.fidelity);

    try {
      Response<Map<String, dynamic>> response;
      if (hasReferenceImages) {
        final files = await Future.wait(
          request.referenceImagePaths.map(MultipartFile.fromFile),
        );
        final fields = <String, dynamic>{
          'model': request.modelId,
          'prompt': request.prompt,
          'image[]': files,
          'output_format': 'webp',
          'output_compression': '80',
        };
        if (size != null) fields['size'] = size;
        if (quality != null) fields['quality'] = quality;
        response = await _dio.post<Map<String, dynamic>>(
          endpoint,
          data: FormData.fromMap(fields),
          options: Options(headers: headers),
          cancelToken: request.cancelToken,
        );
      } else {
        final body = <String, dynamic>{
          'model': request.modelId,
          'prompt': request.prompt,
          'output_format': 'webp',
          'output_compression': 80,
        };
        if (size != null) body['size'] = size;
        if (quality != null) body['quality'] = quality;
        response = await _dio.post<Map<String, dynamic>>(
          endpoint,
          data: body,
          options: Options(headers: headers),
          cancelToken: request.cancelToken,
        );
      }

      final b64 = _extractOpenAIBase64(response.data);
      return ImageGenerationResult(
        bytes: base64Decode(b64),
        mimeType: 'image/webp',
        requestId: response.headers.value('x-request-id'),
      );
    } on DioException catch (e) {
      throw ImageGenerationException(_extractDioError(e));
    }
  }

  Future<ImageGenerationResult> _generateGemini(
    ImageGenerationRequest request,
  ) async {
    final base = _trimTrailingSlash(request.baseUrl);
    final endpoint = '$base/v1beta/models/${request.modelId}:generateContent';
    final parts = <Map<String, dynamic>>[
      {'text': request.prompt},
    ];

    if (request.referenceImagePaths.isNotEmpty) {
      final encodedImages = await Future.wait(
        request.referenceImagePaths.map((imagePath) async {
          final file = File(imagePath);
          if (!await file.exists()) return null;
          return <String, dynamic>{
            'inline_data': {
              'mime_type': _mimeTypeForPath(imagePath),
              'data': base64Encode(await file.readAsBytes()),
            },
          };
        }),
      );
      parts.addAll(encodedImages.whereType<Map<String, dynamic>>());
    }

    final imageSize = _geminiImageSize(request.fidelity);
    final imageConfig = <String, dynamic>{'aspectRatio': request.aspectRatio};
    if (imageSize != null) imageConfig['imageSize'] = imageSize;
    final body = {
      'contents': [
        {'parts': parts},
      ],
      'generationConfig': {
        'responseModalities': ['TEXT', 'IMAGE'],
        'imageConfig': imageConfig,
      },
    };

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        endpoint,
        queryParameters: {'key': request.apiKey},
        data: body,
        options: Options(headers: {'Content-Type': 'application/json'}),
        cancelToken: request.cancelToken,
      );
      return _extractGeminiImage(response.data);
    } on DioException catch (e) {
      throw ImageGenerationException(_extractDioError(e));
    }
  }

  String _extractOpenAIBase64(Map<String, dynamic>? data) {
    final items = data?['data'] as List<dynamic>?;
    if (items == null || items.isEmpty) {
      throw const ImageGenerationException('OpenAI 响应中没有图片数据');
    }
    final first = items.first;
    if (first is Map<String, dynamic>) {
      final b64 = first['b64_json'] as String?;
      if (b64 != null && b64.isNotEmpty) return b64;
    }
    throw const ImageGenerationException('无法解析 OpenAI 图片结果');
  }

  ImageGenerationResult _extractGeminiImage(Map<String, dynamic>? data) {
    final text = StringBuffer();
    final candidates = data?['candidates'] as List<dynamic>? ?? const [];
    for (final candidate in candidates) {
      if (candidate is! Map) continue;
      final content = candidate['content'];
      if (content is! Map) continue;
      final parts = content['parts'] as List<dynamic>? ?? const [];
      for (final part in parts) {
        if (part is! Map) continue;
        final partText = part['text']?.toString();
        if (partText != null && partText.isNotEmpty) {
          if (text.isNotEmpty) text.write('\n');
          text.write(partText);
        }
        final inline = part['inlineData'] ?? part['inline_data'];
        if (inline is Map) {
          final b64 = inline['data']?.toString() ?? '';
          if (b64.isEmpty) continue;
          return ImageGenerationResult(
            bytes: base64Decode(b64),
            mimeType:
                inline['mimeType']?.toString() ??
                inline['mime_type']?.toString() ??
                'image/png',
            providerText: text.isEmpty ? null : text.toString(),
          );
        }
      }
    }
    throw const ImageGenerationException('Gemini 响应中没有图片数据');
  }

  String? _openAIImageSize(String aspectRatio) => switch (aspectRatio) {
    '1:1' => '1024x1024',
    '4:3' => '1536x1152',
    '3:2' => '1536x1024',
    '16:9' => '1536x864',
    '21:9' => '1536x660',
    '9:16' => '864x1536',
    _ => '1536x1024',
  };

  String? _openAIQuality(String fidelity) => switch (fidelity) {
    'auto' => 'auto',
    'standard' => 'medium',
    'high' => 'high',
    _ => null,
  };

  String? _geminiImageSize(String fidelity) => switch (fidelity) {
    'standard' => '1K',
    'high' => '2K',
    _ => null,
  };

  String _trimTrailingSlash(String value) {
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  String _mimeTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/png';
  }

  String _extractDioError(DioException e) {
    final body = e.response?.data;
    if (body is Map<String, dynamic>) {
      final error = body['error'];
      if (error is Map) {
        return error['message']?.toString() ?? '图片生成失败';
      }
      if (error is String) return error;
      final message = body['message']?.toString();
      if (message != null && message.isNotEmpty) return message;
    }
    return e.response?.statusCode != null
        ? '图片生成失败：HTTP ${e.response!.statusCode}'
        : '图片生成失败：${e.message ?? e.type.name}';
  }
}
