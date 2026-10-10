import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:markdown_widget/markdown_widget.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../providers/reader_settings_provider.dart';
import '../md_widget/nr_custom_text_node.dart';
import '../md_widget/nr_image_node.dart';
import '../md_widget/nr_latex_node.dart';
import '../reader_background.dart';
import '../reader_typography.dart';
import 'native_reader_document.dart';

// ─── 公式 ───

/// 行内/块级公式。
///
/// 公式本身不参与文本选择；紧随其后的隐形源码（[_invisible]）承担选区、
/// 复制和锚点对齐，[ReaderAnchoredText] 再据此给公式补选中底色与标注底色。
class ReaderMath extends StatelessWidget {
  const ReaderMath({
    super.key,
    required this.equation,
    required this.style,
    this.display = false,
    this.trailing = '',
  });

  final String equation;
  final TextStyle style;
  final bool display;

  /// 紧跟公式的标点，与公式同排，避免被折到下一行行首。
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final formula = Math.tex(
      equation,
      textStyle: style,
      mathStyle: display ? MathStyle.display : MathStyle.text,
      textScaleFactor: 1,
      onErrorFallback: (_) => Text(
        display ? '\$\$$equation\$\$' : '\$$equation\$',
        style: style.copyWith(fontStyle: FontStyle.italic),
      ),
    );
    // 公式自然宽度可能超过行宽：行内按比例缩小，块级横向滚动。
    final Widget body = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: trailing.isEmpty
          ? formula
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                formula,
                Text(trailing, style: style),
              ],
            ),
    );
    return SelectionContainer.disabled(
      child: display
          ? LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Center(child: body),
                ),
              ),
            )
          : body,
    );
  }
}

TextStyle _invisible(TextStyle base) => base.copyWith(
  fontSize: 0.01,
  color: const Color(0x00000000),
  height: 0,
  letterSpacing: 0,
  wordSpacing: 0,
  shadows: const <Shadow>[],
  decoration: TextDecoration.none,
);

bool _isInvisible(TextStyle? style) {
  final size = style?.fontSize;
  return size != null && size < 1;
}

class _LatexNode extends SpanNode {
  _LatexNode(this.attributes, this.equation, this.config);

  final Map<String, String> attributes;
  final String equation;
  final MarkdownConfig config;

  @override
  InlineSpan build() {
    final style = parentStyle ?? config.p.textStyle;
    final display = attributes['MathStyle'] == 'display';
    final trailing = attributes['TrailingText'] ?? '';
    if (equation.isEmpty) return TextSpan(text: trailing, style: style);
    return TextSpan(
      children: [
        WidgetSpan(
          alignment: display
              ? PlaceholderAlignment.bottom
              : PlaceholderAlignment.middle,
          child: ReaderMath(
            equation: equation,
            style: style,
            display: display,
            trailing: trailing,
          ),
        ),
        TextSpan(
          text:
              attributes['Source'] ??
              (display ? '\$\$$equation\$\$' : '\$$equation\$$trailing'),
          style: _invisible(style),
        ),
      ],
    );
  }
}

/// `\( … \)` 行内公式。
class _ParenLatexSyntax extends md.InlineSyntax {
  _ParenLatexSyntax() : super(r'\\\(([\s\S]+?)\\\)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final equation = match[1]!.trim();
    if (equation.isEmpty) return false;
    parser.addNode(
      md.Element.text('latex', equation)
        ..attributes['MathStyle'] = 'text'
        ..attributes['Source'] = match[0]!,
    );
    return true;
  }
}

/// `$$ … $$` 与 `\[ … \]` 块级公式，允许起止符与内容同行。
class _LatexBlockSyntax extends md.BlockSyntax {
  @override
  RegExp get pattern => RegExp(r'^\s*(\$\$|\\\[)');

  @override
  bool canParse(md.BlockParser parser) {
    final line = parser.current.content.trimLeft();
    if (line.startsWith(r'$$')) return true;
    if (!line.startsWith(r'\[')) return false;
    // `\[1\] 作者…` 这类以转义方括号开头的正文不是公式块。
    final close = line.indexOf(r'\]', 2);
    return close < 0 || line.substring(close + 2).trim().isEmpty;
  }

