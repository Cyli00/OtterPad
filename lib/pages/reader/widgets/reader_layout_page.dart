import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../data/models/book/highlight.dart';
import 'reader_pdf_annotation_geometry.dart';
import 'reader_pdf_document.dart';

class ReaderLayoutPage extends StatefulWidget {
  final ReaderPdfPage page;
  final Size size;
  final List<Highlight> highlights;
  final ValueListenable<List<PdfPageTextRange>>? selection;
  final PdfTextSearcher? searcher;
  const ReaderLayoutPage({
    super.key,
    required this.page,
    required this.size,
    required this.highlights,
    this.selection,
    this.searcher,
  });

  @override
  State<ReaderLayoutPage> createState() => _ReaderLayoutPageState();
}

class _ReaderLayoutPageState extends State<ReaderLayoutPage> {
  bool _hoveringAnnotation = false;

  /// 单击命中容差（屏幕逻辑像素）换算到页坐标。
  double get _hitTolerance =>
      widget.size.width <= 0 ? 6 : 6 * (widget.page.width / widget.size.width);

  void _handleHover(
    Offset localPosition,
    ReaderPdfAnnotationGeometry geometry,
  ) {
    final size = widget.size;
    if (size.width <= 0 || size.height <= 0) return;
    final point = Offset(
      localPosition.dx * widget.page.width / size.width,
      localPosition.dy * widget.page.height / size.height,
    );
    final hovering = geometry.hitTest(point, tolerance: _hitTolerance) != null;
    if (hovering != _hoveringAnnotation) {
      setState(() => _hoveringAnnotation = hovering);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ReaderPdfPageLayout>(
      key: ObjectKey(widget.page),
      future: widget.page.layout,
      initialData: widget.page.readyLayout,
      builder: (context, snapshot) {
        final layout = snapshot.data;
        if (layout == null) {
          return IgnorePointer(
            child: CustomPaint(size: widget.size, painter: null),
          );
        }
        final geometry = widget.page.annotationGeometry(
          layout,
          widget.highlights,
        );
        return MouseRegion(
          // 悬停在可点击的标注上换手型，其余交给 pdfrx 的文本光标。
          cursor: _hoveringAnnotation
              ? SystemMouseCursors.click
              : MouseCursor.defer,
          hitTestBehavior: HitTestBehavior.translucent,
          onHover: (event) => _handleHover(event.localPosition, geometry),
          onExit: (_) {
            if (_hoveringAnnotation) {
              setState(() => _hoveringAnnotation = false);
            }
          },
          child: IgnorePointer(
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    painter: _PagePainter(
                      widget.page,
                      layout,
                      geometry,
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                if (layout.blocks.any((b) => b.typeset != null))
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: _SelectionPainter(
                        widget.page,
                        layout,
                        Theme.of(context).colorScheme.primary,
                        widget.selection,
                        widget.searcher,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PagePainter extends CustomPainter {
  final ReaderPdfPage page;
  final ReaderPdfPageLayout layout;
  final ReaderPdfAnnotationGeometry geometry;
  final Color associatedColor;
  _PagePainter(this.page, this.layout, this.geometry, this.associatedColor);

  /// 与 HTML 覆盖层一致的 0.3 透明度与轻圆角；关联提示更淡。
  static const _highlightAlpha = 77;
  static const _associationAlpha = 45;
  static const _radius = Radius.circular(2);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / page.width, size.height / page.height);

    // 译文擦除区域 → 译文内容。
    for (final block in layout.blocks) {
      final typeset = block.typeset;
      if (typeset == null) continue;
      canvas.drawRect(block.rect, Paint()..color = Colors.white);
      typeset.paint(canvas, block.rect.topLeft);
    }

    // 持久标注：行级合并后的轻透明圆角块；跨语言关联提示用更淡的同色底色
    // 加一条 ColorScheme 边标，不伪造逐字对应。
    for (final mark in geometry.marks) {
      final highlight = _highlightColor(mark.highlight);
      if (mark.isAssociation) {
        final fill = Paint()..color = highlight.withAlpha(_associationAlpha);
        for (final line in mark.lines) {
          canvas.drawRRect(RRect.fromRectAndRadius(line, _radius), fill);
        }
        final edge = mark.edge;
        if (edge != null) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(edge, _radius),
            Paint()..color = associatedColor,
          );
        }
        continue;
      }
      final paint = Paint()..color = highlight.withAlpha(_highlightAlpha);
      for (final line in mark.lines) {
        canvas.drawRRect(RRect.fromRectAndRadius(line, _radius), paint);
      }
    }

    canvas.restore();
  }

  Color _highlightColor(Highlight highlight) =>
      Color(int.parse('FF${highlight.color}', radix: 16));

  @override
  bool shouldRepaint(covariant _PagePainter oldDelegate) =>
      !identical(oldDelegate.geometry, geometry) ||
      oldDelegate.layout != layout ||
      oldDelegate.associatedColor != associatedColor;
}

// 译文与持久标注保持独立绘制边界；鼠标选区只重绘这一层。
class _SelectionPainter extends CustomPainter {
  _SelectionPainter(
    this.page,
    this.layout,
    this.color,
    this.selection,
    this.searcher,
  ) : super(repaint: Listenable.merge([selection, searcher]));

  final ReaderPdfPage page;
  final ReaderPdfPageLayout layout;
  final Color color;
  final ValueListenable<List<PdfPageTextRange>>? selection;
  final PdfTextSearcher? searcher;
  late final Path _clip = () {
    final path = Path();
    for (final block in layout.blocks) {
      if (block.typeset != null) path.addRect(block.rect);
    }
    return path;
  }();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / page.width, size.height / page.height);
    canvas.clipPath(_clip);
    // 多个译文块一次裁切，搜索与选区每页只绘制一次。
    searcher?.pageTextMatchPaintCallback(
      canvas,
      Rect.fromLTWH(0, 0, page.width, page.height),
      page,
    );
    final paint = Paint()..color = color.withAlpha(90);
    for (final range in selection?.value ?? const <PdfPageTextRange>[]) {
      if (range.pageNumber != page.pageNumber) continue;
      for (final fragment in range.enumerateFragmentBoundingRects()) {
        canvas.drawRect(fragment.bounds.toRect(page: page), paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SelectionPainter old) =>
      old.page != page ||
      old.layout != layout ||
      old.color != color ||
      old.selection != selection ||
      old.searcher != searcher;
}
