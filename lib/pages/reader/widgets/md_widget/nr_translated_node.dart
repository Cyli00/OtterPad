import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:markdown_widget/markdown_widget.dart';

import '../../../../services/translation_style.dart';

/// 主题色样式产出的标记 `[[tr]]...[[/tr]]` 在此被识别为 inline span，
/// 整段上 `ColorScheme.primary` 色。
///
/// 选用 inline 而非 block：译文段落本来就是独立的 P，inline 语法
/// 天然被上层 PConfig 的段落结构所包含，不会破坏列表 / 引用等嵌套场景。
class NRTranslatedInlineSyntax extends md.InlineSyntax {
  NRTranslatedInlineSyntax()
      : super(
          '${RegExp.escape(ThemedTranslationStyle.markerOpen)}'
          r'([\s\S]*?)'
          '${RegExp.escape(ThemedTranslationStyle.markerClose)}',
        );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final content = match.group(1) ?? '';
    if (content.isEmpty) return false;
    final element = md.Element.text('translated', content);
    parser.addNode(element);
    return true;
  }
}

class NRTranslatedSpanNode extends SpanNode {
  final String content;
  final Color color;
  final MarkdownConfig config;

  NRTranslatedSpanNode(this.content, this.color, this.config);

  @override
  InlineSpan build() {
    final base = parentStyle ?? config.p.textStyle;
    final styled = base.copyWith(color: color);

    final matches = _inlineLatexRe.allMatches(content).toList();
    if (matches.isEmpty) {
      return TextSpan(text: content, style: styled);
    }

    final children = <InlineSpan>[];
    int cursor = 0;

    for (final match in matches) {
      if (match.start > cursor) {
        children.add(TextSpan(
          text: content.substring(cursor, match.start),
          style: styled,
        ));
      }

      final equation = match.group(1)!.trim();
      final trailingPunct = match.group(2);
      final mathStyle =
          styled.copyWith(color: color.withValues(alpha: 0.85));

      final mathWidget = Math.tex(
        equation,
        textStyle: mathStyle,
        mathStyle: MathStyle.text,
        textScaleFactor: 1,
        onErrorFallback: (e) => Text('\$$equation\$', style: styled),
      );

      if (trailingPunct != null && trailingPunct.isNotEmpty) {
        children.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                mathWidget,
                Text(trailingPunct, style: styled),
              ],
            ),
          ),
        ));
      } else {
        children.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: mathWidget,
        ));
      }

      cursor = match.end;
    }

    if (cursor < content.length) {
      children.add(TextSpan(
        text: content.substring(cursor),
        style: styled,
      ));
    }

    return TextSpan(children: children);
  }

  static final _inlineLatexRe = RegExp(r'\$([^\$\n]+?)\$([.,;:!?])?');
}

/// 构造带指定主题色的 generator。颜色从 [ColorScheme.primary] 取，
/// 随主题切换需要在 `nr_markdown_config` 里每次重建 generator。
SpanNodeGeneratorWithTag nrTranslatedGenerator({required Color color}) {
  return SpanNodeGeneratorWithTag(
    tag: 'translated',
    generator: (e, config, _) =>
        NRTranslatedSpanNode(e.textContent, color, config),
  );
}
