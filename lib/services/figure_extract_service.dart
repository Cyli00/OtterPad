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

// ─── 数据模型 ───────────────────────────────────────────────

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

  LayoutBlock copyWith({String? blockLabel, String? blockContent}) =>
      LayoutBlock(
        blockId: blockId,
        blockLabel: blockLabel ?? this.blockLabel,
        blockBbox: blockBbox,
        blockContent: blockContent ?? this.blockContent,
      );
}

/// 一个检测到的 figure 区域（由若干连续 block 组成）
class FigureSegment {
  final int pageIndex;
  final List<LayoutBlock> blocks;
  final String captionText;

  /// 由服务在构建时计算的文件名标识，例如 "Figure_1"
  final String captionName;

  const FigureSegment({
    required this.pageIndex,
    required this.blocks,
    required this.captionText,
    required this.captionName,
  });
}

/// 清单中的单条记录
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

/// 用于主标题连续性恢复的序列状态
class _CaptionSeries {
  _CaptionSeries(this.prefix);
  final String prefix;
  final Set<int> present = <int>{};
  int get minNumber => present.reduce((a, b) => a < b ? a : b);
  int get maxNumber => present.reduce((a, b) => a > b ? a : b);
}

/// 内部 bbox 表示，避免到处手写 `[0] [1] [2] [3]`。
class _Bbox {
  const _Bbox(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  factory _Bbox.fromList(List<double> bbox) =>
      _Bbox(bbox[0], bbox[1], bbox[2], bbox[3]);

  factory _Bbox.fromBlock(LayoutBlock block) => _Bbox.fromList(block.blockBbox);

  factory _Bbox.fromBlocks(Iterable<LayoutBlock> blocks) {
    double left = double.infinity;
    double top = double.infinity;
    double right = double.negativeInfinity;
    double bottom = double.negativeInfinity;
    var hasAny = false;

    for (final block in blocks) {
      hasAny = true;
      final bbox = _Bbox.fromBlock(block);
      if (bbox.left < left) left = bbox.left;
      if (bbox.top < top) top = bbox.top;
      if (bbox.right > right) right = bbox.right;
      if (bbox.bottom > bottom) bottom = bbox.bottom;
    }

    if (!hasAny) return const _Bbox(0, 0, 0, 0);
    return _Bbox(left, top, right, bottom);
  }

  double gapTo(_Bbox other) {
    final dx = (left > other.right)
        ? left - other.right
        : (other.left > right ? other.left - right : 0.0);
    final dy = (top > other.bottom)
        ? top - other.bottom
        : (other.top > bottom ? other.top - bottom : 0.0);
    return math.sqrt(dx * dx + dy * dy);
  }

  double get diagonal {
    final width = right - left;
    final height = bottom - top;
    return math.sqrt(width * width + height * height);
  }

  List<double> toList() => [left, top, right, bottom];
}

class _ContentCluster {
  _ContentCluster(this.blocks) : bbox = _Bbox.fromBlocks(blocks);

  final List<LayoutBlock> blocks;
  final _Bbox bbox;
}

/// figure 提取的完整结果
class FigureExtractResult {
  final String outputDir;
  final List<FigureManifestEntry> entries;

  const FigureExtractResult({
    required this.outputDir,
    required this.entries,
  });
}

// ─── 服务 ───────────────────────────────────────────────────

/// 从 PaddleOCR 版面解析 JSON + 原始 PDF 中提取 figure 区域图片。
///
/// 流程：
/// 1. 解析 JSON 中每页的 `prunedResult.parsing_res_list` block 列表
/// 2. 连续的 figure 相关 block 聚合为粗段落，再按主标题二次切割
/// 3. 计算每个 segment 的外接矩形（排除标题 block）
/// 4. 通过 pdfrx 渲染 PDF 页面，按比例裁剪出 figure 区域
/// 5. 保存为 PNG 并生成 manifest（`_figures.json`）
///
/// 使用前必须调用 [init] 加载 caption 配置。
class FigureExtractService {
  FigureExtractService._();
  static final FigureExtractService instance = FigureExtractService._();

