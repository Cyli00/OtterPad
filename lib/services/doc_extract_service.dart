import 'dart:convert';
import 'dart:io';
import 'dart:math' show min, max;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../providers/api_provider.dart';
import '../utils/markdown_preprocessor.dart';
import 'figure_extract_service.dart';

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
  final String? jsonContent;
  String? savedPath;
  String? rawPath;
  String? jsonPath;
  String? imageDir;
  String? processedMarkdown;

  DocExtractResult({
    required this.rawMarkdown,
    required this.images,
    this.jsonContent,
    this.savedPath,
    this.rawPath,
    this.jsonPath,
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
      jsonContent: jsonEncode(parsingResults),
    );
  }

  /// 输出文件：
  /// - `{pdfName}.raw.md`：API 原始 Markdown
  /// - `{pdfName}.md`：阅读器使用的预处理 Markdown
  /// - `{pdfName}.json`：版面解析完整结果（扁平页面数组）
  /// - `{pdfName}_figures/`：本地裁切的 figure 图片 + figures.json
  ///
  /// 流程（参照 PaddleApiTest/main.py）：
  /// 1. 保存 raw.md + JSON
  /// 2. 从 PDF 本地裁切 figure 图片（FigureExtractService）
  /// 3. 用 block_ids 匹配替换 Markdown 中的 figure 区域为本地图片
  /// 4. 清理残留 HTML 图片标签 → LaTeX 预处理 → 标题过滤
  Future<String> saveResult(
    String pdfPath,
    DocExtractResult result, {
    String? token,
    String? title,
  }) async {
    final dir = p.dirname(pdfPath);
    final baseName = p.basenameWithoutExtension(pdfPath);
    final rawMdPath = p.join(dir, '$baseName.raw.md');
    final mdPath = p.join(dir, '$baseName.md');
    final jsonPath = p.join(dir, '$baseName.json');

    // 1. 保存原始文件
    await File(rawMdPath).writeAsString(result.rawMarkdown, flush: true);
    result.rawPath = rawMdPath;

    if (result.jsonContent != null) {
      await File(jsonPath).writeAsString(result.jsonContent!, flush: true);
      result.jsonPath = jsonPath;
    }

    // 2. 从 PDF 提取 figure → 替换 Markdown 中的 figure 区域
    var processedMarkdown = result.rawMarkdown;
    if (result.jsonContent != null) {
      try {
        await FigureExtractService.instance.init();
        final figResult = await FigureExtractService.instance.extractFigures(
          resultPath: jsonPath,
          pdfPath: pdfPath,
        );
        processedMarkdown = replaceFigureRegions(
          jsonContent: result.jsonContent!,
          figures: figResult.entries,
          mdDir: dir,
        );
      } catch (e) {
        debugPrint('[DocExtract] Figure 提取/替换失败，回退原始 Markdown: $e');
      }
    }

    // 3. 清理残留 API 图片标签 + 居中 div → 斜体
    processedMarkdown = _stripApiImageTags(processedMarkdown);
    processedMarkdown = _convertCenteredDivs(processedMarkdown);

    // 4. LaTeX / 格式预处理 + 标题过滤
    processedMarkdown = MarkdownPreprocessor.process(processedMarkdown);
    processedMarkdown = MarkdownPreprocessor.filterBeforeTitle(
      processedMarkdown,
      title,
    );

    await File(mdPath).writeAsString(processedMarkdown, flush: true);
    result.processedMarkdown = processedMarkdown;
    result.savedPath = mdPath;
    result.imageDir = p.join(dir, '${baseName}_figures');
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

  // ─── Figure 替换（移植自 PaddleApiTest/replace_md.py） ─────────────────

  /// 用本地 figure 图片替换原始 Markdown 中的 figure 区域。
  ///
  /// 按页遍历 API JSON，通过 block_ids 在每页的 raw markdown.text 中
  /// 精确定位 figure 行范围，替换为 `![caption](file:///path/to/figure.png)`。
  static String replaceFigureRegions({
    required String jsonContent,
    required List<FigureManifestEntry> figures,
    required String mdDir,
  }) {
    final pages = jsonDecode(jsonContent) as List<dynamic>;

    final pageFigs = <int, List<FigureManifestEntry>>{};
    for (final fig in figures) {
      pageFigs.putIfAbsent(fig.pageIndex, () => []).add(fig);
    }

    final mdPages = <String>[];
    for (var pageIdx = 0; pageIdx < pages.length; pageIdx++) {
      final page = pages[pageIdx] as Map<String, dynamic>;
      var mdText = (page['markdown'] as Map<String, dynamic>?)?['text']
              as String? ??
          '';

      if (pageFigs.containsKey(pageIdx)) {
        final pageBlocks = (page['prunedResult']
                    as Map<String, dynamic>?)?['parsing_res_list']
                as List<dynamic>? ??
            [];
        mdText =
            _replaceInPageMd(mdText, pageFigs[pageIdx]!, pageBlocks, mdDir);
      }
      mdPages.add(mdText);
    }

    return mdPages.join('\n\n');
  }

  /// 在单页 raw markdown 中替换 figure 区域为本地图片引用
  static String _replaceInPageMd(
    String mdText,
    List<FigureManifestEntry> pageFigures,
    List<dynamic> rawBlocks,
    String mdDir,
  ) {
    final lines = mdText.split('\n');
    final usedLines = <int>{};

    final blockMap = <String, Map<String, dynamic>>{};
    for (final b in rawBlocks) {
      final block = b as Map<String, dynamic>;
      final id = block['block_id']?.toString() ?? '';
      if (id.isNotEmpty) blockMap[id] = block;
    }

    final replacements = <(int, int, String)>[];
    for (final fig in pageFigures) {
      final region =
          _findFigureRegion(lines, blockMap, fig.blockIds, usedLines);
      if (region == null) {
        debugPrint(
          '[DocExtract] 未定位到 '
          '"${fig.captionText.substring(0, min(30, fig.captionText.length))}…"',
        );
        continue;
      }
      final (start, end) = region;
      usedLines.addAll(List.generate(end - start, (i) => start + i));

      final uri = Uri.file(fig.imagePath);
      replacements.add((start, end, '\n![${fig.captionText}]($uri)\n'));
    }

    // 从后往前替换，保持行号不偏移
    replacements.sort((a, b) => b.$1.compareTo(a.$1));
    for (final r in replacements) {
      lines.replaceRange(r.$1, r.$2, [r.$3]);
    }

    return lines.join('\n');
  }

  /// 通过 block 内容/bbox 在 markdown 行中定位 figure 所占的行范围
  static (int, int)? _findFigureRegion(
    List<String> lines,
    Map<String, Map<String, dynamic>> blockMap,
    List<String> blockIds,
    Set<int> usedLines,
  ) {
    final matched = <int>{};

    for (final bid in blockIds) {
      final block = blockMap[bid];
      if (block == null) continue;

      final label = block['block_label'] as String? ?? '';
      final content = (block['block_content'] as String? ?? '').trim();

      int? idx;
      if (label == 'figure_title' && content.isNotEmpty) {
        idx = _findLine(
          lines,
          content.substring(0, min(30, content.length)),
          usedLines,
        );
      } else if (label == 'image' || label == 'chart') {
        final bbox = block['block_bbox'] as List<dynamic>?;
        if (bbox != null && bbox.length >= 4) {
          idx = _findLine(
            lines,
            '_${bbox[0]}_${bbox[1]}_${bbox[2]}_${bbox[3]}',
            usedLines,
          );
        }
      } else if (label == 'vision_footnote' && content.isNotEmpty) {
        idx = _findLine(
          lines,
          content.substring(0, min(20, content.length)),
          usedLines,
        );
      } else if (label == 'table' && content.isNotEmpty) {
        idx = _findLine(
          lines,
          content.substring(0, min(30, content.length)),
          usedLines,
        );
      }

      if (idx != null) matched.add(idx);
    }

    if (matched.isEmpty) return null;

    var start = matched.reduce(min);
    var end = matched.reduce(max) + 1;

    // 向上收纳紧邻空行
    while (start > 0 &&
        lines[start - 1].trim().isEmpty &&
        !usedLines.contains(start - 1)) {
      start--;
    }
    // 向下收纳紧邻空行
    while (end < lines.length &&
        lines[end].trim().isEmpty &&
        !usedLines.contains(end)) {
      end++;
    }

    return (start, end);
  }

  /// 在行列表中找到包含 [text] 的第一行（跳过已使用的行）
  static int? _findLine(
    List<String> lines,
    String text,
    Set<int> usedLines,
  ) {
    for (var i = 0; i < lines.length; i++) {
      if (!usedLines.contains(i) && lines[i].contains(text)) return i;
    }
    return null;
  }

  /// 移除 API 生成的 HTML 图片标签（figure 已替换为 `![]()`，其余无本地文件）
  static String _stripApiImageTags(String markdown) {
    var result = markdown;
    // <div><img src="relative_path"></div>
    result = result.replaceAllMapped(
      RegExp(
          r'<div[^>]*>\s*<img\s+[^>]*?src="([^"]+)"[^>]*/?\s*>\s*</div>'),
      (match) {
        final src = match.group(1)!;
        if (src.startsWith('http') || src.startsWith('file:///')) {
          return match.group(0)!;
        }
        return '';
      },
    );
    // 独立 <img> 标签
    result = result.replaceAllMapped(
      RegExp(r'<img\s+[^>]*?src="([^"]+)"[^>]*/?\s*>'),
      (match) {
        final src = match.group(1)!;
        if (src.startsWith('http') || src.startsWith('file:///')) {
          return match.group(0)!;
        }
        return '';
      },
    );
    return result;
  }

  /// 将居中文本 div 转为斜体（含 img 的 div 直接移除）
  static String _convertCenteredDivs(String markdown) {
    return markdown.replaceAllMapped(
      RegExp(r'<div\s+style="text-align:\s*center;\s*">\s*(.+?)\s*</div>'),
      (match) {
        final content = match.group(1)!;
        if (content.contains('<img')) return '';
        return '*$content*';
      },
    );
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
