import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'proxy_adapter.dart';
import 'package:path/path.dart' as p;

import '../data/models/ocr/doc_extract_config.dart';
import '../utils/doc_paths.dart';
import '../utils/markdown_preprocessor.dart';
import 'document_structure.dart';
import 'figure_extract_service.dart';
import 'figure_markdown.dart';
import 'mineru_result_converter.dart';
import 'extraction_artifacts.dart';
import '../core/app_logger.dart';

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
    _dio.httpClientAdapter = buildProxyAdapter(mode.name, host, port);
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
  /// 4. 保留未归属源图 → LaTeX 预处理 → 标题过滤
  Future<String> saveResult(
    String pdfPath,
    DocExtractResult result, {
    String? token,
    String? title,
  }) async {
    final previous =
        await FigureExtractService.loadManifest(pdfPath) ??
        const <FigureManifestEntry>[];
    final dir = p.dirname(pdfPath);
    final rawMdPath = DocPaths.rawMd(pdfPath);
    final mdPath = DocPaths.md(pdfPath);
    final jsonPath = DocPaths.json(pdfPath);
    var jsonContent = result.jsonContent;
    if (jsonContent != null && result.images.isNotEmpty) {
      jsonContent = await localizeImages(
        pdfPath: pdfPath,
        jsonContent: jsonContent,
        images: result.images,
        fetch: (url) async => (await _dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        )).data,
      );
    }

    FigureExtractResult? figures;
    // 2. 从 PDF 提取 figure → 替换 Markdown 中的 figure 区域
    var processedMarkdown = result.rawMarkdown;
    if (jsonContent != null) {
      try {
        await FigureExtractService.instance.init();
        final figResult = await FigureExtractService.instance.extractFigures(
          resultPath: jsonPath,
          pdfPath: pdfPath,
          jsonContent: jsonContent,
          publishManifest: false,
        );
        figures = figResult;
        retainSourceFigures(jsonContent, dir, figResult.entries);
        processedMarkdown = replaceFigureRegions(
          jsonContent: jsonContent,
          figures: figResult.entries,
          mdDir: dir,
          recordReferences: true,
        );
      } catch (e) {
        if (await File(mdPath).exists()) rethrow;
        log.d('[DocExtract] Figure 提取/替换失败，回退原始 Markdown: $e');
      }
    }

    // 3. 清理残留标签 + 格式预处理
    processedMarkdown = _cleanPipeline(
      processedMarkdown,
      jsonContent: jsonContent,
      title: title,
    );

    try {
      await ExtractionArtifacts.publish(pdfPath, DocExtractProvider.paddle, {
        rawMdPath: result.rawMarkdown,
        jsonPath: ?jsonContent,
        DocPaths.figuresManifest(pdfPath): FigureExtractService.encodeManifest(
          _visibleInMarkdown(figures?.entries ?? const [], processedMarkdown),
          pdfPath,
        ),
        mdPath: processedMarkdown,
      });
    } catch (_) {
      if (figures != null) {
        await Directory(figures.outputDir).delete(recursive: true);
      }
      rethrow;
    }
    result.rawPath = rawMdPath;
    if (figures != null) {
      await pruneFigureGenerations(DocPaths.figuresDir(pdfPath), [
        ...figures.entries.map((e) => e.imagePath),
        ...previous.map((e) => e.imagePath),
      ]);
    }
    result.jsonPath = result.jsonContent == null ? null : jsonPath;
    result.processedMarkdown = processedMarkdown;
    result.savedPath = mdPath;
    result.imageDir = DocPaths.figuresDir(pdfPath);
    return mdPath;
  }

  /// 从已有的 `.raw.md` + `.json` + PDF 重新排版，跳过 API 请求。
  ///
  /// 用于用户修改了 figure 提取逻辑或预处理管道后，
  /// 不重新调用 API 直接刷新最终 `.md`。
  Future<(String mdPath, String content)> reprocessMarkdown({
    required String pdfPath,
    String? title,
    DocExtractProvider? source,
  }) async {
    final previous =
        await FigureExtractService.loadManifest(pdfPath) ??
        const <FigureManifestEntry>[];
    final sources = await ExtractionArtifacts.availableSources(pdfPath);
    if (source == null && sources.length > 1) {
      throw StateError('extraction_source_required');
    }
    source ??=
        sources.firstOrNull ?? await ExtractionArtifacts.activeSource(pdfPath);
    if (source == DocExtractProvider.mineru) {
      return MinerUResultConverter.instance.reprocess(
        pdfPath: pdfPath,
        title: title,
      );
    }
    final dir = p.dirname(pdfPath);
    final (jsonPath, rawMdPath) = await ExtractionArtifacts.inputs(
      pdfPath,
      source,
    );
    final mdPath = DocPaths.md(pdfPath);

    final rawMdFile = File(rawMdPath);
    if (!rawMdFile.existsSync()) {
      throw FileSystemException(
        'raw.md not found; run extraction first',
        rawMdPath,
      );
    }

    final rawMarkdown = await rawMdFile.readAsString();
    var processedMarkdown = rawMarkdown;

    // figure 提取 + 替换
    final jsonFile = File(jsonPath);
    String? jsonContent;
    FigureExtractResult? figures;
    if (jsonFile.existsSync()) {
      jsonContent = await jsonFile.readAsString();
      try {
        await FigureExtractService.instance.init();
        final figResult = await FigureExtractService.instance.extractFigures(
          resultPath: jsonPath,
          pdfPath: pdfPath,
          publishManifest: false,
        );
        figures = figResult;
        retainSourceFigures(jsonContent, dir, figResult.entries);
        processedMarkdown = replaceFigureRegions(
          jsonContent: jsonContent,
          figures: figResult.entries,
          mdDir: dir,
          recordReferences: true,
        );
      } catch (e) {
        log.d('[DocExtract] 重新排版: 保留已有产物: $e');
        rethrow;
      }
    }

    // 清理 + 预处理（与 saveResult 完全一致）
    processedMarkdown = _cleanPipeline(
      processedMarkdown,
      jsonContent: jsonContent,
      title: title,
    );

    try {
      await ExtractionArtifacts.publish(pdfPath, source, {
        DocPaths.rawMd(pdfPath): rawMarkdown,
        DocPaths.json(pdfPath): ?jsonContent,
        DocPaths.figuresManifest(pdfPath): FigureExtractService.encodeManifest(
          _visibleInMarkdown(figures?.entries ?? const [], processedMarkdown),
          pdfPath,
        ),
        mdPath: processedMarkdown,
      });
    } catch (_) {
      if (figures != null) {
        await Directory(figures.outputDir).delete(recursive: true);
      }
      rethrow;
    }
    if (figures != null) {
      await pruneFigureGenerations(DocPaths.figuresDir(pdfPath), [
        ...figures.entries.map((e) => e.imagePath),
        ...previous.map((e) => e.imagePath),
      ]);
    }
    return (mdPath, processedMarkdown);
  }

  /// 用已裁决的 [figures] manifest 重生成 `.md`（AI 修缮 figure 的落盘入口）。
  ///
  /// 读 `raw.md` → [replaceFigureRegions] 用 [figures] 替换 figure 区域 →
  /// [_cleanPipeline] 清理 + 预处理 → 写 `extract.md`。**不删 figures 目录**、
  /// **不重跑 [FigureExtractService.extractFigures]**——figures 由调用方已
  /// 裁好写入。回滚靠 [reprocessMarkdown]（重跑启发式覆盖 AI 产物）。
  ///
  /// [jsonContent] 是 extract.json 文本（[_normalizeSectionHeadingLevels] 与
  /// [replaceFigureRegions] 均需）。
  Future<(String mdPath, String content)> applyFigureManifest({
    required String pdfPath,
    required String jsonContent,
    required List<FigureManifestEntry> figures,
    String? title,
  }) async {
    final dir = p.dirname(pdfPath);
    final rawMdPath = DocPaths.rawMd(pdfPath);
    final mdPath = DocPaths.md(pdfPath);

    final rawMdFile = File(rawMdPath);
    if (!rawMdFile.existsSync()) {
      throw FileSystemException(
        'raw.md not found; run extraction first',
        rawMdPath,
      );
    }

    var processedMarkdown = await rawMdFile.readAsString();
    processedMarkdown = replaceFigureRegions(
      jsonContent: jsonContent,
      figures: figures,
      mdDir: dir,
    );
    processedMarkdown = _cleanPipeline(
      processedMarkdown,
      jsonContent: jsonContent,
      title: title,
    );

    final source = await ExtractionArtifacts.activeSource(pdfPath);
    await ExtractionArtifacts.publish(pdfPath, source, {
      DocPaths.figuresManifest(pdfPath): FigureExtractService.encodeManifest(
        _visibleInMarkdown(figures, processedMarkdown),
        pdfPath,
        source: source.artifactKey,
        diagnostics: {'source': 'ai_fix'},
      ),
      mdPath: processedMarkdown,
    });
    return (mdPath, processedMarkdown);
  }

  static String replaceFigureRegions({
    required String jsonContent,
    required List<FigureManifestEntry> figures,
    required String mdDir,
    bool recordReferences = false,
  }) {
    final structure = DocumentStructure.parse(jsonContent);
    if (structure.isEmpty) throw const FormatException('unsupported_layout');
    final emitted = <FigureManifestEntry>{};
    final output = <int, String>{};
    final refs = <FigureManifestEntry, List<Map<String, dynamic>>>{};
    final decoded = jsonDecode(jsonContent);
    final assets = decoded is Map && decoded['_paddle_assets'] is Map
        ? (decoded['_paddle_assets'] as Map).map(
            (k, v) => MapEntry(k.toString(), p.join(mdDir, v.toString())),
          )
        : <String, String>{};
    for (final page in structure.pages) {
      final result = FigureMarkdown.replace(
        page.markdown,
        figures,
        structure: structure,
        pageIndex: page.pageIndex,
        assets: assets,
        emitted: emitted,
      );
      output[page.pageIndex] = result.markdown;
      for (final entry in result.replacements.entries) {
        refs.putIfAbsent(entry.key, () => []).addAll(entry.value);
      }
    }
    if (recordReferences) {
      for (var i = 0; i < figures.length; i++) {
        final entry = figures[i];
        figures[i] = FigureManifestEntry.fromJson({
          ...entry.toJson(),
          'replacement_refs': refs[entry] ?? const [],
        });
      }
    }
    return structure.pages.map((p) => output[p.pageIndex]!).join('\n\n');
  }

  static void retainSourceFigures(
    String jsonContent,
    String mdDir,
    List<FigureManifestEntry> figures,
  ) {
    final data = jsonDecode(jsonContent);
    if (data is! Map || data['_paddle_assets'] is! Map) return;
    final assets = (data['_paddle_assets'] as Map).map(
      (k, v) => MapEntry(k.toString(), p.join(mdDir, v.toString())),
    );
    FigureMarkdown.retainSourceFigures(
      DocumentStructure.parse(jsonContent),
      assets,
      figures,
    );
  }

  /// 只下载响应声明的图片，不向资源地址转发 OCR 凭据；单图失败不丢失原底稿。
  static Future<String> localizeImages({
    required String pdfPath,
    required String jsonContent,
    required Map<String, String> images,
    required Future<List<int>?> Function(String url) fetch,
  }) async {
    final decoded = jsonDecode(jsonContent);
    final root = decoded is List
        ? <String, dynamic>{'layoutParsingResults': decoded}
        : Map<String, dynamic>.from(decoded as Map);
    final assets = Map<String, dynamic>.from(
      root['_paddle_assets'] as Map? ?? {},
    );
    final generation = await createFigureGeneration(
      DocPaths.figuresDir(pdfPath),
    );
    for (final entry in images.entries) {
      try {
        final uri = Uri.tryParse(entry.value);
        if (uri == null ||
            !const ['http', 'https', 'data'].contains(uri.scheme)) {
          continue;
        }
        final bytes = uri.scheme == 'data'
            ? uri.data?.contentAsBytes()
            : await fetch(entry.value);
        if (bytes == null || bytes.isEmpty) continue;
        final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
        final frame = await codec.getNextFrame();
        frame.image.dispose();
        codec.dispose();
        final filename = '${sha256.convert(utf8.encode(entry.key))}.image';
        final file = File(p.join(generation.path, filename));
        await file.writeAsBytes(bytes, flush: true);
        final relative = p.relative(file.path, from: p.dirname(pdfPath));
        assets[entry.key] = relative;
        assets[entry.value] = relative;
      } on Exception {
        // 保留原 URL／HTML，不能因一张失效资源阻断其他图表。
      }
    }
    root['_paddle_assets'] = assets;
    return jsonEncode(root);
  }

  /// 清理 + 预处理管线（saveResult / reprocessMarkdown / applyFigureManifest 共用）。
  ///
  /// 顺序固定：保留未匹配图片 → [_convertCenteredDivs] →
  /// [MarkdownPreprocessor.process] → [MarkdownPreprocessor.filterBeforeTitle] →
  /// [_normalizeSectionHeadingLevels]（仅 [jsonContent] 非空时）。
  /// 改顺序即改三处渲染结果，禁止调整。
  static String _cleanPipeline(
    String markdown, {
    String? jsonContent,
    String? title,
  }) {
    var md = markdown;
    md = _convertCenteredDivs(md);
    md = MarkdownPreprocessor.process(md);
    md = MarkdownPreprocessor.filterBeforeTitle(md, title);
    if (jsonContent != null) {
      md = _normalizeSectionHeadingLevels(md, jsonContent);
    }
    return md;
  }

  /// 将 JSON paragraph_title 对应的 ATX heading 统一为 ##（二级标题）。
  ///
  /// API 返回的标题级别不一致（##/###），归一化后渲染大小一致。
  static String _normalizeSectionHeadingLevels(
    String markdown,
    String jsonContent,
  ) {
    final titles = _extractParagraphTitles(jsonContent);
    if (titles.isEmpty) return markdown;

    return markdown.replaceAllMapped(
      RegExp(r'^(#{1,6})\s+(.+?)(?:\s+#+\s*)?$', multiLine: true),
      (match) {
        final level = match.group(1)!;
        final text = match.group(2)!.trim();
        if (level == '##') return match.group(0)!;
        if (_titleSetContains(titles, text)) return '## $text';
        return match.group(0)!;
      },
    );
  }

  static Set<String> _extractParagraphTitles(String jsonContent) {
    final titles = <String>{};
    for (final page in DocumentStructure.parse(jsonContent).pages) {
      for (final block in page.blocks) {
        if (block.blockLabel == 'paragraph_title') {
          final c = block.blockContent.trim();
          if (c.isNotEmpty) titles.add(c);
        }
      }
    }
    return titles;
  }

  static bool _titleSetContains(Set<String> titles, String text) {
    if (titles.contains(text)) return true;
    final stripped = text.replaceFirst(
      RegExp(
        r'^(?:\d+(?:\.\d+)*|[ivxlcdm]+)\s*[:.)\-]?\s+',
        caseSensitive: false,
      ),
      '',
    );
    return stripped != text && titles.contains(stripped);
  }

  static List<FigureManifestEntry> _visibleInMarkdown(
    List<FigureManifestEntry> entries,
    String markdown,
  ) => [
    for (final entry in entries)
      if (entry.isDisplayFigure &&
          (entry.id == null || markdown.contains(entry.markdownAnchor)))
        entry,
  ];

  static final _figureSubLabelRe = RegExp(
    r'^\(?[a-zA-Z](?:\s*,\s*[a-zA-Z])*\)?$',
  );

  /// 将居中文本 div 转为斜体（含 img / figure 子标签的 div 直接移除）
  static String _convertCenteredDivs(String markdown) {
    return markdown.replaceAllMapped(
      RegExp(r'<div\s+style="text-align:\s*center;\s*">\s*(.+?)\s*</div>'),
      (match) {
        final content = match.group(1)!;
        if (content.contains('<img')) return content;
        if (_figureSubLabelRe.hasMatch(content.trim())) return content;
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
      'mergeTables': state.mergeTables,
      'relevelTitles': true,
      'restructurePages': state.restructurePages,
      'topP': 1,
      'layoutNms': state.layoutNms,
      'layoutShapeMode': state.layoutShapeMode,
      'minPixels': 147384,
      'maxPixels': 2822400,
      'repetitionPenalty': state.repetitionPenalty,
      'temperature': state.temperature,
    };
  }
}

/// 单个 figure 的替换计划——在 `_replaceInPageMd` 流水线中传递。
///
/// 行集合表达（而非连续区间）让"同页两 figure 行号交错"的双栏排版也能正确替换：
/// 两个 figure 的 [ownedLines] 互不相交，各自的 [anchorLine] 独立定位插入点。
