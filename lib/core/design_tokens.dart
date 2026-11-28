import 'package:flutter/material.dart';

import 'app_fonts.dart';

// ── Folio 设计语言 ──
//
// OtterPad 的界面是一张「纸」：暖白纸面 + 墨色文字，层级靠细线和字体，
// 不靠色块和柔光阴影。只有真正浮起的东西（菜单、浮层、弹窗、反馈条）
// 才有阴影。完整规范见 docs/design-system.md。

/// 圆角：大而连续。容器与控件用连续曲率（超椭圆）的形状，
/// 让圆角成为界面的主要识别特征。
abstract final class AppRadius {
  /// 细进度条、拖拽条。
  static const double hairline = 3;

  /// 封面、Tooltip、徽标、复选框。
  static const double xs = 8;

  /// 控件：按钮、输入框、Chip、图标盒、菜单项。
  static const double sm = 14;

  /// 容器：卡片、设置分组、菜单、反馈条。
  static const double md = 20;

  /// 大浮层：弹窗、底部面板。
  static const double lg = 28;

  /// 胶囊：悬浮栏、发送按钮、快捷提问。
  static const double pill = 999;

  static BorderRadius get xsAll => BorderRadius.circular(xs);
  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);

  static const BorderRadius sheetTop = BorderRadius.vertical(
    top: Radius.circular(lg),
  );
}

/// 连续曲率形状：与 [AppRadius] 同值，但用超椭圆代替圆弧，转角更柔和饱满。
abstract final class AppShape {
  static OutlinedBorder of(
    double radius, {
    BorderSide side = BorderSide.none,
  }) => RoundedSuperellipseBorder(
    borderRadius: BorderRadius.circular(radius),
    side: side,
  );

  static OutlinedBorder sm([BorderSide side = BorderSide.none]) =>
      of(AppRadius.sm, side: side);
  static OutlinedBorder md([BorderSide side = BorderSide.none]) =>
      of(AppRadius.md, side: side);
  static OutlinedBorder lg([BorderSide side = BorderSide.none]) =>
      of(AppRadius.lg, side: side);
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

/// 主题风格：决定中性色（纸面、文字、细线）的色相与浓淡。
///
/// 主题色（或系统动态色）始终只决定强调色；风格决定整页「纸」的气质。
enum ThemeStyle {
  /// 纸墨：暖白纸 + 墨色，固定中性色。
  paper,

  /// 随色：中性色跟着主题色走，容器保留饱和色块。
  vivid,

  /// 雾凇：冷调蓝灰。
  mist,

  /// 苔原：低饱和灰绿。
  moss,

  /// 暮色：带玫瑰紫调的灰。
  dusk,

  /// 石墨：几乎无彩的灰，深色下是纯黑。
  graphite;

  static ThemeStyle parse(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => paper);
}

/// 由风格 + 主题色生成配色。
///
/// 强调色只用于：选中、焦点、主操作、进度。其余由风格的中性色承担。
abstract final class FolioPalette {
  static ColorScheme scheme(
    Color seed,
    Brightness brightness, [
    ThemeStyle style = ThemeStyle.paper,
  ]) {
    final base = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: style == ThemeStyle.vivid
          ? DynamicSchemeVariant.vibrant
          : DynamicSchemeVariant.fidelity,
    );
    final light = brightness == Brightness.light;
    return switch (style) {
      ThemeStyle.paper => _washContainers(
        light ? _paper(base) : _ink(base),
        light ? 31 : 51,
      ),
      ThemeStyle.vivid => _tinted(
        base,
        HSLColor.fromColor(seed).hue,
        light ? .34 : .24,
        brightness,
      ),
      ThemeStyle.mist => _washContainers(
        _tinted(base, 212, light ? .48 : .26, brightness),
        light ? 38 : 56,
      ),
      ThemeStyle.moss => _washContainers(
        _tinted(base, 96, light ? .30 : .17, brightness),
        light ? 38 : 56,
      ),
      ThemeStyle.dusk => _washContainers(
        _tinted(base, 318, light ? .36 : .22, brightness),
        light ? 38 : 56,
      ),
      ThemeStyle.graphite => _washContainers(
        _tinted(base, 220, light ? .05 : .04, brightness, oled: true),
        light ? 34 : 60,
      ),
    };
  }

  /// `*Container` 角色不再是饱和色块，而是强调色在纸面上的一层淡彩，
  /// 文字用强调色本身。散落在各处的 `primaryContainer` 图标盒、标签
  /// 因此自动退成「淡彩」的分量。「随色」风格保留饱和色块。
  static ColorScheme _washContainers(ColorScheme cs, int alpha) {
    final paper = cs.surfaceContainerLowest;
    Color wash(Color c) => Color.alphaBlend(c.withAlpha(alpha), paper);
    return cs.copyWith(
      primaryContainer: wash(cs.primary),
      onPrimaryContainer: cs.primary,
      secondaryContainer: wash(cs.secondary),
      onSecondaryContainer: cs.secondary,
      tertiaryContainer: wash(cs.tertiary),
      onTertiaryContainer: cs.tertiary,
    );
  }

  /// 按色相 [hue] 与饱和度 [sat] 生成一整套中性色阶。
  static ColorScheme _tinted(
    ColorScheme base,
    double hue,
    double sat,
    Brightness brightness, {
    bool oled = false,
  }) {
    Color t(double l, [double satScale = 1]) =>
        HSLColor.fromAHSL(1, hue, (sat * satScale).clamp(0, 1), l).toColor();
    if (brightness == Brightness.light) {
      return base.copyWith(
        surface: t(.962),
        onSurface: t(.12, .5),
        onSurfaceVariant: t(.37, .45),
        surfaceDim: t(.88),
        surfaceBright: t(.98),
        surfaceContainerLowest: t(.99),
        surfaceContainerLow: t(.944),
        surfaceContainer: t(.925),
        surfaceContainerHigh: t(.905),
        surfaceContainerHighest: t(.885),
        outline: t(.56, .4),
        outlineVariant: t(.85, .7),
        inverseSurface: t(.15, .5),
        onInverseSurface: t(.95),
        shadow: t(.1, .5),
        scrim: t(.1, .5),
      );
    }
    return base.copyWith(
      surface: oled ? Colors.black : t(.085),
      onSurface: t(.92, .4),
      onSurfaceVariant: t(.72, .35),
      surfaceDim: oled ? Colors.black : t(.085),
      surfaceBright: t(.24),
      // 纯黑底上「一张纸」要比底色亮一点
      surfaceContainerLowest: oled ? t(.07) : t(.055),
      surfaceContainerLow: oled ? t(.09) : t(.105),
      surfaceContainer: oled ? t(.11) : t(.125),
      surfaceContainerHigh: oled ? t(.14) : t(.155),
      surfaceContainerHighest: oled ? t(.18) : t(.19),
      outline: t(.52, .4),
      outlineVariant: t(.24, .7),
      inverseSurface: t(.92, .4),
      onInverseSurface: t(.15),
      shadow: Colors.black,
      scrim: Colors.black,
    );
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
