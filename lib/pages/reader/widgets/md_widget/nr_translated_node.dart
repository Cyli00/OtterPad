import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:markdown_widget/markdown_widget.dart';

import '../../../../services/translation_style.dart';
import 'nr_selectable_math.dart';

/// `[[tr]]...[[/tr]]` 标记的 inline syntax 识别器。
/// 被 themed / weakened / dashed / highlight / blur 五种自定义渲染样式共用。
class NRTranslatedInlineSyntax extends md.InlineSyntax {
  NRTranslatedInlineSyntax()
    : super(
        '${RegExp.escape(kTranslationMarkerOpen)}'
        r'([\s\S]*?)'
        '${RegExp.escape(kTranslationMarkerClose)}',
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

/// 根据当前 [styleId] 分派到不同的渲染策略：
/// - `themed`：primary 色文本
/// - `weakened`：降低文本透明度
/// - `dashed`：primary 色 + 虚线下划线
/// - `highlight`：背景高亮
/// - `blur`：模糊遮罩，点击后显示
class NRTranslatedSpanNode extends SpanNode {
  final String content;
  final Color color;
  final MarkdownConfig config;
  final String styleId;
  final ValueListenable<String?>? selectedTextListenable;

  NRTranslatedSpanNode(
    this.content,
    this.color,
    this.config, {
    this.styleId = 'themed',
    this.selectedTextListenable,
  });

  @override
  InlineSpan build() {
    return switch (styleId) {
      'weakened' => _buildWeakened(),
      'dashed' => _buildDashed(),
      'highlight' => _buildHighlight(),
      'blur' => _buildBlur(),
      _ => _buildThemed(),
    };
  }

  // ── Themed: primary 色文本 ──

  InlineSpan _buildThemed() {
    final base = parentStyle ?? config.p.textStyle;
    final styled = base.copyWith(color: color);
    return _buildWithLatex(styled, color);
  }

  // ── Weakened: 降低文本透明度 ──

  InlineSpan _buildWeakened() {
    final base = parentStyle ?? config.p.textStyle;
    final baseColor = base.color ?? const Color(0xFF000000);
    final styled = base.copyWith(color: baseColor.withAlpha(120));
    return _buildWithLatex(styled, baseColor.withAlpha(120));
  }

  // ── Dashed: primary 色 + 虚线下划线 ──

  InlineSpan _buildDashed() {
    final base = parentStyle ?? config.p.textStyle;
    final styled = base.copyWith(
      color: color,
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dashed,
      decorationColor: color.withAlpha(140),
    );
    return _buildWithLatex(styled, color);
  }

  // ── Highlight: 背景高亮 ──

  InlineSpan _buildHighlight() {
    final base = parentStyle ?? config.p.textStyle;
    final styled = base.copyWith(backgroundColor: color.withAlpha(36));
    return _buildWithLatex(styled, color.withAlpha(180));
  }

  // ── Blur: 模糊遮罩 + 点击切换 ──

  InlineSpan _buildBlur() {
    final base = parentStyle ?? config.p.textStyle;
    final styled = base.copyWith(color: color);
    final span = _buildWithLatex(styled, color);
    return WidgetSpan(child: _BlurRevealText(child: Text.rich(span)));
  }

  // ── LaTeX 感知的文本构建器 ──

  InlineSpan _buildWithLatex(TextStyle styled, Color mathColor) {
    final matches = _inlineLatexRe.allMatches(content).toList();
    if (matches.isEmpty) {
      return TextSpan(text: content, style: styled);
    }

    final children = <InlineSpan>[];
    int cursor = 0;

    for (final match in matches) {
      if (match.start > cursor) {
        children.add(
          TextSpan(text: content.substring(cursor, match.start), style: styled),
        );
      }

      final equation = match.group(1)!.trim();
      final trailingPunct = match.group(2);
      final mathStyle = styled.copyWith(
        color: mathColor.withValues(alpha: 0.85),
      );

      children.add(
        buildNrSelectableMathSpan(
          source: trailingPunct != null && trailingPunct.isNotEmpty
              ? '\$$equation\$$trailingPunct'
              : '\$$equation\$',
          equation: equation,
          style: mathStyle,
          mathStyle: MathStyle.text,
          selectedTextListenable: selectedTextListenable,
          trailingText: trailingPunct,
        ),
      );

      cursor = match.end;
    }

    if (cursor < content.length) {
      children.add(TextSpan(text: content.substring(cursor), style: styled));
    }

    return TextSpan(children: children);
  }

  static final _inlineLatexRe = RegExp(r'\$([^\$\n]+?)\$([.,;:!?])?');
}

/// 模糊译文：初始模糊，点击切换显示/隐藏。
class _BlurRevealText extends StatefulWidget {
  final Widget child;
  const _BlurRevealText({required this.child});

  @override
  State<_BlurRevealText> createState() => _BlurRevealTextState();
}

class _BlurRevealTextState extends State<_BlurRevealText> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _revealed = !_revealed),
      child: _revealed
          ? widget.child
          : ClipRect(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: widget.child,
              ),
            ),
    );
  }
}

/// 构造带指定样式的 generator。
SpanNodeGeneratorWithTag nrTranslatedGenerator({
  required Color color,
  String styleId = 'themed',
  ValueListenable<String?>? selectedTextListenable,
}) {
  return SpanNodeGeneratorWithTag(
    tag: 'translated',
    generator: (e, config, _) => NRTranslatedSpanNode(
      e.textContent,
      color,
      config,
      styleId: styleId,
      selectedTextListenable: selectedTextListenable,
    ),
  );
}