  // ─── 常量 ─────────────────────────────────────────────

  /// figure 相关的 block label 集合
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

  // ─── 标题正则（从 assets/config/caption_patterns.json 加载） ───

  late final RegExp _mainCaptionRe;
  late final List<String> _prefixes;
  late final String _suffixPattern;
  bool _initialized = false;

  /// 从 asset bundle 加载 caption 配置并编译正则。
  ///
  /// 应在 app 启动时调用一次（可与 GStorage.init 并行）。
  Future<void> init() async {
    if (_initialized) return;
    final raw = await rootBundle.loadString(
      'assets/config/caption_patterns.json',
    );
    final conf = jsonDecode(raw) as Map<String, dynamic>;

    final prefixes = (conf['prefixes'] as List<dynamic>)
        .map((e) => e as String)
        .toList()
      // 按长度降序，防止短前缀抢先匹配长前缀
      ..sort((a, b) => b.length.compareTo(a.length));

    final prefixGroup = prefixes.map(RegExp.escape).join('|');
    final numberPattern = conf['number_pattern'] as String;
    final suffixPattern = conf['suffix_pattern'] as String;

    _mainCaptionRe = RegExp(
      '^(?:$prefixGroup)$numberPattern$suffixPattern',
      caseSensitive: false,
    );
    _prefixes = List.unmodifiable(prefixes);
    _suffixPattern = suffixPattern;
    _initialized = true;
  }

  /// 判断 anchor 是否为表格类（标题以 Table/Tab/表 等前缀开头）。
  ///
  /// 用于在分配 `table` / `vision_footnote` block 时优先挂到同类 anchor，
  /// 避免表格注释被几何上稍近的 figure 抢走。
  static final _tableAnchorRe = RegExp(
    r'^(?:table|tab\.?|tabelle|tabla|cuadro|таблица|表|표|bảng)',
    caseSensitive: false,
  );

  bool _isTableAnchor(LayoutBlock anchor) =>
      _tableAnchorRe.hasMatch(anchor.blockContent.trim());

  /// 过滤 OCR 误标：`figure_title` 内容过长且不匹配主标题正则的视为正文噪声。
  ///
  /// 其它 figure-label（image/chart/table/vision_footnote）一律放行。
  bool _isValidFigureBlock(LayoutBlock block) {
    if (block.blockLabel != 'figure_title') return true;
    if (isMainCaption(block)) return true;
    return block.blockContent.trim().length <= _maxSubLabelLength;
  }

  /// 判断 block 是否为主标题（Figure N. / Table N.），排除子标签如 (a)、(b)
  bool isMainCaption(LayoutBlock block) {
    assert(_initialized, 'FigureExtractService.init() 未调用');
    if (block.blockLabel != 'figure_title') return false;
    return _mainCaptionRe.hasMatch(block.blockContent.trim());
  }

  /// 从主标题文本中提取文件名标识（如 "Figure 1." → "Figure_1"）
  String _extractCaptionName(String captionText) {
    final m = _mainCaptionRe.firstMatch(captionText.trim());
    if (m != null) {
      return m.group(0)!.replaceAll('.', '').replaceAll(' ', '_').trim();
    }
    return '';
  }

  // ─── 版面数据解析 ─────────────────────────────────────

