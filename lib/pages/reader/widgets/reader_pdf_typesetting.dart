import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';

final _cjkText = RegExp(r'[㐀-鿿]');
final _inlineFormula = RegExp(r'\$([^$\n]+)\$|\\\(([\s\S]*?)\\\)');

class _Formula {
  final int start;
  final int end;
  final ui.Image image;
  final Size size;
  _Formula(this.start, this.end, this.image, this.size);
}

/// 排版后的实际可见行：规范文本范围 + 相对排版原点的行框。
class ReaderTypesetLine {
  final TextRange range;
  final Rect rect;
  const ReaderTypesetLine(this.range, this.rect);
}

class ReaderTypesetText {
  final TextPainter painter;
  final List<Rect> charRects;
  final List<ReaderTypesetLine> lines;
  final List<_Formula> _formulas;
  final List<Rect> _formulaRects;
  double get height => painter.height;
  double get fontSize => painter.text!.style!.fontSize!;
  ReaderTypesetText._(
    this.painter,
    this.charRects,
    this.lines,
    this._formulas,
    this._formulaRects,
  );

  static Future<ReaderTypesetText> fit({
    required String text,
    required String source,
    required Rect rect,
    required bool heading,
    required TextStyle style,
    double? preferredFontSize,
    bool centered = false,
  }) async {
    final baseSize = style.fontSize ?? 14;
    final base = style.copyWith(
      fontFamily: _cjkText.hasMatch(text) ? 'SimSun' : 'Times New Roman',
      fontFamilyFallback: const [
        'Times New Roman',
        'Noto Serif CJK SC',
        'Songti SC',
        'serif',
      ],
      fontWeight: heading ? FontWeight.bold : FontWeight.normal,
      height: 1.2,
    );
    final formulas = <_Formula>[];
    for (final match in _inlineFormula.allMatches(text)) {
      try {
        final rendered = await _renderFormula(
          match[1] ?? match[2]!,
          baseSize,
          base.color!,
        );
        formulas.add(
          _Formula(match.start, match.end, rendered.image, rendered.size),
        );
      } catch (_) {
        // 无效公式保留原始内容，正文排版仍可继续。
      }
    }
    final buffer = StringBuffer();
    final offsets = <int>[];
    final ends = <int>[];
    var cursor = 0;
    for (final f in formulas) {
      for (; cursor < f.start; cursor++) {
        buffer.write(text[cursor]);
        offsets.add(cursor);
        ends.add(cursor + 1);
      }
      buffer.write('\uFFFC');
      offsets.add(f.start);
      ends.add(f.end);
      cursor = f.end;
    }
    for (; cursor < text.length; cursor++) {
      buffer.write(text[cursor]);
      offsets.add(cursor);
      ends.add(cursor + 1);
    }
    final display = buffer.toString();
    TextPainter create(double fs, {String? plain}) {
      final spans = <InlineSpan>[];
      final dimensions = <PlaceholderDimensions>[];
      var formulaIndex = 0;
      for (final part in (plain ?? display).split('\uFFFC')) {
        if (spans.isNotEmpty && plain == null) {
          final f = formulas[formulaIndex++];
          dimensions.add(
            PlaceholderDimensions(
              size: f.size * (fs / baseSize),
              alignment: PlaceholderAlignment.middle,
            ),
          );
          spans.add(
            const WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: SizedBox(),
            ),
          );
        }
        spans.add(TextSpan(text: part));
      }
      final painter = TextPainter(
        text: TextSpan(
          style: base.copyWith(fontSize: fs),
          children: spans,
        ),
        textDirection: TextDirection.ltr,
        textAlign: centered
            ? TextAlign.center
            : heading
            ? TextAlign.start
            : TextAlign.justify,
        textScaler: TextScaler.noScaling,
      );
      painter.setPlaceholderDimensions(dimensions);
      painter.layout(minWidth: rect.width, maxWidth: rect.width);
      return painter;
    }