  @override
  md.Node? parse(md.BlockParser parser) {
    final first = parser.current.content.trimLeft();
    final closer = first.startsWith(r'$$') ? r'$$' : r'\]';
    final lines = <String>[];
    var line = first;
    while (true) {
      final close = line.indexOf(closer, lines.isEmpty ? 2 : 0);
      parser.advance();
      if (close >= 0) {
        lines.add(line.substring(0, close + closer.length));
        final rest = line.substring(close + closer.length).trim();
        // 收尾符之后的文字仍按普通 Markdown 解析。
        if (rest.isNotEmpty) {
          final index = parser.isDone
              ? -1
              : parser.lines.indexOf(parser.current);
          if (index < 0) {
            parser.lines.add(md.Line(rest));
          } else {
            parser.lines.insert(index, md.Line(rest));
          }
        }
        break;
      }
      lines.add(line);
      if (parser.isDone) break;
      line = parser.current.content;
    }
    final source = lines.join('\n');
    var equation = source.substring(2);
    if (equation.endsWith(closer)) {
      equation = equation.substring(0, equation.length - closer.length);
    }
    return md.Element('p', [
      md.Element.text('latex', equation.trim())
        ..attributes['MathStyle'] = 'display'
        ..attributes['Source'] = source,
    ]);
  }
}

class _ScriptNode extends ElementNode {
  _ScriptNode(this.superscript);

  final bool superscript;

  @override
  TextStyle? get style {
    final base = parentStyle ?? const TextStyle();
    final size = base.fontSize;
    return base.copyWith(
      fontSize: size == null ? null : size * 0.75,
      fontFeatures: [
        superscript
            ? const FontFeature.superscripts()
            : const FontFeature.subscripts(),
      ],
    );
  }
}

// ─── 渲染资源 ───

/// 一套随主题、字号、译文样式变化的渲染资源；身份即版本，变了才重建段落。
class NativeReaderStyle {
  NativeReaderStyle({
    required this.palette,
    required this.fontSize,
    required this.font,
    required this.translationStyleId,
    required this.onImageTap,
  });

  final ReaderPalette palette;
  final double fontSize;
  final ReaderFont font;
  final String translationStyleId;
  final void Function(String url) onImageTap;

  /// 块间距，对应 reader.css 的 `--block-margin`。
  double get blockGap => fontSize * ReaderTypography.blockMarginScale;

  late final TextStyle body = TextStyle(
    color: palette.text,
    fontSize: fontSize,
    fontFamily: font.fontFamily,
    fontFamilyFallback: font.fontFamilyFallback,
    height: ReaderTypography.bodyHeight,
  );

  late final MarkdownGenerator generator = MarkdownGenerator(
    generators: [
      SpanNodeGeneratorWithTag(
        tag: 'latex',
        generator: (e, config, _) =>
            _LatexNode(e.attributes, e.textContent, config),
      ),
      SpanNodeGeneratorWithTag(
        tag: 'sup',
        generator: (_, _, _) => _ScriptNode(true),
      ),
      SpanNodeGeneratorWithTag(
        tag: 'sub',
        generator: (_, _, _) => _ScriptNode(false),
      ),
    ],
    // 与 WebView 版、段落纯文本用同一套行内语法，显示文字才能逐字对上。
    inlineSyntaxList: [NRLatexInlineSyntax(), _ParenLatexSyntax()],
    blockSyntaxList: [_LatexBlockSyntax()],
    textGenerator: (node, config, visitor) =>
        NRCustomTextNode(node.textContent, config, visitor),
    richTextBuilder: ReaderAnchoredText.new,
    // CSS 相邻块的外边距会折叠成一份，这里上下各取一半。
    linesMargin: EdgeInsets.symmetric(vertical: blockGap / 2),
  );

  final _configs = <int, MarkdownConfig>{};

  MarkdownConfig config({bool caption = false, bool translated = false}) =>
      _configs[(caption ? 1 : 0) | (translated ? 2 : 0)] ??= _buildConfig(
        caption,
        translated,
      );

  TextStyle _translated(TextStyle base) => switch (translationStyleId) {
    'bold' => base.copyWith(fontWeight: FontWeight.bold),
    'italic' => base.copyWith(fontStyle: FontStyle.italic),
    'weakened' => base.copyWith(
      color: palette.text.withValues(alpha: ReaderTypography.trWeakAlpha),
    ),
    'dashed' => base.copyWith(
      color: palette.link,
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dashed,
      decorationColor: palette.link.withValues(
        alpha: ReaderTypography.trDecoAlpha,
      ),
    ),
    'highlight' => base.copyWith(
      color: palette.link.withValues(alpha: ReaderTypography.trHlTextAlpha),
      backgroundColor: palette.link.withValues(
        alpha: ReaderTypography.trHlBgAlpha,
      ),
    ),
    'blur' => base,
    'quote' => base.copyWith(color: palette.secondaryText),
    _ => base.copyWith(color: palette.link),
  };

