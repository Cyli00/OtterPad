import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:markdown_widget/markdown_widget.dart';

// ─── Inline Syntax: $...$ ───

class NRLatexInlineSyntax extends md.InlineSyntax {
  NRLatexInlineSyntax() : super(_pattern);

  static const _pattern = r'\$([^\$\n]+?)\$([.,;:!?])?';

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final equation = match.group(1)!.trim();
    if (equation.isEmpty) return false;

    final element = md.Element.text('latex', equation);
    element.attributes['MathStyle'] = 'text';

    final trailingText = match.group(2);
    if (trailingText != null && trailingText.isNotEmpty) {
      element.attributes['TrailingText'] = trailingText;
    }

    parser.addNode(element);
    return true;
  }
}

// ─── Block Syntax: $$...$$ ───

class NRLatexBlockSyntax extends md.BlockSyntax {
  @override
  RegExp get pattern => RegExp(
        r'^(?:(\${1,2})(?:\n|$))|(?:(?:\\\[(.+)\\\])(?:\n|$))',
        multiLine: true,
      );

  @override
  List<md.Line> parseChildLines(md.BlockParser parser) {
    final m = pattern.firstMatch(parser.current.content);
    if (m?[2] != null) {
      parser.advance();
      return [md.Line(m?[2] ?? '')];
    }

    final childLines = <md.Line>[];
    parser.advance();

    while (!parser.isDone) {
      final match = pattern.hasMatch(parser.current.content);
      if (!match) {
        childLines.add(parser.current);
        parser.advance();
      } else {
        parser.advance();
        break;
      }
    }

    return childLines;
  }

  @override
  md.Node parse(md.BlockParser parser) {
    final lines = parseChildLines(parser);
    final content = lines.map((e) => e.content).join('\n').trim();
    final textElement = md.Element.text('latex', content);
    textElement.attributes['MathStyle'] = 'display';
    return md.Element('p', [textElement]);
  }
}

// ─── SpanNode: 渲染 LaTeX 公式 ───

class NRLatexSpanNode extends SpanNode {
  final Map<String, String> attributes;
  final String textContent;
  final MarkdownConfig config;

  NRLatexSpanNode(this.attributes, this.textContent, this.config);

  @override
  InlineSpan build() {
    final content = attributes['content'] ?? textContent;
    final isDisplay = attributes['MathStyle'] == 'display';
    final style = parentStyle ?? config.p.textStyle;

    if (content.isEmpty) return TextSpan(style: style, text: textContent);

    // 视觉妥协：把 0.85 alpha 放进字形颜色（不包 Opacity widget，避免 saveLayer
    // 触发 GPU 层切换），让底下 RenderParagraph 的选区矩形从 glyph 缝隙透出来。
    final mathStyle = style.color == null
        ? style
        : style.copyWith(color: style.color!.withValues(alpha: 0.85));
    final mathWidget = Math.tex(
      content,
      textStyle: mathStyle,
      mathStyle: isDisplay ? MathStyle.display : MathStyle.text,
      textScaleFactor: 1,
      onErrorFallback: (e) => Text(
        '\$$content\$',
        style: style.copyWith(
          fontStyle: FontStyle.italic,
          fontSize: (style.fontSize ?? 14) * 0.9,
        ),
      ),
    );

    if (isDisplay) {
      final mathSpan = WidgetSpan(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Center(child: mathWidget),
              ),
            );
          },
        ),
      );
      return TextSpan(children: [
        mathSpan,
        _invisibleSourceSpan('\$\$$content\$\$', style),
      ]);
    }

    // inline 模式：将公式与尾随标点合并到同一个 WidgetSpan 中
    final trailingText = attributes['TrailingText'];
    if (trailingText != null && trailingText.isNotEmpty) {
      final mathSpan = WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              mathWidget,
              Text(trailingText, style: style),
            ],
          ),
        ),
      );
      return TextSpan(children: [
        mathSpan,
        _invisibleSourceSpan('\$$content\$$trailingText', style),
      ]);
    }

    return TextSpan(children: [
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: mathWidget,
      ),
      _invisibleSourceSpan('\$$content\$', style),
    ]);
  }

  /// 与 `WidgetSpan` 平级的透明源码 TextSpan——
  /// 让该公式在外层 `RichText` 的同一段 `RenderParagraph` 里拥有真实的
  /// 可选 fragment：选区能跨越公式、复制时得到 LaTeX 源码。
  ///
  /// 不用 `fontSize: 0`（Flutter 会限制最小渲染尺寸），改用极小字号 + 透明色
  /// + 行高倍率为 0 + 无字距，让这段文字在视觉和布局上都接近于零。
  TextSpan _invisibleSourceSpan(String source, TextStyle baseStyle) {
    return TextSpan(
      text: source,
      style: baseStyle.copyWith(
        fontSize: 0.01,
        color: const Color(0x00000000),
        height: 0,
        letterSpacing: 0,
        wordSpacing: 0,
        shadows: const <Shadow>[],
        decoration: TextDecoration.none,
      ),
    );
  }
}

// ─── Generator ───

SpanNodeGeneratorWithTag nrLatexGenerator = SpanNodeGeneratorWithTag(
  tag: 'latex',
  generator: (e, config, visitor) =>
      NRLatexSpanNode(e.attributes, e.textContent, config),
);
