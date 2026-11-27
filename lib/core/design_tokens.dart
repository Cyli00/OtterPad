import 'package:flutter/material.dart';

import 'app_fonts.dart';

// ── Folio 设计语言 ──
//
// OtterPad 的界面是一张「纸」：暖白纸面 + 墨色文字，层级靠细线和字体，
// 不靠色块和柔光阴影。只有真正浮起的东西（菜单、浮层、弹窗、反馈条）
// 才有阴影。完整规范见 docs/design-system.md。

/// 圆角：收紧。纸张、印刷品没有 28 的大圆角。
abstract final class AppRadius {
  /// 1px 级元素、细进度条、拖拽条。
  static const double hairline = 2;

  /// 胶囊内的小元素、Tooltip、徽标。
  static const double xs = 4;

  /// 控件：按钮、输入框、Chip、图标盒、菜单项。
  static const double sm = 6;

  /// 容器：卡片、设置分组、菜单、反馈条。
  static const double md = 10;

  /// 大浮层：弹窗、底部面板。
  static const double lg = 14;

  static BorderRadius get xsAll => BorderRadius.circular(xs);
  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);

  static const BorderRadius sheetTop = BorderRadius.vertical(
    top: Radius.circular(lg),
  );
}

/// 间距：4 的倍数。页面左右边距桌面 32、移动端 20。
abstract final class AppSpace {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x12 = 48;

  static double pageGutter(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 600 ? x5 : x8;
}

/// 线：细线是 Folio 的主要分隔手段。
abstract final class AppStroke {
  static const double hairline = 1;
  static const double emphasis = 1.5;
  static const double focus = 2;

  /// 容器、卡片、行之间的细线。
  static Color rule(ColorScheme cs) => cs.outlineVariant;

  /// 悬停 / 按下时加深的细线。
  static Color ruleStrong(ColorScheme cs) =>
      Color.alphaBlend(cs.onSurface.withAlpha(40), cs.outlineVariant);

  static BorderSide side(ColorScheme cs) =>
      BorderSide(color: rule(cs), width: hairline);
}

/// 纸与墨：中性色固定为暖纸色系，用户选的主题色只作为唯一强调色。
///
/// 强调色只用于：选中、焦点、主操作、进度。其余一律中性。
abstract final class FolioPalette {
  static ColorScheme scheme(Color seed, Brightness brightness) {
    final base = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    return brightness == Brightness.light ? _paper(base) : _ink(base);
  }

  static ColorScheme _paper(ColorScheme base) => base.copyWith(
    surface: const Color(0xFFF6F3EC),
    onSurface: const Color(0xFF1C1A17),
    onSurfaceVariant: const Color(0xFF5F594F),
    surfaceDim: const Color(0xFFE4DED3),
    surfaceBright: const Color(0xFFFBF9F5),
    surfaceContainerLowest: const Color(0xFFFDFCF9),
    surfaceContainerLow: const Color(0xFFF1EDE5),
    surfaceContainer: const Color(0xFFECE7DE),
    surfaceContainerHigh: const Color(0xFFE6E1D6),
    surfaceContainerHighest: const Color(0xFFDFD9CD),
    outline: const Color(0xFF8D867A),
    outlineVariant: const Color(0xFFDCD5C8),
    inverseSurface: const Color(0xFF22201C),
    onInverseSurface: const Color(0xFFF3EFE7),
    shadow: const Color(0xFF1C1A17),
    scrim: const Color(0xFF1C1A17),
  );

  static ColorScheme _ink(ColorScheme base) => base.copyWith(
    surface: const Color(0xFF141311),
    onSurface: const Color(0xFFEDE7DC),
    onSurfaceVariant: const Color(0xFFADA597),
    surfaceDim: const Color(0xFF141311),
    surfaceBright: const Color(0xFF3A3732),
    surfaceContainerLowest: const Color(0xFF0E0D0C),
    surfaceContainerLow: const Color(0xFF1A1916),
    surfaceContainer: const Color(0xFF1F1D1A),
    surfaceContainerHigh: const Color(0xFF272522),
    surfaceContainerHighest: const Color(0xFF302D29),
    outline: const Color(0xFF7E776C),
    outlineVariant: const Color(0xFF37332E),
    inverseSurface: const Color(0xFFEDE7DC),
    onInverseSurface: const Color(0xFF22201C),
    shadow: Colors.black,
    scrim: Colors.black,
  );
}

/// 字体分工：衬线管「内容与标题」，无衬线管「界面」。
abstract final class AppType {
  /// 页面刊头、文献标题等编辑型文字用的衬线字体。
  static String? displayFamily(TargetPlatform platform) => switch (platform) {
    TargetPlatform.windows ||
    TargetPlatform.macOS ||
    TargetPlatform.iOS => 'Georgia',
    // Linux 的 fontconfig 不认 Flutter 传入的 `serif` 别名，直接点名
    TargetPlatform.linux => 'Noto Serif',
    _ => 'serif',
  };

  static List<String> displayFallbacks(TargetPlatform platform) => [
    'Noto Serif CJK SC',
    'Noto Serif CJK TC',
    'Source Han Serif SC',
    'Songti SC',
    'Songti TC',
    'SimSun',
    'Noto Serif',
    'DejaVu Serif',
    'Liberation Serif',
    if (AppFonts.family(AppFonts.sans, platform) case final String name) name,
  ];

  /// 在 [base] 上把展示级与标题级换成衬线，并收紧字距与字重。
  static TextTheme editorial(TextTheme base, TargetPlatform platform) {
    final family = displayFamily(platform);
    final fallbacks = displayFallbacks(platform);
    TextStyle? serif(TextStyle? s, {double? size, double? tracking}) =>
        s?.copyWith(
          fontFamily: family,
          fontFamilyFallback: fallbacks,
          fontSize: size,
          fontWeight: FontWeight.w500,
          letterSpacing: tracking,
          height: 1.18,
        );
    return base.copyWith(
      displayLarge: serif(base.displayLarge, tracking: -1.2),
      displayMedium: serif(base.displayMedium, tracking: -0.9),
      displaySmall: serif(base.displaySmall, size: 34, tracking: -0.6),
      headlineLarge: serif(base.headlineLarge, size: 30, tracking: -0.5),
      headlineMedium: serif(base.headlineMedium, size: 26, tracking: -0.4),
      headlineSmall: serif(base.headlineSmall, size: 22, tracking: -0.2),
      titleLarge: serif(base.titleLarge, size: 20, tracking: -0.1),
      titleMedium: base.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      bodyLarge: base.bodyLarge?.copyWith(height: 1.5, letterSpacing: 0.1),
      bodyMedium: base.bodyMedium?.copyWith(height: 1.45, letterSpacing: 0.1),
      bodySmall: base.bodySmall?.copyWith(height: 1.4, letterSpacing: 0.2),
      labelLarge: base.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 1.1,
      ),
    );
  }

  /// 栏目眉题：小号、加宽字距、中性色。替代原来「primary 色加粗标题」。
  static TextStyle eyebrow(BuildContext context) {
    final theme = Theme.of(context);
    return theme.textTheme.labelSmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
  }

  /// 页面刊头：每页唯一的视觉重心。
  static TextStyle masthead(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 600;
    return (compact
            ? theme.textTheme.headlineLarge!
            : theme.textTheme.displaySmall!)
        .copyWith(color: theme.colorScheme.onSurface);
  }

  /// 数字：等宽数位，计数与百分比不跳动。
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];
}

/// 栏目眉题文本：英文自动转大写，中文不变。
String eyebrowText(String text) => text.toUpperCase();
