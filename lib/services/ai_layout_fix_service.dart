import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../providers/api_provider.dart';
import '../utils/doc_paths.dart';
import 'agent_model_capability.dart';
import 'agent_thinking_payload.dart';
import 'pdf_process_lock.dart';

class NumberedParagraph {
  final int id;
  final String content;
  const NumberedParagraph(this.id, this.content);
}

/// 单个批次：一组目标 PDF 页 + 落在这些页上的图片清单条目与公式段落。
/// 按批调用可控制单请求体积（Gemini inline 上限 20MB）、避免输出超长截断，
/// 并支持批间进度展示与失败重试。
class AiLayoutFixChunk {
  final List<int> pages;
  final List<NumberedParagraph> paragraphs;
  final List<Map<String, dynamic>> figures;

  AiLayoutFixChunk({
    required this.pages,
    List<NumberedParagraph>? paragraphs,
    List<Map<String, dynamic>>? figures,
  })  : paragraphs = paragraphs ?? [],
        figures = figures ?? [];
}

class AiLayoutFixAnalysis {
  final String documentId;
  final String pdfPath;
  final String mdPath;
  final String mdContent;
  final List<String> allParagraphs;
  final List<int> targetPages;
  final List<NumberedParagraph> formulaParagraphs;
  final Map<String, dynamic> currentManifest;
  final List<AiLayoutFixChunk> chunks;
  final int estimatedTokens;

  const AiLayoutFixAnalysis({
    required this.documentId,
    required this.pdfPath,
    required this.mdPath,
    required this.mdContent,
    required this.allParagraphs,
    required this.targetPages,
    required this.formulaParagraphs,
    required this.currentManifest,
    required this.chunks,
    required this.estimatedTokens,
  });

  bool get isEmpty =>
      formulaParagraphs.isEmpty &&
      ((currentManifest['figures'] as List?)?.isEmpty ?? true);
}

/// execute() 的产物：校验通过的段落修复 + 图片清单（crop_bbox 已转回 144 DPI）。
class AiLayoutFixResult {
  /// 段落 id → 修复后内容（仅含确有改动且通过校验的段落）。
  final Map<int, String> paragraphs;

  /// LLM 返回并通过校验的图片条目：{img, figure_title, page_idx, crop_bbox}。
  final List<Map<String, dynamic>> figures;

  /// LLM 实际审阅过的页（渲染成功并送入模型）。manifest 合并时只对这些页
  /// 做"整页替换"，渲染失败页上的旧条目原样保留。
  final Set<int> coveredPages;

  const AiLayoutFixResult({
    required this.paragraphs,
    required this.figures,
    required this.coveredPages,
  });
}

class AiLayoutFixSummary {
  final int paragraphsFixed;
  final int figuresAdjusted;
  const AiLayoutFixSummary({
    required this.paragraphsFixed,
    required this.figuresAdjusted,
  });
}

class _PageImage {
  final int pageIdx;
  final String base64Png;
  final double widthPx;
  final double heightPx;
  const _PageImage({
    required this.pageIdx,
    required this.base64Png,
    required this.widthPx,
    required this.heightPx,
  });
}

/// AI 排版修复服务：多模态 LLM 修正公式排版 + 图片重提。
///
/// 与模型交换 bbox 时统一用 **0–1000 归一化坐标**（Gemini 用其原生
/// [ymin,xmin,ymax,xmax] 顺序，其余服务商用 [left,top,right,bottom]）：
/// 服务商可能在服务端缩放图片（Anthropic 长边 >1568px 即缩、Qwen smart_resize
/// 等），绝对像素坐标会随之漂移，归一化坐标与分辨率无关。
class AiLayoutFixService {
  AiLayoutFixService._();

  /// manifest 中 crop_bbox 的坐标空间（144 DPI = PDF 72pt × 2）。
  static const _apiZoom = 2.0;
  static const _renderZoom = 3.0;
  static const _llmZoom = 2.0;
  static const _maxPagesPerChunk = 5;

  static final _formulaRe = RegExp(r'\$');
  static final _unescapedDollarRe = RegExp(r'(?<!\\)\$');

  // ── Step 1: 分析 ─────────────────────────────────────────

