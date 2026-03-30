import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../providers/api_provider.dart';
import '../utils/markdown_preprocessor.dart';

/// 文档提取异常
class DocExtractException implements Exception {
  final String message;
  const DocExtractException(this.message);

  @override
  String toString() => message;
}

/// 单页提取结果
class _PageResult {
  final String markdown;
  final Map<String, String> images;

  const _PageResult({required this.markdown, required this.images});
}

/// 文档提取结果
class DocExtractResult {
  final String rawMarkdown;
  final Map<String, String> images;
  final String? jsonlContent;
  String? savedPath;
  String? rawPath;
  String? jsonlPath;
  String? imageDir;
  String? processedMarkdown;

  DocExtractResult({
    required this.rawMarkdown,
    required this.images,
    this.jsonlContent,
    this.savedPath,
    this.rawPath,
    this.jsonlPath,
    this.imageDir,
    this.processedMarkdown,
  });
}

/// 百度 AI Studio PaddleOCR-VL 文档版面解析服务
class DocExtractService {
  DocExtractService._();
  static final DocExtractService instance = DocExtractService._();

  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 300),
      sendTimeout: const Duration(seconds: 120),
    ),
  );

  void applyProxy(Enum mode, String host, int port) {
    final adapter = IOHttpClientAdapter();
    switch (mode.name) {
      case 'custom':
        adapter.createHttpClient = () {
          final client = HttpClient();
          client.findProxy = (_) => 'PROXY $host:$port';
          client.badCertificateCallback = (_, _, _) => true;
          return client;
        };
      case 'system':
        adapter.createHttpClient = () => HttpClient();
      default:
        adapter.createHttpClient = () {
          final client = HttpClient();
          client.findProxy = (_) => 'DIRECT';
          return client;
        };
    }
    _dio.httpClientAdapter = adapter;
  }

  Future<DocExtractResult> extract({
    required String filePath,
    required String apiUrl,
    required String token,
    required DocExtractApiState state,
    CancelToken? cancelToken,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw const DocExtractException('PDF 文件不存在');
    }

    final fileBytes = await file.readAsBytes();
    final fileData = base64Encode(fileBytes);

    final payload = <String, dynamic>{
      'file': fileData,
      'fileType': 0,
      ...buildOptions(state),
    };

    final normalizedApiUrl = apiUrl.trim();
    final url = normalizedApiUrl.endsWith('/layout-parsing')
      ? normalizedApiUrl
      : normalizedApiUrl.endsWith('/')
      ? '${normalizedApiUrl}layout-parsing'
      : '$normalizedApiUrl/layout-parsing';

    final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        url,
        data: payload,
        options: Options(
          headers: {
            'Authorization': 'token $token',
            'Content-Type': 'application/json',
          },
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) rethrow;
      throw DocExtractException('网络请求失败: ${e.message ?? e.type.name}');
    }

    final data = response.data;
    if (data == null) {
      throw const DocExtractException('服务器返回空响应');
    }

    final errorCode = data['errorCode'] as int?;
    if (errorCode != null && errorCode != 0) {
      final errorMsg = data['errorMsg'] as String? ?? '未知错误';
      throw DocExtractException('API 错误 ($errorCode): $errorMsg');
    }

    final result = data['result'] as Map<String, dynamic>?;
    if (result == null) {
      throw const DocExtractException('响应中缺少 result 字段');
    }

    final parsingResults = result['layoutParsingResults'] as List<dynamic>?;
    if (parsingResults == null || parsingResults.isEmpty) {
      throw const DocExtractException('未获取到提取结果');
    }

    final pages = <_PageResult>[];
    for (final page in parsingResults) {
      final mdSection = page['markdown'] as Map<String, dynamic>?;
      if (mdSection == null) continue;

      final text = mdSection['text'] as String? ?? '';
      final images = <String, String>{};
      final rawImages = mdSection['images'] as Map<String, dynamic>?;
      if (rawImages != null) {
        for (final entry in rawImages.entries) {
          images[entry.key] = entry.value.toString();
        }
      }
      pages.add(_PageResult(markdown: text, images: images));
    }

    final rawMarkdown = pages.map((p) => p.markdown).join('\n\n');
    final allImages = <String, String>{};
    for (final page in pages) {
      allImages.addAll(page.images);
    }

    return DocExtractResult(
      rawMarkdown: rawMarkdown,
      images: allImages,
      jsonlContent: jsonEncode({'result': result}),
    );
  }

  /// 输出文件：
  /// - `{pdfName}.raw.md`：API 原始 Markdown
  /// - `{pdfName}.md`：阅读器使用的预处理 Markdown
  /// - `{pdfName}.jsonl`：官方结果；同步接口本地封装为单行 JSONL
  /// - `{pdfName}_images/`：提取到的图片
  Future<String> saveResult(
    String pdfPath,
    DocExtractResult result, {
    String? token,
    String? title,
  }) async {
    final dir = p.dirname(pdfPath);
    final baseName = p.basenameWithoutExtension(pdfPath);
    final imgDir = p.join(dir, '${baseName}_images');
    final rawMdPath = p.join(dir, '$baseName.raw.md');
    final mdPath = p.join(dir, '$baseName.md');
    final jsonlPath = p.join(dir, '$baseName.jsonl');

    await File(rawMdPath).writeAsString(result.rawMarkdown, flush: true);
    result.rawPath = rawMdPath;

    if (result.jsonlContent != null) {
      await File(jsonlPath).writeAsString(result.jsonlContent!, flush: true);
      result.jsonlPath = jsonlPath;
    }

    final localPaths = <String, String>{};
    final networkUrls = <String, String>{};

    if (result.images.isNotEmpty) {
      await Directory(imgDir).create(recursive: true);

      for (final entry in result.images.entries) {
        final value = entry.value;

        if (!value.startsWith('http://') && !value.startsWith('https://')) {
          try {
            final bytes = base64Decode(value);
            final imgPath = p.join(imgDir, entry.key);
            await Directory(p.dirname(imgPath)).create(recursive: true);
            await File(imgPath).writeAsBytes(bytes);
            localPaths[entry.key] = imgPath;
          } catch (e) {
            debugPrint('[DocExtract] Base64 图片解码失败: ${entry.key} → $e');
          }
          continue;
        }

        networkUrls[entry.key] = value;

        try {
          final imgPath = p.join(imgDir, entry.key);
          await Directory(p.dirname(imgPath)).create(recursive: true);
          final isBosPresigned = value.contains('authorization=bce-auth');
          final imgResponse = await _dio.get<List<int>>(
            value,
            options: Options(
              responseType: ResponseType.bytes,
              headers: (!isBosPresigned && token != null)
                  ? {'Authorization': 'token $token'}
                  : null,
            ),
          );
          if (imgResponse.data != null && imgResponse.data!.isNotEmpty) {
            await File(imgPath).writeAsBytes(imgResponse.data!);
            localPaths[entry.key] = imgPath;
          }
        } catch (e) {
          debugPrint('[DocExtract] 图片下载失败: ${entry.key} → $e');
        }
      }
    }

    result.imageDir = imgDir;

    var resolvedMarkdown = result.rawMarkdown;
    for (final entry in networkUrls.entries) {
      if (!localPaths.containsKey(entry.key)) {
        resolvedMarkdown = resolvedMarkdown
            .replaceAll('src="${entry.key}"', 'src="${entry.value}"')
            .replaceAll('(${entry.key})', '(${entry.value})');
      }
    }

    resolvedMarkdown = resolveMarkdownImagePaths(resolvedMarkdown, imgDir);
    resolvedMarkdown = MarkdownPreprocessor.filterBeforeTitle(
      resolvedMarkdown,
      title,
    );

    await File(mdPath).writeAsString(resolvedMarkdown, flush: true);
    result.processedMarkdown = resolvedMarkdown;
    result.savedPath = mdPath;
    return mdPath;
  }

  /// 规范化图片标签并将相对路径解析为 `file:///` 绝对路径。
  static String resolveMarkdownImagePaths(String markdown, String imageDir) {
    var processed = markdown;

    processed = processed.replaceAllMapped(
      RegExp(r'<div[^>]*>\s*<img\s+[^>]*?src="([^"]+)"[^>]*/?\s*>\s*</div>'),
      (match) {
        final src = match.group(1)!;
        final altMatch = RegExp(r'alt="([^"]*)"').firstMatch(match.group(0)!);
        final alt = altMatch?.group(1) ?? '';
        return '![$alt]($src)';
      },
    );

    processed = processed.replaceAllMapped(
      RegExp(r'<div\s+style="text-align:\s*center;\s*">\s*(.+?)\s*</div>'),
      (match) {
        final content = match.group(1)!;
        if (content.contains('<img')) return match.group(0)!;
        return '*$content*';
      },
    );

    processed = processed.replaceAllMapped(
      RegExp(r'<img\s+[^>]*?src="([^"]+)"[^>]*/?\s*>'),
      (match) {
        final src = match.group(1)!;
        final altMatch = RegExp(r'alt="([^"]*)"').firstMatch(match.group(0)!);
        final alt = altMatch?.group(1) ?? '';
        return '![$alt]($src)';
      },
    );

    processed = MarkdownPreprocessor.process(processed);

    processed = processed.replaceAllMapped(
      RegExp(r'!\[([^\]]*)\]\(([^)]+)\)'),
      (match) {
        final alt = match.group(1)!;
        final imgPath = match.group(2)!;

        if (imgPath.startsWith('http://') ||
            imgPath.startsWith('https://') ||
            imgPath.startsWith('file:///')) {
          return match.group(0)!;
        }

        final localFile = File(p.join(imageDir, imgPath));
        if (localFile.existsSync()) {
          final uri = Uri.file(localFile.path);
          return '![$alt]($uri)';
        }

        return match.group(0)!;
      },
    );

    return processed;
  }

  static Map<String, dynamic> buildOptions(DocExtractApiState state) {
    return {
      'markdownIgnoreLabels': state.markdownIgnoreLabels,
      'promptLabel': 'ocr',
      'useLayoutDetection': true,
      'useChartRecognition': state.useChartRecognition,
      'useDocOrientationClassify': state.useDocOrientationClassify,
      'useDocUnwarping': state.useDocUnwarping,
      'useSealRecognition': state.useSealRecognition,
      'useOcrForImageBlock': state.useOcrForImageBlock,
      'mergeTables': true,
      'relevelTitles': true,
      'restructurePages': state.restructurePages,
      'topP': 1,
      'layoutNms': state.layoutNms,
      'layoutShapeMode': state.layoutShapeMode,
      'layoutThreshold': state.layoutThreshold,
      'minPixels': 147384,
      'maxPixels': 2822400,
      'repetitionPenalty': state.repetitionPenalty,
      'temperature': 0,
    };
  }
}
