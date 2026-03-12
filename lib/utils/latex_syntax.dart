import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

class NRLatexInlineSyntax extends md.InlineSyntax {
  NRLatexInlineSyntax() : super(_pattern);

  static const _pattern = r'\$([^\$\n]+?)\$([.,;:!?])?';

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final equation = match.group(1)!.trim();
    if (equation.isEmpty) {
      return false;
    }

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

class NRLatexElementBuilder extends MarkdownElementBuilder {
  NRLatexElementBuilder({this.textStyle, this.textScaleFactor});

  final TextStyle? textStyle;
  final double? textScaleFactor;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final text = element.textContent;
    if (text.isEmpty) {
      return const SizedBox();
    }

    final isDisplay = element.attributes['MathStyle'] == 'display';
    final effectiveStyle =
        parentStyle ??
        preferredStyle ??
        textStyle ??
        DefaultTextStyle.of(context).style;
    final mathWidget = Math.tex(
      text,
      textStyle: effectiveStyle,
      mathStyle: isDisplay ? MathStyle.display : MathStyle.text,
      textScaleFactor: textScaleFactor,
      onErrorFallback: (e) => Text(
        '\$$text\$',
        style: effectiveStyle.copyWith(
          fontStyle: FontStyle.italic,
          fontSize: (effectiveStyle.fontSize ?? 14) * 0.9,
        ),
      ),
    );

    if (isDisplay) {
      return LayoutBuilder(
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
      );
    }

    final trailingText = element.attributes['TrailingText'];
    if (trailingText == null || trailingText.isEmpty) {
      return mathWidget;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        mathWidget,
        Text(trailingText, style: effectiveStyle),
      ],
    );
  }
}

