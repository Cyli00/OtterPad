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
import 'figure_extract_service.dart';
import 'pdf_process_lock.dart';
import 'prompts.dart';

/// 单个批次：一组目标 PDF 页 + 落在这些页上的图片清单条目。
/// 按批调用可控制单请求体积（Gemini inline 上限 20MB）、避免输出超长截断，
/// 并支持批间进度展示与失败重试。
class AiLayoutFixChunk {
  final List<int> pages;
  final List<Map<String, dynamic>> figures;

  AiLayoutFixChunk({
    required this.pages,
    List<Map<String, dynamic>>? figures,
  }) : figures = figures ?? [];
}

class AiLayoutFixAnalysis {
  final String documentId;
  final String pdfPath;
  final List<int> targetPages;
  final Map<String, dynamic> currentManifest;
  final List<AiLayoutFixChunk> chunks;

  /// 每页 main caption 块的 bbox（144 DPI）——applyResults 用它做
  /// "caption 不入框" 的机械校验（与 FigureExtractService 的
  /// trimCaptionFromRegion 契约对齐）。
  final Map<int, List<List<double>>> captionBlocksByPage;
  final int estimatedTokens;

  const AiLayoutFixAnalysis({
    required this.documentId,
    required this.pdfPath,
    required this.targetPages,
    required this.currentManifest,
    required this.chunks,
    required this.captionBlocksByPage,
    required this.estimatedTokens,
  });

  int get figureCount =>
      (currentManifest['figures'] as List?)?.length ?? 0;

  bool get isEmpty => targetPages.isEmpty;
}

/// execute() 的产物——纯增量语义：未提及的条目一律保留原状。
class AiLayoutFixResult {
  /// 修复条目（img 已通过送审白名单校验）：
  /// {img, page_idx, crop_bbox?(144 DPI), figure_title?, subfigures}。
  /// crop_bbox / figure_title 缺失 = 该字段无改动。
  final List<Map<String, dynamic>> fixes;

  /// 模型发现的漏检图：{page_idx, crop_bbox, figure_title?, subfigures}。
  /// img 文件名由 applyResults 生成，模型无命名权。
  final List<Map<String, dynamic>> additions;

  /// 显式删除白名单（仅含送审清单中存在的 img）。
  final Set<String> removals;

  const AiLayoutFixResult({
    required this.fixes,
    required this.additions,
    required this.removals,
  });
}

