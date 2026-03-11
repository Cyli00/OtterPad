import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:path/path.dart' as p;

import '../providers/api_provider.dart';

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
  final Map<String, String> images; // 相对路径 → 图片下载 URL

  const _PageResult({required this.markdown, required this.images});
}

/// 文档提取结果
class DocExtractResult {
  final String markdown;
  final Map<String, String> images;
  String? savedPath;

  DocExtractResult({
    required this.markdown,
    required this.images,
    this.savedPath,
  });
}

/// 百度 AI Studio PaddleOCR-VL 文档版面解析服务
///
/// 将 PDF 文件通过 Layout Parsing API 提取为 Markdown 文本。
/// 单例模式，与 [IdentifierResolver] 保持一致的 Dio + 代理模式。
class DocExtractService {
  DocExtractService._();
  static final DocExtractService instance = DocExtractService._();

  late final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 300),
    sendTimeout: const Duration(seconds: 120),
  ));

  // ─── 代理配置 ──────────────────────────────────────────────────────────────

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

  // ─── 主方法：提取 PDF → Markdown ──────────────────────────────────────────

  /// 提取文档内容。
  ///
  /// [filePath] PDF 文件路径
  /// [apiUrl]   API 地址（如 https://xxx.aistudio-app.com）
  /// [token]    Access Token
  /// [state]    包含提取选项的 DocExtractApiState
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

    // Base64 编码文件内容
    final fileBytes = await file.readAsBytes();
    final fileData = base64Encode(fileBytes);

    // 构建请求 payload
    final payload = <String, dynamic>{
      'file': fileData,
      'fileType': 0, // PDF
      ..._buildOptions(state),
    };

    // 发送请求
    final url = apiUrl.endsWith('/')
        ? '${apiUrl}layout-parsing'
        : '$apiUrl/layout-parsing';

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

    // 解析响应
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

    // 汇总所有页面的 Markdown 和图片
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

    final fullMarkdown = pages.map((p) => p.markdown).join('\n\n');
    final allImages = <String, String>{};
    for (final page in pages) {
      allImages.addAll(page.images);
    }

    return DocExtractResult(markdown: fullMarkdown, images: allImages);
  }

  // ─── 保存结果到磁盘 ──────────────────────────────────────────────────────

  /// 将提取结果保存到 PDF 同目录。
  ///
  /// Markdown 文件：`{pdfName}.md`
  /// 图片目录：`{pdfName}_images/`
  Future<String> saveResult(String pdfPath, DocExtractResult result) async {
    final dir = p.dirname(pdfPath);
    final baseName = p.basenameWithoutExtension(pdfPath);

    // 保存 Markdown 文件
    final mdPath = p.join(dir, '$baseName.md');
    final mdFile = File(mdPath);
    await mdFile.writeAsString(result.markdown, flush: true);

    // 下载并保存图片
    if (result.images.isNotEmpty) {
      final imgDir = p.join(dir, '${baseName}_images');
      await Directory(imgDir).create(recursive: true);

      for (final entry in result.images.entries) {
        try {
          final imgPath = p.join(imgDir, entry.key);
          await Directory(p.dirname(imgPath)).create(recursive: true);
          final imgResponse = await _dio.get<List<int>>(
            entry.value,
            options: Options(responseType: ResponseType.bytes),
          );
          if (imgResponse.data != null) {
            await File(imgPath).writeAsBytes(imgResponse.data!);
          }
        } catch (_) {
          // 图片下载失败不阻断整体流程
        }
      }
    }

    result.savedPath = mdPath;
    return mdPath;
  }

  // ─── 内部工具 ──────────────────────────────────────────────────────────────

  Map<String, dynamic> _buildOptions(DocExtractApiState state) {
    return {
      'useLayoutDetection': state.useLayoutDetection,
      'useChartRecognition': state.useChartRecognition,
      'useDocOrientationClassify': state.useDocOrientationClassify,
      'useDocUnwarping': state.useDocUnwarping,
      'useSealRecognition': state.useSealRecognition,
      'useOcrForImageBlock': state.useOcrForImageBlock,
      'mergeTables': state.mergeTables,
      'relevelTitles': state.relevelTitles,
      'restructurePages': state.restructurePages,
      'layoutNms': state.layoutNms,
      if (state.markdownIgnoreLabels.isNotEmpty)
        'markdownIgnoreLabels': state.markdownIgnoreLabels,
    };
  }
}
