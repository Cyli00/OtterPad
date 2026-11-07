import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../src/rust/api/document.dart';
import '../../src/rust/document.dart';
import '../reader/widgets/reader_typography.dart';
import 'widget_measurer.dart';

/// 版式参数。相同参数必然得到相同的测量与分页，[ReaderLayout] 以它为缓存键。
@immutable
class ReaderLayoutSpec {
  const ReaderLayoutSpec({
    required this.width,
    required this.pageHeight,
    required this.body,
    required this.mutedColor,
    required this.linkColor,
    required this.ruleColor,
    this.blockMargin = ReaderTypography.blockMarginScale,
    this.rtlTranslations = false,
  });

  /// 正文列宽与分页模式下每页可用高度（不含页边距）。
  final double width;
  final double pageHeight;

  /// 正文样式；字号已含系统字体缩放，RichText 与 TextPainter 都不再缩放。
  final TextStyle body;
  final Color mutedColor;
  final Color linkColor;
  final Color ruleColor;
  final double blockMargin;

  /// 译文为阿拉伯语、波斯语等从右向左书写的语言时，译文块按 RTL 排版。
  final bool rtlTranslations;

  double get fontSize => body.fontSize!;

  TextStyle heading(int level) {
    final (scale, weight, height) = switch (level) {
      1 => (
        ReaderTypography.h1Scale,
        ReaderTypography.h1Weight,
        ReaderTypography.h1Height,
      ),
      2 => (
        ReaderTypography.h2Scale,
        ReaderTypography.h2Weight,
        ReaderTypography.h2Height,
      ),
      3 => (
        ReaderTypography.h3Scale,
        ReaderTypography.h3Weight,
        ReaderTypography.h3to6Height,
      ),
      4 => (
        ReaderTypography.h4Scale,
        ReaderTypography.h4Weight,
        ReaderTypography.h3to6Height,
      ),
      5 => (1.0, ReaderTypography.h5Weight, ReaderTypography.h3to6Height),
      _ => (1.0, ReaderTypography.h6Weight, ReaderTypography.h3to6Height),
    };
    return body.copyWith(
      fontSize: fontSize * scale,
      fontWeight: weight,
      height: height,
    );
  }

  TextStyle get caption => body.copyWith(
    fontSize: fontSize * ReaderTypography.captionScale,
    color: mutedColor,
  );

  TextStyle get code => body.copyWith(
    fontFamily: ReaderTypography.codeFontFamily,
    fontFamilyFallback: ReaderTypography.codeFontFallback,
    fontSize: fontSize * ReaderTypography.codeScale,
  );

  /// 与 0.1.x reader.css 一致：块间距取相邻 margin 的较大值（margin 折叠）。
  double gapBefore(Block block) => switch (block.kind) {
    BlockKind.heading =>
      fontSize *
          switch (block.headingLevel ?? 1) {
            1 => 0.8,
            2 => 0.7,
            _ => 0.6,
          },
    _ => fontSize * blockMargin,
  };

  @override
  bool operator ==(Object other) =>
      other is ReaderLayoutSpec &&
      other.width == width &&
      other.pageHeight == pageHeight &&
      other.body == body &&
      other.mutedColor == mutedColor &&
      other.linkColor == linkColor &&
      other.ruleColor == ruleColor &&
      other.blockMargin == blockMargin &&
      other.rtlTranslations == rtlTranslations;

  @override
  int get hashCode => Object.hash(
    width,
    pageHeight,
    body,
    mutedColor,
    linkColor,
    ruleColor,
    blockMargin,
    rtlTranslations,
  );
}

/// 文本上的着色区间（高亮、搜索命中、选区），偏移为 [Block.text] 的 UTF-16 下标。
@immutable
class TextMark {
  const TextMark(this.start, this.end, this.color);

  final int start;
  final int end;
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is TextMark &&
      other.start == start &&
      other.end == end &&
      other.color == color;

  @override
  int get hashCode => Object.hash(start, end, color);
}

