import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../utils/doc_paths.dart';
import 'pdf_process_lock.dart';

// ─── 公开数据模型 ─────────────────────────────────────────

/// 版面解析 API 返回的单个 block
class LayoutBlock {
  final String blockId;
  final String blockLabel;

  /// [left, top, right, bottom]，坐标基于 API zoom = 2.0（144 DPI）
  final List<double> blockBbox;
  final String blockContent;

  const LayoutBlock({
    required this.blockId,
    required this.blockLabel,
    required this.blockBbox,
    required this.blockContent,
  });

  factory LayoutBlock.fromJson(Map<String, dynamic> json) {
    final bbox = (json['block_bbox'] as List<dynamic>)
        .map((v) => (v as num).toDouble())
        .toList();
    return LayoutBlock(
      blockId: json['block_id']?.toString() ?? '',
      blockLabel: json['block_label'] as String? ?? '',
      blockBbox: bbox,
      blockContent: json['block_content'] as String? ?? '',
    );
  }
}

/// 一个检测到的 figure 区域（caption + 视觉块 + 子图注 block 的集合）
class FigureSegment {
  final int pageIndex;
  final List<LayoutBlock> blocks;
  final String captionText;
  final String captionName;

  const FigureSegment({
    required this.pageIndex,
    required this.blocks,
    required this.captionText,
    required this.captionName,
  });
}

/// manifest 中的一条记录,持久化到 figures.json
class FigureManifestEntry {
  final String imagePath;
  final String captionText;
  final int pageIndex;
  final List<String> blockIds;

  const FigureManifestEntry({
    required this.imagePath,
    required this.captionText,
    required this.pageIndex,
    required this.blockIds,
  });

  Map<String, dynamic> toJson() => {
        'img': imagePath,
        'figure_title': captionText,
        'page_idx': pageIndex,
        'block_ids': blockIds,
      };