  static Future<AiLayoutFixAnalysis> analyze({
    required String documentId,
  }) async {
    final pdfPath = DocPaths.pdf(documentId);
    final mdPath = DocPaths.md(documentId);
    final jsonPath = DocPaths.json(documentId);
    final manifestPath = DocPaths.figuresManifest(documentId);

    final mdFile = File(mdPath);
    if (!mdFile.existsSync()) throw Exception('Markdown 文件不存在');
    final mdContent = await mdFile.readAsString();

    final allParagraphs = mdContent.split(RegExp(r'\n\s*\n'));

    final formulaParagraphs = <NumberedParagraph>[];
    for (var i = 0; i < allParagraphs.length; i++) {
      final para = allParagraphs[i].trim();
      if (para.isEmpty) continue;
      if (para.startsWith('#')) continue;
      if (para.startsWith('![')) continue;
      if (_formulaRe.hasMatch(para)) {
        formulaParagraphs.add(NumberedParagraph(i, para));
      }
    }

    final targetPages = <int>{};
    final pageMdNorm = <int, String>{};
    final extractFile = File(jsonPath);
    if (extractFile.existsSync()) {
      final extractData =
          jsonDecode(await extractFile.readAsString()) as Map<String, dynamic>;
      final pages =
          extractData['layoutParsingResults'] as List<dynamic>? ?? [];

      for (final page in pages) {
        final pageMap = page as Map<String, dynamic>;
        final pageIdx = pageMap['page_index'] as int;
        final blocks = (pageMap['prunedResult']
                    as Map<String, dynamic>?)?['parsing_res_list']
                as List<dynamic>? ??
            [];

        for (final block in blocks) {
          final label =
              (block as Map<String, dynamic>)['block_label'] as String?;
          if (label == 'image' || label == 'chart') {
            targetPages.add(pageIdx);
            break;
          }
        }

        final pageMd = (pageMap['markdown']
                as Map<String, dynamic>?)?['text'] as String? ??
            '';
        pageMdNorm[pageIdx] = _normalizeWs(pageMd);
        if (_formulaRe.hasMatch(pageMd)) {
          targetPages.add(pageIdx);
        }
      }
    }

    var manifest = <String, dynamic>{'figures': <dynamic>[], 'diagnostics': <String, dynamic>{}};
    final manifestFile = File(manifestPath);
    if (manifestFile.existsSync()) {
      manifest =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    }
    final manifestFigures = (manifest['figures'] as List<dynamic>? ?? [])
        .map((f) => Map<String, dynamic>.from(f as Map))
        .toList();

    // 清单图片所在页一并纳入目标页——图片对照必须有该页截图
    for (final f in manifestFigures) {
      final page = f['page_idx'];
      if (page is int) targetPages.add(page);
    }

    // 公式段落 → 来源页映射（按归一化文本片段在页 markdown 中查找）。
    // 用于分批；找不到来源页的段落归入第一批。
    final paragraphPages = <int, int>{};
    for (final fp in formulaParagraphs) {
      final snippet = _snippetOf(fp.content);
      if (snippet.length < 16) continue;
      for (final entry in pageMdNorm.entries) {
        if (entry.value.contains(snippet)) {
          paragraphPages[fp.id] = entry.key;
          targetPages.add(entry.key);
          break;
        }
      }
    }

    // ── 组装批次 ──
    final sortedPages = targetPages.toList()..sort();
    final chunks = <AiLayoutFixChunk>[];
    for (var i = 0; i < sortedPages.length; i += _maxPagesPerChunk) {
      chunks.add(AiLayoutFixChunk(
        pages: sortedPages.sublist(
          i,
          math.min(i + _maxPagesPerChunk, sortedPages.length),
        ),
      ));
    }
    if (chunks.isEmpty && formulaParagraphs.isNotEmpty) {
      // 无 extract.json / 无目标页：退化为单个纯文本批次
      chunks.add(AiLayoutFixChunk(pages: const []));
    }
    final chunkOfPage = <int, AiLayoutFixChunk>{
      for (final c in chunks)
        for (final page in c.pages) page: c,
    };
    for (final f in manifestFigures) {
      final page = f['page_idx'];
      final chunk = page is int ? chunkOfPage[page] : null;
      chunk?.figures.add({
        'img': f['img'],
        'figure_title': f['figure_title'],
        'page_idx': f['page_idx'],
        'crop_bbox': f['crop_bbox'],
      });
    }
    if (chunks.isNotEmpty) {
      for (final fp in formulaParagraphs) {
        final page = paragraphPages[fp.id];
        final chunk = (page != null ? chunkOfPage[page] : null) ?? chunks.first;
        chunk.paragraphs.add(fp);
      }
    }

    // 粗略估算：高 detail 下主流服务商单页约 1500~2600 token，取 2500；
    // 输出只回传有改动的段落（按约一半改动率估）+ 图片清单
    final imageTokens = sortedPages.length * 2500;
    final figuresJson = jsonEncode(manifest['figures']);
    final paragraphsText =
        formulaParagraphs.map((fp) => '[${fp.id}] ${fp.content}').join('\n\n');
    final textTokens = (figuresJson.length + paragraphsText.length + 800) ~/ 4;
    final outputTokens =
        figuresJson.length ~/ 3 + paragraphsText.length ~/ 8;

    return AiLayoutFixAnalysis(
      documentId: documentId,
      pdfPath: pdfPath,
      mdPath: mdPath,
      mdContent: mdContent,
      allParagraphs: allParagraphs,
      targetPages: sortedPages,
      formulaParagraphs: formulaParagraphs,
      currentManifest: manifest,
      chunks: chunks,
      estimatedTokens: imageTokens + textTokens + outputTokens,
    );
  }