  /// 从 JSON 文件内容解析每页的 block 列表。
  ///
  /// 输入为扁平 JSON 数组 `[page0, page1, ...]`，
  /// 每个 page 中取 `prunedResult.parsing_res_list`。
  static List<List<LayoutBlock>> parseLayoutBlocks(String jsonContent) {
    final pages = <List<LayoutBlock>>[];
    try {
      final list = jsonDecode(jsonContent) as List<dynamic>;
      for (final page in list) {
        final map = page as Map<String, dynamic>;
        final pruned = map['prunedResult'] as Map<String, dynamic>?;
        final blockList = pruned?['parsing_res_list'] as List<dynamic>?;
        if (blockList == null) {
          pages.add([]);
          continue;
        }
        pages.add(
          blockList
              .map((b) => LayoutBlock.fromJson(b as Map<String, dynamic>))
              .toList(),
        );
      }
    } catch (e) {
      debugPrint('[FigureExtract] 解析 JSON 失败: $e');
    }
    return pages;
  }

  // ─── 主标题连续性恢复（OCR 误标 fallback） ────────────

  /// 允许被"升格"为主标题的原始 block label。
  static const _promotableLabels = {'text', 'footer', 'paragraph_title'};

  /// 在 segmentation 之前扫描所有页面，把被 OCR 误标为正文的 Figure/Table
  /// 标题升格回 `figure_title`，使后续 [findFigureSegments] 能正确识别。
  ///
  /// Pattern 自学习：只补全当前文档已经使用的前缀序列；整数序号限定。
  List<List<LayoutBlock>> _recoverMissingAnchors(
    List<List<LayoutBlock>> pages,
  ) {
    final series = _collectSeries(pages);
    if (series.isEmpty) return pages;

    // 深拷贝外层 list，页面内部的 LayoutBlock 需要替换时再新建
    final result = pages.map((page) => List<LayoutBlock>.from(page)).toList();

    for (final s in series.values) {
      // 中间空缺
      for (var n = s.minNumber; n <= s.maxNumber; n++) {
        if (s.present.contains(n)) continue;
        _tryPromote(result, s.prefix, n);
      }
      // 尾端延伸：n+1 开始，找不到就停
      var probe = s.maxNumber + 1;
      while (_tryPromote(result, s.prefix, probe)) {
        probe++;
      }
    }
    return result;
  }

  /// 扫描所有 anchor，按前缀归类为 [_CaptionSeries]。
  Map<String, _CaptionSeries> _collectSeries(List<List<LayoutBlock>> pages) {
    final map = <String, _CaptionSeries>{};
    for (final page in pages) {
      for (final b in page) {
        if (!isMainCaption(b)) continue;
        final trimmed = b.blockContent.trim();
        final prefix = _matchPrefix(trimmed);
        if (prefix == null) continue;
        final number = _parseIntegerNumber(trimmed, prefix);
        if (number == null) continue;
        map
            .putIfAbsent(prefix, () => _CaptionSeries(prefix))
            .present
            .add(number);
      }
    }
    return map;
  }

  /// 在 [content] 头部匹配已知前缀（长度优先），返回配置中的原始形式。
  String? _matchPrefix(String content) {
    for (final p in _prefixes) {
      if (content.length < p.length) continue;
      if (content.substring(0, p.length).toLowerCase() == p.toLowerCase()) {
        return p;
      }
    }
    return null;
  }

  /// 从 "Figure 12." / "FIG. 3:" 之类的字符串里抠出整数序号；
  /// 非整数形式（"S1"、"3A"、"2.1"）返回 null，不参与续号。
  int? _parseIntegerNumber(String content, String prefix) {
    final tail = content.substring(prefix.length).trimLeft();
    final m = RegExp(r'^(\d+)').firstMatch(tail);
    if (m == null) return null;
    final after = tail.substring(m.end);
    if (after.isEmpty) return int.tryParse(m.group(1)!);
    final next = after.codeUnitAt(0);
    // 字母或点紧跟在数字后面（如 "3A"、"3.1"）都拒绝
    if ((next >= 0x41 && next <= 0x5A) ||
        (next >= 0x61 && next <= 0x7A) ||
        next == 0x2E) {
      return null;
    }
    return int.tryParse(m.group(1)!);
  }