  MarkdownConfig _buildConfig(bool caption, bool translated) {
    final size = caption ? fontSize * ReaderTypography.captionScale : fontSize;
    var base = body.copyWith(fontSize: size, height: caption ? 1.5 : null);
    if (translated) base = _translated(base);
    TextStyle heading(double scale, FontWeight weight, double height) =>
        base.copyWith(
          fontSize: size * scale,
          fontWeight: weight,
          height: height,
        );
    final code = TextStyle(
      fontFamily: ReaderTypography.codeFontFamily,
      fontFamilyFallback: ReaderTypography.codeFontFallback,
      fontSize: size * ReaderTypography.codeScale,
      color: base.color,
    );
    return MarkdownConfig(
      configs: [
        PConfig(textStyle: base),
        _H1(
          style: heading(
            ReaderTypography.h1Scale,
            ReaderTypography.h1Weight,
            ReaderTypography.h1Height,
          ),
        ),
        _H2(
          style: heading(
            ReaderTypography.h2Scale,
            ReaderTypography.h2Weight,
            ReaderTypography.h2Height,
          ),
        ),
        _H3(
          style: heading(
            ReaderTypography.h3Scale,
            ReaderTypography.h3Weight,
            ReaderTypography.h3to6Height,
          ),
        ),
        H4Config(
          style: heading(
            ReaderTypography.h4Scale,
            ReaderTypography.h4Weight,
            ReaderTypography.h3to6Height,
          ),
        ),
        H5Config(
          style: heading(
            1,
            ReaderTypography.h5Weight,
            ReaderTypography.h3to6Height,
          ),
        ),
        H6Config(
          style: heading(
            1,
            ReaderTypography.h6Weight,
            ReaderTypography.h3to6Height,
          ).copyWith(color: palette.secondaryText),
        ),
        BlockquoteConfig(
          sideColor: palette.divider,
          textColor: palette.secondaryText,
          sideWith: ReaderTypography.blockquoteSideWidth,
          padding: const EdgeInsets.only(
            left: ReaderTypography.blockquotePadLeft,
          ),
          margin: EdgeInsets.zero,
        ),
        PreConfig(
          textStyle: code,
          decoration: BoxDecoration(
            color: palette.codeBlock,
            borderRadius: const BorderRadius.all(Radius.circular(8)),
          ),
          padding: const EdgeInsets.all(12),
          margin: EdgeInsets.zero,
        ),
        CodeConfig(style: code.copyWith(backgroundColor: palette.codeBlock)),
        LinkConfig(
          style: base.copyWith(
            color: palette.link,
            decoration: TextDecoration.none,
          ),
          onTap: (url) {
            final uri = Uri.tryParse(url);
            if (uri != null && const {'https', 'http'}.contains(uri.scheme)) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
        ),
        TableConfig(
          headerStyle: base.copyWith(fontWeight: FontWeight.w600),
          bodyStyle: base,
          border: TableBorder.all(color: palette.divider, width: 0.5),
          headPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          bodyPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          wrapper: (table) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: table,
          ),
        ),
        HrConfig(height: 1, color: palette.divider),
        NRImgConfig(
          captionStyle: base.copyWith(
            fontSize: fontSize * ReaderTypography.captionScale,
          ),
          onTap: onImageTap,
        ),
      ],
    );
  }
}

// reader.css 的标题没有分隔线。
class _H1 extends H1Config {
  const _H1({required super.style});

  @override
  HeadingDivider? get divider => null;
}

class _H2 extends H2Config {
  const _H2({required super.style});

  @override
  HeadingDivider? get divider => null;
}

class _H3 extends H3Config {
  const _H3({required super.style});

  @override
  HeadingDivider? get divider => null;
}

// ─── 语言单元上下文 ───

/// 一段显示文字当前的选区。[text] 为空串表示该文字已无选区。
class NativeTextSelection {
  const NativeTextSelection({
    required this.cell,
    required this.order,
    required this.range,
    required this.text,
    required this.rects,
  });

  final NativeReaderCell cell;

  /// 同一语言单元内多段文字的先后。
  final int order;

  /// 选区在 [NativeReaderCell.text] 中的范围；显示文字对不上时为 null。
  final ({int start, int end})? range;
  final String text;

  /// 选区当前在屏幕上的矩形；文字已卸载时为空。
  final List<Rect> Function() rects;
}