  static String _normalizeWs(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _snippetOf(String paragraph) {
    final n = _normalizeWs(paragraph);
    return n.length > 60 ? n.substring(0, 60) : n;
  }

  // ── Step 2: 分批调用 LLM ─────────────────────────────────

  static Future<AiLayoutFixResult> execute({
    required AiLayoutFixAnalysis analysis,
    required AgentApiState agentState,
    required CancelToken cancelToken,
    required void Function(String stage, int current, int total) onProgress,
  }) async {
    final modelId = agentState.defaultModelId;
    if (modelId == null) throw Exception('未设置专家模型');
    final modelParams = agentState.paramsFor(modelId);

    // Gemini 原生 bbox 训练约定是 [ymin,xmin,ymax,xmax]，沿用可提高定位精度
    final yFirst = agentState.provider == AgentApiProvider.gemini;
    final systemPrompt = _systemPrompt(yFirst: yFirst);

    final outParagraphs = <int, String>{};
    final outFigures = <Map<String, dynamic>>[];
    final coveredPages = <int>{};

    final total = analysis.chunks.length;
    for (var i = 0; i < total; i++) {
      if (cancelToken.isCancelled) break;
      final chunk = analysis.chunks[i];

      onProgress('rendering', i + 1, total);
      final pageImages =
          await _renderPages(analysis.pdfPath, chunk.pages, cancelToken);
      if (cancelToken.isCancelled) break;
      final imagesByPage = <int, _PageImage>{
        for (final pi in pageImages) pi.pageIdx: pi,
      };

      // 渲染失败的页退出本批：图片条目保留原状、段落不做无对照的盲改
      final figures = chunk.figures
          .where((f) => imagesByPage.containsKey(f['page_idx']))
          .toList();
      final paragraphs = chunk.paragraphs.where((fp) {
        if (chunk.pages.isEmpty) return true; // 纯文本批次
        return imagesByPage.isNotEmpty;
      }).toList();
      if (figures.isEmpty && paragraphs.isEmpty) continue;

      onProgress('calling', i + 1, total);
      final userPrompt = _buildUserPrompt(
        figures: figures,
        paragraphs: paragraphs,
        imagesByPage: imagesByPage,
        yFirst: yFirst,
      );
      final response = await _callMultimodalApi(
        provider: agentState.provider,
        baseUrl: agentState.effectiveBaseUrl,
        apiKey: agentState.apiKey,
        modelId: modelId,
        modelParams: modelParams,
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        images: pageImages,
        cancelToken: cancelToken,
      );

      _mergeChunkResult(
        parsed: _parseJsonResponse(response),
        sentParagraphs: paragraphs,
        chunkFigures: figures,
        imagesByPage: imagesByPage,
        yFirst: yFirst,
        outParagraphs: outParagraphs,
        outFigures: outFigures,
      );
      coveredPages.addAll(imagesByPage.keys);
    }

    return AiLayoutFixResult(
      paragraphs: outParagraphs,
      figures: outFigures,
      coveredPages: coveredPages,
    );
  }

  // ── Step 3: 应用结果 ────────────────────────────────────

  static Future<AiLayoutFixSummary> applyResults({
    required AiLayoutFixAnalysis analysis,
    required AiLayoutFixResult result,
    required CancelToken cancelToken,
    required void Function(String stage, int current, int total) onProgress,
  }) async {
    onProgress('applying', 1, 1);

    final updatedParagraphs = List<String>.from(analysis.allParagraphs);
    var paragraphsFixed = 0;
    result.paragraphs.forEach((id, content) {
      if (id >= 0 && id < updatedParagraphs.length) {
        updatedParagraphs[id] = content;
        paragraphsFixed++;
      }
    });
    await File(analysis.mdPath).writeAsString(updatedParagraphs.join('\n\n'));

    onProgress('cropping', 1, 1);

    final existingFigures =
        (analysis.currentManifest['figures'] as List<dynamic>? ?? [])
            .map((f) => Map<String, dynamic>.from(f as Map))
            .toList();

    // 只对模型实际审阅过的页做"整页替换"；其余页旧条目原样保留
    final kept = <Map<String, dynamic>>[];
    final coveredByImg = <String, Map<String, dynamic>>{};
    for (final f in existingFigures) {
      final page = f['page_idx'];
      if (page is int && result.coveredPages.contains(page)) {
        coveredByImg[f['img'] as String] = f;
      } else {
        kept.add(f);
      }
    }

    final merged = <Map<String, dynamic>>[];
    final figuresToRecrop = <Map<String, dynamic>>[];
    final seenImgs = <String>{};
    for (final lf in result.figures) {
      final img = lf['img'] as String;
      if (!seenImgs.add(img)) continue;
      final existing = coveredByImg.remove(img);

      if (existing != null) {
        final m = Map<String, dynamic>.from(existing);
        if (lf['figure_title'] != null) m['figure_title'] = lf['figure_title'];
        m['page_idx'] = lf['page_idx'];

        final newBbox = lf['crop_bbox'] as List<dynamic>;
        if (_bboxChanged(existing['crop_bbox'] as List<dynamic>?, newBbox)) {
          m['crop_bbox'] = newBbox;
          m['region_method'] = 'ai_layout_fix';
          figuresToRecrop.add(m);
        }
        merged.add(m);
      } else {
        final newEntry = <String, dynamic>{
          'img': img,
          'figure_title': lf['figure_title'],
          'page_idx': lf['page_idx'],
          'crop_bbox': lf['crop_bbox'],
          'block_ids': <String>[],
          'region_method': 'ai_layout_fix',
        };
        merged.add(newEntry);
        figuresToRecrop.add(newEntry);
      }
    }
    // 覆盖页上模型未回传的条目 = 模型判定不是真图片 → 删除
    final removedCount = coveredByImg.length;

    if (figuresToRecrop.isNotEmpty && !cancelToken.isCancelled) {
      await _recropFigures(analysis.pdfPath, analysis.documentId, figuresToRecrop);
    }

    // 稳定按页排序（Dart sort 不稳定，用原序号兜底）
    final indexed = [...kept, ...merged].asMap().entries.toList()
      ..sort((a, b) {
        final pa = a.value['page_idx'] is int
            ? a.value['page_idx'] as int
            : 1 << 30;
        final pb = b.value['page_idx'] is int
            ? b.value['page_idx'] as int
            : 1 << 30;
        final c = pa.compareTo(pb);
        return c != 0 ? c : a.key.compareTo(b.key);
      });

    final manifestPath = DocPaths.figuresManifest(analysis.documentId);
    await File(manifestPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'figures': indexed.map((e) => e.value).toList(),
        'diagnostics': analysis.currentManifest['diagnostics'] ?? {},
      }),
    );

