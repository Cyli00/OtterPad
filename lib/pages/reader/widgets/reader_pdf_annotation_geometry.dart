import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../data/models/book/highlight.dart';
import '../../../data/models/book/reader_anchor.dart';
import '../../../services/reader/reader_document_index.dart';
import 'reader_pdf_document.dart';

/// 一条标注在一页上的行级几何。
class ReaderPdfAnnotationMark {
  const ReaderPdfAnnotationMark({
    required this.highlight,
    required this.paragraphId,
    required this.language,
    required this.lines,
  });

  final Highlight highlight;
  final String paragraphId;
  final String language;

  /// 合并后的同语言高亮行框（页坐标，y 轴向下）。
  final List<Rect> lines;

  Rect get bounds => lines.reduce((a, b) => a.expandToInclude(b));
}

/// 单击命中的标注及命中的那一行。
class ReaderPdfAnnotationHit {
  const ReaderPdfAnnotationHit(this.mark, this.line);

  final ReaderPdfAnnotationMark mark;

  /// 被点中的高亮行框，用于锚定悬浮工具栏。
  final Rect line;
}

/// PDF 标注几何：绘制与命中共用同一份行框结果，避免看得到却点不中。
///
/// 只做同语言行框合并和命中计算；页面几何或标注列表实例变化时由
/// [ReaderPdfPage.annotationGeometry] 重建，单击不会重排整页。
class ReaderPdfAnnotationGeometry {
  ReaderPdfAnnotationGeometry._(this.marks);

  final List<ReaderPdfAnnotationMark> marks;

  static ReaderPdfAnnotationGeometry build({
    required ReaderPdfPage page,
    required ReaderPdfPageLayout layout,
    required List<Highlight> highlights,
  }) {
    final marks = <ReaderPdfAnnotationMark>[];
    final blocksById = <String, List<ReaderPdfBlock>>{};
    for (final block in layout.blocks) {
      (blocksById[block.paragraph.id] ??= []).add(block);
    }
    final revisions = <String, String>{};
    final pageAnchorId = 'pdf-page:${page.sourcePageNumber}';
    for (final highlight in highlights) {
      for (final anchor
          in highlight.anchor?.ranges ?? const <ReaderAnchorRange>[]) {
        if (anchor.paragraphId == pageAnchorId) {
          final range = anchor.resolve(
            layout.text.fullText,
            readerTextRevision(layout.text.fullText),
          );
          if (range == null || range.start >= layout.text.charRects.length) {
            continue;
          }
          final lines = mergeLineRects(
            layout.text.charRects
                .sublist(
                  range.start,
                  math.min(range.end, layout.text.charRects.length),
                )
                .map((box) => box.toRect(page: page)),
          );
          if (lines.isNotEmpty) {
            marks.add(
              ReaderPdfAnnotationMark(
                highlight: highlight,
                paragraphId: anchor.paragraphId,
                language: anchor.language,
                lines: lines,
              ),
            );
          }
          continue;
        }
        for (final block
            in blocksById[anchor.paragraphId] ?? const <ReaderPdfBlock>[]) {
          if (anchor.language != block.language) continue;
          final range = anchor.resolve(
            block.text,
            revisions.putIfAbsent(
              block.text,
              () => readerTextRevision(block.text),
            ),
          );
          if (range == null) continue;
          final boxes = <Rect>[];
          for (
            var i = range.start;
            i < range.end && i < block.charRects.length;
            i++
          ) {
            boxes.add(block.charRects[i]);
          }
          final lines = mergeLineRects(boxes);
          if (lines.isNotEmpty) {
            marks.add(
              ReaderPdfAnnotationMark(
                highlight: highlight,
                paragraphId: anchor.paragraphId,
                language: anchor.language,
                lines: lines,
              ),
            );
          }
        }
      }
    }
    return ReaderPdfAnnotationGeometry._(marks);
  }

  /// 只命中实际高亮行框，不把同段落的未标记正文作为点击目标。
  ///
  /// [tolerance] 是页坐标下的容差，调用方按当前缩放从屏幕逻辑像素换算。
  ReaderPdfAnnotationHit? hitTest(Offset point, {double tolerance = 0}) {
    ReaderPdfAnnotationHit? exact;
    var exactDistance = double.infinity;
    for (final mark in marks) {
      for (final line in mark.lines) {
        if (!line.inflate(tolerance).contains(point)) continue;
        final distance = _distanceToRect(line, point);
        if (distance < exactDistance) {
          exactDistance = distance;
          exact = ReaderPdfAnnotationHit(mark, line);
        }
      }
    }
    return exact;
  }

  static double _distanceToRect(Rect rect, Offset point) {
    final dx = math.max(
      math.max(rect.left - point.dx, point.dx - rect.right),
      0.0,
    );
    final dy = math.max(
      math.max(rect.top - point.dy, point.dy - rect.bottom),
      0.0,
    );
    return math.sqrt(dx * dx + dy * dy);
  }
}

/// 字框按行合并：垂直重叠且水平相邻才连续，杜绝跨栏、跨段拼成一整块。
List<Rect> mergeLineRects(Iterable<Rect> boxes) {
  final rects = boxes.where((r) => r.isFinite && !r.isEmpty).toSet().toList()
    ..sort((a, b) => a.top.compareTo(b.top));
  final bands = <({Rect bounds, List<Rect> boxes})>[];
  for (final rect in rects) {
    var at = -1;
    for (var i = bands.length - 1; i >= 0; i--) {
      final band = bands[i].bounds;
      if (band.bottom < rect.top) break;
      final overlap =
          math.min(band.bottom, rect.bottom) - math.max(band.top, rect.top);
      if (overlap > math.min(band.height, rect.height) * .5) {
        at = i;
        break;
      }
    }
    if (at < 0) {
      bands.add((bounds: rect, boxes: [rect]));
    } else {
      final band = bands[at];
      band.boxes.add(rect);
      bands[at] = (
        bounds: band.bounds.expandToInclude(rect),
        boxes: band.boxes,
      );
    }
  }
  final lines = <Rect>[];
  for (final band in bands) {
    band.boxes.sort((a, b) => a.left.compareTo(b.left));
    var line = band.boxes.first;
    for (final rect in band.boxes.skip(1)) {
      if (rect.left - line.right <= math.min(rect.height, line.height) * .6) {
        line = line.expandToInclude(rect);
      } else {
        lines.add(line);
        line = rect;
      }
    }
    lines.add(line);
  }
  return lines;
}