class AiLayoutFixSummary {
  final int figuresAdjusted;
  final int figuresAdded;
  final int figuresRemoved;
  const AiLayoutFixSummary({
    required this.figuresAdjusted,
    required this.figuresAdded,
    required this.figuresRemoved,
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

/// AI 排版修复服务：多模态 LLM 审核 figure 裁剪区域。
///
/// 任务边界：bbox 边缘修复（子图与 (a)/(b) 序号标签完整入框、main caption
/// 排除）+ figure_title 纠错/补缺 + 新增漏检图 + 显式 remove 删除。
/// 纯增量语义——模型未提及的条目一律保留原状，没有"整页替换"。
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

  // ── Step 1: 分析 ─────────────────────────────────────────

  static Future<AiLayoutFixAnalysis> analyze({
    required String documentId,
  }) async {
    final pdfPath = DocPaths.pdf(documentId);
    final jsonPath = DocPaths.json(documentId);
    final manifestPath = DocPaths.figuresManifest(documentId);

    // main caption 判定与提取管线同源（caption 配置从 assets 加载）
    await FigureExtractService.instance.init();

    final targetPages = <int>{};
    final captionBlocksByPage = <int, List<List<double>>>{};
    final extractFile = File(jsonPath);
    if (extractFile.existsSync()) {
      final decoded = jsonDecode(await extractFile.readAsString());
      final List<dynamic> pages;
      if (decoded is Map<String, dynamic>) {
        pages = decoded['layoutParsingResults'] as List<dynamic>? ?? [];
      } else if (decoded is List<dynamic>) {
        pages = decoded;
      } else {
        pages = [];
      }

      for (var pi = 0; pi < pages.length; pi++) {
        final pageMap = pages[pi] as Map<String, dynamic>;
        final pageIdx = (pageMap['page_index'] as int?) ?? pi;
        final blocks = (pageMap['prunedResult']
                    as Map<String, dynamic>?)?['parsing_res_list']
                as List<dynamic>? ??
            [];

        for (final block in blocks) {
          final b = block as Map<String, dynamic>;
          final label = b['block_label'] as String?;
          if (label == 'image' || label == 'chart') {
            targetPages.add(pageIdx);
          } else if (label == 'figure_title' &&
              FigureExtractService.instance
                  .isMainCaption(b['block_content'] as String? ?? '')) {
            // main caption 块 bbox（144 DPI）→ "caption 不入框" 输出校验
            final bbox = (b['block_bbox'] as List<dynamic>?)
                ?.map((v) => (v as num).toDouble())
                .toList();
            if (bbox != null && bbox.length == 4) {
              captionBlocksByPage.putIfAbsent(pageIdx, () => []).add(bbox);
            }
          }
        }
      }
    }

    var manifest = <String, dynamic>{
      'figures': <dynamic>[],
      'diagnostics': <String, dynamic>{},
    };
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

    // 粗略估算：高 detail 下主流服务商单页约 1500~2600 token，取 2500；
    // 输出为增量修复条目，按清单体量的 1/3 估
    final imageTokens = sortedPages.length * 2500;
    final figuresJson = jsonEncode(manifest['figures']);
    final textTokens = (figuresJson.length + 1200) ~/ 4;
    final outputTokens = figuresJson.length ~/ 3;

    return AiLayoutFixAnalysis(
      documentId: documentId,
      pdfPath: pdfPath,
      targetPages: sortedPages,
      currentManifest: manifest,
      chunks: chunks,
      captionBlocksByPage: captionBlocksByPage,
      estimatedTokens: imageTokens + textTokens + outputTokens,
    );
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
    final systemPrompt = Prompts.layoutFixSystem(yFirst: yFirst);

    final outFixes = <Map<String, dynamic>>[];
    final outAdditions = <Map<String, dynamic>>[];
    final outRemovals = <String>{};

    final total = analysis.chunks.length;
    for (var i = 0; i < total; i++) {
      if (cancelToken.isCancelled) break;
      final chunk = analysis.chunks[i];

      onProgress('rendering', i + 1, total);
      final pageImages =
          await _renderPages(analysis.pdfPath, chunk.pages, cancelToken);
      if (cancelToken.isCancelled) break;
      if (pageImages.isEmpty) continue;
      final imagesByPage = <int, _PageImage>{
        for (final pi in pageImages) pi.pageIdx: pi,
      };

      // 渲染失败的页退出本批，其条目不送审——增量语义下天然保留原状。
      // figures 可以为空：有视觉块但无 manifest 条目的页仍要送审（漏检场景）。
      final figures = chunk.figures
          .where((f) => imagesByPage.containsKey(f['page_idx']))
          .toList();

      onProgress('calling', i + 1, total);
      final userPrompt = _buildUserPrompt(
        figures: figures,
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
        chunkFigures: figures,
        imagesByPage: imagesByPage,
        yFirst: yFirst,
        outFixes: outFixes,
        outAdditions: outAdditions,
        outRemovals: outRemovals,
      );
    }

    return AiLayoutFixResult(
      fixes: outFixes,
      additions: outAdditions,
      removals: outRemovals,
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

    final existingFigures =
        (analysis.currentManifest['figures'] as List<dynamic>? ?? [])
            .map((f) => Map<String, dynamic>.from(f as Map))
            .toList();

    // 1. 显式删除（白名单在 merge 阶段已校验）
    final kept = existingFigures
        .where((f) => !result.removals.contains(f['img']))
        .toList();
    final byImg = <String, Map<String, dynamic>>{
      for (final f in kept) f['img'] as String: f,
    };

    // 2. 按 img 增量更新；bbox 先过 "caption 不入框" 机械校验
    final figuresToRecrop = <Map<String, dynamic>>[];
    final subfigureDiag = <String, dynamic>{};
    var adjusted = 0;
    for (final fix in result.fixes) {
      final target = byImg[fix['img'] as String];
      if (target == null) continue; // 同条目被 remove 时 remove 优先

      var changed = false;
      final title = fix['figure_title'];
      if (title is String && title != target['figure_title']) {
        target['figure_title'] = title;
        changed = true;
      }
      final newBbox = fix['crop_bbox'];
      if (newBbox is List) {
        final pageIdx = fix['page_idx'] as int;
        final trimmed = _trimCaptionOverlap(
          newBbox.map((v) => (v as num).toDouble()).toList(),
          analysis.captionBlocksByPage[pageIdx] ?? const [],
        );
        if (_bboxChanged(target['crop_bbox'] as List<dynamic>?, trimmed)) {
          target['crop_bbox'] = trimmed;
          target['page_idx'] = pageIdx;
          target['region_method'] = 'ai_layout_fix';
          figuresToRecrop.add(target);
          changed = true;
        }
      }
      if (changed) {
        adjusted++;
        subfigureDiag[fix['img'] as String] = fix['subfigures'];
      }
    }

    // 3. 新增漏检图：文件名由客户端生成，避开 manifest 与磁盘已有名字
    final outputDir = DocPaths.figuresDir(analysis.documentId);
    final usedImgs = kept.map((f) => f['img'] as String).toSet();
    for (final add in result.additions) {
      final pageIdx = add['page_idx'] as int;
      final trimmed = _trimCaptionOverlap(
        (add['crop_bbox'] as List)
            .map((v) => (v as num).toDouble())
            .toList(),
        analysis.captionBlocksByPage[pageIdx] ?? const [],
      );
      final img = _nextAiFixName(outputDir, usedImgs, pageIdx);
      usedImgs.add(img);
      final entry = <String, dynamic>{
        'img': img,
        'figure_title': add['figure_title'],
        'page_idx': pageIdx,
        'crop_bbox': trimmed,
        'block_ids': <String>[],
        'region_method': 'ai_layout_fix',
      };
      kept.add(entry);
      figuresToRecrop.add(entry);
      subfigureDiag[img] = add['subfigures'];
    }

    onProgress('cropping', 1, 1);
    if (figuresToRecrop.isNotEmpty && !cancelToken.isCancelled) {
      await _recropFigures(
          analysis.pdfPath, analysis.documentId, figuresToRecrop);
    }

    // 稳定按页排序（Dart sort 不稳定，用原序号兜底）
    final indexed = kept.asMap().entries.toList()
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

    // 模型的子图枚举入 diagnostics 留诊断线索（客户端不校验其内容）
    final diagnostics = Map<String, dynamic>.from(
        analysis.currentManifest['diagnostics'] as Map? ?? {});
    if (subfigureDiag.isNotEmpty) {
      diagnostics['ai_layout_fix_subfigures'] = subfigureDiag;
    }

    final manifestPath = DocPaths.figuresManifest(analysis.documentId);
    await File(manifestPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'figures': indexed.map((e) => e.value).toList(),
        'diagnostics': diagnostics,
      }),
    );

    return AiLayoutFixSummary(
      figuresAdjusted: adjusted,
      figuresAdded: result.additions.length,
      figuresRemoved: result.removals.length,
    );
  }

  /// 生成新增图文件名 `ai_fix_p{page}_{n}.png`——模型无命名权（消灭重名/
  /// 格式幻觉面）。跳过 manifest 已占用与磁盘已存在的名字。
  static String _nextAiFixName(
    String outputDir,
    Set<String> usedImgs,
    int pageIdx,
  ) {
    for (var n = 1;; n++) {
      final name = 'ai_fix_p${pageIdx}_$n.png';
      if (usedImgs.contains(name)) continue;
      if (File(p.join(outputDir, name)).existsSync()) continue;
      return name;
    }
  }

  /// "caption 不入框" 机械校验：bbox 与 main caption 块重叠超过 caption
  /// 自身面积 50% 时，从损失面积最小的方向把 bbox 裁到 caption 边界外
  /// （与 FigureExtractService.trimCaptionFromRegion 的 4 方向思路一致）。
  /// 50% 容差防御 PaddleOCR caption 块本身框错位置时裁坏 AI 的正确修复；
  /// 裁完区域翻转/塌缩则放弃裁剪，保留模型原框。
  static List<double> _trimCaptionOverlap(
    List<double> bbox,
    List<List<double>> captions,
  ) {
    var l = bbox[0], t = bbox[1], r = bbox[2], b = bbox[3];
    for (final c in captions) {
      final ow = math.min(r, c[2]) - math.max(l, c[0]);
      final oh = math.min(b, c[3]) - math.max(t, c[1]);
      if (ow <= 0 || oh <= 0) continue;
      final capArea = (c[2] - c[0]) * (c[3] - c[1]);
      if (capArea <= 0 || ow * oh < capArea * 0.5) continue;

      // 4 方向 trim 候选，选损失面积最小的
      final candidates = <(double, void Function())>[
        if (c[1] > t) ((b - c[1]) * (r - l), () => b = c[1]),
        if (c[3] < b) ((c[3] - t) * (r - l), () => t = c[3]),
        if (c[0] > l) ((r - c[0]) * (b - t), () => r = c[0]),
        if (c[2] < r) ((c[2] - l) * (b - t), () => l = c[2]),
      ];
      if (candidates.isEmpty) continue;
      candidates.reduce((a, x) => x.$1 < a.$1 ? x : a).$2();
    }
    if (r - l <= 0 || b - t <= 0) return bbox;
    return [l, t, r, b];
  }

  // ── Prompt 构造 ─────────────────────────────────────────

  // system prompt 措辞在 Prompt Registry：Prompts.layoutFixSystem(yFirst:)

  static String _buildUserPrompt({
    required List<Map<String, dynamic>> figures,
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

    return (StringBuffer()
          ..writeln(Prompts.layoutFixUserManifestHeader)
          ..writeln('```json')
          ..writeln(const JsonEncoder.withIndent('  ').convert(promptFigures))
          ..writeln('```')
          ..writeln()
          ..writeln(promptFigures.isEmpty
              ? Prompts.layoutFixUserScanHint
              : Prompts.layoutFixUserAuditHint))
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
    required List<Map<String, dynamic>> chunkFigures,
    required Map<int, _PageImage> imagesByPage,
    required bool yFirst,
    required List<Map<String, dynamic>> outFixes,
    required List<Map<String, dynamic>> outAdditions,
    required Set<String> outRemovals,
  }) {
    final sentImgs = {for (final f in chunkFigures) f['img'] as String};

    for (final entry in parsed['fixes'] as List<dynamic>? ?? const []) {
      if (entry is! Map) continue;
      final img = entry['img'];
      // img 白名单：只接受本批送审的条目，模型编造的名字直接丢弃
      if (img is! String || !sentImgs.contains(img)) continue;
      final pageIdx = entry['page_idx'];
      final pi = pageIdx is int ? imagesByPage[pageIdx] : null;
      if (pi == null) continue;

      final crop = _bbox1000ToCrop(entry['bbox'], pi, yFirst);
      final title = entry['figure_title'];
      final hasTitle = title is String && title.trim().isNotEmpty;
      if (crop == null && !hasTitle) continue; // 无实质改动
      outFixes.add({
        'img': img,
        'page_idx': pageIdx,
        'crop_bbox': ?crop,
        if (hasTitle) 'figure_title': title.trim(),
        'subfigures': _stringList(entry['subfigures']),
      });
    }

    for (final entry in parsed['additions'] as List<dynamic>? ?? const []) {
      if (entry is! Map) continue;
      final pageIdx = entry['page_idx'];
      final pi = pageIdx is int ? imagesByPage[pageIdx] : null;
      if (pi == null) continue;
      final crop = _bbox1000ToCrop(entry['bbox'], pi, yFirst);
      if (crop == null) continue; // 新增条目必须有有效框
      final title = entry['figure_title'];
      outAdditions.add({
        'page_idx': pageIdx,
        'crop_bbox': crop,
        'figure_title': (title is String && title.trim().isNotEmpty)
            ? title.trim()
            : null,
        'subfigures': _stringList(entry['subfigures']),
      });
    }

    for (final entry in parsed['remove'] as List<dynamic>? ?? const []) {
      // 与 fixes 同款白名单：只能删本批送审过的条目
      if (entry is String && sentImgs.contains(entry)) {
        outRemovals.add(entry);
      }
    }
  }

  static List<String> _stringList(dynamic v) =>
      v is List ? v.whereType<String>().toList() : const [];

  /// 0-1000 归一化 bbox → 144 DPI crop_bbox。无效（非 4 元数组 / 过小
  /// 不足页面 1%）返回 null。
  static List<double>? _bbox1000ToCrop(
    dynamic bbox,
    _PageImage pi,
    bool yFirst,
  ) {
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
    if (r - l < 10 || b - t < 10) return null;

    final w144 = pi.widthPx / _llmZoom * _apiZoom;
    final h144 = pi.heightPx / _llmZoom * _apiZoom;
    return [
      l / 1000 * w144,
      t / 1000 * h144,
      r / 1000 * w144,
      b / 1000 * h144,
    ];
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
            '0-1000 relative to the page image — same convention as the '
            'manifest bboxes in the input.'
        : 'Bounding box [left, top, right, bottom], integers normalized to '
            '0-1000 relative to the page image — same convention as the '
            'manifest bboxes in the input.';
    const subfiguresDesc =
        'Sequence labels of every subfigure panel visible in this figure, '
        'e.g. ["a","b","c"]. Empty for single-panel figures.';
    final bboxSchema = {
      'type': ['array', 'null'],
      'items': {'type': 'integer'},
      'description': '$bboxDesc Null = bbox unchanged.',
    };
    return {
      'type': 'object',
      'properties': {
        'fixes': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'img': {'type': 'string'},
              'page_idx': {'type': 'integer'},
              'subfigures': {
                'type': 'array',
                'items': {'type': 'string'},
                'description': subfiguresDesc,
              },
              'bbox': bboxSchema,
              'figure_title': {
                'type': ['string', 'null'],
                'description': 'Corrected title. Null = title unchanged.',
              },
            },
            'required': [
              'img',
              'page_idx',
              'subfigures',
              'bbox',
              'figure_title',
            ],
            'additionalProperties': false,
          },
        },
        'additions': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'page_idx': {'type': 'integer'},
              'subfigures': {
                'type': 'array',
                'items': {'type': 'string'},
                'description': subfiguresDesc,
              },
              'bbox': {
                'type': 'array',
                'items': {'type': 'integer'},
                'description': bboxDesc,
              },
              'figure_title': {
                'type': ['string', 'null'],
              },
            },
            'required': ['page_idx', 'subfigures', 'bbox', 'figure_title'],
            'additionalProperties': false,
          },
        },
        'remove': {
          'type': 'array',
          'items': {'type': 'string'},
          'description':
              'img values (from the manifest) that are not real figures.',
        },
      },
      'required': ['fixes', 'additions', 'remove'],
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
    final decoded = jsonDecode(cleaned.trim());
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is List) {
      if (decoded.length == 1 && decoded[0] is Map) {
        return Map<String, dynamic>.from(decoded[0] as Map);
      }
      // 裸数组兜底：当作 fixes 列表（白名单校验会过滤掉不合法条目）
      return {'fixes': decoded};
    }
    throw FormatException('Expected JSON object, got ${decoded.runtimeType}');
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
