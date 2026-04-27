import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:markdown_widget/markdown_widget.dart';

import 'nr_selectable_math.dart';

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

class NRLatexSpanNode extends SpanNode {
  final Map<String, String> attributes;
  final String textContent;
  final MarkdownConfig config;
  final ValueListenable<String?>? selectedTextListenable;

  NRLatexSpanNode(
    this.attributes,
    this.textContent,
    this.config, {
    this.selectedTextListenable,
  });

  @override
  InlineSpan build() {
    final content = attributes['content'] ?? textContent;
    final isDisplay = attributes['MathStyle'] == 'display';
    final style = parentStyle ?? config.p.textStyle;

    if (content.isEmpty) return TextSpan(style: style, text: textContent);

    final mathStyle = style.color == null
        ? style
        : style.copyWith(color: style.color!.withValues(alpha: 0.85));

    if (isDisplay) {
      return buildNrSelectableMathSpan(
        source: '\$\$$content\$\$',
        equation: content,
        style: mathStyle,
        mathStyle: MathStyle.display,
        selectedTextListenable: selectedTextListenable,
        display: true,
      );
    }

    final trailingText = attributes['TrailingText'];
    if (trailingText != null && trailingText.isNotEmpty) {
      return buildNrSelectableMathSpan(
        source: '\$$content\$$trailingText',
        equation: content,
        style: mathStyle,
        mathStyle: MathStyle.text,
        selectedTextListenable: selectedTextListenable,
        trailingText: trailingText,
      );
    }

    return buildNrSelectableMathSpan(
      source: '\$$content\$',
      equation: content,
      style: mathStyle,
      mathStyle: MathStyle.text,
      selectedTextListenable: selectedTextListenable,
    );
  }
}

SpanNodeGeneratorWithTag nrLatexGenerator({
  ValueListenable<String?>? selectedTextListenable,
}) {
  return SpanNodeGeneratorWithTag(
    tag: 'latex',
    generator: (e, config, visitor) => NRLatexSpanNode(
      e.attributes,
      e.textContent,
      config,
      selectedTextListenable: selectedTextListenable,
    ),
  );
}