/// [Block.text] 偏移与 TextPainter 偏移的换算。
///
/// 公式 run 在 `text` 中是 `$…$` 原文，在 TextPainter 中只是一个 U+FFFC 占位，
/// 所以两套偏移只在公式之后出现差值；公式内部不可分割。
class InlineMap {
  InlineMap(List<InlineRun> runs) {
    var t = 0;
    var p = 0;
    for (final run in runs) {
      _textStarts.add(t);
      _painterStarts.add(p);
      _atomic.add(run.math != null);
      t += run.text.length;
      p += run.math != null ? 1 : run.text.length;
    }
    textLength = t;
    painterLength = p;
  }

  final _textStarts = <int>[];
  final _painterStarts = <int>[];
  final _atomic = <bool>[];
  late final int textLength;
  late final int painterLength;

  int _runAt(List<int> starts, int offset) {
    var lo = 0;
    var hi = starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (starts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  int toPainter(int text) {
    if (_textStarts.isEmpty || text >= textLength) return painterLength;
    final i = _runAt(_textStarts, text);
    final delta = text - _textStarts[i];
    return _painterStarts[i] + (_atomic[i] ? (delta == 0 ? 0 : 1) : delta);
  }

  int toText(int painter) {
    if (_painterStarts.isEmpty || painter >= painterLength) return textLength;
    final i = _runAt(_painterStarts, painter);
    final delta = painter - _painterStarts[i];
    return _textStarts[i] + delta;
  }

  /// 把任意偏移吸附到公式边界，保证选区不切开公式。
  int snap(int text, {required bool forward}) {
    if (_textStarts.isEmpty || text <= 0 || text >= textLength) {
      return text.clamp(0, textLength);
    }
    final i = _runAt(_textStarts, text);
    if (!_atomic[i] || text == _textStarts[i]) return text;
    return forward
        ? (i + 1 < _textStarts.length ? _textStarts[i + 1] : textLength)
        : _textStarts[i];
  }
}

enum ItemKind { text, figure, equation, table }

/// 一个测量后的行；text 项的偏移是 TextPainter 偏移，其余项只有一行。
@immutable
class LayoutLine {
  const LayoutLine(this.start, this.end, this.top, this.bottom);

  final int start;
  final int end;
  final double top;
  final double bottom;

  double get height => bottom - top;
}

class MathBox {
  const MathBox(this.tex, this.box);

  final String tex;
  final MeasuredBox box;
}

/// 排版的最小单位。一个文档块可拆成多项：图块 = 图片区 + 题注文本。
class LayoutItem {
  LayoutItem._({
    required this.blockIndex,
    required this.kind,
    required this.gapBefore,
    required this.height,
    required this.lines,
    this.style,
    this.map,
    this.maths = const [],
    this.indent = 0,
    this.mediaSize,
    this.image,
    this.direction = TextDirection.ltr,
  });

  final int blockIndex;
  final ItemKind kind;
  final double gapBefore;
  final double height;
  final List<LayoutLine> lines;
  final TextStyle? style;
  final InlineMap? map;
  final List<MathBox> maths;
  final double indent;

  /// 图片或公式的显示尺寸。
  final Size? mediaSize;

  /// 图块的位图；没有可用图片时只显示比例一致的占位。
  final ReaderFigureImage? image;

  /// 文本块的书写方向；公式以内嵌组件排版，不受影响。
  final TextDirection direction;

  bool get isText => kind == ItemKind.text;

  /// 包含 painter 偏移的行号；超出末尾时取最后一行。
  int lineOf(int painterOffset) {
    for (var i = 0; i < lines.length; i++) {
      if (painterOffset < lines[i].end) return i;
    }
    return lines.length - 1;
  }
}

@immutable
class PageFragment {
  const PageFragment(this.itemIndex, this.firstLine, this.lastLine, this.top);

  final int itemIndex;
  final int firstLine;
  final int lastLine;

  /// 片段在页内的纵向位置。
  final double top;
}

@immutable
class LayoutPage {
  const LayoutPage(this.fragments);

  final List<PageFragment> fragments;
}

/// 阅读位置：(块序号, [Block.text] 偏移)，在重排、换模式后保持不变。
@immutable
class ReaderLocation {
  const ReaderLocation(this.blockIndex, this.offset);

  final int blockIndex;
  final int offset;

  @override
  bool operator ==(Object other) =>
      other is ReaderLocation &&
      other.blockIndex == blockIndex &&
      other.offset == offset;

  @override
  int get hashCode => Object.hash(blockIndex, offset);
}

/// 持有离屏测量器与公式尺寸缓存；生命周期跟随阅读器页面。
class ReaderTypesetter {
  final _measurer = WidgetMeasurer();
  final _mathBoxes = <(String, bool, double), MeasuredBox>{};

  /// 每次调用都重新解析：flutter_math 在语法树上缓存带 GlobalKey 的子 widget，
  /// 同一解析结果在一棵树里挂载两次（同式重复出现、跨页段落翻页时两页同显）会冲突。
  Widget mathWidget(
    String tex, {
    required bool display,
    required TextStyle style,
  }) => Math.tex(
    tex,
    options: MathOptions(
      style: display ? MathStyle.display : MathStyle.text,
      fontSize: style.fontSize!,
      color: style.color!,
    ),
    onErrorFallback: (_) => Text(
      display ? '\$\$$tex\$\$' : '\$$tex\$',
      style: style,
      textScaler: TextScaler.noScaling,
    ),
  );

  MeasuredBox _measureMath(String tex, bool display, TextStyle style) =>
      _mathBoxes.putIfAbsent(
        (tex, display, style.fontSize!),
        () => _measurer.measure(
          mathWidget(tex, display: display, style: style),
          maxWidth: double.infinity,
        ),
      );

  ReaderLayout layout(ReaderDocument model, ReaderLayoutSpec spec) {
    final images = {for (final i in model.figureImages) i.blockId: i};
    final items = <LayoutItem>[];
    for (var i = 0; i < model.blocks.length; i++) {
      final block = model.blocks[i];
      // 子图由所属图块统一显示，不单独占位。
      if (block.ownerId != null) continue;
      final gap = items.isEmpty ? 0.0 : spec.gapBefore(block);
      switch (block.kind) {
        // 无法解析成单元格的表格只有截图，按图块显示。
        case BlockKind.figure:
        case BlockKind.table
            when block.table == null && images.containsKey(block.id):
          // 没有位图的图块（多为无题注的匿名图）不占位，只保留题注，与 0.1.x 一致。
          final image = images[block.id];
          if (image != null) items.add(_figure(model, i, spec, gap, image));
          if (block.text.isNotEmpty) {
            items.add(
              _text(
                block,
                i,
                spec,
                spec.caption,
                image == null ? gap : spec.fontSize * .4,
              ),
            );
          }
        case BlockKind.equation
            when block.runs.length == 1 && block.runs.first.math != null:
          items.add(_equation(block, i, spec, gap));
        case BlockKind.table when block.table != null:
          items.add(_table(block, i, spec, gap));
        case BlockKind.heading:
          items.add(
            _text(block, i, spec, spec.heading(block.headingLevel ?? 1), gap),
          );
        case BlockKind.code:
          items.add(_text(block, i, spec, spec.code, gap));
        case BlockKind.quote:
          items.add(
            _text(
              block,
              i,
              spec,
              spec.body.copyWith(color: spec.mutedColor),
              gap,
              indent:
                  ReaderTypography.blockquotePadLeft +
                  ReaderTypography.blockquoteSideWidth,
            ),
          );
        default:
          if (block.text.isEmpty) continue;
          items.add(_text(block, i, spec, spec.body, gap));
      }
    }
    return ReaderLayout._(model, spec, items);
  }

  /// 构造块的行内 span。[marks] 为空时用于测量，与渲染得到相同的断行。
  InlineSpan span(
    Block block,
    LayoutItem item,
    ReaderLayoutSpec spec, {
    List<TextMark> marks = const [],
  }) {
    final base = item.style!;
    final children = <InlineSpan>[];
    var offset = 0;
    for (final run in block.runs) {
      final start = offset;
      final end = offset += run.text.length;
      var style = base;
      if (run.bold) style = style.copyWith(fontWeight: FontWeight.w700);
      if (run.italic) style = style.copyWith(fontStyle: FontStyle.italic);
      if (run.code) {
        style = spec.code.copyWith(fontSize: base.fontSize! * .92);
      }
      if (run.strike) {
        style = style.copyWith(decoration: TextDecoration.lineThrough);
      }
      if (run.link != null) {
        style = style.copyWith(
          color: spec.linkColor,
          decoration: TextDecoration.underline,
          decorationColor: spec.linkColor.withAlpha(120),
        );
      }
      final tex = run.math;
      if (tex != null) {
        Color? color;
        for (final m in marks) {
          if (m.start < end && m.end > start) color = m.color;
        }
        final widget = mathWidget(tex, display: false, style: style);
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: color == null
                ? widget
                : ColoredBox(color: color, child: widget),
          ),
        );
        continue;
      }
      final cuts = <int>{start, end};
      for (final m in marks) {
        if (m.start > start && m.start < end) cuts.add(m.start);
        if (m.end > start && m.end < end) cuts.add(m.end);
      }
      final sorted = cuts.toList()..sort();
      for (var k = 0; k + 1 < sorted.length; k++) {
        final a = sorted[k];
        final b = sorted[k + 1];
        Color? color;
        for (final m in marks) {
          if (m.start <= a && m.end >= b) color = m.color;
        }
        children.add(
          TextSpan(
            text: block.text.substring(a, b),
            style: color == null
                ? style
                : style.copyWith(backgroundColor: color),
          ),
        );
      }
    }
    return TextSpan(style: base, children: children);
  }

