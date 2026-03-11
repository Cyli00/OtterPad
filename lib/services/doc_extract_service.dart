import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:markdown/markdown.dart' as md;
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
  String? savedPath; // 保存后的 .html 文件路径
  String? imageDir; // 图片保存目录的绝对路径

  DocExtractResult({
    required this.markdown,
    required this.images,
    this.savedPath,
    this.imageDir,
  });
}

/// 百度 AI Studio PaddleOCR-VL 文档版面解析服务
///
/// 将 PDF 文件通过 Layout Parsing API 提取为 Markdown，
/// 然后转换为带排版的 HTML 文件保存。
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
      ..._buildOptions(state),
    };

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
  /// 输出文件：
  /// - `{pdfName}.md` — 原始 Markdown
  /// - `{pdfName}.html` — 带排版的 HTML（图片用 file:// 绝对路径引用）
  /// - `{pdfName}_images/` — 提取到的图片
  ///
  /// [token] 传入 Access Token，部分图片 URL 可能需要认证才能下载。
  Future<String> saveResult(
    String pdfPath,
    DocExtractResult result, {
    String? token,
  }) async {
    final dir = p.dirname(pdfPath);
    final baseName = p.basenameWithoutExtension(pdfPath);
    final imgDir = p.join(dir, '${baseName}_images');

    // 保存原始 Markdown
    final mdPath = p.join(dir, '$baseName.md');
    await File(mdPath).writeAsString(result.markdown, flush: true);

    // 下载图片到本地，收集 <相对路径 → 绝对本地路径> 映射
    final localPaths = <String, String>{};
    // 同时收集 <相对路径 → 原始网络 URL> 作为回退
    final networkUrls = <String, String>{};

    if (result.images.isNotEmpty) {
      await Directory(imgDir).create(recursive: true);

      // BOS 预签名 URL 包含自含签名，不能附加 Authorization 头，也不能经过代理
      // （代理会修改 Host/Via 头，破坏签名校验 → 400）。
      // token == null 表示来自批量提取，使用临时纯净 Dio 直连 BOS。
      final downloadDio = token == null ? Dio() : _dio;

      for (final entry in result.images.entries) {
        final value = entry.value;

        // 非 HTTP URL（如 Base64 数据）：直接解码写入文件
        if (!value.startsWith('http://') && !value.startsWith('https://')) {
          try {
            final bytes = base64Decode(value);
            final imgPath = p.join(imgDir, entry.key);
            await Directory(p.dirname(imgPath)).create(recursive: true);
            await File(imgPath).writeAsBytes(bytes);
            localPaths[entry.key] = imgPath;
          } catch (_) {}
          continue;
        }

        networkUrls[entry.key] = value;

        try {
          final imgPath = p.join(imgDir, entry.key);
          await Directory(p.dirname(imgPath)).create(recursive: true);

          final imgResponse = await downloadDio.get<List<int>>(
            value,
            options: Options(
              responseType: ResponseType.bytes,
              headers: token != null
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

    // Markdown → HTML，优先用本地路径，回退到网络 URL
    final htmlBody = _markdownToHtml(result.markdown, localPaths, networkUrls);
    final htmlPath = p.join(dir, '$baseName.html');
    await File(htmlPath).writeAsString(htmlBody, flush: true);

    result.savedPath = htmlPath;
    return htmlPath;
  }

  // ─── 静态工具 ──────────────────────────────────────────────────────────────

  /// 将 Markdown 中的图片相对路径替换为绝对 file:/// 路径。
  ///
  /// [imageDir] 为图片保存目录的绝对路径（如 `{pdfDir}/{baseName}_images/`）。
  /// 仅替换非 HTTP/file 协议的相对路径，且本地文件确实存在的情况。
  static String resolveMarkdownImagePaths(String markdown, String imageDir) {
    return markdown.replaceAllMapped(
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
          final absPath = localFile.path.replaceAll('\\', '/');
          return '![$alt](file:///$absPath)';
        }

        return match.group(0)!;
      },
    );
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

  /// 将 Markdown 转为带完整排版的 HTML。
  ///
  /// 图片引用替换优先级：本地文件（file:///）→ 网络 URL → 保留原始路径。
  String _markdownToHtml(
    String markdown,
    Map<String, String> localPaths,
    Map<String, String> networkUrls,
  ) {
    var processed = markdown;

    // 在 Markdown 源码中替换图片路径
    final allKeys = {...localPaths.keys, ...networkUrls.keys};
    for (final key in allKeys) {
      String replacement;
      if (localPaths.containsKey(key)) {
        // file:/// URI 需要正斜杠
        final absPath = localPaths[key]!.replaceAll('\\', '/');
        replacement = 'file:///$absPath';
      } else if (networkUrls.containsKey(key)) {
        replacement = networkUrls[key]!;
      } else {
        continue;
      }
      // 替换 Markdown 图片语法 ![alt](key) 中的 key
      processed = processed.replaceAll('($key)', '($replacement)');
    }

    // 转换为 HTML
    final htmlBody = md.markdownToHtml(
      processed,
      extensionSet: md.ExtensionSet.gitHubWeb,
    );

    // 二次处理 HTML：捕捉遗漏的 src="relative_path" 图片引用
    var finalHtml = htmlBody;
    for (final key in allKeys) {
      if (finalHtml.contains('src="$key"')) {
        String replacement;
        if (localPaths.containsKey(key)) {
          final absPath = localPaths[key]!.replaceAll('\\', '/');
          replacement = 'file:///$absPath';
        } else {
          replacement = networkUrls[key]!;
        }
        finalHtml = finalHtml.replaceAll('src="$key"', 'src="$replacement"');
      }
    }

    return '''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
$_htmlCss
</style>
</head>
<body>
<article>
$finalHtml
</article>
</body>
</html>''';
  }

  static const _htmlCss = '''
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
    "Helvetica Neue", Arial, "Noto Sans SC", sans-serif;
  font-size: 15px;
  line-height: 1.8;
  color: #1a1a1a;
  padding: 20px 16px;
  max-width: 800px;
  margin: 0 auto;
}
article { word-wrap: break-word; overflow-wrap: break-word; }

h1 { font-size: 1.6em; margin: 1.2em 0 0.6em; font-weight: 700; }
h2 { font-size: 1.35em; margin: 1em 0 0.5em; font-weight: 700; }
h3 { font-size: 1.15em; margin: 0.8em 0 0.4em; font-weight: 600; }
h4, h5, h6 { font-size: 1em; margin: 0.6em 0 0.3em; font-weight: 600; }

p { margin: 0.6em 0; }
a { color: #1565c0; text-decoration: none; }
a:hover { text-decoration: underline; }

img {
  max-width: 100%;
  height: auto;
  display: block;
  margin: 1em auto;
  border-radius: 4px;
}

blockquote {
  border-left: 3px solid #1565c0;
  padding: 0.4em 1em;
  margin: 0.8em 0;
  color: #555;
  background: #f5f7fa;
  border-radius: 0 4px 4px 0;
}

code {
  font-family: "Cascadia Code", "Fira Code", "JetBrains Mono", monospace;
  font-size: 0.88em;
  background: #f0f2f5;
  padding: 2px 6px;
  border-radius: 3px;
}
pre {
  background: #f0f2f5;
  padding: 12px 16px;
  border-radius: 6px;
  overflow-x: auto;
  margin: 0.8em 0;
}
pre code { background: none; padding: 0; }

table {
  width: 100%;
  border-collapse: collapse;
  margin: 1em 0;
  font-size: 0.92em;
}
th, td {
  border: 1px solid #d0d7de;
  padding: 8px 12px;
  text-align: left;
}
th {
  background: #f0f2f5;
  font-weight: 600;
}
tr:nth-child(even) td { background: #fafbfc; }

ul, ol { padding-left: 1.8em; margin: 0.5em 0; }
li { margin: 0.2em 0; }

hr {
  border: none;
  border-top: 1px solid #d0d7de;
  margin: 1.5em 0;
}
''';
}