    // 两端对齐的公式框可能因浮点舍入略越边界，不能因此触发整段缩字。
    bool fits(TextPainter p) =>
        p.height <= rect.height &&
        p.width <= rect.width &&
        (p.inlinePlaceholderBoxes?.every(
              (b) => b.left >= -.01 && b.right <= rect.width + .01,
            ) ??
            true);
    var preferred = preferredFontSize;
    if (heading || preferred == null || preferred <= 0) {
      var lo = .1;
      var hi = baseSize * (heading ? 2 : 1.25);
      for (var i = 0; i < 14; i++) {
        final mid = (lo + hi) / 2;
        final p = create(mid, plain: source);
        if (fits(p)) {
          lo = mid;
        } else {
          hi = mid;
        }
        p.dispose();
      }
      preferred = lo;
    }
    var low = .1;
    var high = preferred * 1.15;
    for (var i = 0; i < 16; i++) {
      final mid = (low + high) / 2;
      final p = create(mid);
      if (fits(p)) {
        low = mid;
      } else {
        high = mid;
      }
      p.dispose();
    }
    final painter = create(math.max(.1, low * .99));
    final boxes = List<Rect>.filled(text.length, Rect.zero);
    final displayRects = List<Rect>.filled(display.length, Rect.zero);
    var fIndex = 0;
    for (var i = 0; i < display.length; i++) {
      final selection = painter.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1),
      );
      if (selection.isEmpty) continue;
      final box = selection
          .map((b) => b.toRect())
          .reduce((a, b) => a.expandToInclude(b));
      displayRects[i] = box;
      if (display[i] == '\uFFFC') {
        final f = formulas[fIndex++];
        for (var j = f.start; j < f.end; j++) {
          boxes[j] = box;
        }
      } else {
        boxes[offsets[i]] = box;
      }
    }
    return ReaderTypesetText._(
      painter,
      boxes,
      _lineRanges(
        text: text,
        runs: (offsets: offsets, ends: ends),
        displayRects: displayRects,
        metrics: painter.computeLineMetrics(),
      ),
      formulas,
      painter.inlinePlaceholderBoxes?.map((b) => b.toRect()).toList() ?? [],
    );
  }

  void paint(Canvas canvas, Offset offset) {
    painter.paint(canvas, offset);
    for (var i = 0; i < _formulas.length && i < _formulaRects.length; i++) {
      final image = _formulas[i].image;
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        _formulaRects[i].shift(offset),
        Paint()..filterQuality = FilterQuality.high,
      );
    }
  }

  void dispose() {
    painter.dispose();
    for (final formula in _formulas) {
      formula.image.dispose();
    }
  }
}

/// 把 TextPainter 的行边界映射回规范文本范围；代理对不在中间截断。
List<ReaderTypesetLine> _lineRanges({
  required String text,
  required ({List<int> offsets, List<int> ends}) runs,
  required List<Rect> displayRects,
  required List<LineMetrics> metrics,
}) {
  final lines = <ReaderTypesetLine>[];
  var current = -1;
  var start = -1;
  var end = -1;
  void flush() {
    if (start < 0 || end <= start) {
      start = -1;
      end = -1;
      return;
    }
    if (end < text.length &&
        end > 0 &&
        text.codeUnitAt(end - 1) >= 0xD800 &&
        text.codeUnitAt(end - 1) <= 0xDBFF &&
        text.codeUnitAt(end) >= 0xDC00 &&
        text.codeUnitAt(end) <= 0xDFFF) {
      end++;
    }
    final metric = metrics[current];
    lines.add(
      ReaderTypesetLine(
        TextRange(start: start, end: end),
        Rect.fromLTWH(
          metric.left,
          metric.baseline - metric.ascent,
          metric.width,
          metric.height,
        ),
      ),
    );
    start = -1;
    end = -1;
  }

  int lineIndexFor(Rect box) {
    for (var i = 0; i < metrics.length; i++) {
      final top = metrics[i].baseline - metrics[i].ascent;
      final bottom = metrics[i].baseline + metrics[i].descent;
      if (box.center.dy >= top && box.center.dy <= bottom) return i;
    }
    return -1;
  }

  for (var i = 0; i < displayRects.length && i < runs.ends.length; i++) {
    final box = displayRects[i];
    if (box.isEmpty) continue;
    final index = lineIndexFor(box);
    if (index < 0) continue;
    if (index != current) {
      flush();
      current = index;
    }
    if (start < 0 || runs.offsets[i] < start) start = runs.offsets[i];
    end = runs.ends[i];
  }
  flush();
  return lines;
}

Future<({ui.Image image, Size size})> _renderFormula(
  String tex,
  double fontSize,
  Color color,
) async {
  final boundary = RenderRepaintBoundary();
  final view = RenderView(
    view: WidgetsBinding.instance.platformDispatcher.views.first,
    configuration: const ViewConfiguration(
      logicalConstraints: BoxConstraints.tightFor(width: 4096, height: 512),
      physicalConstraints: BoxConstraints.tightFor(width: 4096, height: 512),
      devicePixelRatio: 1,
    ),
    child: RenderPositionedBox(alignment: Alignment.topLeft, child: boundary),
  );
  final pipeline = PipelineOwner()..rootNode = view;
  final focus = FocusManager();
  final owner = BuildOwner(focusManager: focus);
  view.prepareInitialFrame();
  final adapter = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Math.tex(
        tex,
        mathStyle: MathStyle.text,
        textStyle: TextStyle(fontSize: fontSize, color: color),
      ),
    ),
  );
  final root = adapter.attachToRenderTree(owner);
  owner.buildScope(root);
  pipeline.flushLayout();
  pipeline.flushCompositingBits();
  pipeline.flushPaint();
  try {
    final image = await boundary.toImage(pixelRatio: 3);
    return (image: image, size: boundary.size);
  } finally {
    RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
    ).attachToRenderTree(owner, root);
    owner.buildScope(root);
    owner.finalizeTree();
    pipeline.rootNode = null;
    view.dispose();
    pipeline.dispose();
    focus.dispose();
  }
}