  LayoutItem _text(
    Block block,
    int index,
    ReaderLayoutSpec spec,
    TextStyle style,
    double gap, {
    double indent = 0,
  }) {
    final maths = [
      for (final run in block.runs)
        if (run.math != null)
          MathBox(run.math!, _measureMath(run.math!, false, style)),
    ];
    final probe = LayoutItem._(
      blockIndex: index,
      kind: ItemKind.text,
      gapBefore: gap,
      height: 0,
      lines: const [],
      style: style,
      maths: maths,
    );
    final direction = spec.rtlTranslations && block.id.endsWith('#t')
        ? TextDirection.rtl
        : TextDirection.ltr;
    final painter = TextPainter(
      text: span(block, probe, spec),
      textDirection: direction,
      textScaler: TextScaler.noScaling,
    );
    try {
      painter.setPlaceholderDimensions([
        for (final m in maths)
          PlaceholderDimensions(
            size: m.box.size,
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            baselineOffset: m.box.baseline,
          ),
      ]);
      painter.layout(maxWidth: spec.width - indent);
      final map = InlineMap(block.runs);
      final metrics = painter.computeLineMetrics();
      final starts = <int>[];
      final tops = <double>[];
      var cursor = 0;
      // 按逻辑行边界推进而不是按 y 命中，避免高公式或回退字体让偏移乱序。
      for (final line in metrics) {
        var range = painter.getLineBoundary(TextPosition(offset: cursor));
        if (range.end <= cursor && cursor < map.painterLength) {
          range = painter.getLineBoundary(TextPosition(offset: ++cursor));
        }
        if (starts.isEmpty || range.start > starts.last) {
          starts.add(range.start);
          tops.add(tops.isEmpty ? 0 : line.baseline - line.ascent);
        }
        cursor = math.max(range.end, cursor);
      }
      if (starts.isEmpty) {
        starts.add(0);
        tops.add(0);
      }
      return LayoutItem._(
        blockIndex: index,
        kind: ItemKind.text,
        gapBefore: gap,
        height: painter.height,
        style: style,
        map: map,
        maths: maths,
        indent: indent,
        direction: direction,
        lines: List.unmodifiable([
          for (var i = 0; i < starts.length; i++)
            LayoutLine(
              starts[i],
              i + 1 < starts.length ? starts[i + 1] : map.painterLength,
              tops[i],
              i + 1 < starts.length ? tops[i + 1] : painter.height,
            ),
        ]),
      );
    } finally {
      painter.dispose();
    }
  }

