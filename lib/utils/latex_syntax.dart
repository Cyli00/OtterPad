import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

/// 自定义行内 LaTeX 语法
///
/// 修复 flutter_markdown_plus_latex 的 LatexInlineSyntax 存在的问题：
/// 原版正则尾部有 `(?=[\s?!.,:？！。，：]|$)` lookahead，
/// 要求 `$` 后必须跟空白/标点/行尾，导致 `${}^{2}$UCL` 等模式无法匹配。
class NRLatexInlineSyntax extends md.InlineSyntax {
  NRLatexInlineSyntax() : super(_pattern);

  // 只处理 $...$ 行内公式（$$...$$ 块级由 LatexBlockSyntax 处理）
  // 移除了尾部 lookahead，允许 $ 后紧跟任意字符
  static const _pattern = r'\$([^\$\n]+?)\$';

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final equation = match.group(1)!.trim();
    if (equation.isEmpty) return false;

    final element = md.Element.text('latex', equation);
    element.attributes['MathStyle'] = 'text';
    parser.addNode(element);
    return true;
  }
}

/// 自定义 LaTeX 元素构建器
///
/// 修复原版 LatexElementBuilder 的两个问题：
/// 1. 行内公式被 SingleChildScrollView 包裹，导致后续文字换行
/// 2. 解析失败时无 fallback，显示红色错误 widget
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
    if (text.isEmpty) return const SizedBox();

    final isDisplay = element.attributes['MathStyle'] == 'display';

    final mathWidget = Math.tex(
      text,
      textStyle: textStyle,
      mathStyle: isDisplay ? MathStyle.display : MathStyle.text,
      textScaleFactor: textScaleFactor,
      onErrorFallback: (e) => Text(
        '\$$text\$',
        style: textStyle?.copyWith(
              fontStyle: FontStyle.italic,
              fontSize: (textStyle?.fontSize ?? 14) * 0.9,
            ) ??
            const TextStyle(fontStyle: FontStyle.italic),
      ),
    );

    // 块级公式允许水平滚动；行内公式直接嵌入文本流
    if (isDisplay) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.antiAlias,
        child: mathWidget,
      );
    }

    return mathWidget;
  }
}