abstract interface class NativeReaderTextHost {
  /// 桌面双语时把拖选限制在按下处的语言；null 为不限制。
  ValueListenable<NativeCellKind?> get selectionLock;

  void textSelectionChanged(NativeTextSelection selection);

  void highlightTapped(String highlightId, Rect globalRect);
}

class NativeCellScope extends InheritedWidget {
  const NativeCellScope({
    super.key,
    required this.cell,
    required this.marks,
    required this.host,
    required super.child,
  });

  final NativeReaderCell cell;
  final List<ReaderMark> marks;
  final NativeReaderTextHost host;

  static NativeCellScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NativeCellScope>();

  @override
  bool updateShouldNotify(NativeCellScope oldWidget) =>
      !identical(cell, oldWidget.cell) ||
      !identical(host, oldWidget.host) ||
      !listEquals(marks, oldWidget.marks);
}

// ─── 可定位文字 ───

class _SelectionDelegate extends StaticSelectionContainerDelegate {
  _SelectionDelegate(this.onChanged);

  final VoidCallback onChanged;

  @override
  void notifyListeners() {
    super.notifyListeners();
    onChanged();
  }
}

class _Leaf {
  _Leaf.text(this.text, this.style, TextSpan this.source) : widget = null;
  _Leaf.widget(WidgetSpan this.widget) : text = '', style = null, source = null;

  final String text;
  final TextStyle? style;
  final TextSpan? source;
  final WidgetSpan? widget;

  /// 在去掉公式占位符的显示文字中的起点。
  int start = 0;
}

typedef _Range = ({int start, int end});

/// Markdown 一个文本块的显示文字。
///
/// 位于 [NativeCellScope] 之下时，把显示文字与段落纯文本逐字对齐：
/// - 选区换算成段落内的 UTF-16 范围后上报，供生成 `ReaderAnchor`；
/// - 标注、搜索命中等 [ReaderMark] 直接画成 `TextSpan` 背景色。
///
/// 含列表、表格等嵌套容器的文字块自身不参与对齐，由内层文字各自处理。
class ReaderAnchoredText extends StatefulWidget {
  const ReaderAnchoredText(this.span, {super.key});

  final InlineSpan span;

  @override
  State<ReaderAnchoredText> createState() => _ReaderAnchoredTextState();
}

class _ReaderAnchoredTextState extends State<ReaderAnchoredText> {
  final _textKey = GlobalKey();
  final _selection = ValueNotifier<_Range?>(null);
  final _recognizers = <TapGestureRecognizer>[];
  late final _delegate = _SelectionDelegate(_scheduleSelectionSync);

  NativeCellScope? _scope;
  bool _syncScheduled = false;

  // 以 (span, cell) 为键的排版缓存。
  InlineSpan? _preparedSpan;
  NativeReaderCell? _preparedCell;
  List<_Leaf> _leaves = const [];
  String _plain = '';
  CompactText _compact = CompactText('');
  bool _trackable = false;

  /// 显示文字在段落 compact 文字中的起点；-1 表示对不上。
  int _base = -1;

