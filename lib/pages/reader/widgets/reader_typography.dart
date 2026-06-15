import 'dart:ui' show FontWeight;

/// 阅读器排版 token 单一来源。
///
/// WebView 正文（reader.css）与 Flutter Markdown 栈（nr_markdown_config.dart
/// 服务问 AI 气泡 / 提取结果页）共用同一套「阅读器排版语言」：标题倍率、
/// 字体栈、行高、间距、译文派生色 alpha。数值只住在这里——
/// Flutter 侧直接引用常量；WebView 侧经 [cssVars] 注入 `:root` CSS 变量，
/// reader.css 用 `calc(var(--font-size) * var(--h1-scale))` 等引用，不再持有数字。
///
/// 标题的 margin-top（0.8/0.7/0.6 倍率）是 CSS 独有知识（markdown_widget
/// 用统一 linesMargin，无逐级标题间距概念），留在 reader.css 不收编。
abstract final class ReaderTypography {
  // ── 标题（字号倍率 / 字重 / 行高）──
  static const double h1Scale = 1.6;
  static const FontWeight h1Weight = FontWeight.w700;
  static const double h1Height = 1.3;
  static const double h2Scale = 1.35;
  static const FontWeight h2Weight = FontWeight.w700;
  static const double h2Height = 1.35;
  static const double h3Scale = 1.15;
  static const FontWeight h3Weight = FontWeight.w600;
  static const double h4Scale = 1.05;
  static const FontWeight h4Weight = FontWeight.w600;
  static const FontWeight h5Weight = FontWeight.w600;
  static const FontWeight h6Weight = FontWeight.w500;

  /// h3–h6 共用行高。
  static const double h3to6Height = 1.4;

  // ── 正文 ──
  static const double bodyHeight = 1.7;

  /// 段落 / 块级元素纵向间距 = fontSize × 此倍率。
  static const double blockMarginScale = 0.4;

  // ── 代码 ──
  static const String codeFontFamily = 'Consolas';
  static const List<String> codeFontFallback = [
    'Cascadia Mono',
    'Courier New',
    'Menlo',
    'Noto Sans Mono',
  ];
  static const double codeScale = 0.88;

  // ── 图注 ──
  static const double captionScale = 0.85;

  // ── blockquote ──
  static const double blockquoteSideWidth = 3;
  static const double blockquotePadLeft = 12;

  // ── 译文派生色 alpha（消费端 ReaderPalette.toCssVars）──
  static const double trWeakAlpha = 0.47;
  static const double trHlBgAlpha = 0.14;
  static const double trHlTextAlpha = 0.71;
  static const double trDecoAlpha = 0.55;

  /// 代码字体栈的 CSS font-family 串（含空格的字体名加单引号）。
  static final String codeFontCss =
      '${[codeFontFamily, ...codeFontFallback].map((f) => f.contains(' ') ? "'$f'" : f).join(', ')}, monospace';

  /// 静态排版 token → CSS 变量。
  ///
  /// 与 [ReaderPalette.toCssVars]（主题色，可热更新）、
  /// [ReaderSettingsState.toCssVars]（字号/字体，可热更新）不同，
  /// 这组值随 app 版本固定，只需在 `buildReaderHtml` 的 `:root` 初始注入一次，
  /// 不参与 `buildThemeCssVars` 增量更新。
  static Map<String, String> cssVars() => {
    '--line-height': _n(bodyHeight),
    '--block-margin': _n(blockMarginScale),
    '--h1-scale': _n(h1Scale),
    '--h1-weight': '${h1Weight.value}',
    '--h1-lh': _n(h1Height),
    '--h2-scale': _n(h2Scale),
    '--h2-weight': '${h2Weight.value}',
    '--h2-lh': _n(h2Height),
    '--h3-scale': _n(h3Scale),
    '--h3-weight': '${h3Weight.value}',
    '--h3-lh': _n(h3to6Height),
    '--h4-scale': _n(h4Scale),
    '--h4-weight': '${h4Weight.value}',
    '--h4-lh': _n(h3to6Height),
    '--h5-weight': '${h5Weight.value}',
    '--h5-lh': _n(h3to6Height),
    '--h6-weight': '${h6Weight.value}',
    '--h6-lh': _n(h3to6Height),
    '--code-font': codeFontCss,
    '--code-scale': _n(codeScale),
    '--caption-scale': _n(captionScale),
    '--bq-side': '${_n(blockquoteSideWidth)}px',
    '--bq-pad': '${_n(blockquotePadLeft)}px',
  };

  /// 整数值去掉 Dart double 的 `.0` 尾巴（`3.0` → `3`），其余原样。
  static String _n(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toString();
}
