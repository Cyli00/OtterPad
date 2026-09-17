import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:dio/dio.dart' show CancelToken;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:crypto/crypto.dart';

import '../utils/doc_paths.dart';
import '../data/models/ocr/doc_extract_config.dart';
import 'document_structure.dart';
import 'pdf_process_lock.dart';
import 'extraction_artifacts.dart';
import '../core/app_logger.dart';

export 'document_structure.dart' show LayoutBlock;

// ─── 诊断枚举 ─────────────────────────────────────────────

/// Caption 的发现来源
enum CaptionSource {
  /// Phase 1/2: parsing_res_list block 内容匹配正则
  blockMatch,

  /// Phase 3: markdown 行兜底
  markdownFallback,

  /// 兼容旧清单；新提取不会创建无题注实体。
  none,
}

/// Figure-Caption 配对方式
enum PairMethod {
  /// Pass 1: 同页空间距离最近
  samePage,

  /// Pass 2: 跨页 ±1 双向唯一
  crossPage,

  /// Pass 3: 同页晚到 caption 认领
  lateBound,

  /// Pass 4: 分离式排版序号配对（预印本 Figure Legends 布局）
  ordinalMatch,

  /// 兼容旧清单；新提取不再使用此配对方式。
  visualOnly,
}

/// 提取策略 profile。
///
/// 保留旧调用接口；三种策略均以题注为入口，auto 仅用于诊断分流。
enum FigureExtractProfile { auto, paper, general }

// ─── 公开数据模型 ─────────────────────────────────────────
//
// LayoutBlock 已上移到 document_structure.dart（extract.json 的唯一防腐层），
// 此处 export 维持原有公开 API。

/// 一个检测到的 figure 区域（caption + 视觉块 + 子图注 block 的集合）
class FigureCaptionRef {
  final int pageIndex;
  final String? blockId;
  final String text;
  final int? lineIndex;
  final int? start;
  final int? end;

  const FigureCaptionRef({
    required this.pageIndex,
    required this.text,
    this.blockId,
    this.lineIndex,
    this.start,
    this.end,
  });

  Map<String, dynamic> toJson() => {
    'page_idx': pageIndex,
    'text': text,
    if (blockId != null) 'block_id': blockId,
    if (lineIndex != null) 'line_index': lineIndex,
    if (start != null) 'start': start,
    if (end != null) 'end': end,
  };

  factory FigureCaptionRef.fromJson(Map<String, dynamic> json) =>
      FigureCaptionRef(
        pageIndex: json['page_idx'] as int,
        text: json['text'] as String,
        blockId: json['block_id'] as String?,
        lineIndex: json['line_index'] as int?,
        start: json['start'] as int?,
        end: json['end'] as int?,
      );
}

class FigureSegment {
  final int pageIndex;
  final List<LayoutBlock> blocks;
  final String captionText;
  final String captionName;
  final CaptionSource captionSource;
  final PairMethod pairMethod;
  final List<FigureCaptionRef> captionRefs;

  const FigureSegment({
    required this.pageIndex,
    required this.blocks,
    required this.captionText,
    required this.captionName,
    required this.captionSource,
    required this.pairMethod,
    this.captionRefs = const [],
  });
}

/// manifest 中的一条记录,持久化到 figures.json
class FigureVisualRegion {
  final int pageIndex;
  final List<double> bbox;
  final List<String> blockIds;
  final String imagePath;
  const FigureVisualRegion({
    required this.pageIndex,
    required this.bbox,
    required this.blockIds,
    required this.imagePath,
  });
  Map<String, dynamic> toJson() => {
    'page_idx': pageIndex,
    'bbox': bbox,
    'block_ids': blockIds,
    'img': imagePath,
  };
  factory FigureVisualRegion.fromJson(Map<String, dynamic> json) =>
      FigureVisualRegion(
        pageIndex: json['page_idx'] as int,
        bbox: (json['bbox'] as List).map((v) => (v as num).toDouble()).toList(),
        blockIds: (json['block_ids'] as List).cast<String>(),
        imagePath: json['img'] as String,
      );
}

class FigureManifestEntry {
  final List<FigureVisualRegion> visualRegions;
  final List<Map<String, dynamic>> sourceRefs;
  final List<Map<String, dynamic>> replacementRefs;
  final String assignment;
  final String? sourceVersion;
  final List<String> notes;
  final String? id;
  final String imagePath;
  final String captionText;
  final int pageIndex;
  final List<String> blockIds;
  final List<FigureCaptionRef> captionRefs;

  /// MinerU 复合图对应的原始图片文件名；旧 manifest 没有此字段。
  final List<String>? sourceImageNames;

  /// 裁剪区域 [left, top, right, bottom]，API 坐标系 (144 DPI)
  final List<double>? cropBbox;

  /// Caption 的 bbox [left, top, right, bottom]，API 坐标系
  final List<double>? captionBbox;

  /// 输出图片宽度 (px)
  final int? widthPx;

  /// 输出图片高度 (px)
  final int? heightPx;

  /// Caption 发现来源 (block_match / markdown_fallback)
  final String? captionSource;

  /// Figure 相对 caption 的方向 (above / below / left / right)
  final String? direction;

  /// 配对方式 (same_page / cross_page / late_bound)
  final String? pairMethod;

  /// 裁剪区域推断方式 (caption_anchored / visual_union / legacy_fallback)
  final String? regionMethod;

  /// 条目种类：`figure` / `table` / `chart`（chart 覆盖 Scheme/Plate/Map 等
  /// `other` 类别 caption）。旧 manifest 无此字段 → null，消费方按 figure 兜底。
  final String? kind;

  const FigureManifestEntry({
    this.visualRegions = const [],
    this.sourceRefs = const [],
    this.replacementRefs = const [],
    this.assignment = 'confirmed',
    this.sourceVersion,
    this.notes = const [],
    required this.imagePath,
    required this.captionText,
    required this.pageIndex,
    required this.blockIds,
    this.id,
    this.sourceImageNames,
    this.captionRefs = const [],
    this.cropBbox,
    this.captionBbox,
    this.widthPx,
    this.heightPx,
    this.captionSource,
    this.direction,
    this.pairMethod,
    this.regionMethod,
    this.kind,
  });

  /// 兼容读取旧清单，匿名条目不再进入展示链路。
  bool get isAnonymous =>
      pairMethod == PairMethod.visualOnly.name || captionSource == 'none';

  /// caption 不是完整题注时不进入用户可见区域（例如 `a`、`(b)`）。
  static bool isUsableCaption(String text) {
    final normalized = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return false;
    return !RegExp(
      r'^\(?[a-z](?:\s*(?:,|and|&)\s*[a-z])*\)?[).:;,-]?$',
      caseSensitive: false,
    ).hasMatch(normalized);
  }

  /// 是否适合出现在用户可见的 figure 面。
  ///
  /// 视觉区域本身不能绕过题注与归属检查。
  bool get isDisplayFigure =>
      assignment == 'confirmed' && !isAnonymous && isUsableCaption(captionText);

  List<FigureVisualRegion> get regions => visualRegions.isNotEmpty
      ? visualRegions
      : [
          FigureVisualRegion(
            pageIndex: pageIndex,
            bbox: cropBbox ?? const [],
            blockIds: blockIds,
            imagePath: imagePath,
          ),
        ];

  Set<String> blocksOnPage(int page) => {
    for (final region in regions.where((r) => r.pageIndex == page))
      ...region.blockIds,
    for (final ref in captionRefs.where((r) => r.pageIndex == page))
      if (ref.blockId != null) ref.blockId!,
  };

