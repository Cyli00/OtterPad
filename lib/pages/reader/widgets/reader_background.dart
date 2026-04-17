import 'package:flutter/material.dart';

import '../../../providers/reader_settings_provider.dart';

/// 解析 [ReaderTheme] 到具体背景色。
///
/// [ReaderTheme.themed] 使用当前应用的 [ColorScheme.surface]，
/// 与工具栏背景一致（跟随应用主题）。其他值直接返回硬编码色。
/// widgets 在渲染阅读区时统一走此函数，避免 state getter 依赖 `BuildContext`。
Color resolveReaderBackground(ReaderTheme theme, ColorScheme cs) {
  return switch (theme) {
    ReaderTheme.themed => cs.surface,
    ReaderTheme.sepia => const Color(0xFFF5F0E8),
    ReaderTheme.night => const Color(0xFF1C1B1F),
    ReaderTheme.dark => const Color(0xFF0D0D0D),
  };
}

/// 解析正文文字色，配合 [resolveReaderBackground] 使用。
Color resolveReaderTextColor(ReaderTheme theme, ColorScheme cs) {
  return switch (theme) {
    ReaderTheme.themed => cs.onSurface,
    ReaderTheme.sepia => const Color(0xFF3B3530),
    ReaderTheme.night => const Color(0xFFE6E1E5),
    ReaderTheme.dark => const Color(0xFFE6E1E5),
  };
}

/// 次要文字色（作者、注释、blockquote 等）。
Color resolveReaderSecondaryTextColor(ReaderTheme theme, ColorScheme cs) {
  return switch (theme) {
    ReaderTheme.themed => cs.outline,
    ReaderTheme.sepia => const Color(0xFF5D5549),
    ReaderTheme.night => const Color(0xFFCAC4D0),
    ReaderTheme.dark => const Color(0xFFB0ABB5),
  };
}

/// 链接颜色。
Color resolveReaderLinkColor(ReaderTheme theme, ColorScheme cs) {
  return switch (theme) {
    ReaderTheme.themed => cs.primary,
    ReaderTheme.sepia => const Color(0xFF8B6914),
    ReaderTheme.night => const Color(0xFF93B4FF),
    ReaderTheme.dark => const Color(0xFF93B4FF),
  };
}

/// 分割线颜色。
Color resolveReaderDividerColor(ReaderTheme theme, ColorScheme cs) {
  return switch (theme) {
    ReaderTheme.themed => cs.outlineVariant,
    ReaderTheme.sepia => const Color(0xFFD5CEBC),
    ReaderTheme.night => const Color(0xFF49454F),
    ReaderTheme.dark => const Color(0xFF2A2A2A),
  };
}

/// 代码块 / pre 块背景色。
Color resolveReaderCodeBlockColor(ReaderTheme theme, ColorScheme cs) {
  return switch (theme) {
    ReaderTheme.themed => cs.surfaceContainerHigh,
    ReaderTheme.sepia => const Color(0xFFEDE5D5),
    ReaderTheme.night => const Color(0xFF2B2930),
    ReaderTheme.dark => const Color(0xFF1A1A1A),
  };
}
