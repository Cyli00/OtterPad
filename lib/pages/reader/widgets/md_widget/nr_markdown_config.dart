import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../../../../providers/reader_settings_provider.dart';
import 'nr_custom_text_node.dart';
import 'nr_image_node.dart';
import 'nr_latex_node.dart';

/// 将 [ReaderSettingsState] + [ColorScheme] 映射到 [MarkdownConfig]。
MarkdownConfig buildReaderMarkdownConfig({
  required ReaderSettingsState settings,
  required ColorScheme colorScheme,
}) {
  final baseStyle = TextStyle(
    color: settings.textColor,
    fontSize: settings.fontSize,
    fontFamily: settings.font.fontFamily,
    fontFamilyFallback: settings.font.fontFamilyFallback,
    height: 1.7,
  );

  return MarkdownConfig(configs: [
    PConfig(textStyle: baseStyle),
    H1Config(
      style: baseStyle.copyWith(
        fontSize: settings.fontSize * 1.6,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
    ),
    H2Config(
      style: baseStyle.copyWith(
        fontSize: settings.fontSize * 1.35,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
    ),
    H3Config(
      style: baseStyle.copyWith(
        fontSize: settings.fontSize * 1.15,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
    ),
    H4Config(
      style: baseStyle.copyWith(
        fontSize: settings.fontSize * 1.05,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
    ),
    H5Config(
      style: baseStyle.copyWith(fontWeight: FontWeight.w600, height: 1.4),
    ),
    H6Config(
      style: baseStyle.copyWith(
        fontWeight: FontWeight.w500,
        color: settings.secondaryTextColor,
        height: 1.4,
      ),
    ),
    BlockquoteConfig(
      sideColor: settings.dividerColor,
      textColor: settings.secondaryTextColor,
      sideWith: 3.0,
      padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
    ),
    PreConfig(
      textStyle: TextStyle(
        fontFamily: 'Consolas',
        fontFamilyFallback: const [
          'Cascadia Mono',
          'Courier New',
          'Menlo',
          'Noto Sans Mono',
        ],
        fontSize: settings.fontSize * 0.88,
        color: settings.textColor,
      ),
      decoration: BoxDecoration(
        color: settings.theme == ReaderTheme.dark
            ? const Color(0xFF2D2D3A)
            : const Color(0xFFF5F5F5),
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      padding: const EdgeInsets.all(12),
    ),
    CodeConfig(
      style: TextStyle(
        fontFamily: 'Consolas',
        fontFamilyFallback: const [
          'Cascadia Mono',
          'Courier New',
          'Menlo',
          'Noto Sans Mono',
        ],
        fontSize: settings.fontSize * 0.88,
        color: settings.textColor,
        backgroundColor: settings.theme == ReaderTheme.dark
            ? const Color(0xFF2D2D3A)
            : const Color(0xFFF5F5F5),
      ),
    ),
    LinkConfig(
      style: baseStyle.copyWith(
        color: settings.linkColor,
        decoration: TextDecoration.none,
      ),
    ),
    TableConfig(
      headerStyle: baseStyle.copyWith(fontWeight: FontWeight.w600),
      bodyStyle: baseStyle,
      border: TableBorder.all(color: settings.dividerColor, width: 0.5),
      headPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      bodyPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    HrConfig(height: 1, color: settings.dividerColor),
    NRImgConfig(
      captionStyle: baseStyle.copyWith(
        fontSize: settings.fontSize * 0.85,
        color: settings.secondaryTextColor,
      ),
    ),
  ]);
}

/// 组装 [MarkdownGenerator]，整合 LaTeX / HTML 表格等自定义节点。
MarkdownGenerator buildReaderMarkdownGenerator({
  required ReaderSettingsState settings,
  Widget Function(InlineSpan span)? searchRichTextBuilder,
}) {
  return MarkdownGenerator(
    generators: [nrLatexGenerator],
    inlineSyntaxList: [NRLatexInlineSyntax()],
    blockSyntaxList: [NRLatexBlockSyntax()],
    textGenerator: (node, config, visitor) =>
        NRCustomTextNode(node.textContent, config, visitor),
    richTextBuilder: searchRichTextBuilder ?? (span) => Text.rich(span),
    linesMargin: EdgeInsets.symmetric(vertical: settings.fontSize * 0.4),
  );
}
