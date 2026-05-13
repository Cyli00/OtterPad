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

/// 一条 caption 来源:既可能源自 parsing_res_list 某 block,也可能仅出现在 markdown.
class _CaptionMention {
  _CaptionMention({
    required this.pageIndex,
    required this.text,
    required this.captionName,
    this.bbox,
    this.blockId,
  });

  final int pageIndex;
  final String text;
  final String captionName;
  final _Bbox? bbox;
  final String? blockId;
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

  final List<_CaptionMention> captions;
  final List<_FigureBlock> figureBlocks;
  final List<_PageData> pages;
}

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

  /// 内容若匹配 caption 正则,这些 label 的 block 都可作 caption mention.
  /// 不限于 figure_title——PaddleOCR 常把 caption 错标为这些 label.
  static const _captionCandidateLabels = {
    'figure_title',
    'text',
    'footer',
    'paragraph_title',
    'abstract',
    'vision_footnote',
  };

  /// figure_title 子标签(如 `A`、`(b)`)的最大长度,超过视为正文误标
  static const _maxSubLabelLength = 30;

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

  bool _isTableCaption(_CaptionMention c) => _tableCaptionRe.hasMatch(c.text);

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

  /// 把所有 caption 来源归一到一个 mention 列表;所有视觉/子图注块单独成 list.
  ///
  /// caption 来源(同 captionName 选最长内容):
  ///   1. parsing_res_list 中 `_captionCandidateLabels` 任一 label 的 block,
  ///      内容匹配主标题正则——一次性吃掉旧实现里的 figure_title 直采 +
  ///      `_recoverMissingAnchors` 升格 + `_unifyAnchorCaptions` 短标签扩展.
  ///   2. markdown.text 中匹配正则的行——救 parsing_res_list 漏掉的 caption
  ///      (双流不一致的常见现场).
  _Inventory _buildInventory(List<_PageData> pages) {
    final captions = <_CaptionMention>[];
    final figureBlocks = <_FigureBlock>[];

    for (final page in pages) {
      final pageMentions = <String, _CaptionMention>{};

      // 来源 1: parsing_res_list
      for (final b in page.blocks) {
        final content = b.blockContent.trim();
        if (content.isEmpty) continue;
        if (!_captionCandidateLabels.contains(b.blockLabel)) continue;
        if (!_mainCaptionRe.hasMatch(content)) continue;

        final name = _extractCaptionName(content);
        if (name.isEmpty) continue;

        final existing = pageMentions[name];
        if (existing == null || content.length > existing.text.length) {
          pageMentions[name] = _CaptionMention(
            pageIndex: page.pageIndex,
            text: content,
            captionName: name,
            bbox: _Bbox.fromBlock(b),
            blockId: b.blockId,
          );
        }
      }

      // 来源 2: markdown 行(只补 parsing_res_list 漏掉的)
      if (page.markdown.isNotEmpty) {
        for (final raw in page.markdown.split('\n')) {
          final t = raw.trim();
          if (t.isEmpty || !_mainCaptionRe.hasMatch(t)) continue;
          final name = _extractCaptionName(t);
          if (name.isEmpty || pageMentions.containsKey(name)) continue;
          pageMentions[name] = _CaptionMention(
            pageIndex: page.pageIndex,
            text: t,
            captionName: name,
          );
        }
      }

      captions.addAll(pageMentions.values);

      // 视觉/子图注块(不包括已成 caption 的 figure_title block)
      final captionBlockIds = pageMentions.values
          .map((m) => m.blockId)
          .whereType<String>()
          .toSet();
      for (final b in page.blocks) {
        if (!figureLabels.contains(b.blockLabel)) continue;
        if (captionBlockIds.contains(b.blockId)) continue;
        // figure_title 但内容过长 → 正文噪声(否则 (a)/(b) 这类短标签会被错误剔除)
        if (b.blockLabel == 'figure_title' &&
            b.blockContent.trim().length > _maxSubLabelLength) {
          continue;
        }
        figureBlocks.add(_FigureBlock(page.pageIndex, b));
      }
    }

    return _Inventory(
      captions: captions,
      figureBlocks: figureBlocks,
      pages: pages,
    );
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

    final captionsByPage = <int, List<_CaptionMention>>{};
    for (final c in inv.captions) {
      captionsByPage.putIfAbsent(c.pageIndex, () => []).add(c);
    }

    final segments = <FigureSegment>[];
    final usedClusters = <_Cluster>{};
    final usedCaptions = <_CaptionMention>{};

    // Pass 1: 同页配对——每个 cluster 找同页最近 caption,然后按 caption 合并簇.
    // 多个簇映射到同一 caption(如 Figure_2 的 image + 远处 vision_footnote 被
    // cluster gap 切开) 时,应合并为一个 segment,而不是各起一个 .
    final byCaption = <_CaptionMention, List<_Cluster>>{};
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

    // Pass 3: 匿名兜底——仍未配对 cluster 若含 image/chart 就升格.
    // 限 image/chart(不含 table)——独立 table 多为侧栏定义框,宁可漏不可错.
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

      // 同页未占用 caption(包括 markdown-only)优先认领
      _CaptionMention? attached;
      for (final c in captionsByPage[cluster.pageIndex] ?? const []) {
        if (usedCaptions.contains(c)) continue;
        if (claimedNames.contains(c.captionName)) continue;
        attached = c;
        break;
      }
      if (attached != null) {
        usedCaptions.add(attached);
        claimedNames.add(attached.captionName);
        segments.add(_buildSegmentFromBlocks(cluster.blocks, attached));
        debugPrint(
          '[FigureExtract] anonymous + same-page caption: '
          '"${attached.captionName}" on page ${cluster.pageIndex}',
        );
      } else {
        segments.add(FigureSegment(
          pageIndex: cluster.pageIndex,
          blocks: cluster.blocks.map((b) => b.block).toList(),
          captionText: '',
          captionName: '',
        ));
        debugPrint(
          '[FigureExtract] anonymous orphan emitted on page '
          '${cluster.pageIndex} (${cluster.blocks.length} blocks)',
        );
      }
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
  _CaptionMention? _nearestCaption(
    _Cluster cluster,
    List<_CaptionMention> candidates,
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

    _CaptionMention? best;
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
  /// caption 若来自 parsing_res_list block,合成对应 LayoutBlock 放在 blocks 头部,
  /// 让下游 markdown 替换能按 block_id 找到 caption 行并占住.
  FigureSegment _buildSegmentFromBlocks(
    List<_FigureBlock> figureBlocks,
    _CaptionMention caption,
  ) {
    final blocks = <LayoutBlock>[];
    if (caption.blockId != null) {
      blocks.add(LayoutBlock(
        blockId: caption.blockId!,
        blockLabel: 'figure_title',
        blockBbox: caption.bbox?.toList() ?? const [0, 0, 0, 0],
        blockContent: caption.text,
      ));
    }
    for (final b in figureBlocks) {
      if (b.block.blockId == caption.blockId) continue;
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
  /// 优先 image/chart/table——这是论文 figure 真正的视觉内容,自动排除
  /// caption、vision_footnote 等文字标签.
  ///
  /// 当 [pageBlocks] 提供时,会针对 PaddleOCR 漏检子图的常见现场做向上扩展:
  /// 若 caption 在 visual union 下方,而 union 上方在同栏宽度内存在大段完全
  /// 无 layout block 的空白,则把 top 抬升到最近上方阻塞的 bottom + 小 margin.
  /// 触发条件:绝对 gap ≥ [_missedVisualGapAbs] **且** gap / visualHeight
  /// ≥ [_missedVisualGapRatio],双门控避免误伤紧邻段落的 figure.
  @visibleForTesting
  List<double> computeMergedBbox(
    List<LayoutBlock> segment, {
    List<LayoutBlock>? pageBlocks,
  }) {
    final visuals = segment
        .where((b) =>
            b.blockLabel == 'image' ||
            b.blockLabel == 'chart' ||
            b.blockLabel == 'table')
        .toList();

    if (visuals.isNotEmpty) {
      final base = _Bbox.union(visuals).toList();
      if (pageBlocks == null || pageBlocks.isEmpty) return base;
      return _expandForMissedVisuals(
        baseBbox: base,
        segment: segment,
        pageBlocks: pageBlocks,
      );
    }

    // 完全无视觉块时退一步:排除 caption 和子图注文字
    final contents = segment
        .where((b) =>
            !_mainCaptionRe.hasMatch(b.blockContent.trim()) &&
            b.blockLabel != 'vision_footnote')
        .toList();
    final effective = contents.isNotEmpty ? contents : segment;
    return _Bbox.union(effective).toList();
  }

  /// 上方扩展的双重阈值——只有两条同时满足才扩展.
  /// 阈值均基于 API 坐标系 (zoom 2.0, 144 DPI).
  static const _missedVisualGapAbs = 80.0;
  static const _missedVisualGapRatio = 0.30;

  /// 扩展后留给 blocker 的 margin (API 坐标系),避免裁到上方段落底部.
  static const _missedVisualMargin = 8.0;

  List<double> _expandForMissedVisuals({
    required List<double> baseBbox,
    required List<LayoutBlock> segment,
    required List<LayoutBlock> pageBlocks,
  }) {
    // 找 segment 内的 caption block (label==figure_title 且匹配主标题正则)
    LayoutBlock? caption;
    for (final b in segment) {
      if (b.blockLabel == 'figure_title' &&
          _mainCaptionRe.hasMatch(b.blockContent.trim())) {
        caption = b;
        break;
      }
    }
    if (caption == null) return baseBbox;
    // caption 必须在 visualUnion 下方,才认为是"下置 caption + 上方 figure"格局
    if (caption.blockBbox[1] < baseBbox[3]) return baseBbox;

    final visualLeft = baseBbox[0];
    final visualTop = baseBbox[1];
    final visualRight = baseBbox[2];
    final visualHeight = baseBbox[3] - baseBbox[1];
    if (visualHeight <= 0) return baseBbox;

    final segmentIds = segment.map((b) => b.blockId).toSet();

    // 收集 page 上所有"非 segment 内"且横向与 visualUnion 有 overlap 的块.
    // 这些是上方扩展时的潜在 blocker——本栏内最低 bottom 决定扩展上限.
    double? nearestBlockerBottom;
    for (final b in pageBlocks) {
      if (segmentIds.contains(b.blockId)) continue;
      final bLeft = b.blockBbox[0];
      final bRight = b.blockBbox[2];
      final bBottom = b.blockBbox[3];
      // 横向必须与 visualUnion 有交集 (双栏 layout 下排除邻栏块)
      if (bRight <= visualLeft || bLeft >= visualRight) continue;
      // 仅看位于 visualUnion 上方的 blocker
      if (bBottom >= visualTop) continue;
      if (nearestBlockerBottom == null || bBottom > nearestBlockerBottom) {
        nearestBlockerBottom = bBottom;
      }
    }
    final blockerBottom = nearestBlockerBottom ?? 0.0;

    final gap = visualTop - blockerBottom;
    if (gap < _missedVisualGapAbs) return baseBbox;
    if (gap / visualHeight < _missedVisualGapRatio) return baseBbox;

    final newTop = blockerBottom + _missedVisualMargin;
    if (newTop >= visualTop) return baseBbox;
    return [baseBbox[0], newTop, baseBbox[2], baseBbox[3]];
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
