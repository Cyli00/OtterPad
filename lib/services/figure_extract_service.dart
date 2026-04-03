import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

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
    _initialized = true;
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

  // ─── Segment 检测（两步分片） ─────────────────────────

  /// 在单页 block 列表中找到所有 figure segment。
  ///
  /// **第一步**：连续的 figure 相关 block 聚合为粗段落。
  /// **第二步**：在粗段落内部按主标题（Figure N. / Table N.）做二次切割，
  /// 同时处理标题在上/在下两种排版风格。
  List<List<LayoutBlock>> findFigureSegments(List<LayoutBlock> blocks) {
    // 第一步：粗分片
    final rawSegments = <List<LayoutBlock>>[];
    var current = <LayoutBlock>[];
    for (final block in blocks) {
      if (figureLabels.contains(block.blockLabel)) {
        current.add(block);
      } else {
        if (current.isNotEmpty) {
          rawSegments.add(current);
          current = [];
        }
      }
    }
    if (current.isNotEmpty) rawSegments.add(current);

    // 第二步：按主标题二次切割
    final segments = <List<LayoutBlock>>[];
    for (final rawSeg in rawSegments) {
      var sub = <LayoutBlock>[];
      for (final block in rawSeg) {
        if (isMainCaption(block)) {
          final hasContent =
              sub.any((b) => b.blockLabel != 'figure_title');
          final subHasCaption = sub.any(isMainCaption);

          if (hasContent && subHasCaption) {
            // sub 已是完整的"标题在上"段，切出去；新标题开启下一段
            segments.add(sub);
            sub = [block];
          } else if (hasContent && !subHasCaption) {
            // sub 有内容但无标题 → "标题在下"，附加后切割
            sub.add(block);
            segments.add(sub);
            sub = [];
          } else {
            // sub 无内容 → "标题在上"，先不切
            sub.add(block);
          }
        } else {
          sub.add(block);
        }
      }
      if (sub.isNotEmpty) segments.add(sub);
    }
    return segments;
  }

  // ─── BBox 计算 ────────────────────────────────────────

  /// 计算 segment 内非主标题 block 的外接矩形（裁图时排除图注文字）。
  ///
  /// 返回 `[left, top, right, bottom]`，坐标基于 API zoom。
  List<double> computeMergedBbox(List<LayoutBlock> segment) {
    final contentBlocks =
        segment.where((b) => !isMainCaption(b)).toList();
    final effective = contentBlocks.isNotEmpty ? contentBlocks : segment;

    double left = double.infinity;
    double top = double.infinity;
    double right = double.negativeInfinity;
    double bottom = double.negativeInfinity;

    for (final b in effective) {
      if (b.blockBbox[0] < left) left = b.blockBbox[0];
      if (b.blockBbox[1] < top) top = b.blockBbox[1];
      if (b.blockBbox[2] > right) right = b.blockBbox[2];
      if (b.blockBbox[3] > bottom) bottom = b.blockBbox[3];
    }
    return [left, top, right, bottom];
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
    final allPages = parseLayoutBlocks(content);

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
    final dir = p.dirname(pdfPath);
    final baseName = p.basenameWithoutExtension(pdfPath);
    final outputDir = p.join(dir, '${baseName}_figures');
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
    final dir = p.dirname(pdfPath);
    final baseName = p.basenameWithoutExtension(pdfPath);
    final manifestPath = p.join(dir, '${baseName}_figures', 'figures.json');
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