  /// 尝试升格 `<prefix> <number>` 开头的候选 block；成功返回 true。
  ///
  /// 跨所有页面的 text/footer/paragraph_title，按阅读顺序取第一个命中。
  /// 若同一序号有 2 个以上命中视为内嵌引用歧义，拒绝升格。
  bool _tryPromote(
    List<List<LayoutBlock>> pages,
    String prefix,
    int number,
  ) {
    final re = RegExp(
      '^${RegExp.escape(prefix)}\\s*$number$_suffixPattern',
      caseSensitive: false,
    );

    (int, int)? firstHit;
    var hitCount = 0;
    outer:
    for (var pi = 0; pi < pages.length; pi++) {
      for (var bi = 0; bi < pages[pi].length; bi++) {
        final b = pages[pi][bi];
        if (!_promotableLabels.contains(b.blockLabel)) continue;
        if (!re.hasMatch(b.blockContent.trim())) continue;
        hitCount++;
        firstHit ??= (pi, bi);
        if (hitCount > 1) break outer;
      }
    }

    if (firstHit == null || hitCount > 1) return false;
    final (pi, bi) = firstHit;
    final original = pages[pi][bi];
    pages[pi][bi] = original.copyWith(blockLabel: 'figure_title');
    debugPrint(
      '[FigureExtract] recovered "$prefix $number" '
      'on page $pi (block ${original.blockId})',
    );
    return true;
  }

  // ─── 标题格式统一化（统计学去重） ─────────────────────

  /// 为短标签补全完整图注。
  ///
  /// 短标签 = 主标题去掉前缀+序号后几乎没有描述文本（≤10 字符），
  /// 例如 "Figure 5"、"Fig 3."。按序号在全文 `figure_title → text → footer`
  /// 中搜索任意前缀、同序号、更长的完整图注（如 "Fig. 5. Calcium dynamics..."）。
  /// 找到后短标签吸收其文本，完整图注降级为 `text`。
  List<List<LayoutBlock>> _unifyAnchorCaptions(List<List<LayoutBlock>> pages) {
    final result = pages.map((p) => List<LayoutBlock>.from(p)).toList();

    for (var pi = 0; pi < result.length; pi++) {
      for (var bi = 0; bi < result[pi].length; bi++) {
        final b = result[pi][bi];
        if (!isMainCaption(b)) continue;
        final trimmed = b.blockContent.trim();
        final prefix = _matchPrefix(trimmed);
        if (prefix == null) continue;

        // 判断是否为短标签
        final tail = trimmed.substring(prefix.length).trimLeft();
        final numMatch = RegExp(r'^(\d+)').firstMatch(tail);
        if (numMatch == null) continue;
        final number = numMatch.group(1)!;
        final afterNumber = tail.substring(numMatch.end)
            .replaceAll(RegExp(r'^[.:\s]+'), '')
            .trim();
        if (afterNumber.length > 10) continue;

        // 搜索同序号、任意已知前缀的完整图注
        final allPrefixGroup =
            _prefixes.map(RegExp.escape).join('|');
        final searchRe = RegExp(
          '^(?:$allPrefixGroup)\\s*$number$_suffixPattern',
          caseSensitive: false,
        );

        (int pj, int bj)? found;
        for (final label in ['figure_title', 'text', 'footer']) {
          for (var pj = 0; pj < result.length && found == null; pj++) {
            for (var bj = 0; bj < result[pj].length; bj++) {
              final c = result[pj][bj];
              if (c.blockLabel != label) continue;
              if (pj == pi && bj == bi) continue;
              if (!searchRe.hasMatch(c.blockContent.trim())) continue;
              if (c.blockContent.length > b.blockContent.length) {
                found = (pj, bj);
                break;
              }
            }
          }
          if (found != null) break;
        }

        if (found != null) {
          final (pj, bj) = found;
          final donor = result[pj][bj];
          result[pi][bi] = b.copyWith(
            blockContent: donor.blockContent.trim(),
          );
          result[pj][bj] = donor.copyWith(blockLabel: 'text');
          debugPrint(
            '[FigureExtract] unified: "$trimmed" ← '
            '"${donor.blockContent.trim().substring(0, math.min(60, donor.blockContent.trim().length))}…"',
          );
        }
      }
    }

    return result;
  }