  LayoutItem _figure(
    ReaderDocument model,
    int index,
    ReaderLayoutSpec spec,
    double gap,
    ReaderFigureImage? image,
  ) {
    final block = model.blocks[index];
    var regions = block.sourceRegions;
    if (regions.isEmpty) {
      regions = [
        for (final b in model.blocks)
          if (b.ownerId == block.id) ...b.sourceRegions,
      ];
    }
    // 只用首页的区域估算比例；跨页图按首页显示。
    final page = regions.isEmpty ? null : regions.first.pageIndex;
    double? l, t, r, b;
    for (final region in regions) {
      if (region.pageIndex != page || region.bbox.length < 4) continue;
      l = math.min(l ?? region.bbox[0], region.bbox[0]);
      t = math.min(t ?? region.bbox[1], region.bbox[1]);
      r = math.max(r ?? region.bbox[2], region.bbox[2]);
      b = math.max(b ?? region.bbox[3], region.bbox[3]);
    }
    final ratio = image != null && image.widthPx > 0 && image.heightPx > 0
        ? image.widthPx / image.heightPx
        : l != null && r! > l && b! > t!
        ? (r - l) / (b - t)
        : 4 / 3;
    var height = spec.width / ratio;
    if (height > spec.pageHeight * .8) height = spec.pageHeight * .8;
    final size = Size(math.min(spec.width, height * ratio), height);
    return LayoutItem._(
      blockIndex: index,
      kind: ItemKind.figure,
      gapBefore: gap,
      height: height,
      lines: [LayoutLine(0, 0, 0, height)],
      mediaSize: size,
      image: image,
    );
  }

