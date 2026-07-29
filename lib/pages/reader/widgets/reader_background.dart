import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/reader_settings_provider.dart';
import 'reader_typography.dart';

/// [Color] → CSS `rgba(...)` 字符串。
///
/// 公开给 [webview_reader_html.dart] 等所有需要把 palette 颜色塞进 CSS
/// 的调用方共用，避免重复实现。
String cssColor(Color c) {
  final r = (c.r * 255).round();
  final g = (c.g * 255).round();
  final b = (c.b * 255).round();
  return 'rgba($r,$g,$b,${c.a.toStringAsFixed(2)})';
}

/// [Color] + 指定 alpha → CSS `rgba(...)` 字符串。
String _cssColorWithAlpha(Color c, double a) {
  final r = (c.r * 255).round();
  final g = (c.g * 255).round();
  final b = (c.b * 255).round();
  return 'rgba($r,$g,$b,${a.toStringAsFixed(2)})';
}

/// 阅读器主题的 6 色调色板——所有 `resolveReader*` 入口唯一出处。
///
/// 以 record 形态一次性派发，让 `nr_markdown_config.dart` 等调用方
/// **一次 switch** 拿到整套颜色，省去 5 次重复分派；视觉上也把"一个主题
/// 的颜色组合"表达为一个值，新增主题只改一个 arm。
class ReaderPalette {
  final Color background;
  final Color text;
  final Color secondaryText;
  final Color link;
  final Color divider;
  final Color codeBlock;

  const ReaderPalette({
    required this.background,
    required this.text,
    required this.secondaryText,
    required this.link,
    required this.divider,
    required this.codeBlock,
  });

  /// palette → 所有相关 CSS 变量。
  ///
  /// 包含 6 个原始色 + 4 个翻译派生色（`--tr-*`，从 text/link 算 alpha 变体）。
  /// **唯一映射出处**——`buildReaderHtml` 的 `:root` 初始注入和 `buildThemeCssVars`
  /// 增量更新都基于此 map 生成，新增字段只改一处。
  Map<String, String> toCssVars() => {
    '--bg': cssColor(background),
    '--text': cssColor(text),
    '--secondary': cssColor(secondaryText),
    '--link': cssColor(link),
    '--divider': cssColor(divider),
    '--code-bg': cssColor(codeBlock),
    '--tr-weak': _cssColorWithAlpha(text, ReaderTypography.trWeakAlpha),
    '--tr-hl-bg': _cssColorWithAlpha(link, ReaderTypography.trHlBgAlpha),
    '--tr-hl-text': _cssColorWithAlpha(link, ReaderTypography.trHlTextAlpha),
    '--tr-deco': _cssColorWithAlpha(link, ReaderTypography.trDecoAlpha),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReaderPalette &&
          background == other.background &&
          text == other.text &&
          secondaryText == other.secondaryText &&
          link == other.link &&
          divider == other.divider &&
          codeBlock == other.codeBlock;

  @override
  int get hashCode =>
      Object.hash(background, text, secondaryText, link, divider, codeBlock);
}

/// 根据 [readerTheme] 生成阅读器页面的局部 [ThemeData]。
///
/// 以 parent 的 primary 为 seed 生成对应亮度的基础 [ColorScheme]，
/// 再用 [ReaderPalette] 覆盖 surface 及文字相关字段，使 Flutter 侧
/// 工具栏/底栏/sheet 的前景色与 WebView 内容保持一致。
/// **强调色（primary 等）继续来自 seed 派生**，保证外观面板里
/// 选的主题色（橙/紫/蓝…）在所有背景下保持一致。
ThemeData buildReaderThemeData(ThemeData parent, ReaderTheme readerTheme) {
  final brightness = readerTheme.brightness;
  final baseCs = parent.colorScheme.brightness == brightness
      ? parent.colorScheme
      : ColorScheme.fromSeed(
          seedColor: parent.colorScheme.primary,
          brightness: brightness,
        );
  final palette = resolveReaderPalette(readerTheme, baseCs);
  final localCs = baseCs.copyWith(
    surface: palette.background,
    onSurface: palette.text,
    onSurfaceVariant: palette.secondaryText,
    outlineVariant: palette.divider,
  );
  return ThemeData(
    colorScheme: localCs,
    useMaterial3: true,
    textTheme: parent.textTheme.apply(
      bodyColor: palette.text,
      displayColor: palette.text,
    ),
  );
}

/// 包裹子组件，使其使用阅读器背景亮度对应的局部主题。
///
/// 用于 [showModalBottomSheet] 等走 root navigator 的浮层，
/// 使它们跟随阅读器亮度而非全局 [ThemeMode]。
class ReaderLocalTheme extends ConsumerWidget {
  final Widget child;
  const ReaderLocalTheme({required this.child, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readerTheme = ref.watch(
      readerSettingsProvider.select((s) => s.theme),
    );
    return Theme(
      data: buildReaderThemeData(Theme.of(context), readerTheme),
      child: child,
    );
  }
}

/// 按 [theme] 解析 [ReaderPalette]。
///
/// [ReaderTheme.themed] 借用传入的 [cs] 相应字段——阅读器页面传入的是
/// 局部 light [ColorScheme]，所以始终解析为浅色；其他主题用硬编码色值。
ReaderPalette resolveReaderPalette(ReaderTheme theme, ColorScheme cs) {
  return switch (theme) {
    ReaderTheme.themed => ReaderPalette(
      background: cs.surface,
      text: cs.onSurface,
      secondaryText: cs.outline,
      link: cs.primary,
      divider: cs.outlineVariant,
      codeBlock: cs.surfaceContainerHigh,
    ),
    ReaderTheme.sepia => const ReaderPalette(
      background: Color(0xFFF5F0E8),
      text: Color(0xFF3B3530),
      secondaryText: Color(0xFF5D5549),
      link: Color(0xFF8B6914),
      divider: Color(0xFFD5CEBC),
      codeBlock: Color(0xFFEDE5D5),
    ),
    ReaderTheme.green => const ReaderPalette(
      background: Color(0xFFC7EDCC),
      text: Color(0xFF2B3A28),
      secondaryText: Color(0xFF556B4C),
      link: Color(0xFF4F6B3A),
      divider: Color(0xFFA5D1AD),
      codeBlock: Color(0xFFB8DFBE),
    ),
    ReaderTheme.night => const ReaderPalette(
      background: Color(0xFF1C1B1F),
      text: Color(0xFFE6E1E5),
      secondaryText: Color(0xFFCAC4D0),
      link: Color(0xFF93B4FF),
      divider: Color(0xFF49454F),
      codeBlock: Color(0xFF2B2930),
    ),
    ReaderTheme.dark => const ReaderPalette(
      background: Color(0xFF0D0D0D),
      text: Color(0xFFE6E1E5),
      secondaryText: Color(0xFFB0ABB5),
      link: Color(0xFF93B4FF),
      divider: Color(0xFF2A2A2A),
      codeBlock: Color(0xFF1A1A1A),
    ),
  };
}