  // ─── Segment 检测（空间聚类） ──────────────────────────

  /// `figure_title` block 被视作合法 figure 构件所允许的最大内容长度。
  ///
  /// OCR 偶尔会把正文段落误标为 `figure_title`，这些误标内容通常很长；
  /// 合法的主标题会通过 [isMainCaption] 放行，子标签（如 `(a)`、`BALB/c WT`）
  /// 实测不超过 30 字符。超过这个阈值且不匹配主标题正则的 `figure_title`
  /// 视为噪声，从 figure 聚类中剔除。
  static const _maxSubLabelLength = 30;

  static const _anchorAssignThresholdRatio = 0.5;
  static const _contentClusterGapRatio = 0.025;
  static const _minContentClusterGap = 24.0;
  static const _maxContentClusterGap = 56.0;

  /// 在单页 block 列表中找到所有 figure segment。
  ///
  /// 每个主标题（Figure N. / Table N.）是一个 segment 锚点。
  /// 其它 figure-label block（image/chart/table/sub-caption/vision_footnote）
  /// 先按空间相邻关系聚成内容簇，再按内容簇 bbox 归属到最近锚点。
  ///
  /// 这种做法对"标题在上/下/左/右"四种排版一视同仁，
  /// 并且不依赖 API 的阅读顺序——当双栏版面把 caption 和 image
  /// 在阅读顺序上打断时也能正确配对。
  List<List<LayoutBlock>> findFigureSegments(List<LayoutBlock> blocks) {
    final figureBlocks = blocks
        .where((b) => figureLabels.contains(b.blockLabel))
        .where(_isValidFigureBlock)
        .toList();
    if (figureBlocks.isEmpty) return const [];

    final anchors = figureBlocks.where(isMainCaption).toList();
    if (anchors.isEmpty) return const [];

    // 按 label 把 anchor 分成两类，用于同类亲和性匹配
    final tableAnchors = anchors.where(_isTableAnchor).toList();
    final figureAnchors =
        anchors.where((a) => !_isTableAnchor(a)).toList();

    final segments = {
      for (final anchor in anchors) anchor: <LayoutBlock>[anchor],
    };

    final pageDiagonal = _pageDiagonal(blocks);

    // 超出阈值的内容簇视为与任何锚点都不相关，丢弃。
    // 0.5 留出余量，使侧向排版中位于另一列的子标题也能配对。
    final threshold = pageDiagonal * _anchorAssignThresholdRatio;
    final contentClusterGap = (pageDiagonal * _contentClusterGapRatio)
        .clamp(_minContentClusterGap, _maxContentClusterGap)
        .toDouble();

    for (final cluster in _buildContentClusters(
      figureBlocks,
      contentClusterGap,
    )) {
      final preferred = _prefersTableAnchor(cluster)
          ? tableAnchors
          : figureAnchors;
      final anchor =
          _nearestAnchor(cluster.bbox, preferred, threshold) ??
          _nearestAnchor(cluster.bbox, anchors, threshold);
      if (anchor == null) continue;
      segments[anchor]!.addAll(cluster.blocks);
    }

    return segments.values.toList();
  }