  factory FigureManifestEntry.fromJson(Map<String, dynamic> json) {
    return FigureManifestEntry(
      imagePath: json['img'] as String,
      captionText: json['figure_title'] as String,
      pageIndex: json['page_idx'] as int,
      blockIds: (json['block_ids'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class FigureExtractResult {
  final String outputDir;
  final List<FigureManifestEntry> entries;
  const FigureExtractResult({required this.outputDir, required this.entries});
}

// ─── 内部数据 ────────────────────────────────────────────

/// bbox 工具类，避免到处手写 `[0] [1] [2] [3]`
class _Bbox {
  const _Bbox(this.left, this.top, this.right, this.bottom);

  final double left, top, right, bottom;

  factory _Bbox.fromBlock(LayoutBlock b) => _Bbox(
        b.blockBbox[0],
        b.blockBbox[1],
        b.blockBbox[2],
        b.blockBbox[3],
      );

  factory _Bbox.union(Iterable<LayoutBlock> blocks) {
    var l = double.infinity, t = double.infinity;
    var r = double.negativeInfinity, b = double.negativeInfinity;
    var any = false;
    for (final blk in blocks) {
      any = true;
      final box = _Bbox.fromBlock(blk);
      if (box.left < l) l = box.left;
      if (box.top < t) t = box.top;
      if (box.right > r) r = box.right;
      if (box.bottom > b) b = box.bottom;
    }
    return any ? _Bbox(l, t, r, b) : const _Bbox(0, 0, 0, 0);
  }

  /// 两个 bbox 的最近距离(矩形外距,重叠时为 0)
  double gapTo(_Bbox o) {
    final dx = (left > o.right)
        ? left - o.right
        : (o.left > right ? o.left - right : 0.0);
    final dy = (top > o.bottom)
        ? top - o.bottom
        : (o.top > bottom ? o.top - bottom : 0.0);
    return math.sqrt(dx * dx + dy * dy);
  }

  double get diagonal {
    final w = right - left, h = bottom - top;
    return math.sqrt(w * w + h * h);
  }

  List<double> toList() => [left, top, right, bottom];
}

/// Stage B1 召回的 caption 候选.可能来自 parsing_res_list 某 block,
/// 也可能仅出现在 markdown 行(此时 bbox/blockId 为 null).
///
/// 命名暗示: 这是"候选",最终是否采纳要等 Stage D 匹配决定.
///
/// 字段 [continuationBlocks] 用于多行 caption 合并: PaddleOCR 偶尔把长 caption
/// 拆成多个相邻 block,本字段记录除 anchor 外的延续行(原 LayoutBlock,保留各自
/// 原始 bbox/content). [text] 已是合并后的完整 caption 文本, [bbox] 已是
/// 全部参与合并 block 的 outer union. 下游 [FigureSegment.blocks] 会把它们
/// 一并带上,markdown 替换时确保不留多余孤行.
class _CaptionCandidate {
  _CaptionCandidate({
    required this.pageIndex,
    required this.text,
    required this.captionName,
    this.bbox,
    this.blockId,
    this.continuationBlocks = const [],
  });

  final int pageIndex;
  final String text;
  final String captionName;
  final _Bbox? bbox;
  final String? blockId;
  final List<LayoutBlock> continuationBlocks;
}

class _PageData {
  _PageData(this.pageIndex, this.blocks, this.markdown);

  final int pageIndex;
  final List<LayoutBlock> blocks;
  final String markdown;
}

/// 视觉块或子图注块,绑定 pageIndex 用于跨页配对
class _FigureBlock {
  _FigureBlock(this.pageIndex, this.block);
  final int pageIndex;
  final LayoutBlock block;
  _Bbox get bbox => _Bbox.fromBlock(block);
}

class _Cluster {
  _Cluster(this.pageIndex, this.blocks)
      : bbox = _Bbox.union(blocks.map((b) => b.block));
  final int pageIndex;
  final List<_FigureBlock> blocks;
  final _Bbox bbox;
}

class _Inventory {
  _Inventory({
    required this.captions,
    required this.figureBlocks,
    required this.pages,
  });

  final List<_CaptionCandidate> captions;
  final List<_FigureBlock> figureBlocks;
  final List<_PageData> pages;
}

/// 页面上一个连续的文字栏区域(单栏论文整页一栏,双栏论文左右两栏).
///
/// caption-anchored region inference 用它做两件事:
///   1. direction inference 时,只看同栏内的 visual blocks 投票.
///   2. 完全漏检场景(无 visual block) 时,作为横向边界兜底.
///
/// 注意:扩展 bbox 时的横向 overlap 判断**仍然用 visualUnion** 横向,
/// column 不参与;这样保留原行为,避免邻栏污染.
class _Column {
  const _Column(this.left, this.right);
  final double left, right;
  double get width => right - left;
}

/// trimCaptionFromRegion 内部使用: 表示从 region 哪一侧收缩.
enum _TrimSide { top, bottom, left, right }

/// figure 相对 caption 的方向. 语义: 该枚举值 = "figure 相对 caption 的位置".
///
///   * [above] — figure 在 caption **上方**. 论文常态 (~80% caption 在下).
///   * [below] — figure 在 caption **下方**. 少数现场 (caption 顶置).
///   * [left]  — figure 在 caption **左侧**. 大 figure + caption 在右侧栏注.
///   * [right] — figure 在 caption **右侧**. 大 figure + caption 在左侧栏注.
///
/// PR-5a 把方向从纵向 2-向扩到 4-向, 让"caption 在大 figure 左右侧"的版面
/// 也能被正确识别 (PaddleOCR-VL 把这种 caption 误判为别的 label 的概率很高).
enum _FigureDirection { above, below, left, right }

// ─── 服务 ───────────────────────────────────────────────

/// 从 PaddleOCR 版面解析 JSON + 原始 PDF 中提取 figure 区域。
///
/// 流水线:
///   Stage 0  解析 JSON → [_PageData] (blocks + markdown)
///   Stage 1  Inventory: 收集所有 caption mention + figure block
///   Stage 2  Pair: 视觉块聚类,每簇配最近 caption(跨页 ±1 兜底,孤儿匿名兜底)
///   Stage 3  Crop & write
///
/// 使用前必须调用 [init] 加载 caption 配置。
class FigureExtractService {
  FigureExtractService._();
  static final FigureExtractService instance = FigureExtractService._();

  // ─── 常量 ─────────────────────────────────────────────

  /// figure 相关的 block label——会被聚类成视觉簇
  static const figureLabels = {
    'figure_title',
    'image',
    'chart',
    'table',
    'vision_footnote',
  };

  /// API 返回 bbox 所基于的 zoom 级别（144 DPI）
  static const apiZoom = 2.0;

  /// 裁剪渲染时使用的 zoom 级别（216 DPI，比 API 高 50%）
  static const renderZoom = 3.0;

  /// caption 多行合并时,延续行不能是这些视觉 label——它们绝不是 caption 文本.
  /// (PR-2 把 caption 召回从 label 白名单改为内容匹配,但合并扫描时仍要排除视觉块)
  static const _captionMergeExcludeLabels = {
    'image',
    'chart',
    'table',
  };

  /// figure_title 子标签(如 `A`、`(b)`)的最大长度,超过视为正文误标
  static const _maxSubLabelLength = 30;

  /// 多行 caption 合并: 延续行与上一行的最大纵向 gap 占 anchor 行高的比例.
  /// 超过此比例则视为非延续 (caption 与下方段落已分开).
  static const _continuationGapRatio = 0.8;

  /// 多行合并 gap 阈值的最小绝对值 (API 坐标系 144 DPI).
  /// 防止 caption 块高度极小(如单字符)时阈值塌成 0.
  static const _continuationGapMin = 15.0;

  /// 多行合并要求延续行与 anchor 横向 overlap ≥ 此比例 (按 anchor 宽度).
  /// 偏低 (≥0.5) 容忍 caption 延续行轻微缩排; 太低则容易吃入邻栏文字.
  static const _continuationOverlapRatio = 0.6;

  /// 视觉簇配 caption 的距离阈值占整页对角线的比例
  static const _captionMatchRatio = 0.5;

  /// 视觉块聚类的最大允许间距占整页对角线的比例(再 clamp 到固定范围)
  static const _clusterGapRatio = 0.025;
  static const _minClusterGap = 24.0;
  static const _maxClusterGap = 56.0;

  // ─── caption 配置(从 assets 加载) ────────────────────

  late final RegExp _mainCaptionRe;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    final raw = await rootBundle.loadString(
      'assets/config/caption_patterns.json',
    );
    final conf = jsonDecode(raw) as Map<String, dynamic>;

    final prefixes = (conf['prefixes'] as List<dynamic>)
        .map((e) => e as String)
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    final prefixGroup = prefixes.map(RegExp.escape).join('|');
    _mainCaptionRe = RegExp(
      '^(?:$prefixGroup)${conf['number_pattern']}${conf['suffix_pattern']}',
      caseSensitive: false,
    );
    _initialized = true;
  }

  /// 从 caption 文本提取文件名标识(如 "Figure 1." → "Figure_1")
  String _extractCaptionName(String text) {
    final m = _mainCaptionRe.firstMatch(text.trim());
    if (m == null) return '';
    return m.group(0)!.replaceAll('.', '').replaceAll(' ', '_').trim();
  }

  static final _tableCaptionRe = RegExp(
    r'^(?:table|tab|tabelle|tabla|cuadro|таблица|表|표|bảng)',
    caseSensitive: false,
  );

  bool _isTableCaption(_CaptionCandidate c) => _tableCaptionRe.hasMatch(c.text);

  // ─── Stage 0: 解析 ────────────────────────────────────

  static List<_PageData> _parsePages(String jsonContent) {
    try {
      final list = jsonDecode(jsonContent) as List<dynamic>;
      return [
        for (var i = 0; i < list.length; i++)
          _parsePage(list[i] as Map<String, dynamic>, i),
      ];
    } catch (e) {
      debugPrint('[FigureExtract] 解析 JSON 失败: $e');
      return const [];
    }
  }

  static _PageData _parsePage(Map<String, dynamic> page, int index) {
    final blockList =
        ((page['prunedResult'] as Map<String, dynamic>?)?['parsing_res_list']
                as List<dynamic>?) ??
            const [];
    final blocks = blockList
        .map((b) => LayoutBlock.fromJson(b as Map<String, dynamic>))
        .toList();
    final markdown =
        ((page['markdown'] as Map<String, dynamic>?)?['text'] as String?) ??
            '';
    return _PageData(index, blocks, markdown);
  }

  // ─── Stage 1: Inventory ───────────────────────────────

  /// Stage B: 收集 caption + figure 候选,聚合为 inventory.
  ///
  /// 拆成两个独立 collector 是 PR-1 重构的核心动作之一:
  /// caption 召回与 figure 召回从此互相解耦,后续 PR 可以独立扩展 caption 来源
  /// (markdown 行→ PDF 文本流 → 多行合并) 或 figure 来源 (PDF 图形元素聚类),
  /// 不会引入串扰.
  _Inventory _buildInventory(List<_PageData> pages) {
    final captions = <_CaptionCandidate>[];
    final figureBlocks = <_FigureBlock>[];

    for (final page in pages) {
      final pageCaptions = _collectCaptionCandidates(page);
      captions.addAll(pageCaptions);

      // 排除集合 = anchor blockId ∪ 所有 continuation block ids.
      // 后者由多行 caption 合并产生, 同样不应被 figure 召回当成视觉块/子标签.
      final captionBlockIds = <String>{};
      for (final c in pageCaptions) {
        if (c.blockId != null) captionBlockIds.add(c.blockId!);
        for (final cont in c.continuationBlocks) {
          captionBlockIds.add(cont.blockId);
        }
      }
      figureBlocks.addAll(_collectFigureCandidates(page, captionBlockIds));
    }

    return _Inventory(
      captions: captions,
      figureBlocks: figureBlocks,
      pages: pages,
    );
  }

  /// Stage B1: 召回单页所有 caption 候选.
  ///
  /// 三个 Phase:
  ///   Phase 1 (anchor 识别): 遍历 parsing_res_list, 任意 label 的 block
  ///     只要内容匹配 [_mainCaptionRe] 就是 anchor. 同 captionName 选内容最长.
  ///     ★ PR-2 放宽: 去掉 label 白名单——PaddleOCR 把 figure_title 错标为
  ///       paragraph_title / image_caption / 其他未知 label 时仍能召回.
  ///   Phase 2 (多行合并): 对每个 anchor, 沿 page.blocks 顺序向下扫描延续行,
  ///     吸收同 column、纵向相邻、内容不构成新 caption 的 block.合并后 text
  ///     拼接、bbox 取 outer union, continuation block 列表交给下游用.
  ///   Phase 3 (markdown 兜底): markdown.text 行中匹配正则但 parsing_res_list
  ///     完全漏检的 caption 名, 不做合并, 仅以单行候选补入.
  List<_CaptionCandidate> _collectCaptionCandidates(_PageData page) {
    // Phase 1: 识别 anchor — 任意 label, 仅看内容是否匹配主标题正则.
    // 同 captionName 选内容最长的 block (保留它在 page.blocks 中的索引,
    // Phase 2 从该索引向下扫描延续行).
    final anchorByName = <String, ({int index, LayoutBlock block})>{};
    for (var i = 0; i < page.blocks.length; i++) {
      final b = page.blocks[i];
      final content = b.blockContent.trim();
      if (content.isEmpty) continue;
      if (!_mainCaptionRe.hasMatch(content)) continue;

      final name = _extractCaptionName(content);
      if (name.isEmpty) continue;

      final existing = anchorByName[name];
      if (existing == null ||
          content.length > existing.block.blockContent.trim().length) {
        anchorByName[name] = (index: i, block: b);
      }
    }

    // Phase 2: 对每个 anchor 吸收延续行.
    final candidates = <_CaptionCandidate>[];
    for (final pick in anchorByName.values) {
      final continuations = _scanCaptionContinuation(page, pick.index);
      final anchor = pick.block;
      final anchorContent = anchor.blockContent.trim();
      final mergedText = continuations.isEmpty
          ? anchorContent
          : [
              anchorContent,
              for (final c in continuations) c.blockContent.trim()
            ].join(' ');
      final mergedBbox = continuations.isEmpty
          ? _Bbox.fromBlock(anchor)
          : _Bbox.union([anchor, ...continuations]);

      candidates.add(_CaptionCandidate(
        pageIndex: page.pageIndex,
        text: mergedText,
        captionName: _extractCaptionName(anchorContent),
        bbox: mergedBbox,
        blockId: anchor.blockId,
        continuationBlocks: continuations,
      ));
    }

    // Phase 3: markdown 行兜底 (parsing_res_list 完全漏检时).
    final knownNames = candidates.map((c) => c.captionName).toSet();
    if (page.markdown.isNotEmpty) {
      for (final raw in page.markdown.split('\n')) {
        final t = raw.trim();
        if (t.isEmpty || !_mainCaptionRe.hasMatch(t)) continue;
        final name = _extractCaptionName(t);
        if (name.isEmpty || knownNames.contains(name)) continue;
        knownNames.add(name);
        candidates.add(_CaptionCandidate(
          pageIndex: page.pageIndex,
          text: t,
          captionName: name,
        ));
      }
    }

    return candidates;
  }

  /// 从 anchor block 之后扫描连续的延续行, 用于多行 caption 合并.
  ///
  /// 终止条件 (任一满足即停):
  ///   1. **遇到新 caption** — block 内容匹配 [_mainCaptionRe] (这是最强护栏:
  ///      即使 Figure 1 / Figure 2 caption 紧邻, 也不会串吃).
  ///   2. **跨越视觉块** — block 是 image/chart/table (caption 不会继续到这种 block 之后).
  ///   3. **纵向 gap 过大** — gap > max(anchorHeight * 0.8, 15px).
  ///   4. **横向 overlap 不足** — 候选块与 anchor 横向 overlap < 60% (邻栏文字).
  ///   5. **越过 page.blocks 末尾**.
  ///
  /// 满足 (2)/(3)/(4) 时跳过该 block 继续扫描——可能 PaddleOCR 在 caption 中间
  /// 插入了不相关的 vision_footnote 等; 不应中断合并扫描. 但 (1) 是硬终止.
  /// 实际为了简单, 我们对 (2) 直接 break, (3)/(4) 也 break, 只有 (1) 单独标记.
  /// 选择 break 是因为延续行在 PaddleOCR 视角通常是紧邻的, 一旦中断就不再续.
  List<LayoutBlock> _scanCaptionContinuation(_PageData page, int anchorIndex) {
    final anchor = page.blocks[anchorIndex];
    final anchorBbox = _Bbox.fromBlock(anchor);
    final anchorHeight = anchorBbox.bottom - anchorBbox.top;
    final anchorWidth = anchorBbox.right - anchorBbox.left;
    if (anchorHeight <= 0 || anchorWidth <= 0) return const [];

    final maxGap = math.max(
      anchorHeight * _continuationGapRatio,
      _continuationGapMin,
    );

    final result = <LayoutBlock>[];
    var lastBottom = anchorBbox.bottom;

    for (var j = anchorIndex + 1; j < page.blocks.length; j++) {
      final cand = page.blocks[j];
      final candContent = cand.blockContent.trim();

      // 硬终止: 新 caption 出现 — 即使紧邻也不能吃
      if (_mainCaptionRe.hasMatch(candContent)) break;
      // 终止: 视觉块阻断
      if (_captionMergeExcludeLabels.contains(cand.blockLabel)) break;

      final cbox = _Bbox.fromBlock(cand);
      // 终止: 纵向 gap 过大
      final gap = cbox.top - lastBottom;
      if (gap < 0 || gap > maxGap) break;

      // 终止: 横向 overlap 不足 (避免吃入邻栏)
      final overlap = math.max(
        0.0,
        math.min(anchorBbox.right, cbox.right) -
            math.max(anchorBbox.left, cbox.left),
      );
      if (overlap / anchorWidth < _continuationOverlapRatio) break;

      // 跳过空内容 (PaddleOCR 偶有空 block)
      if (candContent.isEmpty) {
        lastBottom = cbox.bottom;
        continue;
      }

      result.add(cand);
      lastBottom = cbox.bottom;
    }

    return result;
  }

  /// Stage B2: 召回单页所有 figure 视觉/子图注 block 候选.
  ///
  /// 跳过 [excludeBlockIds] 中的 block (这些 block 已被识别为 caption,
  /// 不应同时作为 figure 视觉块).
  ///
  /// 当前 figure_title label 的 block 若 [excludeBlockIds] 不含且内容
  /// 长度 ≤ `_maxSubLabelLength`,被视为子标签 ((a)/(b) 这类),保留;
  /// 超长的视为正文噪声,跳过.
  ///
  /// PR-6 会在此处加: PDF 图形元素聚类作为第二条 figure 候选源.
  List<_FigureBlock> _collectFigureCandidates(
    _PageData page,
    Set<String> excludeBlockIds,
  ) {
    final result = <_FigureBlock>[];
    for (final b in page.blocks) {
      if (!figureLabels.contains(b.blockLabel)) continue;
      if (excludeBlockIds.contains(b.blockId)) continue;
      // figure_title 但内容过长 → 正文噪声(否则 (a)/(b) 这类短标签会被错误剔除)
      if (b.blockLabel == 'figure_title' &&
          b.blockContent.trim().length > _maxSubLabelLength) {
        continue;
      }
      result.add(_FigureBlock(page.pageIndex, b));
    }
    return result;
  }

  // ─── Stage 2: 配对 ────────────────────────────────────

  /// 配对策略(按优先级):
  ///   1. 视觉块按空间相邻聚成簇,每簇找同页最近 caption.
  ///   2. 同页 caption 未配上 + ±1 页 cluster 未配上 → 跨页双向唯一配对.
  ///   3. 仍剩的 cluster 含 image/chart → 匿名 figure(若有同页未占用 markdown
  ///      caption 也带上文字).
  List<FigureSegment> _pair(_Inventory inv) {
    final pageDiagonals = <int, double>{
      for (final page in inv.pages)
        page.pageIndex: _pageDiagonal(page.blocks),
    };

    // 视觉块按页聚簇
    final clustersByPage = <int, List<_Cluster>>{};
    final blocksByPage = <int, List<_FigureBlock>>{};
    for (final fb in inv.figureBlocks) {
      blocksByPage.putIfAbsent(fb.pageIndex, () => []).add(fb);
    }
    for (final entry in blocksByPage.entries) {
      final diag = pageDiagonals[entry.key] ?? 0;
      final gap = (diag * _clusterGapRatio)
          .clamp(_minClusterGap, _maxClusterGap)
          .toDouble();
      clustersByPage[entry.key] = _clusterFigureBlocks(
        entry.key,
        entry.value,
        gap,
      );
    }

    final captionsByPage = <int, List<_CaptionCandidate>>{};
    for (final c in inv.captions) {
      captionsByPage.putIfAbsent(c.pageIndex, () => []).add(c);
    }

    final segments = <FigureSegment>[];
    final usedClusters = <_Cluster>{};
    final usedCaptions = <_CaptionCandidate>{};

    // Pass 1: 同页配对——每个 cluster 找同页最近 caption,然后按 caption 合并簇.
    // 多个簇映射到同一 caption(如 Figure_2 的 image + 远处 vision_footnote 被
    // cluster gap 切开) 时,应合并为一个 segment,而不是各起一个 .
    final byCaption = <_CaptionCandidate, List<_Cluster>>{};
    for (final entry in clustersByPage.entries) {
      final pi = entry.key;
      final pageCaptions = captionsByPage[pi] ?? const [];
      final pageDiag = pageDiagonals[pi] ?? 0;
      final threshold = pageDiag * _captionMatchRatio;
      for (final cluster in entry.value) {
        final anchor = _nearestCaption(cluster, pageCaptions, threshold);
        if (anchor == null) continue;
        byCaption.putIfAbsent(anchor, () => []).add(cluster);
      }
    }
    for (final entry in byCaption.entries) {
      final caption = entry.key;
      final merged = entry.value.expand((c) => c.blocks).toList();
      usedCaptions.add(caption);
      for (final c in entry.value) {
        usedClusters.add(c);
      }
      segments.add(_buildSegmentFromBlocks(merged, caption));
    }

    // Pass 2: 跨页 ±1 双向唯一——caption 在 A 页,cluster 在 A±1 页.
    final orphanCaptions =
        inv.captions.where((c) => !usedCaptions.contains(c)).toList();
    final orphanClusters = [
      for (final list in clustersByPage.values)
        ...list.where((c) => !usedClusters.contains(c)),
    ];
    for (final caption in orphanCaptions) {
      final candidates = orphanClusters
          .where((c) => !usedClusters.contains(c))
          .where((c) => (c.pageIndex - caption.pageIndex).abs() == 1)
          .toList();
      if (candidates.length != 1) continue;
      final cluster = candidates.single;

      final reverseHits = orphanCaptions
          .where((c) => (c.pageIndex - cluster.pageIndex).abs() == 1)
          .length;
      if (reverseHits != 1) continue;

      usedClusters.add(cluster);
      usedCaptions.add(caption);
      segments.add(_buildSegmentFromBlocks(cluster.blocks, caption));
      debugPrint(
        '[FigureExtract] cross-page paired: "${caption.captionName}" '
        'page ${caption.pageIndex} ↔ cluster page ${cluster.pageIndex}',
      );
    }

    // Pass 3: 同页晚到 caption 认领——cluster 自己没在 Pass 1 配上 caption,
    // 但同页还有未占用的 figure_title caption 时,把这条 caption 抓过来.
    // 限 image/chart(不含 table)——独立 table 多为侧栏定义框,宁可漏不可错.
    //
    // **不再生成匿名 segment**:没匹配到 figure_title 的视觉簇直接丢弃.
    // (目前临时策略,后续可加 markdown ![](...) 反推 caption 等兜底)
    final claimedNames = segments
        .map((s) => s.captionName)
        .where((n) => n.isNotEmpty)
        .toSet();
    for (final cluster in orphanClusters) {
      if (usedClusters.contains(cluster)) continue;
      final hasVisual = cluster.blocks.any(
        (b) =>
            b.block.blockLabel == 'image' || b.block.blockLabel == 'chart',
      );
      if (!hasVisual) continue;

      _CaptionCandidate? attached;
      for (final c in captionsByPage[cluster.pageIndex] ?? const []) {
        if (usedCaptions.contains(c)) continue;
        if (claimedNames.contains(c.captionName)) continue;
        attached = c;
        break;
      }
      if (attached == null) {
        debugPrint(
          '[FigureExtract] dropped uncaptioned cluster on page '
          '${cluster.pageIndex} (${cluster.blocks.length} blocks)',
        );
        continue;
      }
      usedCaptions.add(attached);
      claimedNames.add(attached.captionName);
      segments.add(_buildSegmentFromBlocks(cluster.blocks, attached));
      debugPrint(
        '[FigureExtract] late-bound caption: "${attached.captionName}" '
        'on page ${cluster.pageIndex}',
      );
    }

    // 按 pageIndex 稳定排序(同页保留插入顺序)
    final tagged = [
      for (var i = 0; i < segments.length; i++) (i, segments[i]),
    ];
    tagged.sort((a, b) {
      final cmp = a.$2.pageIndex.compareTo(b.$2.pageIndex);
      return cmp != 0 ? cmp : a.$1.compareTo(b.$1);
    });
    return [for (final t in tagged) t.$2];
  }

  /// 按邻近距离把 figure block 聚成簇.
  List<_Cluster> _clusterFigureBlocks(
    int pageIndex,
    List<_FigureBlock> blocks,
    double maxGap,
  ) {
    final remaining = List<_FigureBlock>.from(blocks);
    final order = {for (var i = 0; i < blocks.length; i++) blocks[i]: i};
    final clusters = <_Cluster>[];

    while (remaining.isNotEmpty) {
      final cluster = <_FigureBlock>[remaining.removeAt(0)];
      var expanded = true;
      while (expanded) {
        expanded = false;
        for (var i = remaining.length - 1; i >= 0; i--) {
          final cand = remaining[i];
          final touches = cluster.any(
            (b) => b.bbox.gapTo(cand.bbox) <= maxGap,
          );
          if (!touches) continue;
          cluster.add(cand);
          remaining.removeAt(i);
          expanded = true;
        }
      }
      cluster.sort((a, b) => order[a]!.compareTo(order[b]!));
      clusters.add(_Cluster(pageIndex, cluster));
    }
    return clusters;
  }

  /// 在 [candidates] 中找最近 caption(基于 cluster.bbox 到 caption.bbox 的距离).
  /// markdown-only caption(无 bbox) 走"同页且 cluster 找不到其他候选"的兜底.
  _CaptionCandidate? _nearestCaption(
    _Cluster cluster,
    List<_CaptionCandidate> candidates,
    double threshold,
  ) {
    final boxed =
        candidates.where((c) => c.bbox != null).toList();
    final unboxed =
        candidates.where((c) => c.bbox == null).toList();

    // 同类亲和:cluster 全是 table/vision_footnote 时优先 Table N. caption
    final isTableCluster = cluster.blocks.every(
      (b) =>
          b.block.blockLabel == 'table' ||
          b.block.blockLabel == 'vision_footnote',
    );
    final preferred = boxed.where((c) => _isTableCaption(c) == isTableCluster);
    final rest = boxed.where((c) => _isTableCaption(c) != isTableCluster);
    final ordered = [...preferred, ...rest];

    _CaptionCandidate? best;
    var bestGap = double.infinity;
    for (final c in ordered) {
      final gap = cluster.bbox.gapTo(c.bbox!);
      if (gap < bestGap) {
        bestGap = gap;
        best = c;
      }
    }
    if (best != null && bestGap <= threshold) return best;

    // 兜底:同页 markdown-only caption(没 bbox 无法算距离),取第一个
    if (unboxed.isNotEmpty) return unboxed.first;
    return null;
  }

  /// 把若干 figure block + 一个 caption 组装成 FigureSegment.
  ///
  /// caption 若来自 parsing_res_list block,合成对应 LayoutBlock 放在 blocks 头部
  /// (blockBbox 用合并后的 outer union, blockContent 用合并后的完整文本),
  /// 让下游 markdown 替换能按 block_id / 内容前缀找到 caption 行并占住.
  ///
  /// PR-2: caption.continuationBlocks 同样进 blocks (保留各自原始 bbox/content),
  /// 下游 [DocExtractService._planFigureLines] 按内容前缀搜行抹掉它们,
  /// 避免合并的 caption 留下孤行残骸.
  ///
  /// 注: trim 硬契约只识别"label==figure_title 且匹配 _mainCaptionRe"的 caption.
  /// anchor 合成的 LayoutBlock 内容是合并后的完整 caption text → 仍匹配正则,
  /// 其 bbox 已是合并 outer union → trim 自然扣除整个合并区域.
  /// continuation block 内容不匹配正则 → trim 跳过, 不重复扣除 (语义正确).
  FigureSegment _buildSegmentFromBlocks(
    List<_FigureBlock> figureBlocks,
    _CaptionCandidate caption,
  ) {
    final blocks = <LayoutBlock>[];
    final captionAllIds = <String>{};
    if (caption.blockId != null) {
      blocks.add(LayoutBlock(
        blockId: caption.blockId!,
        blockLabel: 'figure_title',
        blockBbox: caption.bbox?.toList() ?? const [0, 0, 0, 0],
        blockContent: caption.text,
      ));
      captionAllIds.add(caption.blockId!);
    }
    for (final cont in caption.continuationBlocks) {
      blocks.add(cont);
      captionAllIds.add(cont.blockId);
    }
    for (final b in figureBlocks) {
      if (captionAllIds.contains(b.block.blockId)) continue;
      blocks.add(b.block);
    }
    return FigureSegment(
      pageIndex:
          figureBlocks.isNotEmpty ? figureBlocks.first.pageIndex : caption.pageIndex,
      blocks: blocks,
      captionText: caption.text,
      captionName: caption.captionName,
    );
  }

  static double _pageDiagonal(List<LayoutBlock> blocks) {
    if (blocks.isEmpty) return 0;
    return _Bbox.union(blocks).diagonal;
  }

  // ─── Stage 3: 裁剪 ─────────────────────────────────────

  /// 计算 segment 的裁剪 bbox.
  ///
  /// **核心思路**: 把 figure 视为 "caption 定义的页面区域",而不是 "已检出
  /// 视觉块的 union". PaddleOCR 检出的 image/chart/table 只作为基础边界 + 信号,
  /// 真正的区域由 caption 在 page geometry 上的位置推断:
  ///
  ///   1. 找 caption 所在 column (单/双栏)
  ///   2. 推断 figure 在 caption 上方还是下方 (基于同 column 内视觉块分布)
  ///   3. 沿该方向找最近 "stable blocker"(正文段落 / 另一 caption / 页眉页脚),
  ///      把 bbox 的对应边扩展到 blocker.bottom (或 .top) + 小 margin
  ///
  /// 这种做法对 PaddleOCR 的视觉块完整性不敏感——即使部分子图被漏检,
  /// 只要 caption 还在,region 就能正确锚定.
  ///
  /// 触发双门控避免误伤紧邻段落: 扩展量 gap 必须满足
  /// `gap ≥ _missedVisualGapAbs` **且** `gap / visualHeight ≥ _missedVisualGapRatio`.
  ///
  /// 不传 [pageBlocks] 或 segment 内无 caption (匿名 segment) 时退化为
  /// legacy "visual union" 路径.
  ///
  /// **硬契约**: 返回的 region 不能与 segment 中任何 main caption 的 bbox 相交.
  /// 所有 return 路径在最后统一过 [trimCaptionFromRegion] 强制实现此契约.
  @visibleForTesting
  List<double> computeMergedBbox(
    List<LayoutBlock> segment, {
    List<LayoutBlock>? pageBlocks,
  }) {
    final visuals = segment.where(_isVisualBlock).toList();

    // 早返路径: 无 pageBlocks / 无 visuals / 无 caption → legacy "visual union".
    if (pageBlocks == null || pageBlocks.isEmpty || visuals.isEmpty) {
      final baseBbox = visuals.isNotEmpty
          ? _Bbox.union(visuals).toList()
          : _legacyFallbackBbox(segment);
      return trimCaptionFromRegion(baseBbox, segment);
    }
    final caption = _findSegmentCaption(segment);
    if (caption == null) {
      return trimCaptionFromRegion(_Bbox.union(visuals).toList(), segment);
    }

    // direction-aware baseBbox.
    //
    // vision_footnote 在 PaddleOCR 视角有两种语义:
    //   (1) caption 下方说明文字 "(B) 2-photon optical path." — 不属于 figure 区域
    //   (2) figure 内部子图位置标签 "(a)/(b)" — 属于 figure 区域 (PaddleOCR 漏检
    //       image 时, 这是唯一能锚定子图位置的 block)
    // 判据: vf 与 figure 同 direction 侧 (相对 caption) → 角色 (2), 并入 baseBbox;
    //       反侧 → 角色 (1), 排除 (保持现有行为).
    final column = _detectColumnFor(caption, pageBlocks);
    final direction = _inferFigureDirection(caption, column, pageBlocks);
    final relevantVfs = segment
        .where((b) =>
            b.blockLabel == 'vision_footnote' &&
            _isVisionFootnoteInFigureRegion(b, caption, direction))
        .toList();
    final baseBbox = relevantVfs.isEmpty
        ? _Bbox.union(visuals).toList()
        : _Bbox.union([...visuals, ...relevantVfs]).toList();

    final region = _inferRegionFromCaption(
      caption: caption,
      baseBbox: baseBbox,
      segment: segment,
      pageBlocks: pageBlocks,
      direction: direction,
    );
    return trimCaptionFromRegion(region, segment);
  }

  /// 判断 vision_footnote 是否属于 figure 内部 (而非 caption 下方说明文字).
  ///
  /// 判据: vf 与 figure 在 [direction] 同侧.
  ///   * `above` (figure 在 caption 上方) → vf.bottom ≤ caption.top
  ///   * `below` (figure 在 caption 下方) → vf.top ≥ caption.bottom
  ///   * `left`  (figure 在 caption 左侧) → vf.right ≤ caption.left
  ///   * `right` (figure 在 caption 右侧) → vf.left ≥ caption.right
  ///
  /// 反侧的 vision_footnote (与 caption 同侧, 远离 figure) 视为 caption 注脚,
  /// 不参与 figure baseBbox.
  bool _isVisionFootnoteInFigureRegion(
    LayoutBlock vf,
    LayoutBlock caption,
    _FigureDirection direction,
  ) {
    final v = _Bbox.fromBlock(vf);
    final c = _Bbox.fromBlock(caption);
    return switch (direction) {
      _FigureDirection.above => v.bottom <= c.top,
      _FigureDirection.below => v.top >= c.bottom,
      _FigureDirection.left => v.right <= c.left,
      _FigureDirection.right => v.left >= c.right,
    };
  }

  /// 硬契约: 把 [region] 收缩到与 [segment] 内任何 main caption 的 bbox 都不相交.
  ///
  /// "main caption" = label==`figure_title` **且** 内容匹配 [_mainCaptionRe].
  /// 子标签 ((a)/(b) 这类短 figure_title) 不被视为 main caption,保留在 region
  /// 内——它们是 figure 内部结构的一部分.
  ///
  /// PR-5a: 算法从"上下二选一"扩展为"4 方向最小损失". 对每个与 region 相交的
  /// caption, 计算从 top/bottom/left/right 4 个方向 trim 后各自损失的面积,
  /// 选损失最小的方向. 这能正确处理 caption 横向重叠 region 的场景 (大 figure
  /// 左右侧 caption), 旧"纵向二选一"在这些场景下会结构性错位.
  ///
  /// 注: 此算法对 PR-1 的 top/bottom 收缩测试 backward compatible —— caption
  /// 在 region 上半时 trim top 损失最小, 下半时 trim bottom 损失最小, 行为
  /// 与旧"二选一"一致.
  ///
  /// 当前路径下大多数情况 region 与 caption 不相交 (因为 baseBbox 由 `_isVisualBlock`
  /// 过滤掉了 figure_title, 扩展方向也避开 caption), 此函数是 no-op. 它的价值
  /// 在于把"裁剪框无 caption"这条不变量提升为可被测试 enforce 的硬契约.
  @visibleForTesting
  List<double> trimCaptionFromRegion(
    List<double> region,
    List<LayoutBlock> segment,
  ) {
    var left = region[0], top = region[1], right = region[2], bottom = region[3];

    for (final b in segment) {
      if (b.blockLabel != 'figure_title') continue;
      if (!_mainCaptionRe.hasMatch(b.blockContent.trim())) continue;

      final cap = _Bbox.fromBlock(b);
      // 不相交直接跳过 (绝大多数路径走这里)
      if (cap.bottom <= top || cap.top >= bottom) continue;
      if (cap.right <= left || cap.left >= right) continue;

      // 4 方向 trim 后的损失面积 (近似: 用 region 宽/高乘以"被吃进的边距").
      // 注: 这是上界估算 (没扣 caption 在 region 外的部分), 但对所有 4 方向
      // 一致, 因此用作相对比较选最优方向是正确的.
      final w = right - left;
      final h = bottom - top;
      final lossTop = w * (cap.bottom - top);
      final lossBottom = w * (bottom - cap.top);
      final lossLeft = h * (cap.right - left);
      final lossRight = h * (right - cap.left);

      // 选损失最小方向
      var bestLoss = lossTop;
      var bestSide = _TrimSide.top;
      if (lossBottom < bestLoss) {
        bestLoss = lossBottom;
        bestSide = _TrimSide.bottom;
      }
      if (lossLeft < bestLoss) {
        bestLoss = lossLeft;
        bestSide = _TrimSide.left;
      }
      if (lossRight < bestLoss) {
        bestSide = _TrimSide.right;
      }

      switch (bestSide) {
        case _TrimSide.top:
          final newTop = cap.bottom + _captionGap;
          if (newTop < bottom) top = newTop;
        case _TrimSide.bottom:
          final newBottom = cap.top - _captionGap;
          if (newBottom > top) bottom = newBottom;
        case _TrimSide.left:
          final newLeft = cap.right + _captionGap;
          if (newLeft < right) left = newLeft;
        case _TrimSide.right:
          final newRight = cap.left - _captionGap;
          if (newRight > left) right = newRight;
      }
    }
    return [left, top, right, bottom];
  }

  /// caption ↔ region 的最小分隔间距 (API 坐标系 144 DPI).
  /// 数值与 [_missedVisualMargin] 一致, 保证 caption 边界与 stable blocker 边界
  /// 视觉对齐. 改动两者中任一个时应同时改另一个.
  static const _captionGap = 8.0;

  /// 视觉内容 block (figure 真正的可视部分).
  static bool _isVisualBlock(LayoutBlock b) =>
      b.blockLabel == 'image' ||
      b.blockLabel == 'chart' ||
      b.blockLabel == 'table';

  /// "稳定阻塞" labels——这些 block 出现在 caption 同 column 一侧意味着
  /// figure 区域不应跨过它. **不包括 figure_title / vision_footnote / 视觉块**,
  /// 它们要么是 figure 本身的一部分,要么是另一 figure 的内部细节.
  static const _stableBlockerLabels = {
    'text',
    'paragraph_title',
    'abstract',
    'header',
    'footer',
    'header_image',
    'aside_text',
    'number',
    'formula',
  };

  bool _isStableBlocker(LayoutBlock b) {
    if (_stableBlockerLabels.contains(b.blockLabel)) return true;
    // 另一个 figure 的主 caption (长 figure_title) 也阻塞,但短子标签
    // ("(A)"/"(b)" 这类) 不算——它们本身就是 figure 内部.
    if (b.blockLabel == 'figure_title' &&
        _mainCaptionRe.hasMatch(b.blockContent.trim())) {
      return true;
    }
    return false;
  }

  /// 在 segment 中找出 main caption (label==figure_title + 匹配主标题正则).
  LayoutBlock? _findSegmentCaption(List<LayoutBlock> segment) {
    for (final b in segment) {
      if (b.blockLabel == 'figure_title' &&
          _mainCaptionRe.hasMatch(b.blockContent.trim())) {
        return b;
      }
    }
    return null;
  }

  /// 完全无视觉块时的 fallback bbox:排除 caption 和 vision_footnote 的 union.
  List<double> _legacyFallbackBbox(List<LayoutBlock> segment) {
    final contents = segment
        .where((b) =>
            !_mainCaptionRe.hasMatch(b.blockContent.trim()) &&
            b.blockLabel != 'vision_footnote')
        .toList();
    final effective = contents.isNotEmpty ? contents : segment;
    return _Bbox.union(effective).toList();
  }

  /// 双重门控阈值——扩展量必须同时满足.阈值基于 API 坐标系(144 DPI).
  /// 绝对值过滤微小扩展引入的 noise; 比例过滤大 figure 紧贴小段落场景.
  static const _missedVisualGapAbs = 80.0;
  static const _missedVisualGapRatio = 0.30;

  /// 扩展后留给 blocker 的安全 margin (API 坐标系).
  static const _missedVisualMargin = 8.0;

  /// 双栏判定要求左右两栏各自至少有这么多 text-like blocks.少于则视为单栏.
  static const _doubleColumnMinPerSide = 3;

  /// caption 中点判栏时的 margin 容忍度(API 坐标系).
  static const _columnSideMargin = 30.0;

  /// caption-anchored region inference 主流程.
  List<double> _inferRegionFromCaption({
    required LayoutBlock caption,
    required List<double> baseBbox,
    required List<LayoutBlock> segment,
    required List<LayoutBlock> pageBlocks,
    required _FigureDirection direction,
  }) {
    // Dart 3 exhaustive switch: 新增 _FigureDirection 值时编译器强制要求处理.
    return switch (direction) {
      _FigureDirection.above => _extendUpward(
          caption: caption,
          baseBbox: baseBbox,
          segment: segment,
          pageBlocks: pageBlocks,
        ),
      _FigureDirection.below => _extendDownward(
          caption: caption,
          baseBbox: baseBbox,
          segment: segment,
          pageBlocks: pageBlocks,
        ),
      _FigureDirection.left => _extendLeftward(
          caption: caption,
          baseBbox: baseBbox,
          segment: segment,
          pageBlocks: pageBlocks,
        ),
      _FigureDirection.right => _extendRightward(
          caption: caption,
          baseBbox: baseBbox,
          segment: segment,
          pageBlocks: pageBlocks,
        ),
    };
  }

  /// 推断 caption 所在的 column(单栏论文整页一栏,双栏论文左右两栏).
  ///
  /// 启发式:
  ///   1. page 上 text/paragraph_title/abstract block 不足 4 个 → 整页一栏
  ///      (页面被 figure 占满的情况,无法可靠判栏,保守用整页)
  ///   2. 否则按 page 横向中点切两半,左右两侧各自 text block 数 ≥
  ///      _doubleColumnMinPerSide → 双栏,否则单栏
  ///   3. 双栏下,caption 的横向位置决定它属于哪一栏:
  ///      - 完全在左 → 左栏 column
  ///      - 完全在右 → 右栏 column
  ///      - 横跨两栏 → 整页 column (cross-column figure)
  _Column _detectColumnFor(LayoutBlock caption, List<LayoutBlock> pageBlocks) {
    // page 横向边界估算
    double pageLeft = double.infinity, pageRight = 0;
    for (final b in pageBlocks) {
      if (b.blockBbox[0] < pageLeft) pageLeft = b.blockBbox[0];
      if (b.blockBbox[2] > pageRight) pageRight = b.blockBbox[2];
    }
    if (pageLeft.isInfinite || pageRight <= pageLeft) {
      return _Column(caption.blockBbox[0], caption.blockBbox[2]);
    }

    const textLabels = {'text', 'paragraph_title', 'abstract'};
    final textBlocks = pageBlocks
        .where((b) => textLabels.contains(b.blockLabel))
        .toList();
    if (textBlocks.length < 4) {
      return _Column(pageLeft, pageRight);
    }

    final pageMid = pageLeft + (pageRight - pageLeft) / 2;
    final leftBlocks = textBlocks
        .where((b) => b.blockBbox[2] <= pageMid + _columnSideMargin)
        .toList();
    final rightBlocks = textBlocks
        .where((b) => b.blockBbox[0] >= pageMid - _columnSideMargin)
        .toList();

    final isDoubleColumn = leftBlocks.length >= _doubleColumnMinPerSide &&
        rightBlocks.length >= _doubleColumnMinPerSide;
    if (!isDoubleColumn) return _Column(pageLeft, pageRight);

    final leftColRight = leftBlocks.fold<double>(
      0.0,
      (m, b) => b.blockBbox[2] > m ? b.blockBbox[2] : m,
    );
    final rightColLeft = rightBlocks.fold<double>(
      double.infinity,
      (m, b) => b.blockBbox[0] < m ? b.blockBbox[0] : m,
    );

    final cLeft = caption.blockBbox[0];
    final cRight = caption.blockBbox[2];

    // caption 同时跨过左栏 right 和右栏 left → 跨栏 figure
    if (cLeft < leftColRight + _columnSideMargin &&
        cRight > rightColLeft - _columnSideMargin) {
      return _Column(pageLeft, pageRight);
    }
    if (cRight <= leftColRight + _columnSideMargin) {
      final lLeft = leftBlocks.fold<double>(
        double.infinity,
        (m, b) => b.blockBbox[0] < m ? b.blockBbox[0] : m,
      );
      return _Column(lLeft, leftColRight);
    }
    if (cLeft >= rightColLeft - _columnSideMargin) {
      final rRight = rightBlocks.fold<double>(
        0.0,
        (m, b) => b.blockBbox[2] > m ? b.blockBbox[2] : m,
      );
      return _Column(rightColLeft, rRight);
    }
    return _Column(pageLeft, pageRight);
  }

  /// 推断 figure 相对 caption 的方向: 比较同 column 内 caption 上方/下方的
  /// 视觉块总高度,多的一边胜出.两边相等时 fallback 到 above (论文常态).
  /// 推断 figure 相对 caption 的 4 方向. 用**视觉块面积**作判据
  /// (纵向 height 与横向 width 不能直接比, 用 area 维度统一).
  ///
  /// 4 个统计区域:
  ///   above — 同 column 内, 完全在 caption 上方的视觉块面积之和
  ///   below — 同 column 内, 完全在 caption 下方的视觉块面积之和
  ///   left  — 同 "row" (caption 纵向区间) 内, 完全在 caption 左侧的视觉块面积
  ///   right — 同 "row" 内, 完全在 caption 右侧的视觉块面积
  ///
  /// 选面积最大方向. 全 0 (无视觉块) 时 fallback 到 above (论文常态).
  _FigureDirection _inferFigureDirection(
    LayoutBlock caption,
    _Column column,
    List<LayoutBlock> pageBlocks,
  ) {
    final captionTop = caption.blockBbox[1];
    final captionBottom = caption.blockBbox[3];
    final captionLeft = caption.blockBbox[0];
    final captionRight = caption.blockBbox[2];

    double aboveArea = 0, belowArea = 0, leftArea = 0, rightArea = 0;
    for (final b in pageBlocks) {
      if (!_isVisualBlock(b)) continue;
      final bLeft = b.blockBbox[0];
      final bTop = b.blockBbox[1];
      final bRight = b.blockBbox[2];
      final bBottom = b.blockBbox[3];
      final area = (bRight - bLeft) * (bBottom - bTop);
      if (area <= 0) continue;

      // 同 column = 横向与 caption.column 有 overlap → 看上下方分布
      final inColumn = bRight > column.left && bLeft < column.right;
      // 同 row = 纵向与 caption 有 overlap → 看左右分布
      final inRow = bBottom > captionTop && bTop < captionBottom;

      if (inColumn) {
        if (bBottom <= captionTop) {
          aboveArea += area;
        } else if (bTop >= captionBottom) {
          belowArea += area;
        }
      }
      if (inRow) {
        if (bRight <= captionLeft) {
          leftArea += area;
        } else if (bLeft >= captionRight) {
          rightArea += area;
        }
      }
    }

    // 4 方向比较, 取最大. 平局 fallback 顺序: above > below > left > right.
    var best = _FigureDirection.above;
    var bestArea = aboveArea;
    if (belowArea > bestArea) {
      best = _FigureDirection.below;
      bestArea = belowArea;
    }
    if (leftArea > bestArea) {
      best = _FigureDirection.left;
      bestArea = leftArea;
    }
    if (rightArea > bestArea) {
      best = _FigureDirection.right;
      bestArea = rightArea;
    }
    return best;
  }

  /// 沿 caption 上方扩展 baseBbox.top.
  /// 横向 overlap 判断仍用 visualUnion 边界(baseBbox 的 left/right),
  /// 这样保留对邻栏块的天然过滤,避免横向污染.
  List<double> _extendUpward({
    required LayoutBlock caption,
    required List<double> baseBbox,
    required List<LayoutBlock> segment,
    required List<LayoutBlock> pageBlocks,
  }) {
    if (caption.blockBbox[1] < baseBbox[3]) return baseBbox;
    final visualTop = baseBbox[1];
    final visualHeight = baseBbox[3] - baseBbox[1];
    if (visualHeight <= 0) return baseBbox;

    final blockerBottom = _nearestBlockerAbove(
      anchorTop: visualTop,
      hLeft: baseBbox[0],
      hRight: baseBbox[2],
      segment: segment,
      pageBlocks: pageBlocks,
    );
    final gap = visualTop - blockerBottom;
    if (gap < _missedVisualGapAbs) return baseBbox;
    if (gap / visualHeight < _missedVisualGapRatio) return baseBbox;

    final newTop = blockerBottom + _missedVisualMargin;
    if (newTop >= visualTop) return baseBbox;
    return [baseBbox[0], newTop, baseBbox[2], baseBbox[3]];
  }

  /// 沿 caption 下方扩展 baseBbox.bottom.对 [_extendUpward] 的对称实现.
  List<double> _extendDownward({
    required LayoutBlock caption,
    required List<double> baseBbox,
    required List<LayoutBlock> segment,
    required List<LayoutBlock> pageBlocks,
  }) {
    if (caption.blockBbox[3] > baseBbox[1]) return baseBbox;
    final visualBottom = baseBbox[3];
    final visualHeight = baseBbox[3] - baseBbox[1];
    if (visualHeight <= 0) return baseBbox;

    final pageBottom = pageBlocks.fold<double>(
      0.0,
      (m, b) => b.blockBbox[3] > m ? b.blockBbox[3] : m,
    );
    final blockerTop = _nearestBlockerBelow(
      anchorBottom: visualBottom,
      pageBottom: pageBottom,
      hLeft: baseBbox[0],
      hRight: baseBbox[2],
      segment: segment,
      pageBlocks: pageBlocks,
    );
    final gap = blockerTop - visualBottom;
    if (gap < _missedVisualGapAbs) return baseBbox;
    if (gap / visualHeight < _missedVisualGapRatio) return baseBbox;

    final newBottom = blockerTop - _missedVisualMargin;
    if (newBottom <= visualBottom) return baseBbox;
    return [baseBbox[0], baseBbox[1], baseBbox[2], newBottom];
  }

  double _nearestBlockerAbove({
    required double anchorTop,
    required double hLeft,
    required double hRight,
    required List<LayoutBlock> segment,
    required List<LayoutBlock> pageBlocks,
  }) {
    final segmentIds = segment.map((b) => b.blockId).toSet();
    double nearest = 0;
    for (final b in pageBlocks) {
      if (segmentIds.contains(b.blockId)) continue;
      if (!_isStableBlocker(b)) continue;
      final bLeft = b.blockBbox[0];
      final bRight = b.blockBbox[2];
      final bBottom = b.blockBbox[3];
      if (bRight <= hLeft || bLeft >= hRight) continue;
      if (bBottom >= anchorTop) continue;
      if (bBottom > nearest) nearest = bBottom;
    }
    return nearest;
  }

  double _nearestBlockerBelow({
    required double anchorBottom,
    required double pageBottom,
    required double hLeft,
    required double hRight,
    required List<LayoutBlock> segment,
    required List<LayoutBlock> pageBlocks,
  }) {
    final segmentIds = segment.map((b) => b.blockId).toSet();
    double nearest = pageBottom;
    for (final b in pageBlocks) {
      if (segmentIds.contains(b.blockId)) continue;
      if (!_isStableBlocker(b)) continue;
      final bLeft = b.blockBbox[0];
      final bRight = b.blockBbox[2];
      final bTop = b.blockBbox[1];
      if (bRight <= hLeft || bLeft >= hRight) continue;
      if (bTop <= anchorBottom) continue;
      if (bTop < nearest) nearest = bTop;
    }
    return nearest;
  }

  /// 沿 caption 左侧扩展 baseBbox.left (figure 在 caption 左侧的版面).
  /// 与 [_extendUpward] 对称: 纵向 overlap 判断用 visualUnion 的 top/bottom,
  /// gap 双门控用 visualUnion 的 width.
  List<double> _extendLeftward({
    required LayoutBlock caption,
    required List<double> baseBbox,
    required List<LayoutBlock> segment,
    required List<LayoutBlock> pageBlocks,
  }) {
    // caption 必须在 baseBbox 右侧 (左侧扩展场景: figure 左, caption 右)
    if (caption.blockBbox[0] < baseBbox[2]) return baseBbox;
    final visualLeft = baseBbox[0];
    final visualWidth = baseBbox[2] - baseBbox[0];
    if (visualWidth <= 0) return baseBbox;

    final blockerRight = _nearestBlockerLeft(
      anchorLeft: visualLeft,
      vTop: baseBbox[1],
      vBottom: baseBbox[3],
      segment: segment,
      pageBlocks: pageBlocks,
    );
    final gap = visualLeft - blockerRight;
    if (gap < _missedVisualGapAbs) return baseBbox;
    if (gap / visualWidth < _missedVisualGapRatio) return baseBbox;

    final newLeft = blockerRight + _missedVisualMargin;
    if (newLeft >= visualLeft) return baseBbox;
    return [newLeft, baseBbox[1], baseBbox[2], baseBbox[3]];
  }

  /// 沿 caption 右侧扩展 baseBbox.right (figure 在 caption 右侧的版面).
  /// 对 [_extendLeftward] 的对称实现.
  List<double> _extendRightward({
    required LayoutBlock caption,
    required List<double> baseBbox,
    required List<LayoutBlock> segment,
    required List<LayoutBlock> pageBlocks,
  }) {
    if (caption.blockBbox[2] > baseBbox[0]) return baseBbox;
    final visualRight = baseBbox[2];
    final visualWidth = baseBbox[2] - baseBbox[0];
    if (visualWidth <= 0) return baseBbox;

    final pageRight = pageBlocks.fold<double>(
      0.0,
      (m, b) => b.blockBbox[2] > m ? b.blockBbox[2] : m,
    );
    final blockerLeft = _nearestBlockerRight(
      anchorRight: visualRight,
      pageRight: pageRight,
      vTop: baseBbox[1],
      vBottom: baseBbox[3],
      segment: segment,
      pageBlocks: pageBlocks,
    );
    final gap = blockerLeft - visualRight;
    if (gap < _missedVisualGapAbs) return baseBbox;
    if (gap / visualWidth < _missedVisualGapRatio) return baseBbox;

    final newRight = blockerLeft - _missedVisualMargin;
    if (newRight <= visualRight) return baseBbox;
    return [baseBbox[0], baseBbox[1], newRight, baseBbox[3]];
  }

  double _nearestBlockerLeft({
    required double anchorLeft,
    required double vTop,
    required double vBottom,
    required List<LayoutBlock> segment,
    required List<LayoutBlock> pageBlocks,
  }) {
    final segmentIds = segment.map((b) => b.blockId).toSet();
    double nearest = 0;
    for (final b in pageBlocks) {
      if (segmentIds.contains(b.blockId)) continue;
      if (!_isStableBlocker(b)) continue;
      final bTop = b.blockBbox[1];
      final bRight = b.blockBbox[2];
      final bBottom = b.blockBbox[3];
      // 必须与 visual union 纵向 overlap (同 row)
      if (bBottom <= vTop || bTop >= vBottom) continue;
      if (bRight >= anchorLeft) continue;
      if (bRight > nearest) nearest = bRight;
    }
    return nearest;
  }

  double _nearestBlockerRight({
    required double anchorRight,
    required double pageRight,
    required double vTop,
    required double vBottom,
    required List<LayoutBlock> segment,
    required List<LayoutBlock> pageBlocks,
  }) {
    final segmentIds = segment.map((b) => b.blockId).toSet();
    double nearest = pageRight;
    for (final b in pageBlocks) {
      if (segmentIds.contains(b.blockId)) continue;
      if (!_isStableBlocker(b)) continue;
      final bLeft = b.blockBbox[0];
      final bTop = b.blockBbox[1];
      final bBottom = b.blockBbox[3];
      if (bBottom <= vTop || bTop >= vBottom) continue;
      if (bLeft <= anchorRight) continue;
      if (bLeft < nearest) nearest = bLeft;
    }
    return nearest;
  }

  /// 将 API 坐标缩放到 renderZoom
  static List<double> scaleBbox(List<double> bbox) {
    final ratio = renderZoom / apiZoom;
    return bbox.map((v) => v * ratio).toList();
  }

  static Future<ui.Image?> _renderFullPage(PdfPage page) async {
    final rendered = await page.render(
      fullWidth: page.width * renderZoom,
      fullHeight: page.height * renderZoom,
    );
    if (rendered == null) return null;
    return rendered.createImage();
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
    final byteData =
        await cropped.toByteData(format: ui.ImageByteFormat.png);
    cropped.dispose();
    return byteData?.buffer.asUint8List();
  }

  // ─── 公开入口 ─────────────────────────────────────────

  /// 测试入口:跑完整 inventory + pair,返回 segment.
  @visibleForTesting
  List<FigureSegment> findFigures(
    List<List<LayoutBlock>> pages, {
    List<String>? markdowns,
  }) {
    assert(_initialized, 'FigureExtractService.init() 未调用');
    final pageData = [
      for (var i = 0; i < pages.length; i++)
        _PageData(i, pages[i], markdowns != null && i < markdowns.length ? markdowns[i] : ''),
    ];
    final inv = _buildInventory(pageData);
    return _pair(inv);
  }

  /// 测试入口:单页用 `List<LayoutBlock>` 输入,返回 `List<List<LayoutBlock>>`.
  /// 等价于 `findFigures([blocks])` 然后投影到 `blocks` 字段.
  @visibleForTesting
  List<List<LayoutBlock>> findFigureSegments(List<LayoutBlock> blocks) {
    return findFigures([blocks]).map((s) => s.blocks).toList();
  }

  /// 从版面解析 JSON + PDF 中提取所有 figure,保存到 `{hash}/figures/`.
  Future<FigureExtractResult> extractFigures({
    required String resultPath,
    required String pdfPath,
    void Function(int done, int total)? onProgress,
  }) async {
    assert(_initialized, 'FigureExtractService.init() 未调用');

    final resultFile = File(resultPath);
    if (!resultFile.existsSync()) {
      throw FileSystemException('版面解析结果文件不存在', resultPath);
    }
    final pdfFile = File(pdfPath);
    if (!pdfFile.existsSync()) {
      throw FileSystemException('PDF 文件不存在', pdfPath);
    }

    final content = await resultFile.readAsString();
    final pages = _parsePages(content);
    final inv = _buildInventory(pages);
    final segments = _pair(inv);

    final totalSegments = segments.length;
    onProgress?.call(0, totalSegments);

    final outputDir = DocPaths.figuresDir(pdfPath);
    final outputDirObj = Directory(outputDir);
    if (outputDirObj.existsSync()) {
      await outputDirObj.delete(recursive: true);
    }
    await outputDirObj.create(recursive: true);

    final manifest = <FigureManifestEntry>[];
    var figureIndex = 0;

    await PdfProcessLock.instance.run(() async {
      PdfDocument? document;
      try {
        document = await PdfDocument.openFile(
          pdfPath,
          passwordProvider: () => '',
        );

        final byPage = <int, List<(int, FigureSegment)>>{};
        for (var i = 0; i < segments.length; i++) {
          final seg = segments[i];
          byPage.putIfAbsent(seg.pageIndex, () => []).add((i, seg));
        }

        for (final entry in byPage.entries) {
          final pageIdx = entry.key;
          if (pageIdx >= document.pages.length) {
            debugPrint('[FigureExtract] 页 $pageIdx 超出 PDF 页数,跳过');
            for (final (idx, _) in entry.value) {
              onProgress?.call(idx + 1, totalSegments);
            }
            continue;
          }

          final page = document.pages[pageIdx];
          final fullImage = await _renderFullPage(page);
          if (fullImage == null) {
            debugPrint('[FigureExtract] 页 $pageIdx 渲染失败');
            for (final (idx, _) in entry.value) {
              onProgress?.call(idx + 1, totalSegments);
            }
            continue;
          }

          try {
            final pageBlocks = pageIdx < pages.length
                ? pages[pageIdx].blocks
                : const <LayoutBlock>[];
            for (final (idx, seg) in entry.value) {
              final apiBbox = computeMergedBbox(
                seg.blocks,
                pageBlocks: pageBlocks,
              );
              final renderBbox = scaleBbox(apiBbox);

              final pngBytes = await _cropRegion(fullImage, renderBbox);
              if (pngBytes == null) {
                debugPrint('[FigureExtract] 页 $pageIdx 裁剪失败');
                onProgress?.call(idx + 1, totalSegments);
                continue;
              }

              final name = seg.captionName.isNotEmpty
                  ? _sanitizeFilename(seg.captionName)
                  : 'fig$figureIndex';
              final outPath = p.join(outputDir, '$name.png');
              await File(outPath).writeAsBytes(pngBytes);

              manifest.add(FigureManifestEntry(
                imagePath: outPath,
                captionText: seg.captionText,
                pageIndex: pageIdx,
                blockIds: seg.blocks.map((b) => b.blockId).toList(),
              ));

              figureIndex++;
              onProgress?.call(idx + 1, totalSegments);
            }
          } finally {
            fullImage.dispose();
          }
        }
      } finally {
        document?.dispose();
      }
    });

    final manifestPath = p.join(outputDir, 'figures.json');
    await File(manifestPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        manifest.map((e) => e.toJson()).toList(),
      ),
    );

    debugPrint('[FigureExtract] 共提取 $figureIndex 个 figure → $outputDir');
    return FigureExtractResult(outputDir: outputDir, entries: manifest);
  }

  static String _sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
  }

  static Future<List<FigureManifestEntry>?> loadManifest(
      String pdfPath) async {
    final manifestPath = DocPaths.figuresManifest(pdfPath);
    final file = File(manifestPath);
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(await file.readAsString()) as List<dynamic>;
      return json
          .map(
              (e) => FigureManifestEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[FigureExtract] 加载 manifest 失败: $e');
      return null;
    }
  }
}