    return AiLayoutFixSummary(
      paragraphsFixed: paragraphsFixed,
      figuresAdjusted: figuresToRecrop.length + removedCount,
    );
  }

  // ── Prompt 构造 ─────────────────────────────────────────

  static String _systemPrompt({required bool yFirst}) {
    final order =
        yFirst ? '[ymin, xmin, ymax, xmax]' : '[left, top, right, bottom]';
    return 'You are an academic document layout expert. You receive rendered '
        'PDF page images (each labeled with its page index and pixel size), '
        'a figures manifest, and numbered formula paragraphs extracted from '
        'a paper.\n\n'
        'Tasks:\n'
        '1. FIGURES: Compare the manifest against the page images. Correct '
        'bbox, figure_title and page_idx; add figures the extraction missed; '
        'omit entries that are not real figures (omission means deletion). '
        'Keep the exact original "img" value for existing figures; for new '
        'figures use "img": "ai_fix_p<page>_<n>.png".\n'
        '2. FORMULAS: Compare each numbered paragraph against the page '
        r'images. Fix LaTeX OCR errors, formula delimiters ($ inline, $$ '
        'display) and broken line structure inside the paragraph. Never '
        'rewrite prose: keep all non-formula wording exactly as given.\n\n'
        'All bounding boxes are $order with integer coordinates normalized '
        "to 0-1000 relative to that page image's width and height.\n\n"
        'Respond with JSON only, exactly this shape:\n'
        '{"figures":[{"img":"...","figure_title":"...","page_idx":0,'
        '"bbox":[0,0,0,0]}],"paragraphs":[{"id":0,"content":"..."}]}\n\n'
        'Rules:\n'
        '- Return ONLY paragraphs you actually changed, with their original '
        'ids; return an empty list if none need fixing.\n'
        '- Return the complete corrected figure list for the pages shown.\n'
        '- No text outside the JSON.';
  }

  static String _buildUserPrompt({
    required List<Map<String, dynamic>> figures,
    required List<NumberedParagraph> paragraphs,
    required Map<int, _PageImage> imagesByPage,
    required bool yFirst,
  }) {
    final promptFigures = figures.map((f) {
      final pi = imagesByPage[f['page_idx'] as int]!;
      return {
        'img': f['img'],
        'figure_title': f['figure_title'],
        'page_idx': f['page_idx'],
        'bbox': _bboxTo1000(f['crop_bbox'] as List<dynamic>, pi, yFirst),
      };
    }).toList();

    final paragraphsText =
        paragraphs.map((fp) => '[${fp.id}] ${fp.content}').join('\n\n');

    return (StringBuffer()
          ..writeln('## Current figures manifest (for the pages shown)')
          ..writeln('```json')
          ..writeln(const JsonEncoder.withIndent('  ').convert(promptFigures))
          ..writeln('```')
          ..writeln()
          ..writeln('## Formula paragraphs')
          ..writeln(paragraphsText.isEmpty ? '(none)' : paragraphsText))
        .toString();
  }

  static String _pageLabel(_PageImage img) =>
      'Page ${img.pageIdx} (${img.widthPx.round()}x${img.heightPx.round()} px):';

  // ── bbox 坐标换算（manifest 144 DPI ↔ 0–1000 归一化） ────

  static List<int> _bboxTo1000(
    List<dynamic> bbox144,
    _PageImage pi,
    bool yFirst,
  ) {
    final w144 = pi.widthPx / _llmZoom * _apiZoom;
    final h144 = pi.heightPx / _llmZoom * _apiZoom;
    int nx(num v) => (v / w144 * 1000).round().clamp(0, 1000);
    int ny(num v) => (v / h144 * 1000).round().clamp(0, 1000);
    final l = nx(bbox144[0] as num);
    final t = ny(bbox144[1] as num);
    final r = nx(bbox144[2] as num);
    final b = ny(bbox144[3] as num);
    return yFirst ? [t, l, b, r] : [l, t, r, b];
  }

  // ── 输出校验与合并 ──────────────────────────────────────

  static void _mergeChunkResult({
    required Map<String, dynamic> parsed,
    required List<NumberedParagraph> sentParagraphs,
    required List<Map<String, dynamic>> chunkFigures,
    required Map<int, _PageImage> imagesByPage,
    required bool yFirst,
    required Map<int, String> outParagraphs,
    required List<Map<String, dynamic>> outFigures,
  }) {
    final sentById = <int, String>{
      for (final fp in sentParagraphs) fp.id: fp.content,
    };
    for (final entry in parsed['paragraphs'] as List<dynamic>? ?? const []) {
      if (entry is! Map) continue;
      final id = entry['id'];
      final content = entry['content'];
      if (id is! int || content is! String) continue;
      final original = sentById[id];
      if (original == null) continue; // 模型编造了未发送的段落 id
      final fixed = content.trim();
      if (fixed.isEmpty || fixed == original.trim()) continue;
      // $ 定界符必须成对，防止半截公式污染整篇渲染
      if (_unescapedDollarRe.allMatches(fixed).length.isOdd) continue;
      outParagraphs[id] = fixed;
    }

    final existingByImg = <String, Map<String, dynamic>>{
      for (final f in chunkFigures) f['img'] as String: f,
    };
    for (final entry in parsed['figures'] as List<dynamic>? ?? const []) {
      if (entry is! Map) continue;
      final validated =
          _validateFigure(Map<String, dynamic>.from(entry), imagesByPage, yFirst);
      if (validated != null) {
        outFigures.add(validated);
      } else {
        // 条目无效但对应已有图片——保留原条目，避免被"整页替换"语义误删
        final img = entry['img'];
        final existing = img is String ? existingByImg[img] : null;
        if (existing != null) {
          outFigures.add(Map<String, dynamic>.from(existing));
        }
      }
    }
  }

  static Map<String, dynamic>? _validateFigure(
    Map<String, dynamic> lf,
    Map<int, _PageImage> imagesByPage,
    bool yFirst,
  ) {
    final img = lf['img'];
    if (img is! String || img.trim().isEmpty) return null;
    final pageIdx = lf['page_idx'];
    if (pageIdx is! int) return null;
    final pi = imagesByPage[pageIdx];
    if (pi == null) return null;

    final bbox = lf['bbox'];
    if (bbox is! List || bbox.length != 4 || bbox.any((v) => v is! num)) {
      return null;
    }
    final n = bbox
        .map((v) => (v as num).toDouble().clamp(0.0, 1000.0).toDouble())
        .toList();
    final l = yFirst ? n[1] : n[0];
    final t = yFirst ? n[0] : n[1];
    final r = yFirst ? n[3] : n[2];
    final b = yFirst ? n[2] : n[3];
    // 过小（不足页面 1%）视为无效框
    if (r - l < 10 || b - t < 10) return null;

    final w144 = pi.widthPx / _llmZoom * _apiZoom;
    final h144 = pi.heightPx / _llmZoom * _apiZoom;
    final title = lf['figure_title'];
    return {
      'img': img.trim(),
      'figure_title': (title is String && title.trim().isNotEmpty)
          ? title.trim()
          : null,
      'page_idx': pageIdx,
      'crop_bbox': [
        l / 1000 * w144,
        t / 1000 * h144,
        r / 1000 * w144,
        b / 1000 * h144,
      ],
    };
  }

  // ── PDF 渲染 ────────────────────────────────────────────

  static Future<List<_PageImage>> _renderPages(
    String pdfPath,
    List<int> pageIndices,
    CancelToken cancelToken,
  ) async {
    if (pageIndices.isEmpty) return const [];
    return PdfProcessLock.instance.run(() async {
      PdfDocument? document;
      try {
        document = await PdfDocument.openFile(pdfPath, passwordProvider: () => '');
        final results = <_PageImage>[];

        for (final pageIdx in pageIndices) {
          if (cancelToken.isCancelled) break;
          if (pageIdx >= document.pages.length) continue;

          final page = document.pages[pageIdx];
          final rendered = await page.render(
            fullWidth: page.width * _llmZoom,
            fullHeight: page.height * _llmZoom,
          );
          if (rendered == null) continue;

          final image = await rendered.createImage();
          final byteData =
              await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();

          if (byteData != null) {
            results.add(_PageImage(
              pageIdx: pageIdx,
              base64Png: base64Encode(byteData.buffer.asUint8List()),
              widthPx: page.width * _llmZoom,
              heightPx: page.height * _llmZoom,
            ));
          }
        }
        return results;
      } finally {
        document?.dispose();
      }
    });
  }

  static Future<void> _recropFigures(
    String pdfPath,
    String documentId,
    List<Map<String, dynamic>> figures,
  ) async {
    await PdfProcessLock.instance.run(() async {
      PdfDocument? document;
      try {
        document = await PdfDocument.openFile(pdfPath, passwordProvider: () => '');
        final outputDir = DocPaths.figuresDir(documentId);

        final byPage = <int, List<Map<String, dynamic>>>{};
        for (final f in figures) {
          byPage.putIfAbsent(f['page_idx'] as int, () => []).add(f);
        }

        for (final entry in byPage.entries) {
          final pageIdx = entry.key;
          if (pageIdx >= document.pages.length) continue;

          final page = document.pages[pageIdx];
          final rendered = await page.render(
            fullWidth: page.width * _renderZoom,
            fullHeight: page.height * _renderZoom,
          );
          if (rendered == null) continue;

          final fullImage = await rendered.createImage();
          try {
            for (final f in entry.value) {
              final bbox = (f['crop_bbox'] as List<dynamic>)
                  .map((v) => (v as num).toDouble())
                  .toList();
              final renderBbox =
                  bbox.map((v) => v * _renderZoom / _apiZoom).toList();

              final pngBytes = await _cropRegion(fullImage, renderBbox);
              if (pngBytes == null) continue;

              final img = f['img'] as String;
              final outPath =
                  p.isAbsolute(img) ? img : p.join(outputDir, p.basename(img));
              await File(outPath).writeAsBytes(pngBytes);

              final w = (renderBbox[2] - renderBbox[0])
                  .clamp(0, fullImage.width.toDouble())
                  .toInt();
              final h = (renderBbox[3] - renderBbox[1])
                  .clamp(0, fullImage.height.toDouble())
                  .toInt();
              if (w > 0) f['width_px'] = w;
              if (h > 0) f['height_px'] = h;
            }
          } finally {
            fullImage.dispose();
          }
        }
      } finally {
        document?.dispose();
      }
    });
  }

  static Future<Uint8List?> _cropRegion(
    ui.Image fullImage,
    List<double> bbox,
  ) async {
    final cropLeft = bbox[0].clamp(0, fullImage.width.toDouble()).toInt();
    final cropTop = bbox[1].clamp(0, fullImage.height.toDouble()).toInt();
    final cropRight = bbox[2].clamp(0, fullImage.width.toDouble()).toInt();
    final cropBottom = bbox[3].clamp(0, fullImage.height.toDouble()).toInt();

    final cropWidth = cropRight - cropLeft;
    final cropHeight = cropBottom - cropTop;
    if (cropWidth <= 0 || cropHeight <= 0) return null;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImageRect(
      fullImage,
      ui.Rect.fromLTWH(
        cropLeft.toDouble(),
        cropTop.toDouble(),
        cropWidth.toDouble(),
        cropHeight.toDouble(),
      ),
      ui.Rect.fromLTWH(0, 0, cropWidth.toDouble(), cropHeight.toDouble()),
      ui.Paint(),
    );
    final picture = recorder.endRecording();
    final cropped = await picture.toImage(cropWidth, cropHeight);
    final byteData = await cropped.toByteData(format: ui.ImageByteFormat.png);
    cropped.dispose();
    return byteData?.buffer.asUint8List();
  }

  // ── 多模态 API 调用 ─────────────────────────────────────

  /// 结构化输出降级阶梯 + 瞬时错误重试。
  ///
  /// 各 provider 先尝试原生 JSON Schema 约束（OpenAI strict json_schema /
  /// Anthropic output_config / Gemini responseJsonSchema / 兼容端
  /// response_format json_schema），被服务商以 400/422 拒绝时逐级退到
  /// json_object 乃至纯 prompt 约束——兼容端各家支持差异极大
  /// （json_schema 仅 Doubao/Grok 官方支持，GLM 视觉模型连 json_object
  /// 都未文档化），由阶梯自动适配。
  static Future<String> _callMultimodalApi({
    required AgentApiProvider provider,
    required String baseUrl,
    required String apiKey,
    required String modelId,
    required AgentModelParams modelParams,
    required String systemPrompt,
    required String userPrompt,
    required List<_PageImage> images,
    required CancelToken cancelToken,
  }) async {
    final url = provider.chatUrl(baseUrl);

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(minutes: 2),
      receiveTimeout: const Duration(minutes: 5),
    ));

    final schema =
        _outputSchema(yFirst: provider == AgentApiProvider.gemini);
    final modes = switch (provider) {
      AgentApiProvider.openai => const ['schema', 'json'],
      AgentApiProvider.anthropic => const ['schema', 'none'],
      AgentApiProvider.gemini => const ['schema', 'json'],
      AgentApiProvider.openAICompatible => const ['schema', 'json', 'none'],
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
            schema: schema,
            mode: modes[m],
            cancelToken: cancelToken,
          ),
        );
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) rethrow;
        final code = e.response?.statusCode;
        final canFallback =
            m < modes.length - 1 && (code == 400 || code == 422);
        if (!canFallback) throw Exception(_readableMessage(e));
      }
    }
    throw StateError('unreachable');
  }

  /// 429/5xx/超时/断连重试一次（移动网络抖动常见），其余错误直接抛出。
  static Future<T> _withTransientRetry<T>(
    CancelToken cancelToken,
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
      if (cancelToken.isCancelled) rethrow;
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
    required List<_PageImage> images,
    required Map<String, dynamic> schema,
    required String mode,
    required CancelToken cancelToken,
  }) async {
    final Response<Map<String, dynamic>> resp;

    switch (provider) {
      case AgentApiProvider.openai:
        final content = <Map<String, dynamic>>[
          for (final img in images) ...[
            {'type': 'input_text', 'text': _pageLabel(img)},
            {
              'type': 'input_image',
              'image_url': 'data:image/png;base64,${img.base64Png}',
              'detail': 'high',
            },
          ],
          {'type': 'input_text', 'text': userPrompt},
        ];
        final text = <String, dynamic>{
          if (mode == 'schema')
            'format': {
              'type': 'json_schema',
              'name': 'layout_fix',
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
            'input': [
              {'role': 'user', 'content': content},
            ],
            if (text.isNotEmpty) 'text': text,
            ...AgentThinkingPayload.forOpenAI(
                modelId, modelParams.thinkingLevel),
          },
          options: Options(headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          }),
          cancelToken: cancelToken,
        );
        return _extractOpenAIText(resp.data!);

      case AgentApiProvider.anthropic:
        final content = <Map<String, dynamic>>[
          for (final img in images) ...[
            {'type': 'text', 'text': _pageLabel(img)},
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
          AgentThinkingPayload.forAnthropic(modelId, modelParams.thinkingLevel),
        );
        // adaptive 模型的 effort 也在 output_config 里，与 format 合并发送
        final outputConfig = <String, dynamic>{
          if (mode == 'schema')
            'format': {'type': 'json_schema', 'schema': schema},
          ...?(thinking.remove('output_config') as Map<String, dynamic>?),
        };
        // 旧模型要求 budget_tokens < max_tokens
        var maxTokens = 16384;
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
        return _extractAnthropicText(resp.data!);

      case AgentApiProvider.gemini:
        final parts = <Map<String, dynamic>>[
          for (final img in images) ...[
            {'text': _pageLabel(img)},
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
              'responseMimeType': 'application/json',
              if (mode == 'schema') 'responseJsonSchema': schema,
              if (thinkingCfg.isNotEmpty) 'thinkingConfig': thinkingCfg,
            },
          },
          cancelToken: cancelToken,
        );
        return _extractGeminiText(resp.data!);

      case AgentApiProvider.openAICompatible:
        final content = <Map<String, dynamic>>[
          for (final img in images) ...[
            {'type': 'text', 'text': _pageLabel(img)},
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
            if (mode == 'schema')
              'response_format': {
                'type': 'json_schema',
                'json_schema': {
                  'name': 'layout_fix',
                  'strict': true,
                  'schema': schema,
                },
              }
            else if (mode == 'json')
              'response_format': {'type': 'json_object'},
            // DashScope 专属：把单图 token 上限 1280 → 16384，密集文档页必需
            if (AgentModelCapability.isQwenVl(modelId))
              'vl_high_resolution_images': true,
            ...AgentThinkingPayload.forOpenAICompat(modelParams.thinkingLevel),
          },
          options: Options(headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          }),
          cancelToken: cancelToken,
        );
        return _extractOpenAICompatibleText(resp.data!);
    }
  }

  /// 输出 JSON Schema（OpenAI strict 模式要求：根为 object、所有属性
  /// required、各级 additionalProperties=false；不用 minItems 等各家
  /// 支持不一的关键字，长度校验留在 client 侧）。
  static Map<String, dynamic> _outputSchema({required bool yFirst}) {
    final bboxDesc = yFirst
        ? 'Bounding box [ymin, xmin, ymax, xmax], integers normalized to '
            '0-1000 relative to the page image.'
        : 'Bounding box [left, top, right, bottom], integers normalized to '
            '0-1000 relative to the page image.';
    return {
      'type': 'object',
      'properties': {
        'figures': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'img': {'type': 'string'},
              'figure_title': {'type': 'string'},
              'page_idx': {'type': 'integer'},
              'bbox': {
                'type': 'array',
                'items': {'type': 'integer'},
                'description': bboxDesc,
              },
            },
            'required': ['img', 'figure_title', 'page_idx', 'bbox'],
            'additionalProperties': false,
          },
        },
        'paragraphs': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'id': {'type': 'integer'},
              'content': {'type': 'string'},
            },
            'required': ['id', 'content'],
            'additionalProperties': false,
          },
        },
      },
      'required': ['figures', 'paragraphs'],
      'additionalProperties': false,
    };
  }

  static String _readableMessage(DioException e) {
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

  static String _extractOpenAIText(Map<String, dynamic> data) {
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
    final choices = data['choices'] as List<dynamic>?;
    if (choices != null && choices.isNotEmpty) {
      final msg = (choices[0] as Map<String, dynamic>)['message'];
      if (msg is Map<String, dynamic>) {
        return (msg['content'] as String? ?? '').trim();
      }
    }
    throw Exception('无法从 OpenAI 响应中提取结果');
  }

  static String _extractAnthropicText(Map<String, dynamic> data) {
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

  static String _extractGeminiText(Map<String, dynamic> data) {
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

  static String _extractOpenAICompatibleText(Map<String, dynamic> data) {
    final choices = data['choices'] as List<dynamic>?;
    if (choices != null && choices.isNotEmpty) {
      final msg = (choices[0] as Map<String, dynamic>)['message'];
      if (msg is Map<String, dynamic>) {
        return (msg['content'] as String? ?? '').trim();
      }
    }
    throw Exception('无法从 API 响应中提取结果');
  }

  // ── 工具方法 ────────────────────────────────────────────

  static Map<String, dynamic> _parseJsonResponse(String text) {
    var cleaned = text.trim();
    if (cleaned.startsWith('```')) {
      final firstNewline = cleaned.indexOf('\n');
      if (firstNewline > 0) cleaned = cleaned.substring(firstNewline + 1);
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3);
      }
    }
    return jsonDecode(cleaned.trim()) as Map<String, dynamic>;
  }

  static bool _bboxChanged(List<dynamic>? old, List<dynamic>? updated) {
    if (old == null || updated == null) return true;
    if (old.length != 4 || updated.length != 4) return true;
    for (var i = 0; i < 4; i++) {
      if (((old[i] as num) - (updated[i] as num)).abs() > 2) return true;
    }
    return false;
  }
}