  /// 将相邻的 figure 内容先聚成簇，再整体分配给标题。
  ///
  /// 连续底部图注容易出现 `Figure -> Figure_title -> Figure -> Figure_title`
  /// 的版面顺序。若逐块按距离分配，后一张图顶部的子标签可能被前一个图注抢走；
  /// 内容簇能用整组 bbox 重新判断归属。
  List<_ContentCluster> _buildContentClusters(
    List<LayoutBlock> figureBlocks,
    double maxGap,
  ) {
    final contentBlocks = figureBlocks.where((b) => !isMainCaption(b)).toList();
    final blockOrder = {
      for (var i = 0; i < figureBlocks.length; i++) figureBlocks[i]: i,
    };
    final remaining = List<LayoutBlock>.from(contentBlocks);
    final clusters = <_ContentCluster>[];

    while (remaining.isNotEmpty) {
      final cluster = <LayoutBlock>[remaining.removeAt(0)];
      var expanded = true;

      while (expanded) {
        expanded = false;
        for (var i = remaining.length - 1; i >= 0; i--) {
          final candidate = remaining[i];
          final touchesCluster = cluster.any(
            (b) =>
                _Bbox.fromBlock(b).gapTo(_Bbox.fromBlock(candidate)) <= maxGap,
          );
          if (!touchesCluster) continue;

          cluster.add(candidate);
          remaining.removeAt(i);
          expanded = true;
        }
      }

      cluster.sort((a, b) => blockOrder[a]!.compareTo(blockOrder[b]!));
      clusters.add(_ContentCluster(cluster));
    }

    return clusters;
  }

  bool _prefersTableAnchor(_ContentCluster cluster) {
    final hasFigureVisual = cluster.blocks.any(
      (b) => b.blockLabel == 'image' || b.blockLabel == 'chart',
    );
    if (hasFigureVisual) return false;
    return cluster.blocks.any(
      (b) => b.blockLabel == 'table' || b.blockLabel == 'vision_footnote',
    );
  }

  LayoutBlock? _nearestAnchor(
    _Bbox bbox,
    List<LayoutBlock> anchors,
    double maxGap,
  ) {
    LayoutBlock? best;
    var bestGap = double.infinity;
    for (final anchor in anchors) {
      final gap = bbox.gapTo(_Bbox.fromBlock(anchor));
      if (gap < bestGap) {
        bestGap = gap;
        best = anchor;
      }
    }
    return bestGap <= maxGap ? best : null;
  }

  /// 当页所有 block 外接矩形的对角线长度，用作距离阈值的基准。
  static double _pageDiagonal(List<LayoutBlock> blocks) {
    if (blocks.isEmpty) return 0;
    return _Bbox.fromBlocks(blocks).diagonal;
  }

  // ─── BBox 计算 ────────────────────────────────────────

  /// 计算 segment 内非主标题 block 的外接矩形（裁图时排除图注文字）。
  ///
  /// 返回 `[left, top, right, bottom]`，坐标基于 API zoom。
  List<double> computeMergedBbox(List<LayoutBlock> segment) {
    final contentBlocks =
        segment.where((b) => !isMainCaption(b)).toList();
    final effective = contentBlocks.isNotEmpty ? contentBlocks : segment;
    return _mergeBbox(effective);
  }

  /// 合并 block bbox，保留主标题与否由调用方决定。
  static List<double> _mergeBbox(List<LayoutBlock> blocks) {
    return _Bbox.fromBlocks(blocks).toList();
  }

  /// 将 API 坐标从 [apiZoom] 缩放到 [renderZoom]
  static List<double> scaleBbox(List<double> bbox) {
    final ratio = renderZoom / apiZoom;
    return bbox.map((v) => v * ratio).toList();
  }

  // ─── PDF 渲染 + 裁剪 ─────────────────────────────────

  /// 渲染整页 PDF 为 [renderZoom] 倍率的 [ui.Image]。
  ///
  /// 同一页的多个 figure 应共用此结果，避免重复渲染。
  /// 调用方须负责 dispose 返回的 Image。
  static Future<ui.Image?> _renderFullPage(PdfPage page) async {
    final rendered = await page.render(
      fullWidth: page.width * renderZoom,
      fullHeight: page.height * renderZoom,
    );
    if (rendered == null) return null;
    return rendered.createImage();
  }