  LayoutItem _equation(
    Block block,
    int index,
    ReaderLayoutSpec spec,
    double gap,
  ) {
    final box = _measureMath(block.runs.first.math!, true, spec.body);
    final pad = spec.fontSize * .3;
    final height = box.size.height + pad * 2;
    return LayoutItem._(
      blockIndex: index,
      kind: ItemKind.equation,
      gapBefore: gap,
      height: height,
      lines: [LayoutLine(0, 0, 0, height)],
      style: spec.body,
      mediaSize: box.size,
    );
  }

  /// 表格 widget；测量与渲染共用，保证高度一致。行列合并暂按普通单元格显示。
  Widget table(Block block, ReaderLayoutSpec spec) {
    final rows = block.table!.rows;
    final columns = rows.fold(0, (n, row) => math.max(n, row.length));
    final style = spec.body.copyWith(fontSize: spec.fontSize * .88);
    return Table(
      border: TableBorder.all(color: spec.ruleColor),
      defaultColumnWidth: const FlexColumnWidth(),
      children: [
        for (final row in rows)
          TableRow(
            children: [
              for (var c = 0; c < columns; c++)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: RichText(
                    textScaler: TextScaler.noScaling,
                    text: TextSpan(
                      text: c < row.length ? row[c].text : '',
                      style: c < row.length && row[c].header
                          ? style.copyWith(fontWeight: FontWeight.w600)
                          : style,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  LayoutItem _table(Block block, int index, ReaderLayoutSpec spec, double gap) {
    final height = _measurer.measure(table(block, spec), maxWidth: spec.width);
    return LayoutItem._(
      blockIndex: index,
      kind: ItemKind.table,
      gapBefore: gap,
      height: height.size.height,
      lines: [LayoutLine(0, 0, 0, height.size.height)],
    );
  }

  void dispose() => _measurer.dispose();
}

/// 一次排版结果：滚动模式的纵向位置与分页模式的页面共用同一组测量行。
class ReaderLayout {
  ReaderLayout._(this.model, this.spec, this.items) {
    var y = 0.0;
    for (final item in items) {
      _tops.add(y);
      y += item.gapBefore + item.height;
    }
    extent = y;
    pages = _paginate();
    for (var p = 0; p < pages.length; p++) {
      for (final f in pages[p].fragments) {
        _pageOf.putIfAbsent(f.itemIndex, () => []).add((p, f.firstLine));
      }
    }
  }

  final ReaderDocument model;
  final ReaderLayoutSpec spec;
  final List<LayoutItem> items;
  final _tops = <double>[];
  final _pageOf = <int, List<(int, int)>>{};
  late final double extent;
  late final List<LayoutPage> pages;

  /// 滚动模式下第 [index] 项（含其前间距）的起点。
  double topOf(int index) => _tops[index];

  List<LayoutPage> _paginate() {
    final pages = <LayoutPage>[];
    var fragments = <PageFragment>[];
    var used = 0.0;
    void finish() {
      if (fragments.isEmpty) return;
      pages.add(LayoutPage(List.unmodifiable(fragments)));
      fragments = [];
      used = 0;
    }

    final limit = spec.pageHeight + .001;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final model = this.model.blocks[item.blockIndex];
      // 标题不留在页底：放不下标题与下一项首行时整体换页。
      if (fragments.isNotEmpty &&
          model.kind == BlockKind.heading &&
          i + 1 < items.length) {
        final next = items[i + 1];
        final need =
            item.gapBefore +
            item.height +
            next.gapBefore +
            next.lines.first.height;
        if (used + need > limit) finish();
      }
      for (var l = 0; l < item.lines.length; l++) {
        final line = item.lines[l];
        final gap = l == 0 && fragments.isNotEmpty ? item.gapBefore : 0.0;
        if (fragments.isNotEmpty && used + gap + line.height > limit) finish();
        if (l > 0 && fragments.isNotEmpty && fragments.last.itemIndex == i) {
          final last = fragments.removeLast();
          fragments.add(PageFragment(i, last.firstLine, l, last.top));
        } else {
          final top = used + (fragments.isEmpty ? 0 : item.gapBefore);
          fragments.add(PageFragment(i, l, l, top));
          used = top;
        }
        used += line.height;
      }
    }
    finish();
    return pages;
  }

  /// 第一项属于 [blockIndex] 的排版项；文本优先，图块的题注即文本项。
  int itemOf(ReaderLocation location) {
    var first = -1;
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item.blockIndex < location.blockIndex) continue;
      if (item.blockIndex > location.blockIndex) return first == -1 ? i : first;
      if (first == -1) first = i;
      if (item.isText) return i;
    }
    return first == -1 ? items.length - 1 : first;
  }

  /// 滚动位置 [y] 处的阅读位置（该处所在行的行首），以及该行已滚过视口顶部的比例。
  ///
  /// 比例让重排后能回到行内原处：只按行首恢复时，顶部露出半行的视图会被整行拉齐。
  (ReaderLocation, double) anchorAtScroll(double y) {
    if (items.isEmpty) return (const ReaderLocation(0, 0), 0);
    var lo = 0;
    var hi = items.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_tops[mid] <= y + .5) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final item = items[lo];
    final local = y - _tops[lo] - item.gapBefore;
    double fraction(double top, double height) =>
        height <= 0 ? 0 : ((local - top) / height).clamp(0.0, .999);
    if (!item.isText) {
      return (ReaderLocation(item.blockIndex, 0), fraction(0, item.height));
    }
    var line = item.lines.first;
    for (final candidate in item.lines) {
      if (candidate.top <= local + .5) line = candidate;
    }
    return (
      ReaderLocation(item.blockIndex, item.map!.toText(line.start)),
      fraction(line.top, line.height),
    );
  }

  /// 阅读位置对应的滚动偏移：该行行顶，再加上行内已滚过的 [fraction]。
  double scrollOf(ReaderLocation location, {double fraction = 0}) {
    if (items.isEmpty) return 0;
    final index = itemOf(location);
    final item = items[index];
    final y = _tops[index] + item.gapBefore;
    if (!item.isText) return y + fraction * item.height;
    final line = item.lines[item.lineOf(item.map!.toPainter(location.offset))];
    return y + line.top + fraction * line.height;
  }

  /// 阅读位置所在页。
  int pageOf(ReaderLocation location) {
    if (items.isEmpty) return 0;
    final index = itemOf(location);
    final item = items[index];
    final line = item.isText
        ? item.lineOf(item.map!.toPainter(location.offset))
        : 0;
    final pages = _pageOf[index] ?? const [];
    var page = pages.isEmpty ? 0 : pages.first.$1;
    for (final (p, firstLine) in pages) {
      if (firstLine <= line) page = p;
    }
    return page;
  }

  /// 页首的阅读位置。
  ReaderLocation locationOfPage(int page) {
    if (pages.isEmpty) return const ReaderLocation(0, 0);
    final fragment = pages[page.clamp(0, pages.length - 1)].fragments.first;
    final item = items[fragment.itemIndex];
    if (!item.isText) return ReaderLocation(item.blockIndex, 0);
    return ReaderLocation(
      item.blockIndex,
      item.map!.toText(item.lines[fragment.firstLine].start),
    );
  }
}
