import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../../../../data/models/book/highlight.dart';

/// 用户高亮的渲染上下文，从 view.dart 经由 _RenderResources 传递到 MarkNode。
class HighlightRenderContext {
  final Color userHighlightColor;
  final Map<String, Highlight> highlightByText;
  final void Function(Highlight highlight, Offset globalPosition)? onHighlightTap;
  final List<TapGestureRecognizer> recognizers;

  HighlightRenderContext({
    required this.userHighlightColor,
    required this.highlightByText,
    this.onHighlightTap,
    required this.recognizers,
  });

  void disposeRecognizers() {
    for (final r in recognizers) {
      r.dispose();
    }
    recognizers.clear();
  }
}

/// 渲染带背景色 + 可选点击手势的高亮文本。
///
/// 由 [NRHighlightDelimiterSyntax] 产生的 `nrhl` 元素触发，
/// 通过 [SpanNodeGeneratorWithTag] 创建。
class MarkNode extends ElementNode {
  final HighlightRenderContext context;

  MarkNode({required this.context});

  @override
  InlineSpan build() {
    final cs = childrenSpan;
    // 清除 \uFFFC（LaTeX WidgetSpan 占位符）以匹配 map key
    final plainText = _extractPlainText(cs).replaceAll('\uFFFC', '').trim();
    // 精确匹配优先，失败后尝试空白归一化（LaTeX 导致的多余空白）
    final hl = context.highlightByText[plainText] ??
        context.highlightByText[
            plainText.replaceAll(RegExp(r'\s+'), ' ').trim()];

    return TextSpan(
      style: TextStyle(backgroundColor: context.userHighlightColor),
      recognizer: hl != null ? _buildTap(hl) : null,
      children: cs.children,
    );
  }

  TapGestureRecognizer? _buildTap(Highlight hl) {
    final onTap = context.onHighlightTap;
    if (onTap == null) return null;
    final r = TapGestureRecognizer()
      ..onTapUp = (d) => onTap(hl, d.globalPosition);
    context.recognizers.add(r);
    return r;
  }

  /// 从 InlineSpan 树中递归提取纯文本，WidgetSpan（LaTeX）用 \uFFFC 占位。
  static String _extractPlainText(InlineSpan span) {
    final buf = StringBuffer();
    _collect(span, buf);
    return buf.toString();
  }

  static void _collect(InlineSpan span, StringBuffer buf) {
    if (span is TextSpan) {
      if (span.text != null) buf.write(span.text);
      if (span.children != null) {
        for (final child in span.children!) {
          _collect(child, buf);
        }
      }
    } else if (span is WidgetSpan) {
      buf.write('\uFFFC');
    }
  }
}