  /// 从已渲染的整页图片中裁剪出 [bbox] 区域，返回 PNG 字节。
  ///
  /// [bbox] 为已缩放到 [renderZoom] 的像素坐标 `[left, top, right, bottom]`。
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

  /// 从版面解析 JSON + PDF 中提取所有 figure 并保存到 `{baseName}_figures/`。
  ///
  /// - [resultPath]：版面解析结果 `.json` 文件路径（扁平页面数组）
  /// - [pdfPath]：原始 PDF 路径
  /// - [onProgress]：进度回调 `(已完成, 总数)`
  ///
  /// 返回 [FigureExtractResult]，包含输出目录和 manifest 条目。
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
    final allPages = _unifyAnchorCaptions(
      _recoverMissingAnchors(parseLayoutBlocks(content)),
    );

    // 收集所有 segment（带页码）
    final segments = <FigureSegment>[];
    for (var pageIdx = 0; pageIdx < allPages.length; pageIdx++) {
      final pageBlocks = allPages[pageIdx];
      final pageSegments = findFigureSegments(pageBlocks);
      for (final seg in pageSegments) {
        // 提取主标题
        String caption = '';
        for (final b in seg) {
          if (isMainCaption(b)) {
            caption = b.blockContent.trim();
            break;
          }
        }
        // 跳过无标题或无内容 block 的 segment
        final hasContent = seg.any((b) => !isMainCaption(b));
        if (caption.isEmpty || !hasContent) continue;

        segments.add(FigureSegment(
          pageIndex: pageIdx,
          blocks: seg,
          captionText: caption,
          captionName: _extractCaptionName(caption),
        ));
      }
    }

    final totalSegments = segments.length;
    onProgress?.call(0, totalSegments);

    // 准备输出目录（重新提取时清理旧文件）
    final outputDir = DocPaths.figuresDir(pdfPath);
    final outputDirObj = Directory(outputDir);
    if (outputDirObj.existsSync()) {
      await outputDirObj.delete(recursive: true);
    }
    await outputDirObj.create(recursive: true);

    // 通过 PdfProcessLock 串行渲染，防止并发 OOM
    final manifest = <FigureManifestEntry>[];
    var figureIndex = 0;

    await PdfProcessLock.instance.run(() async {
      PdfDocument? document;
      try {
        document = await PdfDocument.openFile(
          pdfPath,
          passwordProvider: () => '',
        );

        // 按页分组，同一页只渲染一次
        final byPage = <int, List<(int, FigureSegment)>>{};
        for (var i = 0; i < segments.length; i++) {
          final seg = segments[i];
          byPage.putIfAbsent(seg.pageIndex, () => []).add((i, seg));
        }

        for (final entry in byPage.entries) {
          final pageIdx = entry.key;
          if (pageIdx >= document.pages.length) {
            debugPrint('[FigureExtract] 页 $pageIdx 超出 PDF 页数，跳过');
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
            for (final (idx, seg) in entry.value) {
              final apiBbox = computeMergedBbox(seg.blocks);
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

    // 保存 manifest
    final manifestPath = p.join(outputDir, 'figures.json');
    await File(manifestPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(
        manifest.map((e) => e.toJson()).toList(),
      ),
    );

    debugPrint('[FigureExtract] 共提取 $figureIndex 个 figure → $outputDir');
    return FigureExtractResult(outputDir: outputDir, entries: manifest);
  }

  /// 清理文件名中的非法字符
  static String _sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
  }

  /// 加载已有的 manifest（若存在）
  static Future<List<FigureManifestEntry>?> loadManifest(
      String pdfPath) async {
    final manifestPath = DocPaths.figuresManifest(pdfPath);
    final file = File(manifestPath);
    if (!file.existsSync()) return null;

    try {
      final json = jsonDecode(await file.readAsString()) as List<dynamic>;
      return json
          .map((e) =>
              FigureManifestEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[FigureExtract] 加载 manifest 失败: $e');
      return null;
    }
  }
}
