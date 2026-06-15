import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:markdown_widget/markdown_widget.dart';

import '../../../../providers/reader_settings_provider.dart';
import '../reader_background.dart';
import '../reader_typography.dart';
import 'nr_custom_text_node.dart';
import 'nr_image_node.dart';
import 'nr_latex_node.dart';
import 'nr_translated_node.dart';

/// 将 [ReaderSettingsState] + [ColorScheme] 映射到 [MarkdownConfig]。
///
/// 所有颜色统一走 `reader_background.dart` 的 resolver 函数，
/// 确保 [ReaderTheme.themed] 能正确拿到 [ColorScheme] 派生色。
MarkdownConfig buildReaderMarkdownConfig({
  required ReaderSettingsState settings,
  required ColorScheme colorScheme,
  String? highlightQuery,
  void Function(String url)? onImageTap,
  ValueListenable<String?>? selectedTextListenable,
}) {
  final palette = resolveReaderPalette(settings.theme, colorScheme);
  final textColor = palette.text;
  final secondaryColor = palette.secondaryText;
  final linkColor = palette.link;
  final dividerColor = palette.divider;
  final codeBlockBg = palette.codeBlock;

  final baseStyle = TextStyle(
    color: textColor,
    fontSize: settings.fontSize,
    fontFamily: settings.font.fontFamily,
    fontFamilyFallback: settings.font.fontFamilyFallback,
    height: ReaderTypography.bodyHeight,
  );

  return MarkdownConfig(
    configs: [
      PConfig(textStyle: baseStyle),
      H1Config(
        style: baseStyle.copyWith(
          fontSize: settings.fontSize * ReaderTypography.h1Scale,
          fontWeight: ReaderTypography.h1Weight,
          height: ReaderTypography.h1Height,
        ),
      ),
      H2Config(
        style: baseStyle.copyWith(
          fontSize: settings.fontSize * ReaderTypography.h2Scale,
          fontWeight: ReaderTypography.h2Weight,
          height: ReaderTypography.h2Height,
        ),
      ),
      H3Config(
        style: baseStyle.copyWith(
          fontSize: settings.fontSize * ReaderTypography.h3Scale,
          fontWeight: ReaderTypography.h3Weight,
          height: ReaderTypography.h3to6Height,
        ),
      ),
      H4Config(
        style: baseStyle.copyWith(
          fontSize: settings.fontSize * ReaderTypography.h4Scale,
          fontWeight: ReaderTypography.h4Weight,
          height: ReaderTypography.h3to6Height,
        ),
      ),
      H5Config(
        style: baseStyle.copyWith(
          fontWeight: ReaderTypography.h5Weight,
          height: ReaderTypography.h3to6Height,
        ),
      ),
      H6Config(
        style: baseStyle.copyWith(
          fontWeight: ReaderTypography.h6Weight,
          color: secondaryColor,
          height: ReaderTypography.h3to6Height,
        ),
      ),
      BlockquoteConfig(
        sideColor: dividerColor,
        textColor: secondaryColor,
        sideWith: ReaderTypography.blockquoteSideWidth,
        padding: const EdgeInsets.only(
          left: ReaderTypography.blockquotePadLeft,
          top: 4,
          bottom: 4,
        ),
      ),
      PreConfig(
        textStyle: TextStyle(
          fontFamily: ReaderTypography.codeFontFamily,
          fontFamilyFallback: ReaderTypography.codeFontFallback,
          fontSize: settings.fontSize * ReaderTypography.codeScale,
          color: textColor,
        ),
        decoration: BoxDecoration(
          color: codeBlockBg,
          borderRadius: const BorderRadius.all(Radius.circular(8)),
        ),
        padding: const EdgeInsets.all(12),
      ),
      CodeConfig(
        style: TextStyle(
          fontFamily: ReaderTypography.codeFontFamily,
          fontFamilyFallback: ReaderTypography.codeFontFallback,
          fontSize: settings.fontSize * ReaderTypography.codeScale,
          color: textColor,
          backgroundColor: codeBlockBg,
        ),
      ),
      LinkConfig(
        style: baseStyle.copyWith(
          color: linkColor,
          decoration: TextDecoration.none,
        ),
      ),
      TableConfig(
        headerStyle: baseStyle.copyWith(fontWeight: FontWeight.w600),
        bodyStyle: baseStyle,
        border: TableBorder.all(color: dividerColor, width: 0.5),
        headPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        bodyPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      HrConfig(height: 1, color: dividerColor),
      NRImgConfig(
        captionStyle: baseStyle.copyWith(
          fontSize: settings.fontSize * ReaderTypography.captionScale,
          color: secondaryColor,
        ),
        highlightQuery: highlightQuery,
        highlightBg: colorScheme.primaryContainer,
        highlightFg: colorScheme.onPrimaryContainer,
        onTap: onImageTap,
        selectedTextListenable: selectedTextListenable,
      ),
    ],
  );
}

/// 组装 [MarkdownGenerator]，整合 LaTeX / 主题色译文 / HTML 表格等自定义节点。
///
/// [translatedColor] 非空时注册主题色译文节点；为空时不注册，`[[tr]]...[[/tr]]`
/// 将作为普通文本渲染（相当于不可见的 noop，不会破坏阅读）。
MarkdownGenerator buildReaderMarkdownGenerator({
  required ReaderSettingsState settings,
  Widget Function(InlineSpan span)? searchRichTextBuilder,
  Color? translatedColor,
  String? translatedStyleId,
  ValueListenable<String?>? selectedTextListenable,
}) {
  final generators = <SpanNodeGeneratorWithTag>[
    nrLatexGenerator(selectedTextListenable: selectedTextListenable),
  ];
  final inlineSyntaxes = <md.InlineSyntax>[NRLatexInlineSyntax()];

  if (translatedColor != null) {
    generators.add(
      nrTranslatedGenerator(
        color: translatedColor,
        styleId: translatedStyleId ?? 'themed',
        selectedTextListenable: selectedTextListenable,
      ),
    );
    inlineSyntaxes.add(NRTranslatedInlineSyntax());
  }

  return MarkdownGenerator(
    generators: generators,
    inlineSyntaxList: inlineSyntaxes,
    blockSyntaxList: [NRLatexBlockSyntax()],
    textGenerator: (node, config, visitor) =>
        NRCustomTextNode(node.textContent, config, visitor),
    richTextBuilder: searchRichTextBuilder ?? (span) => Text.rich(span),
    linesMargin: EdgeInsets.symmetric(
      vertical: settings.fontSize * ReaderTypography.blockMarginScale,
    ),
  );
}
