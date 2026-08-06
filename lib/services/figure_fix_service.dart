import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../providers/api_provider.dart';
import 'agent_chat_service.dart';
import 'doc_extract_service.dart';
import 'document_structure.dart';
import 'figure_extract_service.dart';
import 'prompts.dart';
import '../utils/doc_paths.dart';

/// AI 修缮 figure 的失败类型。UI 层按 [FigureFixException.kind] 映射 l10n 文案。
enum FigureFixError {
  /// extract.json / raw.md 缺失，提示先提取文档。
  missingExtractJson,

  /// 未设置专家/快速模型。
  modelNotSet,

  /// 用户取消。
  cancelled,

  /// LLM 输出无法解析为合法 JSON/结构。
  invalidLlmOutput,
}

/// AI 修缮 figure 提取异常。UI 层按 [kind] 映射用户文案，
/// [message] 仅供日志/调试，非用户可见。
class FigureFixException implements Exception {
  final FigureFixError kind;
  final String message;
  const FigureFixException(this.kind, [this.message = '']);
  @override
  String toString() => message.isEmpty ? 'FigureFixException($kind)' : message;
}

/// caption 召回条目在文档中的注册引用（复合 id `p{page}:c{idx}`）。
class CaptionRef {
  final int pageIdx;
  final int indexInPage;
  final CaptionCandidateInfo info;
  CaptionRef(this.pageIdx, this.indexInPage, this.info);
  String get id => 'p$pageIdx:c$indexInPage';
}

/// visual block 在文档中的注册引用（复合 id `p{page}:b{blockId}`）。
class VisualRef {
  final int pageIdx;
  final LayoutBlock block;
  VisualRef(this.pageIdx, this.block);
  String get id => 'p$pageIdx:b${block.blockId}';
}

/// 单页解析数据（blocks + markdown + 栏位）。
class PageData {
  final int pageIndex;
  final List<LayoutBlock> blocks;
  final String markdown;
  final ColumnLayout columns;
  PageData(this.pageIndex, this.blocks, this.markdown, this.columns);
}

/// LLM 输出的一条 figure 归属裁决。
class AiFigure {
  final String? captionId;
  final List<String> visualIds;
  final String kind;
  const AiFigure({this.captionId, required this.visualIds, required this.kind});
}

/// LLM 输出的完整裁决（已过白名单/去重）。
class FigureFixResult {
  final List<AiFigure> figures;
  final Set<String> orphanCaptionIds;
  final Set<String> uncaptionedVisualIds;
  const FigureFixResult({
    required this.figures,
    required this.orphanCaptionIds,
    required this.uncaptionedVisualIds,
  });
}

/// 合并计划：需重裁的 [cropRequests] + 未触碰的启发式条目 [keptHeuristic]。
class MergePlan {
  final List<FigureCropRequest> cropRequests;
  final List<FigureManifestEntry> keptHeuristic;
  const MergePlan({required this.cropRequests, required this.keptHeuristic});
}

/// analyze 阶段产物。
class FigureFixAnalysis {
  final String pdfPath;
  final String jsonContent;
  final List<PageData> pages;
  final Map<String, CaptionRef> captionRegistry;
  final Map<String, VisualRef> visualRegistry;
  final Map<String, dynamic> inventory;
  final int estimatedTokens;
  final List<FigureManifestEntry> heuristic;

  const FigureFixAnalysis({
    required this.pdfPath,
    required this.jsonContent,
    required this.pages,
    required this.captionRegistry,
    required this.visualRegistry,
    required this.inventory,
    required this.estimatedTokens,
    required this.heuristic,
  });
}

/// apply 阶段产物。
class FigureFixSummary {
  final int figuresRebuilt;
  final int figuresKept;
  const FigureFixSummary({
    required this.figuresRebuilt,
    required this.figuresKept,
  });
}

/// AI 修缮 figure 提取编排服务。
///
/// 三阶段：
///   [analyze] 预处理（caption-first 聚合候选 visual + 栏位 + 当前 manifest）
///   [execute] LLM 文本编辑归属（结构化 JSON 输出，纯文本无图）
///   [apply]   保守合并 → 裁剪 → 写 figures.json → 重生成 md
///
/// LLM 只输出 block_id 复合引用，绝不输出 bbox（与已删的多模态方案切割）。
/// 回滚靠 [DocExtractService.reprocessMarkdown]（重跑启发式覆盖 AI 产物）。
class FigureFixService {
  FigureFixService._();
  static final FigureFixService instance = FigureFixService._();