  // 以标记列表为键的着色缓存。重建 TextSpan 会让该段选区失效，故只在
  // 标记确实变化时重建。
  List<ReaderMark>? _decoratedMarks;
  InlineSpan? _decorated;

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _delegate.dispose();
    _selection.dispose();
    super.dispose();
  }

  void _prepare(NativeReaderCell cell) {
    if (identical(_preparedSpan, widget.span) &&
        identical(_preparedCell, cell)) {
      return;
    }
    _preparedSpan = widget.span;
    _preparedCell = cell;
    _decorated = null;
    _decoratedMarks = null;

    final leaves = <_Leaf>[];
    var trackable = true;
    void visit(InlineSpan span, TextStyle? inherited) {
      if (span is TextSpan) {
        final style = inherited?.merge(span.style) ?? span.style;
        final text = span.text;
        if (text != null && text.isNotEmpty) {
          leaves.add(_Leaf.text(text, style, span));
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child, style);
        }
      } else if (span is WidgetSpan) {
        if (span.child is! ReaderMath) trackable = false;
        leaves.add(_Leaf.widget(span));
      } else {
        trackable = false;
      }
    }

    visit(widget.span, null);
    final buffer = StringBuffer();
    for (final leaf in leaves) {
      leaf.start = buffer.length;
      buffer.write(leaf.text);
    }
    _leaves = leaves;
    _plain = buffer.toString();
    _compact = CompactText(_plain);
    _trackable = trackable && _plain.isNotEmpty;
    _base = _trackable ? cell.compact.locate(_compact) : -1;
  }

  /// 段落纯文本范围 → 显示文字范围。
  _Range? _toPlain(NativeReaderCell cell, int start, int end) {
    if (_base < 0) return null;
    return _compact.range(
      math.max(cell.compact.indexOf(start) - _base, 0),
      math.min(cell.compact.indexOf(end) - _base, _compact.length),
    );
  }

  /// 显示文字范围 → 段落纯文本范围。
  _Range? _toSource(NativeReaderCell cell, _Range range) {
    if (_base < 0) return null;
    return cell.compact.range(
      _base + _compact.indexOf(range.start),
      _base + _compact.indexOf(range.end),
    );
  }

  InlineSpan _decorate(NativeCellScope scope) {
    final marks = _base < 0 ? const <ReaderMark>[] : scope.marks;
    final cached = _decorated;
    if (cached != null && listEquals(_decoratedMarks, marks)) return cached;
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();

    final local = <({_Range range, ReaderMark mark})>[];
    for (final mark in marks) {
      final range = _toPlain(scope.cell, mark.start, mark.end);
      if (range != null) local.add((range: range, mark: mark));
    }
    // 后加入的标记盖住先加入的：标注 < 搜索命中 < 定位。
    ReaderMark? markAt(int start, int end) {
      for (final entry in local.reversed) {
        if (entry.range.start < end && entry.range.end > start) {
          return entry.mark;
        }
      }
      return null;
    }

    final children = <InlineSpan>[];
    for (var i = 0; i < _leaves.length; i++) {
      final leaf = _leaves[i];
      final formula = leaf.widget;
      if (formula != null) {
        // 公式的范围取其后的隐形源码。
        final next = i + 1 < _leaves.length ? _leaves[i + 1] : null;
        final end = next != null && _isInvisible(next.style)
            ? leaf.start + next.text.length
            : leaf.start;
        children.add(
          WidgetSpan(
            alignment: formula.alignment,
            baseline: formula.baseline,
            style: formula.style,
            child: _FormulaTint(
              selection: _selection,
              start: leaf.start,
              end: end,
              color: end > leaf.start ? markAt(leaf.start, end)?.color : null,
              child: formula.child,
            ),
          ),
        );
        continue;
      }
      final leafEnd = leaf.start + leaf.text.length;
      final cuts = <int>{leaf.start, leafEnd};
      for (final (:range, mark: _) in local) {
        if (range.start > leaf.start && range.start < leafEnd) {
          cuts.add(range.start);
        }
        if (range.end > leaf.start && range.end < leafEnd) cuts.add(range.end);
      }
      final points = cuts.toList()..sort();
      for (var p = 0; p + 1 < points.length; p++) {
        children.add(
          _piece(
            leaf,
            leaf.text.substring(
              points[p] - leaf.start,
              points[p + 1] - leaf.start,
            ),
            markAt(points[p], points[p + 1]),
          ),
        );
      }
    }
    _decoratedMarks = List.of(marks);
    return _decorated = TextSpan(children: children);
  }

  TextSpan _piece(_Leaf leaf, String text, ReaderMark? mark) {
    final source = leaf.source!;
    var recognizer = source.recognizer;
    final id = mark?.highlightId;
    if (mark != null && id != null && recognizer == null) {
      final tap = TapGestureRecognizer()
        ..onTapUp = (details) =>
            _onHighlightTap(id, mark, details.globalPosition);
      _recognizers.add(tap);
      recognizer = tap;
    }
    return TextSpan(
      text: text,
      style: mark == null
          ? leaf.style
          : (leaf.style ?? const TextStyle()).copyWith(
              backgroundColor: mark.color,
            ),
      recognizer: recognizer,
      // 新挂的点击识别器沿用 TextSpan 的默认手型。
      mouseCursor: identical(recognizer, source.recognizer)
          ? source.mouseCursor
          : null,
    );
  }

  RenderParagraph? _paragraph() {
    RenderObject? object = _textKey.currentContext?.findRenderObject();
    while (object is RenderProxyBox) {
      object = object.child;
    }
    return object is RenderParagraph ? object : null;
  }

  /// 显示文字偏移 → 含公式占位符的段落偏移。
  int _paragraphOffset(int plain) {
    var offset = plain;
    for (final leaf in _leaves) {
      if (leaf.widget != null && leaf.start <= plain) offset++;
    }
    return offset;
  }

  void _onHighlightTap(String id, ReaderMark mark, Offset position) {
    final scope = _scope;
    if (scope == null) return;
    var rect = Rect.fromCenter(center: position, width: 1, height: 1);
    final range = _toPlain(scope.cell, mark.start, mark.end);
    final paragraph = _paragraph();
    if (range != null && paragraph != null) {
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(
          baseOffset: _paragraphOffset(range.start),
          extentOffset: _paragraphOffset(range.end - 1) + 1,
        ),
      );
      if (boxes.isNotEmpty) {
        final bounds = boxes
            .map((box) => box.toRect())
            .reduce((a, b) => a.expandToInclude(b));
        rect = MatrixUtils.transformRect(
          paragraph.getTransformTo(null),
          bounds,
        );
      }
    }
    scope.host.highlightTapped(id, rect);
  }

  // 选区几何可能在布局阶段变化，统一推迟到微任务里读取和上报。
  void _scheduleSelectionSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    scheduleMicrotask(() {
      _syncScheduled = false;
      if (mounted) _syncSelection();
    });
  }

  void _syncSelection() {
    final scope = _scope;
    if (scope == null) return;
    final range = _currentSelection();
    if (range == null && _selection.value == null) return;
    _selection.value = range;
    scope.host.textSelectionChanged(
      NativeTextSelection(
        cell: scope.cell,
        order: _base < 0 ? -1 - identityHashCode(this) : _base,
        range: range == null ? null : _toSource(scope.cell, range),
        text: range == null ? '' : _plain.substring(range.start, range.end),
        rects: _selectionRects,
      ),
    );
  }

  _Range? _currentSelection() {
    if (_delegate.value.status != SelectionStatus.uncollapsed) return null;
    final content = _delegate.getSelectedContent()?.plainText ?? '';
    if (content.isEmpty) return null;
    // 文字里有公式占位时，框架给出的偏移可能有几位出入；选中的原文是
    // 准的，用它在附近校准。
    SelectedContentRange? range;
    try {
      range = _delegate.getSelection();
    } catch (_) {
      range = null;
    }
    if (range != null) {
      final hint = math.min(range.startOffset, range.endOffset);
      for (var delta = 0; delta <= 8; delta++) {
        for (final start in {hint - delta, hint + delta}) {
          if (start >= 0 &&
              start <= _plain.length &&
              _plain.startsWith(content, start)) {
            return (start: start, end: start + content.length);
          }
        }
      }
    }
    final found = _plain.indexOf(content);
    return found < 0 ? null : (start: found, end: found + content.length);
  }

  List<Rect> _selectionRects() {
    if (!mounted) return const [];
    try {
      final transform = _delegate.getTransformTo(null);
      return [
        for (final rect in _delegate.value.selectionRects)
          MatrixUtils.transformRect(transform, rect),
      ];
    } catch (_) {
      // 选区容器尚未布局或已停用。
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope = NativeCellScope.maybeOf(context);
    if (scope == null) return Text.rich(widget.span);
    _prepare(scope.cell);
    if (!_trackable) return Text.rich(widget.span);
    final span = _decorate(scope);
    return ValueListenableBuilder<NativeCellKind?>(
      valueListenable: scope.host.selectionLock,
      builder: (context, lock, _) {
        final text = Text.rich(span, key: _textKey);
        final kind = scope.cell.kind;
        // 两种状态各用一个 key：SelectionContainer 原地从停用切回启用时
        // 不会重新向上级登记，必须换一个 State。
        return lock == null || kind == NativeCellKind.block || kind == lock
            ? SelectionContainer(
                key: const ValueKey(true),
                delegate: _delegate,
                child: text,
              )
            : SelectionContainer.disabled(
                key: const ValueKey(false),
                child: text,
              );
      },
    );
  }
}

/// 给公式补底色：被选中时用选区色，否则用所在标记的颜色。
class _FormulaTint extends StatelessWidget {
  const _FormulaTint({
    required this.selection,
    required this.start,
    required this.end,
    required this.color,
    required this.child,
  });

  final ValueListenable<_Range?> selection;
  final int start;
  final int end;
  final Color? color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_Range?>(
      valueListenable: selection,
      child: child,
      builder: (context, range, child) {
        final selected =
            range != null && range.start < end && range.end > start;
        return ColoredBox(
          color: selected
              ? DefaultSelectionStyle.of(context).selectionColor ??
                    DefaultSelectionStyle.defaultColor
              : color ?? const Color(0x00000000),
          child: child,
        );
      },
    );
  }
}
