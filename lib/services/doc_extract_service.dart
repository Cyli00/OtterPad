import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../providers/api_provider.dart';
import '../utils/doc_paths.dart';
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
    final rawMdPath = DocPaths.rawMd(pdfPath);
    final mdPath = DocPaths.md(pdfPath);
    final jsonPath = DocPaths.json(pdfPath);

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

    // 3. 清理残留标签 + 格式预处理
    processedMarkdown = _stripApiImageTags(processedMarkdown);
    processedMarkdown = _convertCenteredDivs(processedMarkdown);
    processedMarkdown = MarkdownPreprocessor.process(processedMarkdown);
    processedMarkdown = MarkdownPreprocessor.filterBeforeTitle(
      processedMarkdown,
      title,
    );
    if (result.jsonContent != null) {
      processedMarkdown = _normalizeSectionHeadingLevels(
        processedMarkdown,
        result.jsonContent!,
      );
    }

    await File(mdPath).writeAsString(processedMarkdown, flush: true);
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
  }) async {
    final dir = p.dirname(pdfPath);
    final rawMdPath = DocPaths.rawMd(pdfPath);
    final jsonPath = DocPaths.json(pdfPath);
    final mdPath = DocPaths.md(pdfPath);

    final rawMdFile = File(rawMdPath);
    if (!rawMdFile.existsSync()) {
      throw FileSystemException('raw.md 文件不存在，请先提取文档', rawMdPath);
    }

    var processedMarkdown = await rawMdFile.readAsString();

    // figure 提取 + 替换
    final jsonFile = File(jsonPath);
    String? jsonContent;
    if (jsonFile.existsSync()) {
      jsonContent = await jsonFile.readAsString();
      try {
        await FigureExtractService.instance.init();
        final figResult = await FigureExtractService.instance.extractFigures(
          resultPath: jsonPath,
          pdfPath: pdfPath,
        );
        processedMarkdown = replaceFigureRegions(
          jsonContent: jsonContent,
          figures: figResult.entries,
          mdDir: dir,
        );
      } catch (e) {
        debugPrint('[DocExtract] 重新排版: Figure 提取失败，回退原始 Markdown: $e');
      }
    }

    // 清理 + 预处理（与 saveResult 完全一致）
    processedMarkdown = _stripApiImageTags(processedMarkdown);
    processedMarkdown = _convertCenteredDivs(processedMarkdown);
    processedMarkdown = MarkdownPreprocessor.process(processedMarkdown);
    processedMarkdown = MarkdownPreprocessor.filterBeforeTitle(
      processedMarkdown,
      title,
    );
    if (jsonContent != null) {
      processedMarkdown = _normalizeSectionHeadingLevels(
        processedMarkdown,
        jsonContent,
      );
    }

    await File(mdPath).writeAsString(processedMarkdown, flush: true);
    return (mdPath, processedMarkdown);
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
      var mdText =
          (page['markdown'] as Map<String, dynamic>?)?['text'] as String? ?? '';

      if (pageFigs.containsKey(pageIdx)) {
        final pageBlocks =
            (page['prunedResult'] as Map<String, dynamic>?)?['parsing_res_list']
                as List<dynamic>? ??
            [];
        mdText = _replaceInPageMd(
          mdText,
          pageFigs[pageIdx]!,
          pageBlocks,
          mdDir,
        );
      }
      mdPages.add(mdText);
    }

    return mdPages.join('\n\n');
  }

  /// 在单页 raw markdown 中替换 figure 区域为本地图片引用。
  ///
  /// 用**行集合**（而非连续 (start, end) 区间）精确表达每个 figure 占用的行——
  /// 天生支持"双栏排版两个 figure 行段交错"的场景（见 `_planFigureLines` 注释）。
  /// 替换时：figure 的 anchor 行（figure_title 所在行）插入 `![fig:...](path)`，
  /// 其余 owned 行从输出里抹掉。锚点在原始行号位置，不同 figure 的图片自然保持阅读顺序。
  static String _replaceInPageMd(
    String mdText,
    List<FigureManifestEntry> pageFigures,
    List<dynamic> rawBlocks,
    String mdDir,
  ) {
    final lines = mdText.split('\n');

    final blockMap = <String, Map<String, dynamic>>{};
    for (final b in rawBlocks) {
      final block = b as Map<String, dynamic>;
      final id = block['block_id']?.toString() ?? '';
      if (id.isNotEmpty) blockMap[id] = block;
    }

    // Phase 1：按 figure 顺序收集每个 plan 的行集合。`claimed` 累积——
    // 后到的 figure 不会把先到 figure 已占的行（或空行）抢走。
    final claimed = <int>{};
    final plans = <_FigurePlan>[];
    for (final fig in pageFigures) {
      final plan = _planFigureLines(lines, blockMap, fig, claimed);
      if (plan == null) {
        debugPrint(
          '[DocExtract] 未定位到 '
          '"${fig.captionText.substring(0, min(30, fig.captionText.length))}…"',
        );
        continue;
      }
      claimed.addAll(plan.ownedLines);
      plans.add(plan);
    }

    if (plans.isEmpty) return mdText;

    // Phase 2：锚点与占用映射
    final anchorTag = <int, String>{};
    final ownedByAny = <int>{};
    for (final p in plans) {
      anchorTag[p.anchorLine] = p.imgTag;
      ownedByAny.addAll(p.ownedLines);
    }

    // Phase 3：扫 lines——锚点行输出 img_tag，其它 owned 行跳过，其余原样保留
    final out = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final tag = anchorTag[i];
      if (tag != null) {
        out.add(tag);
      } else if (!ownedByAny.contains(i)) {
        out.add(lines[i]);
      }
      // owned but not anchor：deliberately skip (delete)
    }
    return out.join('\n');
  }

  /// 为单个 figure 规划其占用的行集合 + 锚点。
  ///
  /// 返回 `null` 表示所有 block 都没匹配到——通常说明 API 的 block_ids 与
  /// raw markdown 行结构对不上（版本/模型差异），caller 应降级。
  ///
  /// 设计要点：**不做 min/max 连续区间扩张**。旧实现假设"一个 figure 的 blocks
  /// 在 md 里行号连续"，在双栏期刊"同页两个 figure 行号交错"时会把一个区间
  /// 误套到另一个上（如 FIGURE 2 block 行段 `[5..50]` 被 TABLE 1 的 `[2..53]`
  /// 包围），最终 appliedCeiling 保护把外层整体砍掉。集合方式没这个问题。
  static _FigurePlan? _planFigureLines(
    List<String> lines,
    Map<String, Map<String, dynamic>> blockMap,
    FigureManifestEntry fig,
    Set<int> claimed,
  ) {
    final owned = <int>{};
    int? anchor;
    // 本 figure 查找过程中累积的"禁用"行号——既含其他 figure 的占用，
    // 也含本 figure 已匹配的行（避免不同 block 命中同一行）。
    final skip = Set<int>.from(claimed);

    for (final bid in fig.blockIds) {
      final block = blockMap[bid];
      if (block == null) continue;

      final label = block['block_label'] as String? ?? '';
      final content = (block['block_content'] as String? ?? '').trim();

      int? idx;
      if (label == 'image' || label == 'chart') {
        final bbox = block['block_bbox'] as List<dynamic>?;
        if (bbox != null && bbox.length >= 4) {
          idx = _findLine(
            lines,
            '_${bbox[0]}_${bbox[1]}_${bbox[2]}_${bbox[3]}',
            skip,
          );
        }
      } else if (label == 'table') {
        // 表格 HTML：block_content 常是 `<table><tr>...` 但 md 里带属性
        // `<table border=1 ...>`，前缀匹配不上。改用通用 `<table` 起始标签定位。
        idx = _findLine(lines, '<table', skip);
      } else if (content.isNotEmpty) {
        // figure_title / vision_footnote / 内容像 caption 的 text 等,
        // 按内容前缀搜索。
        final probeLen = label == 'vision_footnote' ? 32 : 120;
        idx = _findContentLine(lines, content, probeLen, skip);
      }

      if (idx == null) continue;
      owned.add(idx);
      skip.add(idx);

      // 首个 figure_title 作 anchor——img_tag 落在 caption 原位置，
      // 不同 figure 的图片在最终 md 里保持阅读顺序。
      if (anchor == null && label == 'figure_title') {
        anchor = idx;
      }

      // `<table>...</table>` 是跨多行 HTML，把整个区间吞入 owned。
      if (label == 'table') {
        final tableEnd = _scanTableEnd(lines, idx);
        for (var i = idx + 1; i < tableEnd; i++) {
          if (!claimed.contains(i)) {
            owned.add(i);
            skip.add(i);
          }
        }
      }
    }

    // markdown-only caption 兜底:manifest 带了 caption text 但 parsing_res_list
    // 没对应 block 时,直接按 captionText 在 markdown 里搜行,占住并设为 anchor.
    if (anchor == null && fig.captionText.isNotEmpty) {
      final idx = _findContentLine(lines, fig.captionText, 120, skip);
      if (idx != null) {
        owned.add(idx);
        skip.add(idx);
        anchor = idx;
      }
    }

    if (owned.isEmpty) return null;
    _claimCaptionLines(lines, fig.captionText, owned, skip, claimed);
    anchor ??= owned.reduce(min);
    if (anchor != owned.reduce(min)) {
      anchor = owned.reduce(min);
    }

    // 吸收紧邻空行——避免替换后留下连续空行堆。
    // blockedByOthers=claimed，不越过其他 figure 的行；不触碰自身 owned 行。
    _absorbBlankNeighbors(lines, owned, claimed);

    final uri = Uri.file(fig.imagePath);
    final caption = _normalizeInlineText(fig.captionText);
    return _FigurePlan(
      ownedLines: owned,
      anchorLine: anchor,
      imgTag: '\n![fig:$caption]($uri)\n',
    );
  }

  /// 在行列表中找到包含 [text] 的第一行（跳过已使用的行）
  static int? _findLine(List<String> lines, String text, Set<int> usedLines) {
    for (var i = 0; i < lines.length; i++) {
      if (!usedLines.contains(i) && lines[i].contains(text)) return i;
    }
    return null;
  }

  static int? _findContentLine(
    List<String> lines,
    String content,
    int maxProbeLen,
    Set<int> usedLines,
  ) {
    final normalized = _normalizeInlineText(content);
    if (normalized.isEmpty) return null;

    final lengths = <int>{
      min(maxProbeLen, normalized.length),
      min(80, normalized.length),
      min(48, normalized.length),
      min(24, normalized.length),
    }.where((len) => len > 0).toList()..sort((a, b) => b.compareTo(a));

    for (final len in lengths) {
      final probe = normalized.substring(0, len);
      for (var i = 0; i < lines.length; i++) {
        if (usedLines.contains(i)) continue;
        if (_lineSearchText(lines[i]).contains(probe)) return i;
      }
    }
    return null;
  }

  static final RegExp _inlineWhitespaceRe = RegExp(r'\s+');
  static final RegExp _centeredDivLineRe = RegExp(
    r'^<div\s+style="text-align:\s*center;\s*">\s*(.*?)\s*</div>$',
    caseSensitive: false,
  );
  static final RegExp _htmlTagRe = RegExp(r'<[^>]+>');
  static final RegExp _captionLeadRe = RegExp(
    r'^((?:figure|fig\.?|table|tab\.?)\s*\d+[a-z]?\s*[.)]?)',
    caseSensitive: false,
  );
  static final RegExp _captionNoteLeadRe = RegExp(
    r'^(?:\([a-z](?:\s*(?:,|and|&)\s*[a-z])*\)|[a-z](?:\s*(?:,|and|&)\s*[a-z])*[).:;-])\s+\S',
    caseSensitive: false,
  );

  static String _normalizeInlineText(String text) {
    return text.trim().replaceAll(_inlineWhitespaceRe, ' ');
  }

  static String _lineSearchText(String line) {
    var text = line.trim();
    final divMatch = _centeredDivLineRe.firstMatch(text);
    if (divMatch != null) {
      text = divMatch.group(1)!;
    }
    text = text.replaceAll(_htmlTagRe, ' ');
    text = text.replaceAll(RegExp(r'^[*_]+|[*_]+$'), '');
    return _normalizeInlineText(text);
  }

  static void _claimCaptionLines(
    List<String> lines,
    String captionText,
    Set<int> owned,
    Set<int> skip,
    Set<int> claimed,
  ) {
    final captionLead = _captionLead(captionText);
    if (captionLead == null) return;

    final anchors = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (claimed.contains(i) && !owned.contains(i)) continue;
      final text = _lineSearchText(lines[i]);
      if (!text.toLowerCase().startsWith(captionLead.toLowerCase())) continue;
      owned.add(i);
      skip.add(i);
      anchors.add(i);
    }

    for (final anchor in anchors) {
      _claimFollowingCaptionNotes(lines, anchor, owned, skip, claimed);
    }
  }

  static String? _captionLead(String captionText) {
    final text = _normalizeInlineText(captionText);
    final match = _captionLeadRe.firstMatch(text);
    return match?.group(1);
  }

  static void _claimFollowingCaptionNotes(
    List<String> lines,
    int anchor,
    Set<int> owned,
    Set<int> skip,
    Set<int> claimed,
  ) {
    for (var i = anchor + 1; i < lines.length; i++) {
      if (claimed.contains(i) && !owned.contains(i)) break;
      final text = _lineSearchText(lines[i]);
      if (text.isEmpty) {
        owned.add(i);
        skip.add(i);
        continue;
      }
      if (!_captionNoteLeadRe.hasMatch(text)) break;
      owned.add(i);
      skip.add(i);
    }
  }

  /// 以 [openLine] 为起点（含 `<table`）扫描到闭合 `</table>` 行，返回 end（exclusive）。
  /// 同行闭合或到达 EOF 均正确处理。
  static int _scanTableEnd(List<String> lines, int openLine) {
    if (lines[openLine].contains('</table>')) return openLine + 1;
    var j = openLine + 1;
    while (j < lines.length && !lines[j].contains('</table>')) {
      j++;
    }
    return j < lines.length ? j + 1 : j;
  }

  /// 把 [owned] 行集合两端的紧邻空行也纳入（仅当空行不在 [blockedByOthers] 内）。
  /// 空行被纳入后会在替换阶段被丢弃，避免最终 md 里堆积连续空行。
  static void _absorbBlankNeighbors(
    List<String> lines,
    Set<int> owned,
    Set<int> blockedByOthers,
  ) {
    // 在集合迭代前快照，避免一边扩展一边遍历
    final snapshot = owned.toList();
    for (final i in snapshot) {
      var j = i - 1;
      while (j >= 0 &&
          lines[j].trim().isEmpty &&
          !owned.contains(j) &&
          !blockedByOthers.contains(j)) {
        owned.add(j);
        j--;
      }
      j = i + 1;
      while (j < lines.length &&
          lines[j].trim().isEmpty &&
          !owned.contains(j) &&
          !blockedByOthers.contains(j)) {
        owned.add(j);
        j++;
      }
    }
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
    try {
      final pages = jsonDecode(jsonContent) as List<dynamic>;
      final titles = <String>{};
      for (final page in pages) {
        final blocks =
            (page as Map<String, dynamic>)['prunedResult']?['parsing_res_list']
                as List<dynamic>? ??
            [];
        for (final block in blocks) {
          final b = block as Map<String, dynamic>;
          if (b['block_label'] == 'paragraph_title') {
            final c = (b['block_content'] as String?)?.trim() ?? '';
            if (c.isNotEmpty) titles.add(c);
          }
        }
      }
      return titles;
    } catch (_) {
      return {};
    }
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

  /// 移除 API 生成的 HTML 图片标签（figure 已替换为 `![]()`，其余无本地文件）
  static String _stripApiImageTags(String markdown) {
    var result = markdown;
    // <div><img src="relative_path"></div>
    result = result.replaceAllMapped(
      RegExp(r'<div[^>]*>\s*<img\s+[^>]*?src="([^"]+)"[^>]*/?\s*>\s*</div>'),
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

  static final _figureSubLabelRe = RegExp(
    r'^\(?[a-zA-Z](?:\s*,\s*[a-zA-Z])*\)?$',
  );

  /// 将居中文本 div 转为斜体（含 img / figure 子标签的 div 直接移除）
  static String _convertCenteredDivs(String markdown) {
    return markdown.replaceAllMapped(
      RegExp(r'<div\s+style="text-align:\s*center;\s*">\s*(.+?)\s*</div>'),
      (match) {
        final content = match.group(1)!;
        if (content.contains('<img')) return '';
        if (_figureSubLabelRe.hasMatch(content.trim())) return '';
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

/// 单个 figure 的替换计划——在 `_replaceInPageMd` 流水线中传递。
///
/// 行集合表达（而非连续区间）让"同页两 figure 行号交错"的双栏排版也能正确替换：
/// 两个 figure 的 [ownedLines] 互不相交，各自的 [anchorLine] 独立定位插入点。
class _FigurePlan {
  /// 该 figure 占用的原始行号集合（可以不连续）。替换阶段除了 [anchorLine]
  /// 外的行全部从输出里抹掉。
  final Set<int> ownedLines;

  /// img_tag 插入的原始行号位置——优先选 figure_title 所在行，使 caption
  /// 保持在阅读序中的自然位置。无 figure_title 时退化为 [ownedLines] 的最小值。
  final int anchorLine;

  /// 生成的 markdown 图片标记，形如 `\n![fig:CAPTION](file:///.../FIGURE_N_.png)\n`。
  final String imgTag;

  const _FigurePlan({
    required this.ownedLines,
    required this.anchorLine,
    required this.imgTag,
  });
}