  // ─── Stage 1: analyze ──────────────────────────────────

  Future<FigureFixAnalysis> analyze({required String pdfPath}) async {
    final jsonPath = DocPaths.json(pdfPath);
    final jsonFile = File(jsonPath);
    if (!jsonFile.existsSync()) {
      throw const FigureFixException(
        FigureFixError.missingExtractJson,
        'extract.json 不存在，请先提取文档',
      );
    }
    final jsonContent = await jsonFile.readAsString();
    final structure = DocumentStructure.parse(jsonContent);
    if (structure.isEmpty) {
      throw const FigureFixException(
        FigureFixError.missingExtractJson,
        'extract.json 解析失败或为空',
      );
    }

    await FigureExtractService.instance.init();

    final pages = <PageData>[];
    final captionRegistry = <String, CaptionRef>{};
    final visualRegistry = <String, VisualRef>{};

    for (final page in structure.pages) {
      final cols = FigureExtractService.detectColumns(page.blocks);
      pages.add(PageData(page.pageIndex, page.blocks, page.markdown, cols));

      // caption 召回（含 continuationBlocks + groupId + blockOrder）
      final caps = FigureExtractService.instance.collectCaptionCandidatesPublic(
        page.blocks,
        page.markdown,
        page.pageIndex,
      );
      for (var i = 0; i < caps.length; i++) {
        final ref = CaptionRef(page.pageIndex, i, caps[i]);
        captionRegistry[ref.id] = ref;
      }

      // visual 召回：真实视觉块 + footnote + 短 figure_title/text/footer 子图序号
      for (final b in page.blocks) {
        if (!_isVisualCandidate(b)) continue;
        if (b.blockId.isEmpty) continue;
        final ref = VisualRef(page.pageIndex, b);
        visualRegistry[ref.id] = ref;
      }
    }

    final heuristic =
        await FigureExtractService.loadManifest(pdfPath) ?? const [];

    final inventory = buildInventory(
      pages.map((p) => p.pageIndex).toList(),
      pages,
      captionRegistry,
      visualRegistry,
      heuristic,
    );

    final estimatedTokens = estimateTokens(inventory);

    return FigureFixAnalysis(
      pdfPath: pdfPath,
      jsonContent: jsonContent,
      pages: pages,
      captionRegistry: captionRegistry,
      visualRegistry: visualRegistry,
      inventory: inventory,
      estimatedTokens: estimatedTokens,
      heuristic: heuristic,
    );
  }

  /// 是否作为 visual 候选：实际视觉块、footnote，以及短子图序号。
  ///
  /// 注意：`figure_title` 是 caption 语义，不在此列——短标题若同时进 visual
  /// 注册表会与 captionRegistry 双重身份，LLM 未认领时被保守合并转成匿名
  /// 裁剪，产出仅含标题文本的伪图（见 _anonymousCropRequest）。
  static bool _isVisualCandidate(LayoutBlock b) {
    final label = b.blockLabel;
    if (label == 'image' ||
        label == 'chart' ||
        label == 'table' ||
        label == 'vision_footnote') {
      return true;
    }
    if ((label == 'text' || label == 'vision_footer') &&
        FigureExtractService.instance.isSubfigureLabelBlock(b)) {
      return true;
    }
    return false;
  }

  // ─── Stage 2: execute ──────────────────────────────────

  Future<FigureFixResult> execute({
    required FigureFixAnalysis analysis,
    required AgentApiState agentState,
    CancelToken? cancelToken,
  }) async {
    final modelId = agentState.defaultModelId ?? agentState.fastModelId;
    if (modelId == null) {
      throw const FigureFixException(
        FigureFixError.modelNotSet,
        '未设置专家模型或快速模型',
      );
    }
    final modelParams = agentState
        .paramsFor(modelId)
        .copyWith(thinkingLevel: ThinkingLevel.off);

    final userPrompt = assembleUserPrompt(analysis.inventory);
    final response = await AgentChatService.send(
      provider: agentState.provider,
      baseUrl: agentState.effectiveBaseUrl,
      apiKey: agentState.apiKey,
      modelId: modelId,
      modelParams: modelParams,
      systemPrompt: Prompts.figureFixSystem,
      userPrompt: userPrompt,
      schema: buildOutputSchema(),
      schemaName: 'figure_fix',
      anthropicMaxTokens: 16384,
      cancelToken: cancelToken,
    );

    return parseAndValidate(
      response,
      analysis.captionRegistry,
      analysis.visualRegistry,
    );
  }