  /// 用户可见子集：Outline 列表、正文替换、查看器画廊、摘要配图共用此过滤。
  /// manifest 全量仍留给 AI 补检 / 点图定位。
  static List<FigureManifestEntry> forDisplay(
    Iterable<FigureManifestEntry> all,
  ) => [
    for (final e in all)
      if (e.isDisplayFigure) e,
  ];

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      if (visualRegions.isNotEmpty)
        'visual_regions': visualRegions.map((r) => r.toJson()).toList(),
      if (sourceRefs.isNotEmpty) 'source_refs': sourceRefs,
      if (replacementRefs.isNotEmpty) 'replacement_refs': replacementRefs,
      'assignment': assignment,
      if (sourceVersion != null) 'source_version': sourceVersion,
      if (notes.isNotEmpty) 'notes': notes,
      'img': imagePath,
      'figure_title': captionText,
      'page_idx': pageIndex,
      'block_ids': blockIds,
    };
    if (id != null) m['id'] = id;
    if (captionRefs.isNotEmpty) {
      m['caption_refs'] = [for (final ref in captionRefs) ref.toJson()];
    }
    if (sourceImageNames != null) {
      m['source_images'] = sourceImageNames;
    }
    if (cropBbox != null) m['crop_bbox'] = cropBbox;
    if (captionBbox != null) m['caption_bbox'] = captionBbox;
    if (widthPx != null) m['width_px'] = widthPx;
    if (heightPx != null) m['height_px'] = heightPx;
    if (captionSource != null) m['caption_source'] = captionSource;
    if (direction != null) m['direction'] = direction;
    if (pairMethod != null) m['pair_method'] = pairMethod;
    if (regionMethod != null) m['region_method'] = regionMethod;
    if (kind != null) m['kind'] = kind;
    return m;
  }

  factory FigureManifestEntry.fromJson(Map<String, dynamic> json) {
    return FigureManifestEntry(
      visualRegions: [
        for (final r in json['visual_regions'] as List? ?? [])
          FigureVisualRegion.fromJson(Map<String, dynamic>.from(r as Map)),
      ],
      sourceRefs: [
        for (final r in json['source_refs'] as List? ?? [])
          Map<String, dynamic>.from(r as Map),
      ],
      replacementRefs: [
        for (final r in json['replacement_refs'] as List? ?? [])
          Map<String, dynamic>.from(r as Map),
      ],
      assignment: json['assignment'] as String? ?? 'confirmed',
      sourceVersion: json['source_version'] as String?,
      notes: (json['notes'] as List? ?? []).cast<String>(),
      id: json['id'] as String?,
      captionRefs: [
        for (final ref in json['caption_refs'] as List? ?? const [])
          FigureCaptionRef.fromJson(Map<String, dynamic>.from(ref as Map)),
      ],
      imagePath: json['img'] as String,
      captionText: json['figure_title'] as String,
      pageIndex: json['page_idx'] as int,
      blockIds: (json['block_ids'] as List<dynamic>)
          .map((e) => e.toString())
          .toList(),
      sourceImageNames: (json['source_images'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      cropBbox: (json['crop_bbox'] as List<dynamic>?)
          ?.map((v) => (v as num).toDouble())
          .toList(),
      captionBbox: (json['caption_bbox'] as List<dynamic>?)
          ?.map((v) => (v as num).toDouble())
          .toList(),
      widthPx: json['width_px'] as int?,
      heightPx: json['height_px'] as int?,
      captionSource: json['caption_source'] as String?,
      direction: json['direction'] as String?,
      pairMethod: json['pair_method'] as String?,
      regionMethod: json['region_method'] as String?,
      kind: json['kind'] as String?,
    );
  }

  String get markdownAnchor => id == null ? '' : '<!-- otter-figure:$id -->';

  static String identity(int page, Iterable<String> blocks) {
    final sorted = blocks.toSet().toList()..sort();
    return 'f_${sha256.convert(utf8.encode('$page:${sorted.join('|')}')).toString().substring(0, 20)}';
  }
}

/// 提取过程的整体诊断统计
class FigureExtractDiagnostics {
  final int totalCaptions;
  final int totalClusters;
  final int pairedCount;
  final int croppedCount;
  final int droppedCount;
  final List<Map<String, dynamic>> dropped;

  const FigureExtractDiagnostics({
    required this.totalCaptions,
    required this.totalClusters,
    required this.pairedCount,
    required this.croppedCount,
    required this.droppedCount,
    this.dropped = const [],
  });

  Map<String, dynamic> toJson() => {
    'total_captions': totalCaptions,
    'total_clusters': totalClusters,
    'paired_count': pairedCount,
    'cropped_count': croppedCount,
    'dropped_count': droppedCount,
    if (dropped.isNotEmpty) 'dropped': dropped,
  };
}

class FigureExtractResult {
  final String outputDir;
  final List<FigureManifestEntry> entries;
  final FigureExtractDiagnostics diagnostics;
  const FigureExtractResult({
    required this.outputDir,
    required this.entries,
    required this.diagnostics,
  });
}

/// 页面栏位布局的公开视图，用于 AI 排版修复判断跨栏图/表。
/// 坐标为 144 DPI。单栏时 leftColRight/rightColLeft 为 null。
class ColumnLayout {
  final bool isDoubleColumn;
  final double pageLeft, pageRight;
  final double? leftColRight, rightColLeft;

  const ColumnLayout({
    required this.isDoubleColumn,
    required this.pageLeft,
    required this.pageRight,
    this.leftColRight,
    this.rightColLeft,
  });
}

/// 单页 caption 召回的公开视图（caption-first AI 修缮用）。
///
/// 保留 [continuationBlocks]（多行合并的延续行原 block，
/// 其 blockId 必须进 manifest 的 blockIds 以满足 md 替换契约）与 anchor 的
/// [groupId]/[blockOrder]。bbox 为 144 DPI [left,top,right,bottom]，
/// markdownFallback 来源时为 null。
class CaptionCandidateInfo {
  final int pageIndex;
  final String text;
  final String captionName;
  final CaptionSource source;
  final List<double>? bbox;
  final String? blockId;
  final List<FigureCaptionRef> sourceRefs;

  /// 多行 caption 合并的延续行（保留各自原始 bbox/content），其 blockId 须进
  /// 下游 manifest 的 blockIds。
  final List<LayoutBlock> continuationBlocks;

  final int? groupId;
  final int? blockOrder;

  const CaptionCandidateInfo({
    required this.pageIndex,
    required this.text,
    required this.captionName,
    required this.source,
    required this.bbox,
    required this.blockId,
    required this.continuationBlocks,
    required this.groupId,
    required this.blockOrder,
    this.sourceRefs = const [],
  });

  List<String> get continuationBlockIds => [
    for (final b in continuationBlocks) b.blockId,
  ];
}

/// AI 修缮后处理裁剪的单条请求（[FigureExtractService.cropFiguresFromSegments] 入参）。
///
/// [pageIndex] = visual 所在页（manifest 落点）；caption 在别的页时
/// [captionPageIndex] != [pageIndex]，裁剪排除 caption 块（走 visual_union
/// 退化路径，与 [FigureExtractService.extractFigures] 的跨页处理一致）。
/// [continuationBlockIds] 是 caption 延续行——仅入 manifest blockIds 满足 md
/// 替换契约，不参与裁剪区域（它们是 caption 文本，不是 figure 视觉）。
class FigureCropRequest {
  final List<double>? pageSize;
  final int pageIndex;
  final List<LayoutBlock> visualBlocks;
  final String? id;
  final List<FigureCaptionRef> captionRefs;
  final String? captionBlockId;
  final int? captionPageIndex;
  final String captionText;
  final List<double>? captionBbox;
  final List<String> continuationBlockIds;
  final String kind;
  final String pairMethod;
  final String captionSource;

  const FigureCropRequest({
    this.pageSize,
    required this.pageIndex,
    required this.visualBlocks,
    this.id,
    this.captionRefs = const [],
    required this.captionBlockId,
    required this.captionPageIndex,
    required this.captionText,
    required this.captionBbox,
    required this.continuationBlockIds,
    required this.kind,
    required this.pairMethod,
    required this.captionSource,
  });
}

// ─── 内部数据 ────────────────────────────────────────────

/// bbox 工具类，避免到处手写 `[0] [1] [2] [3]`
class _Bbox {
  const _Bbox(this.left, this.top, this.right, this.bottom);

  final double left, top, right, bottom;

  factory _Bbox.fromBlock(LayoutBlock b) => b.blockBbox.length != 4
      ? const _Bbox(0, 0, 0, 0)
      : _Bbox(b.blockBbox[0], b.blockBbox[1], b.blockBbox[2], b.blockBbox[3]);

  factory _Bbox.union(Iterable<LayoutBlock> blocks) {
    var l = double.infinity, t = double.infinity;
    var r = double.negativeInfinity, b = double.negativeInfinity;
    var any = false;
    for (final blk in blocks) {
      if (blk.blockBbox.length != 4) continue;
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
    required this.source,
    this.bbox,
    this.blockId,
    this.groupId,
    this.blockOrder,
    this.continuationBlocks = const [],
    this.lineIndex,
    this.sourceRefs = const [],
  });

  final int pageIndex;
  final String text;
  final String captionName;
  final CaptionSource source;
  final _Bbox? bbox;
  final String? blockId;

  /// Anchor block 的 PaddleOCR 页内逻辑分组 ID（同组 block 属于同一逻辑实体）。
  /// markdownFallback 来源时为 null（无 anchor block）。
  final int? groupId;

  /// Anchor block 的 PaddleOCR 页内阅读顺序。markdownFallback 来源时为 null。
  final int? blockOrder;

  final List<LayoutBlock> continuationBlocks;
  final int? lineIndex;
  final List<FigureCaptionRef> sourceRefs;
}

class _PageData {
  _PageData(this.pageIndex, this.blocks, this.markdown);

  final int pageIndex;
  final List<LayoutBlock> blocks;
  final String markdown;
}

/// 视觉块或子图注块,绑定 pageIndex 用于跨页配对.
///
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

/// 页面栏位布局——双栏检测结果，用于配对阶段防止跨栏误配。
class _PageColumns {
  const _PageColumns._({
    required this.isDoubleColumn,
    required this.pageLeft,
    required this.pageRight,
    this.leftColRight,
    this.rightColLeft,
  });

  final bool isDoubleColumn;
  final double pageLeft, pageRight;
  final double? leftColRight, rightColLeft;

  /// 两个 bbox 是否在同一栏（单栏页面始终返回 true，跨栏元素与任何栏匹配）。
  bool sameColumn(_Bbox a, _Bbox b) {
    if (!isDoubleColumn) return true;
    final ca = _columnOf(a);
    final cb = _columnOf(b);
    if (ca < 0 || cb < 0) return true;
    return ca == cb;
  }

  /// 0=左栏, 1=右栏, -1=跨栏/不确定
  int _columnOf(_Bbox bbox) {
    if (!isDoubleColumn) return -1;
    const margin = 30.0;
    if (bbox.right <= leftColRight! + margin) return 0;
    if (bbox.left >= rightColLeft! - margin) return 1;
    return -1;
  }

  static _PageColumns detect(List<LayoutBlock> pageBlocks) {
    double pageLeft = double.infinity, pageRight = 0;
    for (final b in pageBlocks) {
      if (b.blockBbox.length < 4) continue;
      if (b.blockBbox[0] < pageLeft) pageLeft = b.blockBbox[0];
      if (b.blockBbox[2] > pageRight) pageRight = b.blockBbox[2];
    }
    if (pageLeft.isInfinite || pageRight <= pageLeft) {
      return _PageColumns._(isDoubleColumn: false, pageLeft: 0, pageRight: 0);
    }

    const textLabels = {'text', 'paragraph_title', 'abstract'};
    final textBlocks = pageBlocks
        .where(
          (b) => textLabels.contains(b.blockLabel) && b.blockBbox.length == 4,
        )
        .toList();
    if (textBlocks.length < 4) {
      return _PageColumns._(
        isDoubleColumn: false,
        pageLeft: pageLeft,
        pageRight: pageRight,
      );
    }

    const minPerSide = 3;
    const margin = 30.0;
    final pageMid = pageLeft + (pageRight - pageLeft) / 2;
    final leftBlocks = textBlocks
        .where((b) => b.blockBbox[2] <= pageMid + margin)
        .toList();
    final rightBlocks = textBlocks
        .where((b) => b.blockBbox[0] >= pageMid - margin)
        .toList();

    if (leftBlocks.length < minPerSide || rightBlocks.length < minPerSide) {
      return _PageColumns._(
        isDoubleColumn: false,
        pageLeft: pageLeft,
        pageRight: pageRight,
      );
    }

    final leftColRight = leftBlocks.fold<double>(
      0.0,
      (m, b) => b.blockBbox[2] > m ? b.blockBbox[2] : m,
    );
    final rightColLeft = rightBlocks.fold<double>(
      double.infinity,
      (m, b) => b.blockBbox[0] < m ? b.blockBbox[0] : m,
    );

    return _PageColumns._(
      isDoubleColumn: true,
      pageLeft: pageLeft,
      pageRight: pageRight,
      leftColRight: leftColRight,
      rightColLeft: rightColLeft,
    );
  }
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

/// 从统一版面结构 + 原始 PDF 中提取 figure/chart/table 区域。
///
/// 流水线:
///   Stage 0  解析 JSON → [_PageData] (blocks + markdown)
///   Stage 1  Inventory: 收集所有 caption mention + figure block
///   Stage 2  Pair: 原生关系优先、题注定界；几何关系有歧义时保留原图
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
  static const _captionMergeExcludeLabels = {'image', 'chart', 'table'};

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

  /// Body-text labels: 当候选块为这些标签且已积累的 caption 描述已完整时,
  /// 终止多行合并. 这既阻止把正文段落吃进 caption, 又容许 OCR 将
  /// caption 延续行错标为 text 的场景 (此时 anchor 描述不完整, 合并继续).
  static const _bodyTextContinuationLabels = {
    'text',
    'paragraph_title',
    'abstract',
    'aside_text',
  };

  /// 视觉簇配 caption 的距离阈值占整页对角线的比例
  static const _captionMatchRatio = 0.5;

  /// Auto profile：编号 caption 数 / image·chart 簇数 ≥ 此值 → paper。
  /// 低于此值（或无编号 caption）→ general。
  static const _autoPaperCaptionRatio = 0.5;

  // ─── caption 配置(从 assets 加载) ────────────────────

  static const _cjkModifierLangs = {'zh', 'zh-Hant', 'ja', 'ko'};

  late final RegExp _mainCaptionRe;
  late final RegExp _supplementaryCaptionRe;
  late final RegExp _tableCaptionRe;
  late final RegExp _otherCaptionRe;
  late final RegExp _captionModifierTailRe;
  bool _initialized = false;
  bool get isInitialized => _initialized;

  static List<String> _collectCategoryPrefixes(
    Map<String, dynamic> conf,
    String category,
  ) {
    final prefixes = <String>[];
    for (final node in conf.values) {
      if (node is! Map<String, dynamic>) continue;
      final items = node[category];
      if (items is List) {
        prefixes.addAll(items.cast<String>());
      }
    }
    return prefixes;
  }

  static List<String> _collectMainPrefixes(Map<String, dynamic> conf) {
    return [
      ..._collectCategoryPrefixes(conf, 'figure'),
      ..._collectCategoryPrefixes(conf, 'table'),
      ..._collectCategoryPrefixes(conf, 'other'),
    ];
  }

  static List<String> _collectSupplementaryPrefixes(
    Map<String, dynamic> conf, {
    String? category,
  }) {
    final supplementary = conf['supplementary'];
    if (supplementary is! Map<String, dynamic>) return const [];

    final prefixes = <String>{};
    final standalone = supplementary['standalone'];
    if (standalone is List && category == null) {
      prefixes.addAll(standalone.cast<String>());
    } else if (standalone is Map) {
      for (final kind
          in category == null ? ['figure', 'table', 'other'] : [category]) {
        prefixes.addAll((standalone[kind] as List? ?? []).cast<String>());
      }
    }

    final modifiers = supplementary['modifiers'];
    if (modifiers is! Map<String, dynamic>) {
      return prefixes.toList();
    }

    for (final entry in modifiers.entries) {
      final lang = entry.key;
      final mods = entry.value;
      if (mods is! List) continue;
      final bases = _langPrefixes(conf, lang, category: category);
      for (final rawMod in mods) {
        final modifier = rawMod as String;
        for (final base in bases) {
          prefixes.add('$modifier $base');
          if (_cjkModifierLangs.contains(lang)) {
            prefixes.add('$modifier$base');
          }
        }
      }
    }

    return prefixes.toList();
  }

  static List<String> _langPrefixes(
    Map<String, dynamic> conf,
    String code, {
    String? category,
  }) {
    final node = conf[code];
    if (node is! Map<String, dynamic>) return const [];
    final result = <String>[];
    for (final kind
        in category == null ? ['figure', 'table', 'other'] : [category]) {
      final items = node[kind];
      if (items is List) {
        result.addAll(items.cast<String>());
      }
    }
    return result;
  }

  static String _prefixAlternatives(Iterable<String> prefixes) {
    final sorted = prefixes.toSet().toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return sorted
        .map((p) {
          final escaped = p
              .split(RegExp(r'\s+'))
              .map(RegExp.escape)
              .join(r'\s+');
          // Figur + e 不能冒充 Figure；但允许无空格的 FigS1、FigureA1。
          final boundary = RegExp(r'[A-Za-z]$').hasMatch(p)
              ? r'(?![A-Za-z](?![.．\-‐‑–]?[0-9０-９]))'
              : '';
          return '$escaped$boundary';
        })
        .join('|');
  }

  /// 召回、分类与补充材料判定使用相同的编号及词边界，避免补充表被归为图。
  static RegExp _buildCaptionRe(
    Map<String, dynamic> conf, {
    String? category,
    bool supplementaryOnly = false,
  }) {
    final normal = category == null
        ? _collectMainPrefixes(conf)
        : _collectCategoryPrefixes(conf, category);
    final supplementary = _collectSupplementaryPrefixes(
      conf,
      category: category,
    );
    final prefixes = [...supplementary, if (!supplementaryOnly) ...normal];
    final branches = <String>[
      if (prefixes.isNotEmpty)
        '(?:${_prefixAlternatives(prefixes)})${conf['number_pattern']}',
      if (supplementaryOnly &&
          normal.isNotEmpty &&
          conf['supplementary_number_pattern'] is String)
        '(?:${_prefixAlternatives(normal)})${conf['supplementary_number_pattern']}',
    ];
    for (final raw in conf['number_first'] as List? ?? []) {
      final item = raw as Map;
      if (supplementaryOnly && item['supplementary'] != true) continue;
      final labels = <String>[
        for (final kind
            in category == null ? ['figure', 'table', 'other'] : [category])
          ...(item[kind] as List? ?? []).cast<String>(),
      ];
      if (labels.isNotEmpty) {
        branches.add(
          '${item['number_pattern']}\\s+(?:${_prefixAlternatives(labels)})',
        );
      }
    }
    return RegExp(
      '^(?:${branches.join('|')})${conf['suffix_pattern']}',
      caseSensitive: false,
    );
  }

  Future<void> init() async {
    if (_initialized) return;
    final raw = await rootBundle.loadString(
      'assets/config/caption_patterns.json',
    );
    final conf = jsonDecode(raw) as Map<String, dynamic>;
    final modifiers = (conf['supplementary'] as Map)['modifiers'] as Map;
    _captionModifierTailRe = RegExp(
      '(?:${modifiers.values.expand((v) => (v as List).cast<String>()).map(RegExp.escape).join('|')})\\s*\$',
      caseSensitive: false,
    );

    _mainCaptionRe = _buildCaptionRe(conf);
    _supplementaryCaptionRe = _buildCaptionRe(conf, supplementaryOnly: true);
    _tableCaptionRe = _buildCaptionRe(conf, category: 'table');
    _otherCaptionRe = _buildCaptionRe(conf, category: 'other');
    _initialized = true;
  }

  /// 判断文本是否为 main caption（"Figure 1." / "图 1" 等主标题）。
  /// 与本服务 trimCaptionFromRegion 的判定保持同源。使用前须 [init]。
  bool isMainCaption(String text) =>
      _mainCaptionRe.hasMatch(_normalizeCaptionText(text));

  static bool isCaptionLabel(String label) =>
      label == 'figure_title' ||
      label == 'table_title' ||
      label == 'chart_title' ||
      label == 'image_title' ||
      label == 'caption' ||
      label.endsWith('_caption');

  /// 返回原文中的题注范围；正文前后缀不能随着整块一起被消费。
  List<({int start, int end})> captionRanges(
    String text, {
    bool explicit = false,
  }) {
    final pattern = RegExp(
      _mainCaptionRe.pattern.substring(1),
      caseSensitive: false,
    );
    final starts = <int>[];
    for (final match in pattern.allMatches(text)) {
      final lineStart = match.start == 0
          ? 0
          : text.lastIndexOf('\n', match.start - 1) + 1;
      final prefix = text.substring(lineStart, match.start);
      final atBoundary =
          prefix.trim().isEmpty ||
          RegExp(r'^[\s#*_]+$').hasMatch(prefix) ||
          (RegExp(r'[。！？.!?]\s+$').hasMatch(prefix) &&
              RegExp(r'[:：|]').hasMatch(match[0]!));
      if (atBoundary) starts.add(match.start);
    }
    if (starts.isEmpty &&
        explicit &&
        FigureManifestEntry.isUsableCaption(text)) {
      return [(start: 0, end: text.length)];
    }
    return [
      for (var i = 0; i < starts.length; i++)
        (
          start: starts[i],
          end: () {
            final limit = i + 1 < starts.length ? starts[i + 1] : text.length;
            final paragraph = RegExp(
              r'\r?\n\s*\r?\n',
            ).firstMatch(text.substring(starts[i], limit));
            return paragraph == null ? limit : starts[i] + paragraph.start;
          }(),
        ),
    ];
  }

  /// 判断文本是否为补充 figure caption（Supplementary / Extended Data 等）。
  /// 生图参考图超限时优先剔除此类条目。使用前须 [init]。
  bool isSupplementaryCaption(String text) =>
      _supplementaryCaptionRe.hasMatch(_normalizeCaptionText(text));

  /// 从 caption 文本提取文件名标识（"Figure 1." → "Figure_1"）。非 caption 返回空串。
  /// 供 AI 修缮合并阶段按 captionName 匹配启发式 manifest 条目。使用前须 [init]。
  String extractCaptionName(String text) => _extractCaptionName(text);

  /// 按 caption 文本分类 kind：`figure` / `table` / `chart`。
  /// `chart` = caption 配置的 `other` 类别（Scheme/Chart/Plate/Map/Box/Diagram/
  /// Exhibit）；supplementary 归 `figure`。使用前须 [init]。
  String classifyKind(String text) {
    final normalized = _normalizeCaptionText(text);
    if (_tableCaptionRe.hasMatch(normalized)) return 'table';
    if (_otherCaptionRe.hasMatch(normalized)) return 'chart';
    return 'figure';
  }

  /// 从 caption 文本提取文件名标识(如 "Figure 1." → "Figure_1")
  String _extractCaptionName(String text) {
    final m = _mainCaptionRe.firstMatch(_normalizeCaptionText(text));
    if (m == null) return '';
    return m.group(0)!.replaceAll('.', '').replaceAll(' ', '_').trim();
  }

  /// 判断 block 内容是否为纯子图序号（如 `a`、`(b)`、`a,b`）。
  ///
  /// 调用方仍需结合 block label、caption 位置和 bbox 判断归属；这里故意
  /// 只识别整块短文本，避免把带完整说明的正文误当成子图视觉块。
  bool isSubfigureLabelBlock(LayoutBlock block) {
    final text = _normalizeCaptionText(block.blockContent);
    return text.length <= _maxSubLabelLength &&
        text.isNotEmpty &&
        _subfigureLabelRe.hasMatch(text);
  }

  static final RegExp _captionWhitespaceRe = RegExp(r'\s+');
  static final RegExp _captionNoteLeadRe = RegExp(
    r'^(?:\([a-z](?:\s*(?:,|and|&)\s*[a-z])*\)|[a-z](?:\s*(?:,|and|&)\s*[a-z])*[).:;-])\s+\S',
    caseSensitive: false,
  );
  static final RegExp _subfigureLabelRe = RegExp(
    r'^(?:\([a-z](?:\s*(?:,|and|&)\s*[a-z])*\)|[a-z](?:\s*(?:,|and|&)\s*[a-z])*[).:;-]?)$',
    caseSensitive: false,
  );

  static String _normalizeCaptionText(String text) {
    return text.trim().replaceAll(_captionWhitespaceRe, ' ');
  }

  /// 判断已积累的 caption 文本是否具有"完整描述": 去掉 figure 编号前缀后,
  /// 剩余文本以句末标点 (. ? !) 结尾.
  /// 用于多行合并: 当 caption 已完整时, 阻止 body-text label 块继续合并.
  bool _captionDescriptionComplete(String text) {
    final normalized = _normalizeCaptionText(text);
    final m = _mainCaptionRe.firstMatch(normalized);
    if (m == null) return false;
    final afterPrefix = normalized.substring(m.end).trim();
    if (afterPrefix.isEmpty) return false;
    final last = afterPrefix[afterPrefix.length - 1];
    return last == '.' || last == '?' || last == '!';
  }

  static String _joinCaptionParts(Iterable<String> parts) {
    final merged = <String>[];
    for (final raw in parts) {
      final text = _normalizeCaptionText(raw);
      if (text.isEmpty) continue;
      if (merged.contains(text)) continue;
      merged.add(text);
    }
    return merged.join(' ');
  }

  bool _isTableCaption(_CaptionCandidate c) => _tableCaptionRe.hasMatch(c.text);

  // ─── Stage 0: 解析 ────────────────────────────────────

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
    final collected = {
      for (final page in pages) page.pageIndex: _collectCaptionCandidates(page),
    };
    // 页尾未完句与下一页首段连接时，仍保留两个页面各自的原文来源。
    for (var pi = 0; pi + 1 < pages.length; pi++) {
      final page = pages[pi], next = pages[pi + 1];
      if (next.pageIndex != page.pageIndex + 1) continue;
      bool contentBlock(LayoutBlock b) =>
          !const {
            'header',
            'footer',
            'number',
            'page_number',
            'header_image',
            'footer_image',
          }.contains(b.blockLabel) &&
          b.blockBbox.length == 4;
      final tail = _Bbox.union(page.blocks.where(contentBlock));
      final head = next.blocks.where(contentBlock).firstOrNull;
      if (head == null ||
          !isCaptionLabel(head.blockLabel) ||
          _isVisualBlock(head) ||
          isMainCaption(head.blockContent)) {
        continue;
      }
      final firstBox = _Bbox.fromBlock(head);
      final nextBounds = _Bbox.union(next.blocks.where(contentBlock));
      final candidates = collected[page.pageIndex]!;
      for (var ci = 0; ci < candidates.length; ci++) {
        final c = candidates[ci], box = candidates[ci].bbox;
        if (box == null ||
            _captionDescriptionComplete(c.text) ||
            tail.bottom - box.bottom > 12 ||
            firstBox.top - nextBounds.top > 12 ||
            !RegExp(
              r'^[a-z\u4e00-\u9fff]',
            ).hasMatch(head.blockContent.trim()) ||
            firstBox.right <= box.left ||
            firstBox.left >= box.right) {
          continue;
        }
        final parts = [
          head,
          ..._scanCaptionContinuation(next, next.blocks.indexOf(head)),
        ];
        final ids = parts.map((b) => b.blockId).toSet();
        collected[next.pageIndex]!.removeWhere(
          (other) => ids.contains(other.blockId),
        );
        candidates[ci] = _CaptionCandidate(
          pageIndex: c.pageIndex,
          text: _joinCaptionParts([
            c.text,
            ...parts.map((b) => b.blockContent),
          ]),
          captionName: c.captionName,
          source: c.source,
          bbox: c.bbox,
          blockId: c.blockId,
          groupId: c.groupId,
          blockOrder: c.blockOrder,
          continuationBlocks: c.continuationBlocks,
          lineIndex: c.lineIndex,
          sourceRefs: [
            ...c.sourceRefs,
            for (final b in parts)
              FigureCaptionRef(
                pageIndex: next.pageIndex,
                blockId: b.blockId,
                text: b.blockContent,
              ),
          ],
        );
        break;
      }
    }
    final normalized = <_PageData>[];

    for (final original in pages) {
      final numberedNearby = collected.entries.any(
        (entry) =>
            (entry.key - original.pageIndex).abs() <= 1 &&
            entry.value.any((c) => isMainCaption(c.text)),
      );
      final visuals = original.blocks.where(_isVisualBlock).toList();
      final visualRegion = _Bbox.union(visuals);
      final pageCaptions = collected[original.pageIndex]!.where((c) {
        if (!numberedNearby || isMainCaption(c.text) || c.bbox == null) {
          return true;
        }
        final block = original.blocks
            .where((b) => b.blockId == c.blockId)
            .firstOrNull;
        if (block?.parentId != null) return true;
        // 编号主图附近、紧贴视觉区域的短标题是图内标注；不屏蔽长的无编号题注。
        return !(c.text.length <= 80 &&
            c.bbox!.gapTo(visualRegion) <= 24 &&
            c.bbox!.bottom - c.bbox!.top <
                (visualRegion.bottom - visualRegion.top) * .1);
      }).toList();
      final pageRegion = _Bbox.union(original.blocks);
      final plate =
          numberedNearby &&
          visuals.length > 1 &&
          !pageCaptions.any((c) => isMainCaption(c.text)) &&
          (visualRegion.right - visualRegion.left) *
                  (visualRegion.bottom - visualRegion.top) >
              pageRegion.right * pageRegion.bottom * 0.5 &&
          !original.blocks.any(
            (b) =>
                b.blockLabel == 'text' &&
                (b.blockContent.length > 80 ||
                    !_contains(visualRegion, _Bbox.fromBlock(b))),
          );
      // 整页图内部的短说明属于图内标记，不能阻断子图聚类；正文页仍保留阻断。
      // 编号主图附近的无编号 OCR 标题通常是图内标记；长段落仍保留正文阻断语义。
      final blocks = original.blocks.map((b) {
        final repeatedHeader =
            b.blockLabel == 'paragraph_title' &&
            b.blockBbox.length == 4 &&
            b.blockBbox[1] < _Bbox.union(original.blocks).bottom * 0.08 &&
            pages
                    .where(
                      (p) => p.blocks.any(
                        (other) =>
                            other.blockLabel == b.blockLabel &&
                            other.blockContent == b.blockContent,
                      ),
                    )
                    .length >=
                2;
        if (repeatedHeader) {
          return LayoutBlock(
            blockId: b.blockId,
            blockLabel: 'header',
            blockBbox: b.blockBbox,
            blockContent: b.blockContent,
            sourceData: b.sourceData,
          );
        }
        if (!numberedNearby ||
            (b.blockLabel != 'figure_title' &&
                !(plate && b.blockLabel == 'text')) ||
            isMainCaption(b.blockContent) ||
            isSubfigureLabelBlock(b)) {
          return b;
        }
        return LayoutBlock(
          blockId: b.blockId,
          blockLabel: b.blockContent.length > 80 ? 'text' : 'figure_annotation',
          blockBbox: b.blockBbox,
          rawBbox: b.rawBbox,
          blockContent: b.blockContent,
          groupId: b.groupId,
          globalGroupId: b.globalGroupId,
          blockOrder: b.blockOrder,
          parentId: b.parentId,
          sourceImage: b.sourceImage,
          sourceData: b.sourceData,
        );
      }).toList();
      final page = _PageData(original.pageIndex, blocks, original.markdown);
      normalized.add(page);
      captions.addAll(pageCaptions);

      // 排除集合 = anchor blockId ∪ 所有 continuation block ids.
      // 后者由多行 caption 合并产生, 同样不应被 figure 召回当成视觉块/子标签.
      final captionBlockIds = <String>{};
      for (final c in collected.values.expand((v) => v)) {
        captionBlockIds.addAll(
          c.sourceRefs
              .where((r) => r.pageIndex == original.pageIndex)
              .map((r) => r.blockId)
              .whereType<String>(),
        );
      }
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
      pages: normalized,
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
  ///     完全漏检的 caption 名, 吸收后续 `(A)`/`(B)` 子图说明后补入.
  List<_CaptionCandidate> _collectCaptionCandidates(_PageData page) {
    // Phase 1: 识别 anchor — 任意 label, 仅看内容是否匹配主标题正则.
    // 同 captionName 选内容最长的 block (保留它在 page.blocks 中的索引,
    // Phase 2 从该索引向下扫描延续行).
    final anchorByName =
        <String, ({int index, LayoutBlock block, int start, int end})>{};
    for (var i = 0; i < page.blocks.length; i++) {
      final b = page.blocks[i];
      if (_isVisualBlock(b)) continue;
      for (final range in captionRanges(
        b.blockContent,
        explicit: isCaptionLabel(b.blockLabel),
      )) {
        final content = b.blockContent.substring(range.start, range.end).trim();
        if (!FigureManifestEntry.isUsableCaption(content)) continue;
        anchorByName['${b.blockId}:${range.start}'] = (
          index: i,
          block: b,
          start: range.start,
          end: range.end,
        );
      }
    }

    // Phase 2: 对每个 anchor 吸收延续行.
    final candidates = <_CaptionCandidate>[];
    final consumed = <String>{};
    for (final pick in anchorByName.values) {
      if (consumed.contains(pick.block.blockId)) continue;
      // OCR can report the same caption twice at overlapping coordinates.
      // Repeated numbers elsewhere on the page remain distinct identities.
      final duplicates = anchorByName.values
          .where(
            (other) =>
                other.block != pick.block &&
                _extractCaptionName(pick.block.blockContent).isNotEmpty &&
                _extractCaptionName(other.block.blockContent) ==
                    _extractCaptionName(pick.block.blockContent) &&
                _overlaps(
                  _Bbox.fromBlock(pick.block),
                  _Bbox.fromBlock(other.block),
                ),
          )
          .toList();
      if (duplicates.any(
        (d) => d.block.blockContent.length > pick.block.blockContent.length,
      )) {
        continue;
      }
      final continuations =
          pick.block.parentId != null ||
              pick.end < pick.block.blockContent.trimRight().length
          ? <LayoutBlock>[]
          : _scanCaptionContinuation(page, pick.index);
      continuations.addAll(duplicates.map((d) => d.block));
      consumed.addAll(continuations.map((b) => b.blockId));
      final anchor = pick.block;
      final anchorContent = _normalizeCaptionText(
        anchor.blockContent.substring(pick.start, pick.end),
      );
      final mergedText = _joinCaptionParts([
        anchorContent,
        for (final c in continuations)
          if (!duplicates.any((d) => d.block == c)) c.blockContent,
      ]);
      final mergedBbox = continuations.isEmpty
          ? _Bbox.fromBlock(anchor)
          : _Bbox.union([anchor, ...continuations]);

      candidates.add(
        _CaptionCandidate(
          pageIndex: page.pageIndex,
          text: mergedText,
          captionName: _extractCaptionName(anchorContent),
          source: CaptionSource.blockMatch,
          bbox: anchor.blockBbox.length == 4 ? mergedBbox : null,
          blockId: anchor.blockId,
          groupId: anchor.groupId,
          blockOrder: anchor.blockOrder,
          continuationBlocks: continuations,
          sourceRefs: [
            FigureCaptionRef(
              pageIndex: page.pageIndex,
              blockId: anchor.blockId,
              text: anchor.blockContent.substring(pick.start, pick.end),
              start: pick.start,
              end: pick.end,
            ),
            for (final block in continuations)
              FigureCaptionRef(
                pageIndex: page.pageIndex,
                blockId: block.blockId,
                text: block.blockContent,
              ),
          ],
        ),
      );
    }

    // Phase 3: markdown 行兜底 (parsing_res_list 完全漏检时).
    final knownNames = candidates.map((c) => c.captionName).toSet();
    if (page.markdown.isNotEmpty) {
      for (final raw in page.markdown.split('\n')) {
        final t = _normalizeCaptionText(raw);
        if (t.isEmpty || !_mainCaptionRe.hasMatch(t)) continue;
        final name = _extractCaptionName(t);
        if (name.isEmpty ||
            knownNames.contains(name) ||
            candidates.any((c) => c.text.contains(t))) {
          continue;
        }
        knownNames.add(name);
        candidates.add(
          _CaptionCandidate(
            pageIndex: page.pageIndex,
            text: _joinCaptionParts([
              t,
              ..._scanMarkdownCaptionContinuation(
                page.markdown.split('\n'),
                raw,
              ),
            ]),
            captionName: name,
            source: CaptionSource.markdownFallback,
            lineIndex: page.markdown.split('\n').indexOf(raw),
          ),
        );
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
  ///   6. **body-text label + 描述已完整** — 候选块标签为 text/paragraph_title 等,
  ///      且已积累的 caption 文本在去掉 figure 编号前缀后以句末标点结尾.
  ///      这阻止把正文段落吃进 caption, 同时保留 OCR 将 caption 延续行错标为
  ///      text 的合并能力 (此时 anchor 描述不完整, 句末标点检查不通过).
  ///
  /// 满足 (2)/(3)/(4)/(6) 时跳过该 block 继续扫描——可能 PaddleOCR 在 caption 中间
  /// 插入了不相关的 vision_footnote 等; 不应中断合并扫描. 但 (1) 是硬终止.
  /// 实际为了简单, 我们对 (2) 直接 break, (3)/(4)/(6) 也 break, 只有 (1) 单独标记.
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
    var previousBox = anchorBbox;
    var accumulatedText = _normalizeCaptionText(anchor.blockContent);

    for (var j = anchorIndex + 1; j < page.blocks.length; j++) {
      final cand = page.blocks[j];
      final candContent = cand.blockContent.trim();

      final cbox = _Bbox.fromBlock(cand);
      final sameBand =
          cand.blockBbox.length == 4 &&
          cbox.left >= previousBox.right &&
          cbox.left - previousBox.right <= anchorWidth * .2 &&
          (cbox.top - previousBox.top).abs() <=
              math.max(12, anchorHeight * .2) &&
          (cbox.right - cbox.left) >= anchorWidth * .6;
      // 左栏以补充材料修饰词结束时，右栏的图号是引用续句，不是新题注。
      final continuedReference =
          sameBand && _captionModifierTailRe.hasMatch(accumulatedText);
      if (_mainCaptionRe.hasMatch(candContent) && !continuedReference) break;
      if (_captionMergeExcludeLabels.contains(cand.blockLabel)) {
        // JSON 中可能晚到一块图像；位于题注带上方的图不打断横向续栏。
        if (cbox.bottom <= anchorBbox.top) continue;
        break;
      }
      if (const {
            'header',
            'footer',
            'number',
            'doc_title',
            'paragraph_title',
          }.contains(cand.blockLabel) &&
          !_captionNoteLeadRe.hasMatch(candContent)) {
        break;
      }

      // 分组只作提示；同组也必须满足几何与正文边界，不能吞并独立段落。
      {
        if (!isMainCaption(anchor.blockContent) &&
            _bodyTextContinuationLabels.contains(cand.blockLabel)) {
          break;
        }
        // 终止: 纵向 gap 过大
        final gap = cbox.top - previousBox.bottom;
        // OCR 脚注行框可能相交；阅读顺序向下且非包含关系时不能截掉续行。
        final overlappingNote =
            const {
              'footnote',
              'vision_footnote',
              'vision_footer',
              'footer',
              'header',
            }.contains(cand.blockLabel) &&
            cbox.top > previousBox.top &&
            cbox.bottom > previousBox.bottom;
        if (!sameBand && ((gap < 0 && !overlappingNote) || gap > maxGap)) break;

        // 终止: 横向 overlap 不足 (避免吃入邻栏)
        final overlap = math.max(
          0.0,
          math.min(anchorBbox.right, cbox.right) -
              math.max(anchorBbox.left, cbox.left),
        );
        final alignedShortNote =
            (cbox.left - anchorBbox.left).abs() <= anchorHeight &&
            (const {
                  'footnote',
                  'vision_footnote',
                  'vision_footer',
                }.contains(cand.blockLabel) ||
                _captionNoteLeadRe.hasMatch(candContent));
        final overlapWidth = alignedShortNote
            ? math.min(anchorWidth, cbox.right - cbox.left)
            : anchorWidth;
        if (!sameBand &&
            (overlapWidth <= 0 ||
                overlap / overlapWidth < _continuationOverlapRatio)) {
          break;
        }

        // 终止: body-text label + caption 描述已完整 → 正文段落, 不是延续行
        if (_bodyTextContinuationLabels.contains(cand.blockLabel) &&
            _captionDescriptionComplete(accumulatedText) &&
            !_captionNoteLeadRe.hasMatch(candContent)) {
          break;
        }

        // 终止: label-only caption + body-text → 全宽段落不是续接.
        // 场景: "图3-11"（66px 宽）后面紧跟全宽正文（837px 宽），
        // 正文的左边缘远在 anchor 左侧，说明它是独立段落而非 caption 续接。
        if (_bodyTextContinuationLabels.contains(cand.blockLabel) &&
            !_captionDescriptionComplete(accumulatedText)) {
          final leftDrift = anchorBbox.left - cbox.left;
          if (leftDrift > anchorWidth) break;
        }

        // group_id 停止信号: 候选 block 与后续 block 共享 group_id
        // (属于另一段落) → 它不是 caption 的续接
        if (!sameBand && cand.groupId != null && j + 1 < page.blocks.length) {
          final next = page.blocks[j + 1];
          if (next.groupId == cand.groupId) break;
        }
      }

      // 跳过空内容 (PaddleOCR 偶有空 block)
      if (candContent.isEmpty) {
        previousBox = cbox;
        continue;
      }

      result.add(cand);
      accumulatedText = _joinCaptionParts([accumulatedText, candContent]);
      previousBox = cbox;
    }

    return result;
  }

  List<String> _scanMarkdownCaptionContinuation(
    List<String> lines,
    String anchorLine,
  ) {
    final anchorIndex = lines.indexOf(anchorLine);
    if (anchorIndex < 0) return const [];

    final result = <String>[];
    for (var i = anchorIndex + 1; i < lines.length; i++) {
      final text = _normalizeCaptionText(lines[i]);
      if (text.isEmpty) continue;
      if (_captionNoteLeadRe.hasMatch(text)) {
        result.add(text);
        continue;
      }
      break;
    }
    return result;
  }

  /// Collect visual bodies and annotations, excluding caption-owned blocks.
  List<_FigureBlock> _collectFigureCandidates(
    _PageData page,
    Set<String> excludeBlockIds,
  ) => [
    for (final block in page.blocks)
      if (figureLabels.contains(block.blockLabel) &&
          !excludeBlockIds.contains(block.blockId) &&
          (block.blockLabel != 'figure_title' || isSubfigureLabelBlock(block)))
        _FigureBlock(page.pageIndex, block),
  ];

  // ─── Stage 2: 配对 ────────────────────────────────────

  /// 从 v0.1.4 的聚类／四轮配对演进：保留拆分候选，在竞争范围内一起裁决。
  ({
    List<FigureSegment> segments,
    List<Map<String, dynamic>> dropped,
    int totalClusters,
    FigureExtractProfile resolvedProfile,
  })
  _pair(
    _Inventory inv, {
    FigureExtractProfile profile = FigureExtractProfile.auto,
  }) {
    final byPage = {for (final page in inv.pages) page.pageIndex: page};
    final visuals = inv.figureBlocks
        .where((v) => _isVisualBlock(v.block) && v.block.blockBbox.length == 4)
        .toList();
    final cross = _crossPageOwners(inv);
    final clusters = <List<_FigureBlock>>[];
    for (final page in inv.pages) {
      final remaining = visuals
          .where((v) => v.pageIndex == page.pageIndex)
          .toList();
      final gap = _pageDiagonal(page.blocks) * .06;
      while (remaining.isNotEmpty) {
        final members = [remaining.removeAt(0)];
        var changed = true;
        while (changed) {
          changed = false;
          for (final v in remaining.toList()) {
            if (!members.any(
              (m) =>
                  m.bbox.gapTo(v.bbox) <= gap ||
                  ((m.bbox.top - v.bbox.top).abs() < 12 &&
                      (m.bbox.bottom - v.bbox.bottom).abs() < 12 &&
                      m.bbox.gapTo(v.bbox) <=
                          math.min(
                                m.bbox.right - m.bbox.left,
                                v.bbox.right - v.bbox.left,
                              ) *
                              .3),
            )) {
              continue;
            }
            final proposed = [...members, v];
            final box = _Bbox.union(proposed.map((m) => m.block));
            if (page.blocks.any(
              (b) =>
                  b.blockBbox.length == 4 &&
                  !proposed.any((m) => m.block == b) &&
                  _isStableBlocker(b) &&
                  _overlaps(box, _Bbox.fromBlock(b)) &&
                  !proposed.any((m) => _contains(m.bbox, _Bbox.fromBlock(b))),
            )) {
              continue;
            }
            members.add(v);
            remaining.remove(v);
            changed = true;
          }
        }
        clusters.add(members);
      }
    }
    final options = <_CaptionCandidate, List<(double, List<_FigureBlock>)>>{};
    for (final caption in inv.captions) {
      final page = byPage[caption.pageIndex]!;
      final cap = page.blocks
          .where((b) => b.blockId == caption.blockId)
          .firstOrNull;
      final diagonal = _pageDiagonal(page.blocks);
      final native = visuals
          .where(
            (v) =>
                v.pageIndex == caption.pageIndex &&
                cap?.parentId != null &&
                v.block.parentId == cap!.parentId,
          )
          .toList();
      final candidates = <List<_FigureBlock>>[
        for (final visual in visuals) [visual],
        ...clusters,
        if (native.isNotEmpty) native,
        if (cross.values.any((v) => v.$2 == caption))
          cross.entries
              .where((e) => e.value.$2 == caption)
              .map((e) => e.key)
              .toList(),
      ];
      final seen = <String>{};
      final choices = <(double, List<_FigureBlock>)>[];
      for (final candidate in candidates) {
        final key =
            candidate.map((v) => '${v.pageIndex}:${v.block.blockId}').toList()
              ..sort();
        if (!seen.add(key.join('|'))) continue;
        var score = 0.0;
        var valid = true;
        for (final v in candidate) {
          final samePage = v.pageIndex == caption.pageIndex;
          final parent =
              samePage &&
              cap?.parentId != null &&
              v.block.parentId == cap!.parentId;
          final isCross = cross[v]?.$2 == caption;
          final visualText = v.block.blockContent.isNotEmpty
              ? v.block.blockContent
              : p
                    .basenameWithoutExtension(v.block.sourceImage ?? '')
                    .replaceAll('_', ' ');
          final match = _mainCaptionRe.firstMatch(
            _normalizeCaptionText(visualText),
          );
          final name = match
              ?.group(0)
              ?.replaceAll('.', '')
              .replaceAll(' ', '_')
              .trim();
          final numbered =
              name != null &&
              name.toLowerCase() == caption.captionName.toLowerCase() &&
              !page.blocks.any(_isVisualBlock);
          if (!samePage && !isCross && !numbered) {
            valid = false;
            break;
          }
          if (samePage && caption.bbox != null) {
            final distance = v.bbox.gapTo(caption.bbox!);
            if (distance > diagonal * _captionMatchRatio ||
                !_PageColumns.detect(
                  page.blocks,
                ).sameColumn(v.bbox, caption.bbox!) ||
                _associationBlocked([v.block], caption, page.blocks)) {
              valid = false;
              break;
            }
            score += 4 - distance / math.max(diagonal, 1) * 10;
          } else if (parent || isCross || numbered) {
            score += isCross ? 3.5 : 4;
          } else if (samePage &&
              caption.source == CaptionSource.markdownFallback &&
              inv.captions
                      .where((c) => c.pageIndex == caption.pageIndex)
                      .length ==
                  1 &&
              clusters
                      .where((c) => c.first.pageIndex == caption.pageIndex)
                      .length ==
                  1) {
            score += 2.5;
          } else {
            valid = false;
            break;
          }
          if (parent) score += 1;
          if ((v.block.blockLabel == 'table') != _isTableCaption(caption)) {
            score -= .35;
          }
        }
        if (!valid) continue;
        if (candidate.length > 1 &&
            candidate.every((v) => v.pageIndex == caption.pageIndex) &&
            caption.bbox != null &&
            _associationBlocked(
              candidate.map((v) => v.block).toList(),
              caption,
              page.blocks,
            )) {
          continue;
        }
        choices.add((score, candidate));
      }
      choices.sort((a, b) => b.$1.compareTo(a.$1));
      options[caption] = choices.take(24).toList();
    }
    // 仅在共享视觉观察的连通分量内搜索，避免全文候选形成笛卡尔积。
    final pending = inv.captions.toSet();
    final assigned = <_FigureBlock, _CaptionCandidate>{};
    while (pending.isNotEmpty) {
      final component = <_CaptionCandidate>{pending.first};
      final related = <_FigureBlock>{};
      var changed = true;
      while (changed) {
        changed = false;
        for (final c in component) {
          related.addAll(options[c]!.expand((v) => v.$2));
        }
        for (final c in pending.toList()) {
          if (component.contains(c) ||
              !options[c]!.any((v) => v.$2.any(related.contains))) {
            continue;
          }
          component.add(c);
          changed = true;
        }
      }
      pending.removeAll(component);
      var beam = <(double, Map<_FigureBlock, _CaptionCandidate>)>[(0, {})];
      for (final caption in component) {
        final next = <(double, Map<_FigureBlock, _CaptionCandidate>)>[];
        for (final state in beam) {
          next.add(state);
          for (final option in options[caption]!) {
            if (option.$2.any(state.$2.containsKey)) continue;
            next.add((
              state.$1 + option.$1,
              {...state.$2, for (final v in option.$2) v: caption},
            ));
          }
        }
        next.sort((a, b) => b.$1.compareTo(a.$1));
        beam = next.take(64).toList();
      }
      final best = beam.first;
      final competitive = beam.where((b) => best.$1 - b.$1 < .2).toList();
      for (final entry in best.$2.entries) {
        if (competitive.every((b) => b.$2[entry.key] == entry.value)) {
          assigned[entry.key] = entry.value;
        }
      }
    }
    final segments = <FigureSegment>[];
    final owned = <LayoutBlock>{};
    for (final caption in assigned.values.toSet()) {
      for (final page in inv.pages) {
        final members = assigned.entries
            .where(
              (e) => e.value == caption && e.key.pageIndex == page.pageIndex,
            )
            .map((e) => e.key)
            .toList();
        if (members.isEmpty) continue;
        final box = _Bbox.union(members.map((m) => m.block));
        // 同一个整图中的未认领子框属于同一出现，记录来源后才能精确去重。
        members.addAll(
          visuals.where(
            (v) =>
                v.pageIndex == page.pageIndex &&
                !assigned.containsKey(v) &&
                members.any((m) => _contains(m.bbox, v.bbox)),
          ),
        );
        final cap = byPage[caption.pageIndex]!.blocks
            .where((b) => b.blockId == caption.blockId)
            .firstOrNull;
        for (final b in page.blocks) {
          if (members.any((m) => m.block == b) ||
              owned.contains(b) ||
              inv.captions.any(
                (c) =>
                    c.sourceRefs.any(
                      (r) =>
                          r.pageIndex == page.pageIndex &&
                          r.blockId == b.blockId,
                    ) ||
                    c.pageIndex == page.pageIndex &&
                        (c.blockId == b.blockId ||
                            c.continuationBlocks.any(
                              (part) => part.blockId == b.blockId,
                            )),
              ) ||
              _isVisualBlock(b)) {
            continue;
          }
          final inside =
              b.blockBbox.length == 4 && _contains(box, _Bbox.fromBlock(b));
          final note = _isVisionAnnotationBlock(b);
          final near =
              b.blockBbox.length == 4 && box.gapTo(_Bbox.fromBlock(b)) <= 24;
          final parent =
              cap?.parentId != null &&
              b.parentId == cap!.parentId &&
              page.pageIndex == caption.pageIndex;
          if (inside ||
              (note && (parent || near)) ||
              ((isSubfigureLabelBlock(b) ||
                      b.blockLabel == 'figure_annotation') &&
                  near)) {
            members.add(
              _FigureBlock(
                page.pageIndex,
                LayoutBlock(
                  blockId: b.blockId,
                  blockLabel: note && !inside && _isCaptionNoteBlock(b)
                      ? 'vision_footnote'
                      : 'figure_annotation',
                  blockBbox: b.blockBbox,
                  rawBbox: b.rawBbox,
                  blockContent: b.blockContent,
                  parentId: b.parentId,
                  sourceData: b.sourceData,
                ),
              ),
            );
            owned.add(b);
          }
        }
        segments.add(
          _buildSegmentFromBlocks(
            members,
            caption,
            caption.pageIndex == page.pageIndex
                ? PairMethod.samePage
                : PairMethod.crossPage,
          ),
        );
      }
    }
    segments.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
    return (
      segments: segments,
      dropped: [
        for (final visual in visuals)
          if (!segments.any(
            (s) =>
                s.pageIndex == visual.pageIndex &&
                s.blocks.contains(visual.block),
          ))
            {
              'page_idx': visual.pageIndex,
              'block_id': visual.block.blockId,
              'reason': 'no_confirmed_caption',
            },
      ],
      totalClusters: clusters.length,
      resolvedProfile: _resolveProfile(
        inv,
        profile,
        visualClusterCount: clusters.length,
      ),
    );
  }

  Map<_FigureBlock, (double, _CaptionCandidate)> _crossPageOwners(
    _Inventory inv,
  ) {
    final byPage = {for (final p in inv.pages) p.pageIndex: p};
    final clusters = <_Cluster>[];
    for (final page in inv.pages) {
      final remaining = inv.figureBlocks
          .where(
            (v) =>
                v.pageIndex == page.pageIndex &&
                _isVisualBlock(v.block) &&
                v.block.blockBbox.length == 4,
          )
          .toList();
      final gap = _pageDiagonal(page.blocks) * 0.06;
      while (remaining.isNotEmpty) {
        final members = [remaining.removeAt(0)];
        var grew = true;
        while (grew) {
          grew = false;
          for (final next in remaining.toList()) {
            final close = members.any(
              (m) =>
                  ((m.block.parentId != null &&
                              m.block.parentId == next.block.parentId) ||
                          (m.block.groupId != null &&
                              m.block.groupId == next.block.groupId)) &&
                      m.bbox.gapTo(next.bbox) <= gap * 3 ||
                  m.bbox.gapTo(next.bbox) <= gap,
            );
            if (!close) continue;
            final proposed = [...members, next];
            final region = _Bbox.union(proposed.map((v) => v.block));
            if (page.blocks.any(
              (b) =>
                  !proposed.any((v) => v.block == b) &&
                  _isStableBlocker(b) &&
                  _overlaps(region, _Bbox.fromBlock(b)) &&
                  !proposed.any((v) => _contains(v.bbox, _Bbox.fromBlock(b))),
            )) {
              continue;
            }
            members.add(next);
            remaining.remove(next);
            grew = true;
          }
        }
        clusters.add(_Cluster(page.pageIndex, members));
      }
    }

    bool boundaryClear(
      _PageData page,
      _Bbox box,
      bool toEnd,
      Set<LayoutBlock> owned,
    ) {
      final columns = _PageColumns.detect(page.blocks);
      return !page.blocks.any((b) {
        if (owned.contains(b) ||
            const {
              'header',
              'footer',
              'header_image',
              'number',
            }.contains(b.blockLabel) ||
            b.blockBbox.length != 4 ||
            (!_isStableBlocker(b) && !_isVisualBlock(b))) {
          return false;
        }
        final other = _Bbox.fromBlock(b);
        if (_contains(box, other) || !columns.sameColumn(box, other)) {
          return false;
        }
        return toEnd ? other.top >= box.bottom : other.bottom <= box.top;
      });
    }

    final candidates = <_Cluster, List<(int, double, _CaptionCandidate)>>{};
    for (final cluster in clusters) {
      final imagePage = byPage[cluster.pageIndex]!;
      for (final caption in inv.captions) {
        if ((caption.pageIndex - cluster.pageIndex).abs() != 1) continue;
        final capPage = byPage[caption.pageIndex]!;
        final capBlock = capPage.blocks
            .where((b) => b.blockId == caption.blockId)
            .firstOrNull;
        if (inv.captions.where((c) => c.pageIndex == caption.pageIndex).length >
                1 &&
            !capPage.blocks.any(_isVisualBlock)) {
          continue;
        }
        final localOwner = inv.figureBlocks.any(
          (v) =>
              v.pageIndex == caption.pageIndex &&
              _isVisualBlock(v.block) &&
              caption.bbox != null &&
              v.bbox.gapTo(caption.bbox!) <=
                  _pageDiagonal(capPage.blocks) * 0.15 &&
              _PageColumns.detect(
                capPage.blocks,
              ).sameColumn(v.bbox, caption.bbox!) &&
              !_associationBlocked([v.block], caption, capPage.blocks),
        );
        if (localOwner) continue;
        final forward = cluster.pageIndex < caption.pageIndex;
        final bounds = _Bbox.union(imagePage.blocks);
        final pageArea = bounds.right * bounds.bottom;
        final imageArea =
            (cluster.bbox.right - cluster.bbox.left) *
            (cluster.bbox.bottom - cluster.bbox.top);
        final dominant =
            pageArea > 0 &&
            imageArea / pageArea >= 0.5 &&
            !inv.captions.any((c) => c.pageIndex == imagePage.pageIndex) &&
            !imagePage.blocks.any(
              (b) =>
                  !const [
                    'header',
                    'footer',
                    'header_image',
                    'number',
                  ].contains(b.blockLabel) &&
                  _isStableBlocker(b) &&
                  !_contains(cluster.bbox, _Bbox.fromBlock(b)),
            );
        if (!dominant &&
            !boundaryClear(
              imagePage,
              cluster.bbox,
              forward,
              cluster.blocks.map((v) => v.block).toSet(),
            )) {
          continue;
        }
        // 整页复合图常把题注放在下一页正文下方；该布局优先于上一页的题注。
        final followingLegend =
            dominant &&
            forward &&
            isMainCaption(caption.text) &&
            caption.bbox != null &&
            !capPage.blocks.any(_isVisualBlock) &&
            caption.bbox!.top > _Bbox.union(capPage.blocks).bottom * 0.5 &&
            (caption.bbox!.right - caption.bbox!.left >=
                    (cluster.bbox.right - cluster.bbox.left) * 0.65 ||
                imagePage.blocks.any(
                  (b) => RegExp(
                    r'\b(?:legend|caption)\s+(?:on|continues?\s+on)\s+(?:the\s+)?next\s+page\b|图注见下页|圖說見下頁',
                    caseSensitive: false,
                  ).hasMatch(b.blockContent),
                ));
        if (caption.bbox == null) {
          final lines = capPage.markdown.split('\n');
          final before = forward
              ? lines.take(caption.lineIndex ?? 0)
              : lines.skip((caption.lineIndex ?? lines.length) + 1);
          if (caption.source != CaptionSource.markdownFallback ||
              before.any((line) => line.trim().isNotEmpty)) {
            continue;
          }
        } else {
          if (!followingLegend &&
              !boundaryClear(capPage, caption.bbox!, !forward, {
                ?capBlock,
                ...caption.continuationBlocks,
              })) {
            continue;
          }
          final a = _PageColumns.detect(
            imagePage.blocks,
          )._columnOf(cluster.bbox);
          final b = _PageColumns.detect(
            capPage.blocks,
          )._columnOf(caption.bbox!);
          if (a >= 0 &&
              b >= 0 &&
              a != b &&
              !(forward ? a == 1 && b == 0 : a == 0 && b == 1)) {
            continue;
          }
        }
        final imageBounds = _Bbox.union(imagePage.blocks);
        final capBounds = _Bbox.union(capPage.blocks);
        final capBox = caption.bbox;
        final distance = capBox == null
            ? 0.0
            : forward
            ? math.max(0.0, imageBounds.bottom - cluster.bbox.bottom) +
                  math.max(0.0, capBox.top - capBounds.top)
            : math.max(0.0, cluster.bbox.top - imageBounds.top) +
                  math.max(0.0, capBounds.bottom - capBox.bottom);
        candidates.putIfAbsent(cluster, () => []).add((
          followingLegend ? 0 : 1,
          distance,
          caption,
        ));
      }
    }
    final preferred = candidates.values
        .expand((v) => v)
        .where((c) => c.$1 == 0)
        .map((c) => c.$3)
        .toSet();
    for (final options in candidates.values) {
      final hasFollowingLegend = options.any((c) => c.$1 == 0);
      options.removeWhere(
        (c) => c.$1 != 0 && (hasFollowingLegend || preferred.contains(c.$3)),
      );
    }
    final result = <_FigureBlock, (double, _CaptionCandidate)>{};
    // 按完整视觉簇检查双向唯一，不能在遍历中删除竞争者制造伪唯一。
    for (final entry in candidates.entries) {
      if (entry.value.length != 1) continue;
      final best = entry.value.single;
      if (candidates.values
              .where((v) => v.any((c) => c.$3 == best.$3))
              .length !=
          1) {
        continue;
      }
      for (final visual in entry.key.blocks) {
        result[visual] = (best.$2, best.$3);
      }
    }
    return result;
  }

  static bool _contains(_Bbox outer, _Bbox inner) =>
      inner.left >= outer.left &&
      inner.right <= outer.right &&
      inner.top >= outer.top &&
      inner.bottom <= outer.bottom;

  static bool _overlaps(_Bbox a, _Bbox b) =>
      a.left < b.right &&
      b.left < a.right &&
      a.top < b.bottom &&
      b.top < a.bottom;

  bool _associationBlocked(
    List<LayoutBlock> visuals,
    _CaptionCandidate caption,
    List<LayoutBlock> page,
  ) {
    if (caption.bbox == null) return true;
    final boxes = [...visuals];
    final cap = LayoutBlock(
      blockId: '',
      blockLabel: 'figure_title',
      blockBbox: caption.bbox!.toList(),
      blockContent: caption.text,
    );
    final region = _Bbox.union([...boxes, cap]);
    for (final b in page) {
      if (b.blockId == caption.blockId ||
          caption.continuationBlocks.any((part) => part.blockId == b.blockId) ||
          visuals.contains(b) ||
          !_isStableBlocker(b) ||
          b.blockBbox.length != 4) {
        continue;
      }
      final box = _Bbox.fromBlock(b);
      // 图内短标记可能略微越过 OCR 图像边框，不应阻断图片与题注的归属。
      if (visuals.any((v) {
        final vb = _Bbox.fromBlock(v);
        return _contains(vb, box) ||
            (b.blockContent.length <= 80 &&
                !isMainCaption(b.blockContent) &&
                _overlaps(vb, box));
      })) {
        continue;
      }
      if (_overlaps(region, box)) return true;
    }
    return false;
  }

  /// Auto 分流：编号 caption 相对 image/chart 数量足够密 → paper，否则 general。
  ///
  /// 无 image/chart 时退回 paper（避免空文档误入 general）。
  /// 显式 [FigureExtractProfile.paper]/[FigureExtractProfile.general] 原样返回。
  FigureExtractProfile _resolveProfile(
    _Inventory inv,
    FigureExtractProfile requested, {
    required int visualClusterCount,
  }) {
    if (requested != FigureExtractProfile.auto) return requested;

    final captionCount = inv.captions.where((c) => !_isTableCaption(c)).length;

    if (visualClusterCount == 0) return FigureExtractProfile.paper;
    if (captionCount == 0) return FigureExtractProfile.general;

    final ratio = captionCount / visualClusterCount;
    return ratio >= _autoPaperCaptionRatio
        ? FigureExtractProfile.paper
        : FigureExtractProfile.general;
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
    PairMethod pairMethod,
  ) {
    final blocks = <LayoutBlock>[];
    final captionAllIds = <String>{};
    final samePage =
        figureBlocks.isEmpty ||
        figureBlocks.first.pageIndex == caption.pageIndex;
    if (samePage && caption.blockId != null) {
      blocks.add(
        LayoutBlock(
          blockId: caption.blockId!,
          blockLabel: 'figure_title',
          blockBbox: caption.bbox?.toList() ?? const [0, 0, 0, 0],
          blockContent: caption.text,
          captionKind: 'caption',
        ),
      );
      captionAllIds.add(caption.blockId!);
    }
    for (final cont
        in samePage ? caption.continuationBlocks : <LayoutBlock>[]) {
      blocks.add(cont);
      captionAllIds.add(cont.blockId);
    }
    for (final b in figureBlocks) {
      if (captionAllIds.contains(b.block.blockId)) continue;
      blocks.add(b.block);
    }
    final notes = figureBlocks
        .where((b) => _isCaptionNoteBlock(b.block))
        .toList();
    final captionText = _joinCaptionParts([
      caption.text,
      for (final b in notes) b.block.blockContent,
    ]);

    return FigureSegment(
      pageIndex: figureBlocks.isNotEmpty
          ? figureBlocks.first.pageIndex
          : caption.pageIndex,
      blocks: blocks,
      captionRefs: [
        if (caption.sourceRefs.isNotEmpty)
          ...caption.sourceRefs
        else
          FigureCaptionRef(
            pageIndex: caption.pageIndex,
            blockId: caption.blockId,
            text: caption.text,
            lineIndex: caption.lineIndex,
          ),
        for (final block
            in caption.sourceRefs.isEmpty
                ? caption.continuationBlocks
                : <LayoutBlock>[])
          FigureCaptionRef(
            pageIndex: caption.pageIndex,
            blockId: block.blockId,
            text: block.blockContent,
          ),
        for (final note in notes)
          FigureCaptionRef(
            pageIndex: note.pageIndex,
            blockId: note.block.blockId,
            text: note.block.blockContent,
          ),
      ],
      captionText: captionText,
      captionName: caption.captionName,
      captionSource: caption.source,
      pairMethod: pairMethod,
    );
  }

  bool _isCaptionNoteBlock(LayoutBlock block) {
    if (!_isVisionAnnotationBlock(block)) return false;
    final text = _normalizeCaptionText(block.blockContent);
    if (text.length <= _maxSubLabelLength) return false;
    return !isSubfigureLabelBlock(block);
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
    final subfigureLabels = segment
        .where(
          (b) =>
              isSubfigureLabelBlock(b) || b.blockLabel == 'figure_annotation',
        )
        .toList(growable: false);

    // 早返路径: 无 pageBlocks / 无 visual anchor / 无 caption → legacy "visual union".
    if (pageBlocks == null ||
        pageBlocks.isEmpty ||
        (visuals.isEmpty && subfigureLabels.isEmpty)) {
      final baseBlocks = [...visuals, ...subfigureLabels];
      final baseBbox = baseBlocks.isNotEmpty
          ? _Bbox.union(baseBlocks).toList()
          : _legacyFallbackBbox(segment);
      return trimCaptionFromRegion(baseBbox, segment);
    }
    final caption = _findSegmentCaption(segment);
    if (caption == null) {
      return trimCaptionFromRegion(
        _Bbox.union([...visuals, ...subfigureLabels]).toList(),
        segment,
      );
    }

    // direction-aware baseBbox.
    //
    // footnote/text 在 PaddleOCR 视角可能是两种语义:
    //   (1) caption 下方说明文字 "(B) 2-photon optical path." — 不属于 figure 区域
    //   (2) figure 内部子图位置标签 "(a)/(b)" — 属于 figure 区域 (PaddleOCR 漏检
    //       image 时, 这是唯一能锚定子图位置的 block)
    // 判据: 子图序号或 footnote/footer 与 figure 同 direction 侧
    //       (相对 caption) → 并入 baseBbox; 反侧 → 排除.
    final column = _detectColumnFor(caption, pageBlocks);
    final direction = _inferFigureDirection(caption, column, pageBlocks);
    final relevantLabels = segment
        .where(
          (b) =>
              (isSubfigureLabelBlock(b) ||
                  _isVisionAnnotationBlock(b) ||
                  b.blockLabel == 'figure_annotation') &&
              _isVisionFootnoteInFigureRegion(b, caption, direction),
        )
        .toList();
    final baseBbox = relevantLabels.isEmpty
        ? _Bbox.union(visuals).toList()
        : _Bbox.union([...visuals, ...relevantLabels]).toList();

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
    var left = region[0],
        top = region[1],
        right = region[2],
        bottom = region[3];

    for (final b in segment) {
      if (b.blockLabel != 'figure_title') continue;
      if (!FigureManifestEntry.isUsableCaption(b.blockContent)) continue;

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

  static bool _isVisionAnnotationBlock(LayoutBlock b) =>
      b.blockLabel == 'vision_footnote' || b.blockLabel == 'vision_footer';

  /// 无 caption 的匿名 segment 的 kind 兜底：按视觉 block label 推断。
  static String _visualKindFallback(List<LayoutBlock> blocks) {
    final visuals = blocks
        .where((b) => const ['image', 'chart', 'table'].contains(b.blockLabel))
        .toList();
    final outer = visuals
        .where(
          (b) =>
              b.blockBbox.length != 4 ||
              !visuals.any(
                (a) =>
                    a != b &&
                    a.blockBbox.length == 4 &&
                    _contains(_Bbox.fromBlock(a), _Bbox.fromBlock(b)) &&
                    (a.blockBbox[2] - a.blockBbox[0]) *
                            (a.blockBbox[3] - a.blockBbox[1]) >
                        (b.blockBbox[2] - b.blockBbox[0]) *
                            (b.blockBbox[3] - b.blockBbox[1]),
              ),
        )
        .toList();
    if (outer.isNotEmpty && outer.every((b) => b.blockLabel == 'table')) {
      return 'table';
    }
    if (outer.any((b) => b.blockLabel == 'chart')) return 'chart';
    return 'figure';
  }

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
    if (isSubfigureLabelBlock(b)) return false;
    if (_stableBlockerLabels.contains(b.blockLabel)) return true;
    // 另一个 figure 的主 caption (长 figure_title) 也阻塞,但短子标签
    // ("(A)"/"(b)" 这类) 不算——它们本身就是 figure 内部.
    if (b.blockLabel == 'figure_title' &&
        FigureManifestEntry.isUsableCaption(b.blockContent)) {
      return true;
    }
    return false;
  }

  /// 在 segment 中找出 main caption (label==figure_title + 匹配主标题正则).
  LayoutBlock? _findSegmentCaption(List<LayoutBlock> segment) {
    for (final b in segment) {
      if (b.blockLabel == 'figure_title' &&
          FigureManifestEntry.isUsableCaption(b.blockContent)) {
        return b;
      }
    }
    return null;
  }

  /// 完全无视觉块时的 fallback bbox:排除 caption 和 vision_footnote 的 union.
  List<double> _legacyFallbackBbox(List<LayoutBlock> segment) {
    final contents = segment
        .where(
          (b) =>
              !_mainCaptionRe.hasMatch(b.blockContent.trim()) &&
              b.blockLabel != 'vision_footnote',
        )
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

    final isDoubleColumn =
        leftBlocks.length >= _doubleColumnMinPerSide &&
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
    picture.dispose();
    final byteData = await cropped.toByteData(format: ui.ImageByteFormat.png);
    cropped.dispose();
    return byteData?.buffer.asUint8List();
  }

  // ─── 诊断辅助 ─────────────────────────────────────────

  /// 裁剪区域 + 推断方式 + 方向，用于填充 manifest 诊断字段。
  /// 不改变 [computeMergedBbox] 的公开接口——在其上层包装。
  ({List<double> bbox, String regionMethod, String? direction})
  _computeCropInfo(List<LayoutBlock> segment, {List<LayoutBlock>? pageBlocks}) {
    final visuals = segment.where(_isVisualBlock).toList();
    final caption = _findSegmentCaption(segment);

    String regionMethod;
    String? direction;

    if (pageBlocks == null || pageBlocks.isEmpty || visuals.isEmpty) {
      regionMethod = visuals.isNotEmpty ? 'visual_union' : 'legacy_fallback';
    } else if (caption == null) {
      regionMethod = 'visual_union';
    } else {
      regionMethod = 'caption_anchored';
      final column = _detectColumnFor(caption, pageBlocks);
      direction = _inferFigureDirection(caption, column, pageBlocks).name;
    }

    final bbox = computeMergedBbox(segment, pageBlocks: pageBlocks);
    return (bbox: bbox, regionMethod: regionMethod, direction: direction);
  }

  // ─── 公开入口 ─────────────────────────────────────────

  /// 检测页面栏位布局（单栏/双栏 + 左右栏边界），用于 AI 排版修复判断
  /// 跨栏图/表。包装 [_PageColumns.detect]，不需 [init]。
  static ColumnLayout detectColumns(List<LayoutBlock> pageBlocks) {
    final pc = _PageColumns.detect(pageBlocks);
    return ColumnLayout(
      isDoubleColumn: pc.isDoubleColumn,
      pageLeft: pc.pageLeft,
      pageRight: pc.pageRight,
      leftColRight: pc.leftColRight,
      rightColLeft: pc.rightColLeft,
    );
  }

  /// 收集单页所有 caption 候选（含 continuationBlocks + groupId + blockOrder），
  /// 用于 caption-first AI 修缮的预处理。复用 [_collectCaptionCandidates] 的
  /// 三阶段召回（anchor 识别 → 多行合并 → markdown 兜底）。使用前须 [init]。
  List<CaptionCandidateInfo> collectCaptionCandidatesPublic(
    List<LayoutBlock> pageBlocks,
    String markdown,
    int pageIndex,
  ) {
    assert(_initialized, 'FigureExtractService.init() 未调用');
    final page = _PageData(pageIndex, pageBlocks, markdown);
    return _collectCaptionCandidates(page)
        .map(
          (c) => CaptionCandidateInfo(
            pageIndex: c.pageIndex,
            text: c.text,
            captionName: c.captionName,
            source: c.source,
            bbox: c.bbox?.toList(),
            blockId: c.blockId,
            continuationBlocks: c.continuationBlocks,
            groupId: c.groupId,
            blockOrder: c.blockOrder,
            sourceRefs: c.sourceRefs,
          ),
        )
        .toList();
  }

  /// 按 AI 修缮裁决的 [segments] 裁剪 figure 图片并生成 [FigureManifestEntry]。
  ///
  /// 复用 [_renderFullPage]/[_computeCropInfo]/[_cropRegion]/[scaleBbox]，在
  /// [PdfProcessLock.instance.run] 内串行执行（与 [extractFigures] 共享 PDF 锁）。
  /// [pageBlocks] 按页索引提供，供 caption-anchored region inference 作 stable
  /// blocker 上下文；缺页传空列表。
  ///
  /// 与 [extractFigures] 的区别：不删 figures 目录、不重跑配对，仅按外部已裁决
  /// 的 segment 裁图。文件名唯一化（同 captionName 加 `_n` 后缀）。
  Future<List<FigureManifestEntry>> cropFiguresFromSegments({
    required String pdfPath,
    required List<FigureCropRequest> segments,
    required List<List<LayoutBlock>> pageBlocks,
    String? outputDir,
    CancelToken? cancelToken,
    void Function(int done, int total)? onProgress,
    bool trimWhitespace = false,
    bool preserveVisualBounds = false,
  }) async {
    assert(_initialized, 'FigureExtractService.init() 未调用');
    if (segments.isEmpty) return const [];

    final outDir = outputDir ?? DocPaths.figuresDir(pdfPath);
    final outDirObj = Directory(outDir);
    if (!outDirObj.existsSync()) {
      await outDirObj.create(recursive: true);
    }

    final byPage = <int, List<(int, FigureCropRequest)>>{};
    for (var i = 0; i < segments.length; i++) {
      byPage.putIfAbsent(segments[i].pageIndex, () => []).add((i, segments[i]));
    }

    final total = segments.length;
    onProgress?.call(0, total);

    final manifest = <FigureManifestEntry>[];
    final usedNames = <String>{};

    await PdfProcessLock.instance.run(() async {
      PdfDocument? document;
      try {
        document = await PdfDocument.openFile(
          pdfPath,
          passwordProvider: () => '',
        );

        for (final entry in byPage.entries) {
          if (cancelToken?.isCancelled ?? false) break;
          final pageIdx = entry.key;
          if (pageIdx < 0 || pageIdx >= document.pages.length) {
            log.d('[FigureExtract] AI 修缮: 页 $pageIdx 超出 PDF 页数,跳过');
            for (final (idx, _) in entry.value) {
              onProgress?.call(idx + 1, total);
            }
            continue;
          }

          final page = document.pages[pageIdx];
          final fullImage = await _renderFullPage(page);
          if (fullImage == null) {
            log.d('[FigureExtract] AI 修缮: 页 $pageIdx 渲染失败');
            for (final (idx, _) in entry.value) {
              onProgress?.call(idx + 1, total);
            }
            continue;
          }

          try {
            final rgba = trimWhitespace
                ? (await fullImage.toByteData(
                    format: ui.ImageByteFormat.rawRgba,
                  ))?.buffer.asUint8List()
                : null;
            final pageBlk = pageIdx < pageBlocks.length
                ? pageBlocks[pageIdx]
                : const <LayoutBlock>[];
            for (final (idx, req) in entry.value) {
              if (cancelToken?.isCancelled ?? false) break;

              // 跨页 segment: caption 在另一页 → 排除 caption 块，避免
              // trimCaptionFromRegion 误剪（与 extractFigures 跨页处理一致）。
              final captionOnPage =
                  req.captionBlockId != null &&
                  req.captionBbox != null &&
                  req.captionBbox!.length == 4 &&
                  req.captionBbox![2] > req.captionBbox![0] &&
                  req.captionBbox![3] > req.captionBbox![1] &&
                  req.captionPageIndex == pageIdx;
              final cropBlocks = captionOnPage
                  ? [
                      LayoutBlock(
                        blockId: req.captionBlockId!,
                        blockLabel: 'figure_title',
                        blockBbox: req.captionBbox!,
                        blockContent: req.captionText,
                      ),
                      ...req.visualBlocks,
                    ]
                  : req.visualBlocks;

              if (req.visualBlocks.isEmpty) continue;
              final cropInfo = _computeCropInfo(
                cropBlocks,
                pageBlocks: pageBlk,
              );
              final bounds = preserveVisualBounds
                  ? _Bbox.union(req.visualBlocks).toList()
                  : cropInfo.bbox;
              final size = req.pageSize;
              final proposedBbox = size == null
                  ? scaleBbox(bounds)
                  : [
                      bounds[0] / size[0] * fullImage.width,
                      bounds[1] / size[1] * fullImage.height,
                      bounds[2] / size[0] * fullImage.width,
                      bounds[3] / size[1] * fullImage.height,
                    ];
              final renderBbox = rgba == null
                  ? proposedBbox
                  : _tightenToInk(
                      rgba,
                      fullImage.width,
                      fullImage.height,
                      proposedBbox,
                    );
              final pngBytes = await _cropRegion(fullImage, renderBbox);
              if (pngBytes == null) {
                log.d('[FigureExtract] AI 修缮: 页 $pageIdx 裁剪失败');
                onProgress?.call(idx + 1, total);
                continue;
              }

              final cropWidth = (renderBbox[2] - renderBbox[0])
                  .clamp(0, fullImage.width.toDouble())
                  .toInt();
              final cropHeight = (renderBbox[3] - renderBbox[1])
                  .clamp(0, fullImage.height.toDouble())
                  .toInt();

              final name = _uniqueAiFixName(
                req.captionText,
                req.pageIndex,
                usedNames,
                outDir,
              );
              usedNames.add(name);
              final outPath = p.join(outDir, '$name.png');
              await File(outPath).writeAsBytes(pngBytes);

              manifest.add(
                FigureManifestEntry(
                  id: req.id,
                  captionRefs: req.captionRefs,
                  imagePath: outPath,
                  captionText: req.captionText,
                  pageIndex: pageIdx,
                  blockIds: [
                    if (captionOnPage) req.captionBlockId!,
                    ...req.continuationBlockIds,
                    for (final b in req.visualBlocks) b.blockId,
                  ],
                  cropBbox: bounds,
                  captionBbox: captionOnPage ? req.captionBbox : null,
                  widthPx: cropWidth > 0 ? cropWidth : null,
                  heightPx: cropHeight > 0 ? cropHeight : null,
                  captionSource: req.captionSource,
                  direction: cropInfo.direction,
                  pairMethod: req.pairMethod,
                  regionMethod: cropInfo.regionMethod == 'caption_anchored'
                      ? 'ai_caption_anchored'
                      : 'ai_${cropInfo.regionMethod}',
                  kind: req.kind,
                ),
              );

              onProgress?.call(idx + 1, total);
            }
          } finally {
            fullImage.dispose();
          }
        }
      } finally {
        document?.dispose();
      }
    });

    return manifest;
  }

  /// Trim only near-white outer space, preserving all disconnected panels and
  /// labels. Pixel data is shared by all crops on a page.
  static List<double> _tightenToInk(
    Uint8List rgba,
    int width,
    int height,
    List<double> proposed,
  ) {
    final left = proposed[0].floor().clamp(0, width);
    final top = proposed[1].floor().clamp(0, height);
    final right = proposed[2].ceil().clamp(left, width);
    final bottom = proposed[3].ceil().clamp(top, height);
    var minX = right, minY = bottom, maxX = left - 1, maxY = top - 1;
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        final i = (y * width + x) * 4;
        if (rgba[i + 3] == 0 ||
            (rgba[i] >= 254 && rgba[i + 1] >= 254 && rgba[i + 2] >= 254)) {
          continue;
        }
        minX = math.min(minX, x);
        maxX = math.max(maxX, x);
        minY = math.min(minY, y);
        maxY = math.max(maxY, y);
      }
    }
    if (maxX < minX || maxY < minY) return proposed;
    const padding = 6;
    return [
      math.max(left, minX - padding).toDouble(),
      math.max(top, minY - padding).toDouble(),
      math.min(right, maxX + 1 + padding).toDouble(),
      math.min(bottom, maxY + 1 + padding).toDouble(),
    ];
  }

  /// AI 修缮裁剪的文件名唯一化：captionName 清理后作 base，冲突时加 `_n`。
  String _uniqueAiFixName(
    String captionText,
    int pageIdx,
    Set<String> usedNames,
    String outputDir,
  ) {
    final m = _mainCaptionRe.firstMatch(_normalizeCaptionText(captionText));
    final base = m != null
        ? _sanitizeFilename(
            m.group(0)!.replaceAll('.', '').replaceAll(' ', '_').trim(),
          )
        : 'ai_fix_p$pageIdx';
    if (!usedNames.contains(base)) {
      final f = File(p.join(outputDir, '$base.png'));
      if (!f.existsSync()) return base;
    }
    for (var n = 2; ; n++) {
      final name = '${base}_$n';
      if (usedNames.contains(name)) continue;
      final f = File(p.join(outputDir, '$name.png'));
      if (f.existsSync()) continue;
      return name;
    }
  }

  /// 测试入口:跑完整 inventory + pair,返回 segment.
  ///
  /// 所有 profile 均要求有确认的题注。
  @visibleForTesting
  List<FigureSegment> findFigures(
    List<List<LayoutBlock>> pages, {
    List<String>? markdowns,
    FigureExtractProfile profile = FigureExtractProfile.auto,
  }) {
    assert(_initialized, 'FigureExtractService.init() 未调用');
    final pageData = [
      for (var i = 0; i < pages.length; i++)
        _PageData(
          i,
          pages[i],
          markdowns != null && i < markdowns.length ? markdowns[i] : '',
        ),
    ];
    final inv = _buildInventory(pageData);
    return _pair(inv, profile: profile).segments;
  }

  /// 从版面解析 JSON + PDF 中提取所有 figure,保存到 `{hash}/figures/`.
  ///
  /// [profile] 保留调用兼容，所有策略均从题注出发。
  Future<FigureExtractResult> extractFigures({
    required String resultPath,
    required String pdfPath,
    void Function(int done, int total)? onProgress,
    FigureExtractProfile profile = FigureExtractProfile.auto,
    String? jsonContent,
    bool publishManifest = true,
  }) async {
    assert(_initialized, 'FigureExtractService.init() 未调用');

    final resultFile = File(resultPath);
    if (jsonContent == null && !resultFile.existsSync()) {
      throw FileSystemException('版面解析结果文件不存在', resultPath);
    }
    final pdfFile = File(pdfPath);
    if (!pdfFile.existsSync()) {
      throw FileSystemException('PDF 文件不存在', pdfPath);
    }

    final structure = DocumentStructure.parse(
      jsonContent ?? await resultFile.readAsString(),
    );
    final root = Directory(DocPaths.figuresDir(pdfPath));
    await root.create(recursive: true);
    final generation = await createFigureGeneration(root.path);
    try {
      final result = await extractStructureFigures(
        structure: structure,
        pdfPath: pdfPath,
        outputDir: generation.path,
        profile: profile,
        onProgress: onProgress,
      );
      if (publishManifest) {
        await publishExtractionArtifacts({
          DocPaths.figuresManifest(pdfPath): encodeManifest(
            result.entries,
            pdfPath,
            diagnostics: result.diagnostics.toJson(),
          ),
        });
      }
      return result;
    } catch (_) {
      await generation.delete(recursive: true);
      rethrow;
    }
  }

  /// Both providers use the same ownership decisions and PDF cropper.
  Future<FigureExtractResult> extractStructureFigures({
    required DocumentStructure structure,
    required String pdfPath,
    required String outputDir,
    FigureExtractProfile profile = FigureExtractProfile.auto,
    void Function(int done, int total)? onProgress,
  }) async {
    final pages = [
      for (final page in structure.pages)
        _PageData(page.pageIndex, page.blocks, page.markdown),
    ];
    final inv = _buildInventory(pages);
    final paired = _pair(inv, profile: profile);
    final segments = paired.segments;
    final requests = <FigureCropRequest>[];
    for (final segment in segments) {
      final size = structure.pages
          .where((p) => p.pageIndex == segment.pageIndex)
          .firstOrNull
          ?.pageSize;
      if (size == null ||
          size.length != 2 ||
          size.any((v) => !v.isFinite || v <= 0)) {
        continue;
      }
      final caption = _findSegmentCaption(segment.blocks);
      requests.add(
        FigureCropRequest(
          pageSize: structure.pages
              .where((p) => p.pageIndex == segment.pageIndex)
              .firstOrNull
              ?.pageSize,
          pageIndex: segment.pageIndex,
          id: FigureManifestEntry.identity(segment.pageIndex, [
            for (final b in segment.blocks) b.blockId,
            for (final c in segment.captionRefs)
              'caption:${c.pageIndex}:${c.blockId ?? c.lineIndex}',
          ]),
          captionRefs: segment.captionRefs,
          visualBlocks: segment.blocks
              .where(
                (b) =>
                    b != caption &&
                    !segment.captionRefs.any(
                      (r) =>
                          r.pageIndex == segment.pageIndex &&
                          r.blockId == b.blockId,
                    ) &&
                    b.blockBbox.length == 4 &&
                    (_isVisualBlock(b) ||
                        isSubfigureLabelBlock(b) ||
                        b.blockLabel == 'figure_annotation' ||
                        b.blockLabel == 'vision_footnote'),
              )
              .toList(),
          captionBlockId: caption?.blockId,
          captionPageIndex:
              segment.captionRefs.firstOrNull?.pageIndex ?? segment.pageIndex,
          captionText: segment.captionText,
          captionBbox: caption?.blockBbox.length == 4
              ? caption!.blockBbox
              : null,
          continuationBlockIds: segment.blocks
              .where(
                (b) =>
                    b != caption &&
                    !_isVisualBlock(b) &&
                    !isSubfigureLabelBlock(b) &&
                    b.blockLabel != 'figure_annotation',
              )
              .map((b) => b.blockId)
              .toList(),
          kind: _visualKindFallback(segment.blocks) != 'figure'
              ? _visualKindFallback(segment.blocks)
              : isMainCaption(segment.captionText)
              ? classifyKind(segment.captionText)
              : _visualKindFallback(segment.blocks),
          pairMethod: segment.pairMethod.name,
          captionSource: segment.captionSource.name,
        ),
      );
    }
    final maxPage = structure.pages.fold<int>(
      -1,
      (v, page) => math.max(v, page.pageIndex),
    );
    final pageBlocks = List.generate(maxPage + 1, (_) => <LayoutBlock>[]);
    for (final page in inv.pages) {
      pageBlocks[page.pageIndex] = page.blocks
          .where((b) => b.blockBbox.length == 4)
          .toList();
    }
    final cropped = await cropFiguresFromSegments(
      pdfPath: pdfPath,
      segments: requests,
      pageBlocks: pageBlocks,
      outputDir: outputDir,
      onProgress: onProgress,
      trimWhitespace: false,
      preserveVisualBounds: true,
    );
    final manifest = <FigureManifestEntry>[];
    final sourceVersion = sha256
        .convert(utf8.encode(jsonEncode(structure.toJson())))
        .toString();
    for (final entry in cropped) {
      final request = requests.firstWhere((request) => request.id == entry.id);
      final segment = segments.firstWhere(
        (s) =>
            s.pageIndex == request.pageIndex &&
            FigureManifestEntry.identity(s.pageIndex, [
                  for (final b in s.blocks) b.blockId,
                  for (final c in s.captionRefs)
                    'caption:${c.pageIndex}:${c.blockId ?? c.lineIndex}',
                ]) ==
                request.id,
      );
      final ids = segment.blocks.map((b) => b.blockId).toList();
      final anchor = segment.captionRefs.firstOrNull;
      manifest.add(
        FigureManifestEntry.fromJson({
          ...entry.toJson(),
          'id': anchor == null
              ? entry.id
              : FigureManifestEntry.identity(anchor.pageIndex, [
                  anchor.blockId ?? 'line:${anchor.lineIndex}',
                  '${anchor.start ?? 0}',
                ]),
          'block_ids': ids,
          'visual_regions': [
            FigureVisualRegion(
              pageIndex: entry.pageIndex,
              bbox: entry.cropBbox ?? const [],
              blockIds: ids,
              imagePath: entry.imagePath,
            ).toJson(),
          ],
          'source_version': sourceVersion,
          'assignment': segment.captionSource == CaptionSource.none
              ? 'unresolved'
              : 'confirmed',
          'notes': segment.blocks
              .where((b) => b.blockLabel == 'vision_footnote')
              .map((b) => b.blockContent)
              .toList(),
          'source_refs': [
            for (final b in segment.blocks)
              {
                'page_idx': segment.pageIndex,
                'block_id': b.blockId,
                'label': b.blockLabel,
                if (b.sourceImage != null) 'path': b.sourceImage,
              },
          ],
          'source_images': segment.blocks
              .map((b) => b.sourceImage)
              .whereType<String>()
              .toSet()
              .toList(),
          'region_method': entry.regionMethod?.replaceFirst('ai_', ''),
        }),
      );
    }
    return FigureExtractResult(
      outputDir: outputDir,
      entries: await _combineRegions(manifest, outputDir),
      diagnostics: FigureExtractDiagnostics(
        totalCaptions: inv.captions.length,
        totalClusters: paired.totalClusters,
        pairedCount: segments
            .where((s) => s.captionSource != CaptionSource.none)
            .length,
        croppedCount: manifest.length,
        droppedCount: paired.dropped.length,
        dropped: paired.dropped,
      ),
    );
  }

  Future<List<FigureManifestEntry>> _combineRegions(
    List<FigureManifestEntry> entries,
    String outputDir,
  ) async {
    final groups = <List<FigureManifestEntry>>[];
    final continued = RegExp(
      r'continued|cont\.|续表|接上表|續表',
      caseSensitive: false,
    );
    for (final entry in entries) {
      final target = groups.where((group) {
        final previous = group.last;
        final shared = entry.captionRefs.any(
          (r) => previous.captionRefs.any(
            (p) =>
                p.pageIndex == r.pageIndex &&
                p.blockId == r.blockId &&
                p.lineIndex == r.lineIndex &&
                p.text == r.text,
          ),
        );
        if (shared) return true;
        if (entry.pageIndex != previous.pageIndex + 1) return false;
        final a = _mainCaptionRe.firstMatch(entry.captionText)?.group(0);
        final b = _mainCaptionRe.firstMatch(previous.captionText)?.group(0);
        final ab = entry.cropBbox, bb = previous.cropBbox;
        return entry.kind == 'table' &&
            previous.kind == 'table' &&
            a != null &&
            a == b &&
            continued.hasMatch(entry.captionText) &&
            ab != null &&
            bb != null &&
            (ab[0] - bb[0]).abs() < 24 &&
            (ab[2] - bb[2]).abs() < 24;
      }).toList();
      if (target.length == 1) {
        target.single.add(entry);
      } else {
        groups.add([entry]);
      }
    }
    final result = <FigureManifestEntry>[];
    for (final group in groups) {
      if (group.length == 1) {
        result.add(group.single);
        continue;
      }
      final images = <ui.Image>[];
      try {
        for (final entry in group) {
          final codec = await ui.instantiateImageCodec(
            await File(entry.imagePath).readAsBytes(),
          );
          try {
            images.add((await codec.getNextFrame()).image);
          } finally {
            codec.dispose();
          }
        }
        final width = images.map((i) => i.width).reduce(math.max);
        final height = images.fold<int>(0, (n, i) => n + i.height + 24);
        final scale = math.min(1.0, 12000 / height);
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.scale(scale);
        canvas.drawColor(const ui.Color(0xFFF0F2F5), ui.BlendMode.src);
        var y = 0.0;
        for (final image in images) {
          canvas.drawImage(
            image,
            ui.Offset((width - image.width) / 2, y),
            ui.Paint(),
          );
          y += image.height + 24;
        }
        final picture = recorder.endRecording();
        final preview = await picture.toImage(
          (width * scale).ceil(),
          (height * scale).ceil(),
        );
        picture.dispose();
        final bytes = await preview.toByteData(format: ui.ImageByteFormat.png);
        preview.dispose();
        if (bytes == null) {
          result.addAll(group);
          continue;
        }
        final first = group.first;
        final captionParts = [first.captionText];
        for (final entry in group.skip(1)) {
          if (entry.captionText == first.captionText) continue;
          final extra = entry.captionText
              .replaceFirst(_mainCaptionRe, '')
              .replaceFirst(
                RegExp(
                  r'^\s*[（(]?\s*(?:continued|cont\.|续表|接上表|續表)\s*[）).:：—-]*\s*',
                  caseSensitive: false,
                ),
                '',
              )
              .trim();
          if (extra.isNotEmpty) captionParts.add(extra);
        }
        final path = p.join(outputDir, 'combined_${first.id}.png');
        await File(path).writeAsBytes(bytes.buffer.asUint8List());
        result.add(
          FigureManifestEntry.fromJson({
            ...first.toJson(),
            'img': path,
            'width_px': (width * scale).ceil(),
            'height_px': (height * scale).ceil(),
            'figure_title': _joinCaptionParts(captionParts),
            'visual_regions': [
              for (final entry in group)
                ...entry.regions.map((r) => r.toJson()),
            ],
            'source_refs': [for (final entry in group) ...entry.sourceRefs],
            'source_images': {
              for (final entry in group) ...?entry.sourceImageNames,
            }.toList(),
            'caption_refs': [
              for (final encoded in {
                for (final entry in group)
                  ...entry.captionRefs.map((r) => jsonEncode(r.toJson())),
              })
                jsonDecode(encoded),
            ],
            'notes': {for (final entry in group) ...entry.notes}.toList(),
          }),
        );
      } finally {
        for (final image in images) {
          image.dispose();
        }
      }
    }
    return result;
  }

  static String encodeManifest(
    List<FigureManifestEntry> entries,
    String pdfPath, {
    Map<String, dynamic>? diagnostics,
    String? source,
  }) => const JsonEncoder.withIndent('  ').convert({
    'algorithm_version': 4,
    '_source': ?source,
    'figures': [
      for (final entry in entries)
        {
          ...entry.toJson(),
          'img': p.relative(
            entry.imagePath,
            from: DocPaths.figuresDir(pdfPath),
          ),
          if (entry.visualRegions.isNotEmpty)
            'visual_regions': [
              for (final region in entry.visualRegions)
                {
                  ...region.toJson(),
                  'img': p.relative(
                    region.imagePath,
                    from: DocPaths.figuresDir(pdfPath),
                  ),
                },
            ],
        },
    ],
    'diagnostics': ?diagnostics,
  });

  static String _sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
  }

  static Future<List<FigureManifestEntry>?> loadManifest(
    String pdfPath, {
    DocExtractProvider? source,
  }) async {
    var file = File(
      DocPaths.figuresManifest(pdfPath, source: source?.artifactKey),
    );
    if (!await file.exists() && source != null) {
      if (await ExtractionArtifacts.activeSource(pdfPath) != source) {
        return null;
      }
      file = File(DocPaths.figuresManifest(pdfPath));
    }
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      final List<dynamic> figuresList;
      if (decoded is List) {
        figuresList = decoded;
      } else if (decoded is Map<String, dynamic>) {
        figuresList = decoded['figures'] as List<dynamic>? ?? [];
      } else {
        return null;
      }
      return figuresList.map((e) {
        final json = Map<String, dynamic>.from(e as Map);
        final path = json['img'] as String;
        if (!p.isAbsolute(path)) {
          json['img'] = p.join(DocPaths.figuresDir(pdfPath), path);
        }
        for (final region in json['visual_regions'] as List? ?? []) {
          final image = region['img'] as String;
          if (!p.isAbsolute(image)) {
            region['img'] = p.join(DocPaths.figuresDir(pdfPath), image);
          }
        }
        return FigureManifestEntry.fromJson(json);
      }).toList();
    } catch (e) {
      log.d('[FigureExtract] 加载 manifest 失败: $e');
      return null;
    }
  }
}