  // ─── Stage 3: apply ────────────────────────────────────

  Future<(String mdPath, String content, FigureFixSummary)> apply({
    required FigureFixAnalysis analysis,
    required FigureFixResult result,
    required String? title,
    CancelToken? cancelToken,
    void Function(int done, int total)? onProgress,
  }) async {
    // raw.md 是 applyFigureManifest 重建底稿，缺失则无法落盘。
    final rawMdPath = DocPaths.rawMd(analysis.pdfPath);
    if (!File(rawMdPath).existsSync()) {
      throw const FigureFixException(
        FigureFixError.missingExtractJson,
        'raw.md 不存在，请先提取文档',
      );
    }

    final plan = mergeFigures(
      result: result,
      heuristic: analysis.heuristic,
      captionRegistry: analysis.captionRegistry,
      visualRegistry: analysis.visualRegistry,
    );

    final pageBlocks = [for (final p in analysis.pages) p.blocks];

    final rebuilt = await FigureExtractService.instance.cropFiguresFromSegments(
      pdfPath: analysis.pdfPath,
      segments: plan.cropRequests,
      pageBlocks: pageBlocks,
      cancelToken: cancelToken,
      onProgress: onProgress,
    );

    if (cancelToken?.isCancelled ?? false) {
      throw const FigureFixException(FigureFixError.cancelled, '已取消');
    }

    // 合并：重裁条目 + 未触碰启发式条目，按页稳定排序。
    final combined = [...rebuilt, ...plan.keptHeuristic];
    combined.sort((a, b) {
      final c = a.pageIndex.compareTo(b.pageIndex);
      return c != 0 ? c : 0; // 同页保留插入顺序（Dart sort 不稳定，但此处够用）
    });

    final manifestPath = DocPaths.figuresManifest(analysis.pdfPath);
    await File(manifestPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'figures': [for (final e in combined) e.toJson()],
        'diagnostics': {'source': 'ai_fix'},
      }),
      flush: true,
    );

    final (mdPath, content) = await DocExtractService.instance
        .applyFigureManifest(
          pdfPath: analysis.pdfPath,
          jsonContent: analysis.jsonContent,
          figures: combined,
          title: title,
        );

    return (
      mdPath,
      content,
      FigureFixSummary(
        figuresRebuilt: rebuilt.length,
        figuresKept: plan.keptHeuristic.length,
      ),
    );
  }

  // ─── 纯函数（@visibleForTesting） ───────────────────────

  /// 构建喂给 LLM 的 inventory JSON。windowPages = 本批权威页（单批=全部页），
  /// 候选 visual 含窗口页 ±1 邻页。LLM 只引用 [captionRegistry]/[visualRegistry]
  /// 中的 id，manifest 仅作参考上下文（其 block_ids 跨页歧义，禁止引用）。
  @visibleForTesting
  static Map<String, dynamic> buildInventory(
    List<int> windowPages,
    List<PageData> pages,
    Map<String, CaptionRef> captionRegistry,
    Map<String, VisualRef> visualRegistry,
    List<FigureManifestEntry> heuristic,
  ) {
    final byIdx = {for (final p in pages) p.pageIndex: p};
    final windowSet = windowPages.toSet();

    // 邻页 visual（窗口 ±1）: 用于 candidate_hints 的跨页候选。
    final neighborVisualIdsByPage = <int, List<String>>{};
    for (final pi in windowPages) {
      for (final offset in [-1, 1]) {
        final nb = pi + offset;
        if (windowSet.contains(nb)) continue;
        final page = byIdx[nb];
        if (page == null) continue;
        for (final b in page.blocks) {
          if (!_isVisualCandidate(b) || b.blockId.isEmpty) continue;
          final id = 'p$nb:b${b.blockId}';
          if (visualRegistry.containsKey(id)) {
            neighborVisualIdsByPage.putIfAbsent(pi, () => []).add(id);
          }
        }
      }
    }

    final pagesJson = <Map<String, dynamic>>[];
    for (final pi in windowPages) {
      final page = byIdx[pi]!;
      final captions = <Map<String, dynamic>>[];
      for (final entry in captionRegistry.entries) {
        final ref = entry.value;
        if (ref.pageIdx != pi) continue;
        captions.add({
          'caption_id': ref.id,
          'text': ref.info.text,
          'kind': FigureExtractService.instance.classifyKind(ref.info.text),
          'bbox': ref.info.bbox,
          'block_id': ref.info.blockId,
          'continuation_block_ids': ref.info.continuationBlockIds,
          'group_id': ref.info.groupId,
          'block_order': ref.info.blockOrder,
          'source': ref.info.source.name,
        });
      }
      final visuals = <Map<String, dynamic>>[];
      for (final entry in visualRegistry.entries) {
        final ref = entry.value;
        if (ref.pageIdx != pi) continue;
        final content = ref.block.blockContent;
        visuals.add({
          'visual_id': ref.id,
          'label': ref.block.blockLabel,
          'role': FigureExtractService.instance.isSubfigureLabelBlock(ref.block)
              ? 'subfigure_label'
              : 'visual',
          'bbox': ref.block.blockBbox,
          'group_id': ref.block.groupId,
          'block_order': ref.block.blockOrder,
          'content': content.length > 500 ? content.substring(0, 500) : content,
          if (content.length > 500) 'content_truncated': true,
        });
      }
      pagesJson.add({
        'page_idx': pi,
        'columns': {
          'double_column': page.columns.isDoubleColumn,
          'page_left': page.columns.pageLeft,
          'page_right': page.columns.pageRight,
          'left_col_right': page.columns.leftColRight,
          'right_col_left': page.columns.rightColLeft,
        },
        'captions': captions,
        'visuals': visuals,
      });
    }

    // candidate_hints: 每 caption 的候选 visual（同页全部 + 邻页 visual）。
    final hints = <Map<String, dynamic>>[];
    for (final pi in windowPages) {
      final samePageVisuals = <String>[];
      for (final entry in visualRegistry.entries) {
        if (entry.value.pageIdx == pi) samePageVisuals.add(entry.key);
      }
      final neighborVisuals = neighborVisualIdsByPage[pi] ?? const [];
      for (final entry in captionRegistry.entries) {
        final ref = entry.value;
        if (ref.pageIdx != pi) continue;
        final candidates = <Map<String, dynamic>>[
          for (final vid in samePageVisuals)
            {'visual_id': vid, 'page_relation': 'same_page'},
          for (final vid in neighborVisuals)
            {
              'visual_id': vid,
              'page_relation': ref.pageIdx < _pageOf(vid)
                  ? 'next_page'
                  : 'prev_page',
            },
        ];
        hints.add({'caption_id': ref.id, 'candidates': candidates});
      }
    }

    final currentFigures = <Map<String, dynamic>>[];
    for (final e in heuristic) {
      currentFigures.add({
        'img': e.imagePath,
        'figure_title': e.captionText,
        'page_idx': e.pageIndex,
        'kind': e.kind,
        'block_ids_raw': e.blockIds,
        'block_count': e.blockIds.length,
        'pair_method': e.pairMethod,
      });
    }

    return {
      'current_figures': currentFigures,
      'pages': pagesJson,
      'candidate_hints': hints,
    };
  }

  static int _pageOf(String id) {
    // id 形如 "p5:b12" / "p5:c2"
    final s = id.substring(1);
    final end = s.indexOf(':');
    return int.parse(s.substring(0, end));
  }

  /// 把 inventory JSON 拼成 user prompt 文本。
  @visibleForTesting
  static String assembleUserPrompt(Map<String, dynamic> inventory) {
    final buf = StringBuffer()
      ..writeln(Prompts.figureFixUserManifestHeader)
      ..writeln('```json')
      ..writeln(jsonEncode(inventory['current_figures']))
      ..writeln('```')
      ..writeln(Prompts.figureFixUserInventoryHeader);
    for (final page in inventory['pages'] as List<dynamic>) {
      final m = page as Map<String, dynamic>;
      final cols = m['columns'] as Map<String, dynamic>;
      final colDesc = cols['double_column'] == true
          ? 'two-column; column split at x≈${cols['left_col_right']}/${cols['right_col_left']}'
          : 'single-column';
      buf
        ..writeln('### Page ${m['page_idx']} ($colDesc)')
        ..writeln('#### Captions')
        ..writeln('```json')
        ..writeln(jsonEncode(m['captions']))
        ..writeln('```')
        ..writeln('#### Visuals')
        ..writeln('```json')
        ..writeln(jsonEncode(m['visuals']))
        ..writeln('```');
    }
    buf
      ..writeln(Prompts.figureFixUserHintsHeader)
      ..writeln('```json')
      ..writeln(jsonEncode(inventory['candidate_hints']))
      ..writeln('```')
      ..writeln(Prompts.figureFixUserFooter);
    return buf.toString();
  }

  /// LLM 结构化输出 JSON Schema（跨 provider strict 兼容）。
  @visibleForTesting
  static Map<String, dynamic> buildOutputSchema() => {
    'type': 'object',
    'properties': {
      'figures': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'caption_id': {
              'type': ['string', 'null'],
              'description':
                  'Reference to a caption in the input, format '
                  'p<page>:c<idx>. Null = uncaptioned visual figure.',
            },
            'visual_ids': {
              'type': 'array',
              'items': {'type': 'string'},
              'description':
                  'visual_id references, format p<page>:b<block_id>. '
                  'Must only contain ids present in the input.',
            },
            'kind': {
              'type': 'string',
              'description':
                  'One of: figure, table, chart. chart covers '
                  'Scheme/Plate/Map/Box/Diagram/Exhibit captions.',
            },
          },
          'required': ['caption_id', 'visual_ids', 'kind'],
          'additionalProperties': false,
        },
      },
      'orphan_captions': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'uncaptioned_visuals': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    },
    'required': ['figures', 'orphan_captions', 'uncaptioned_visuals'],
    'additionalProperties': false,
  };

  /// 估算输入 token（粗略：JSON 字符数 / 4 + prompt 开销）。
  @visibleForTesting
  static int estimateTokens(Map<String, dynamic> inventory) {
    final json = jsonEncode(inventory);
    return json.length ~/ 4 + 1200;
  }

  /// 解析 + 校验 LLM 文本输出：code fence 剥离 → 结构校验 → id 白名单 →
  /// 重复认领去重（document 序先到先得）→ kind 白名单 → 空 visual_ids 降级为 orphan。
  @visibleForTesting
  static FigureFixResult parseAndValidate(
    String text,
    Map<String, CaptionRef> captionRegistry,
    Map<String, VisualRef> visualRegistry,
  ) {
    final cleaned = _stripCodeFence(text);
    dynamic decoded;
    try {
      decoded = jsonDecode(cleaned);
    } catch (_) {
      throw const FigureFixException(
        FigureFixError.invalidLlmOutput,
        'LLM 输出不是合法 JSON',
      );
    }
    // 容忍裸数组或 {fixes:[...]} 包裹。
    List<dynamic> rawFigures;
    List<dynamic> rawOrphans;
    List<dynamic> rawUncaptioned;
    if (decoded is List) {
      rawFigures = decoded;
      rawOrphans = const [];
      rawUncaptioned = const [];
    } else if (decoded is Map<String, dynamic>) {
      if (decoded.containsKey('figures')) {
        rawFigures = decoded['figures'] as List<dynamic>? ?? const [];
        rawOrphans = decoded['orphan_captions'] as List<dynamic>? ?? const [];
        rawUncaptioned =
            decoded['uncaptioned_visuals'] as List<dynamic>? ?? const [];
      } else {
        rawFigures = const [];
        rawOrphans = const [];
        rawUncaptioned = const [];
      }
    } else {
      throw const FigureFixException(
        FigureFixError.invalidLlmOutput,
        'LLM 输出根结构非 object/array',
      );
    }

    final validVisualIds = visualRegistry.keys.toSet();
    final validCaptionIds = captionRegistry.keys.toSet();

    // 第一遍：规范化每个 figure（白名单 id、kind、空 visual_ids 降级）。
    final intermediate = <_ParsedFigure>[];
    for (final raw in rawFigures) {
      if (raw is! Map<String, dynamic>) continue;
      final capId = raw['caption_id'];
      // 未知/缺失 caption_id → 视为 null（匿名）。
      final capIdStr = (capId is String && captionRegistry.containsKey(capId))
          ? capId
          : null;
      final vidsRaw = raw['visual_ids'] as List<dynamic>? ?? const [];
      var vids = vidsRaw
          .whereType<String>()
          .where(validVisualIds.contains)
          .toList(growable: false);
      var kind = raw['kind'];
      if (kind is! String ||
          (kind != 'figure' && kind != 'table' && kind != 'chart')) {
        kind = null; // 后续按 captionText 回退
      }
      // 空 visual_ids + 有 caption → 降级为 orphan。
      if (vids.isEmpty) {
        if (capIdStr != null) {
          intermediate.add(
            _ParsedFigure(
              captionId: capIdStr,
              visualIds: const [],
              kind: kind,
              orphan: true,
            ),
          );
        }
        continue;
      }
      intermediate.add(
        _ParsedFigure(
          captionId: capIdStr,
          visualIds: vids,
          kind: kind,
          orphan: false,
        ),
      );
    }

    // 重复认领去重：按 document 序（caption page 升序，匿名最后）先到先得。
    intermediate.sort((a, b) {
      final pa = a.captionId == null ? 1 << 30 : _pageOf(a.captionId!);
      final pb = b.captionId == null ? 1 << 30 : _pageOf(b.captionId!);
      return pa.compareTo(pb);
    });
    final claimedVisuals = <String>{};
    final claimedCaptions = <String>{};
    final figures = <AiFigure>[];
    final orphanIds = <String>{};
    for (final pf in intermediate) {
      if (pf.orphan) {
        orphanIds.add(pf.captionId!);
        continue;
      }
      if (pf.captionId != null && claimedCaptions.contains(pf.captionId!)) {
        continue; // 同 caption 重复 figure → 丢弃后者
      }
      final freshVids = pf.visualIds
          .where((v) => !claimedVisuals.contains(v))
          .toList(growable: false);
      if (freshVids.isEmpty) continue; // 全部 visual 被前 figure 认领 → 弃
      for (final v in freshVids) {
        claimedVisuals.add(v);
      }
      if (pf.captionId != null) claimedCaptions.add(pf.captionId!);
      final kind = pf.kind ?? _kindFallback(pf.captionId, captionRegistry);
      figures.add(
        AiFigure(captionId: pf.captionId, visualIds: freshVids, kind: kind),
      );
    }

    final uncaptioned = rawUncaptioned
        .whereType<String>()
        .where(validVisualIds.contains)
        .where((v) => !claimedVisuals.contains(v))
        .toSet();
    final orphans = {
      ...orphanIds,
      ...rawOrphans.whereType<String>().where(validCaptionIds.contains),
    };

    return FigureFixResult(
      figures: figures,
      orphanCaptionIds: orphans,
      uncaptionedVisualIds: uncaptioned,
    );
  }

  static String _kindFallback(
    String? captionId,
    Map<String, CaptionRef> captionRegistry,
  ) {
    if (captionId == null) return 'figure';
    final ref = captionRegistry[captionId];
    if (ref == null) return 'figure';
    return FigureExtractService.instance.classifyKind(ref.info.text);
  }

  static String _stripCodeFence(String text) {
    var t = text.trim();
    if (t.startsWith('```')) {
      final firstNl = t.indexOf('\n');
      if (firstNl >= 0) t = t.substring(firstNl + 1);
      if (t.endsWith('```')) t = t.substring(0, t.length - 3);
    }
    return t.trim();
  }

  /// 保守合并：AI figures 取代被触碰的启发式条目；被触碰条目中未被 AI 认领的
  /// visual 回退为匿名条目（零数据丢失）。未触碰启发式条目原样保留。
  @visibleForTesting
  static MergePlan mergeFigures({
    required FigureFixResult result,
    required List<FigureManifestEntry> heuristic,
    required Map<String, CaptionRef> captionRegistry,
    required Map<String, VisualRef> visualRegistry,
  }) {
    final aiClaimedCaptions = {...result.orphanCaptionIds};
    for (final f in result.figures) {
      if (f.captionId != null) aiClaimedCaptions.add(f.captionId!);
    }
    final aiClaimedVisuals = <String>{...result.uncaptionedVisualIds};
    for (final f in result.figures) {
      aiClaimedVisuals.addAll(f.visualIds);
    }

    // 启发式条目 → caption_id 匹配（按 captionName + 页邻近）。
    final heuristicCaptionId = _matchHeuristicCaptions(
      heuristic,
      captionRegistry,
    );

    final cropRequests = <FigureCropRequest>[];
    final keptHeuristic = <FigureManifestEntry>[];

    for (var hi = 0; hi < heuristic.length; hi++) {
      final h = heuristic[hi];
      final cid = heuristicCaptionId[hi];
      final capRef = cid == null ? null : captionRegistry[cid];

      // h 的 visual 键（页内 blockId，排除 caption 自身与 continuation）。
      final hVisualIds = <String>[];
      if (capRef != null) {
        final exclude = {
          capRef.info.blockId,
          ...capRef.info.continuationBlockIds,
        };
        for (final bid in h.blockIds) {
          if (exclude.contains(bid)) continue;
          final vid = 'p${h.pageIndex}:b$bid';
          if (visualRegistry.containsKey(vid)) hVisualIds.add(vid);
        }
      } else {
        // 匿名启发式条目：全部 blockIds 视为 visual。
        for (final bid in h.blockIds) {
          final vid = 'p${h.pageIndex}:b$bid';
          if (visualRegistry.containsKey(vid)) hVisualIds.add(vid);
        }
      }

      final claimedByAi = hVisualIds.where(aiClaimedVisuals.contains).toList();
      final captionClaimed = cid != null && aiClaimedCaptions.contains(cid);

      if (captionClaimed) {
        // 启发式条目的 caption 被 AI 接管 → 丢弃整条；未被 AI 认领的 visual 保留为匿名。
        final unclaimed = hVisualIds.where(
          (v) => !aiClaimedVisuals.contains(v),
        );
        for (final vid in unclaimed) {
          cropRequests.add(_anonymousCropRequest(vid, visualRegistry));
        }
        continue;
      }

      if (claimedByAi.isNotEmpty) {
        // caption 未被 AI 接管，但部分 visual 被 AI 认领 → 用剩余 visual 重建。
        final remaining = hVisualIds.where(
          (v) => !aiClaimedVisuals.contains(v),
        );
        if (remaining.isEmpty) {
          // 所有 visual 被认领，caption 无 visual → 有意丢弃旧 caption（不放回
          // Outline）。visual 不在此分支重建，而是由后续匿名 AI figure /
          // uncaptionedVisualIds 的 cropRequest 独立保留，避免把 caption
          // 强行并入匿名 visual。
          continue;
        }
        cropRequests.add(
          _rebuildHeuristicCropRequest(
            capRef,
            remaining.toList(),
            visualRegistry,
          ),
        );
        continue;
      }

      // 未触碰 → 原样保留。
      keptHeuristic.add(h);
    }

    // AI figures → 裁剪请求。跨页同 caption 的 visual（无法与主页拼成一张图）
    // 回退为匿名条目保留，避免数据丢失。
    for (final f in result.figures) {
      cropRequests.addAll(
        _aiFigureCropRequests(f, captionRegistry, visualRegistry),
      );
    }

    // uncaptioned_visuals → 匿名裁剪请求。
    for (final vid in result.uncaptionedVisualIds) {
      cropRequests.add(_anonymousCropRequest(vid, visualRegistry));
    }

    return MergePlan(cropRequests: cropRequests, keptHeuristic: keptHeuristic);
  }

  /// 启发式条目按 captionName + 页邻近匹配 caption_id。无匹配返回 null（匿名）。
  static List<String?> _matchHeuristicCaptions(
    List<FigureManifestEntry> heuristic,
    Map<String, CaptionRef> captionRegistry,
  ) {
    // 按 captionName 索引 caption（容许多个同名，按页排序）。
    final byName = <String, List<CaptionRef>>{};
    for (final ref in captionRegistry.values) {
      final name = ref.info.captionName;
      if (name.isEmpty) continue;
      byName.putIfAbsent(name, () => []).add(ref);
    }
    byName.forEach(
      (_, list) => list.sort((a, b) => a.pageIdx.compareTo(b.pageIdx)),
    );

    final result = <String?>[];
    final used = <String>{};
    for (final h in heuristic) {
      final name = FigureExtractService.instance.extractCaptionName(
        h.captionText,
      );
      final candidates = byName[name];
      if (name.isEmpty || candidates == null || candidates.isEmpty) {
        result.add(null);
        continue;
      }
      // 最近页匹配，未用过的优先。
      CaptionRef? best;
      var bestDist = 1 << 30;
      for (final ref in candidates) {
        if (used.contains(ref.id)) continue;
        final d = (ref.pageIdx - h.pageIndex).abs();
        if (d < bestDist) {
          bestDist = d;
          best = ref;
        }
      }
      if (best != null) {
        used.add(best.id);
        result.add(best.id);
      } else {
        result.add(null);
      }
    }
    return result;
  }

  /// AI figure → FigureCropRequest 列表。
  ///
  /// 同页多块：一个 caption 的所有 visual 在同一页 → 全部进一个 request →
  /// `computeMergedBbox` 取 `_Bbox.union` + caption-anchored 扩展 → 一张大图。
  ///
  /// 跨页同 caption：一张 PNG 无法跨两页，主页（caption 页优先，否则 visual 最多的页）
  /// 产带 caption 的主图；其余页的 visual 各产一条匿名条目保留（零数据丢失）。
  /// 未来若需跨页拼接成单图，在此处改为多页渲染 + 纵向拼接。
  static List<FigureCropRequest> _aiFigureCropRequests(
    AiFigure f,
    Map<String, CaptionRef> captionRegistry,
    Map<String, VisualRef> visualRegistry,
  ) {
    final visuals = f.visualIds
        .map((v) => visualRegistry[v])
        .whereType<VisualRef>()
        .toList();
    if (visuals.isEmpty) return const [];
    final capRef = f.captionId == null ? null : captionRegistry[f.captionId];
    final byPage = <int, List<VisualRef>>{};
    for (final v in visuals) {
      byPage.putIfAbsent(v.pageIdx, () => []).add(v);
    }
    final pageIndex = (capRef != null && byPage.containsKey(capRef.pageIdx))
        ? capRef.pageIdx
        : (byPage.entries
              .reduce((a, b) => a.value.length >= b.value.length ? a : b)
              .key);
    final pageVisuals = byPage[pageIndex]!;

    final out = <FigureCropRequest>[
      FigureCropRequest(
        pageIndex: pageIndex,
        visualBlocks: [for (final v in pageVisuals) v.block],
        captionBlockId: capRef?.info.blockId,
        captionPageIndex: capRef?.pageIdx,
        captionText: capRef?.info.text ?? '',
        captionBbox: capRef?.info.bbox,
        continuationBlockIds: capRef?.info.continuationBlockIds ?? const [],
        kind: f.kind,
        pairMethod: 'ai_fix',
        captionSource: capRef?.info.source.name ?? 'none',
      ),
    ];
    // 跨页 spillover → 匿名条目（每页一条，合并该页所有 visual）。
    for (final entry in byPage.entries) {
      if (entry.key == pageIndex) continue;
      out.add(
        FigureCropRequest(
          pageIndex: entry.key,
          visualBlocks: [for (final v in entry.value) v.block],
          captionBlockId: null,
          captionPageIndex: null,
          captionText: '',
          captionBbox: null,
          continuationBlockIds: const [],
          kind: _visualKind(entry.value),
          pairMethod: 'ai_cross_page',
          captionSource: 'none',
        ),
      );
    }
    return out;
  }

  /// 重建被部分认领的启发式条目（caption 保留 + 剩余 visual）。
  static FigureCropRequest _rebuildHeuristicCropRequest(
    CaptionRef? capRef,
    List<String> remainingVisualIds,
    Map<String, VisualRef> visualRegistry,
  ) {
    final visuals = remainingVisualIds
        .map((v) => visualRegistry[v])
        .whereType<VisualRef>()
        .toList();
    final byPage = <int, List<VisualRef>>{};
    for (final v in visuals) {
      byPage.putIfAbsent(v.pageIdx, () => []).add(v);
    }
    final pageIndex = (capRef != null && byPage.containsKey(capRef.pageIdx))
        ? capRef.pageIdx
        : (byPage.entries
              .reduce((a, b) => a.value.length >= b.value.length ? a : b)
              .key);
    final pageVisuals = byPage[pageIndex]!;
    return FigureCropRequest(
      pageIndex: pageIndex,
      visualBlocks: [for (final v in pageVisuals) v.block],
      captionBlockId: capRef?.info.blockId,
      captionPageIndex: capRef?.pageIdx,
      captionText: capRef?.info.text ?? '',
      captionBbox: capRef?.info.bbox,
      continuationBlockIds: capRef?.info.continuationBlockIds ?? const [],
      kind: capRef == null
          ? _visualKind(pageVisuals)
          : FigureExtractService.instance.classifyKind(capRef.info.text),
      pairMethod: 'ai_fix_reduced',
      captionSource: capRef?.info.source.name ?? 'none',
    );
  }

  /// 单 visual → 匿名 FigureCropRequest。
  static FigureCropRequest _anonymousCropRequest(
    String visualId,
    Map<String, VisualRef> visualRegistry,
  ) {
    final ref = visualRegistry[visualId]!;
    return FigureCropRequest(
      pageIndex: ref.pageIdx,
      visualBlocks: [ref.block],
      captionBlockId: null,
      captionPageIndex: null,
      captionText: '',
      captionBbox: null,
      continuationBlockIds: const [],
      kind: _visualKind([ref]),
      pairMethod: 'ai_visual_only',
      captionSource: 'none',
    );
  }

  static String _visualKind(List<VisualRef> refs) {
    if (refs.any((r) => r.block.blockLabel == 'table')) return 'table';
    if (refs.any((r) => r.block.blockLabel == 'chart')) return 'chart';
    return 'figure';
  }
}

/// parseAndValidate 内部中间态。
class _ParsedFigure {
  final String? captionId;
  final List<String> visualIds;
  final String? kind;
  final bool orphan;
  const _ParsedFigure({
    required this.captionId,
    required this.visualIds,
    required this.kind,
    required this.orphan,
  });
}
