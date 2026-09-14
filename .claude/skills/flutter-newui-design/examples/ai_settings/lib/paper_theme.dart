import 'package:flutter/material.dart';

// 示例复现项目时长；集成时直接引用项目 animation_constants.dart。
const kAnimFast = Duration(milliseconds: 180);
const kAnim = Duration(milliseconds: 240);
const kAnimCurve = Curves.easeOutCubic;

enum PaperFont { sans, serif }

abstract final class PaperMetrics {
  static const fieldGap = 12.0;
  static const groupGap = 24.0;
  static const cardPadding = 16.0;
  static const controlRadius = 12.0;
  static double target(TargetPlatform platform) => switch (platform) {
    TargetPlatform.android => 48,
    TargetPlatform.iOS => 44,
    _ => 40,
  };
}

@immutable
class PaperColors extends ThemeExtension<PaperColors> {
  const PaperColors({
    required this.selected,
    required this.hover,
    required this.track,
    required this.expertSurface,
    required this.fastSurface,
    required this.imageSurface,
  });
  final Color selected;
  final Color hover;
  final Color track;
  final Color expertSurface;
  final Color fastSurface;
  final Color imageSurface;

  static const light = PaperColors(
    selected: Color(0xFFDFDBD4),
    hover: Color(0xFFEBE8E2),
    track: Color(0xFFF4F2EE),
    expertSurface: Color(0xFFECE9E3),
    fastSurface: Color(0xFFECE9E3),
    imageSurface: Color(0xFFEAE9E5),
  );
  static const dark = PaperColors(
    selected: Color(0xFF454137),
    hover: Color(0xFF39362F),
    track: Color(0xFF211F1B),
    expertSurface: Color(0xFF34312B),
    fastSurface: Color(0xFF34312B),
    imageSurface: Color(0xFF35342F),
  );

  @override
  PaperColors copyWith({
    Color? selected,
    Color? hover,
    Color? track,
    Color? expertSurface,
    Color? fastSurface,
    Color? imageSurface,
  }) => PaperColors(
    selected: selected ?? this.selected,
    hover: hover ?? this.hover,
    track: track ?? this.track,
    expertSurface: expertSurface ?? this.expertSurface,
    fastSurface: fastSurface ?? this.fastSurface,
    imageSurface: imageSurface ?? this.imageSurface,
  );
  @override
  PaperColors lerp(covariant PaperColors? other, double t) => other == null
      ? this
      : PaperColors(
          selected: Color.lerp(selected, other.selected, t)!,
          hover: Color.lerp(hover, other.hover, t)!,
          track: Color.lerp(track, other.track, t)!,
          expertSurface: Color.lerp(expertSurface, other.expertSurface, t)!,
          fastSurface: Color.lerp(fastSurface, other.fastSurface, t)!,
          imageSurface: Color.lerp(imageSurface, other.imageSurface, t)!,
        );
}

ThemeData paperTheme(
  Brightness brightness, {
  PaperFont font = PaperFont.sans,
  TargetPlatform platform = TargetPlatform.windows,
}) {
  final dark = brightness == Brightness.dark;
  final mobile =
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  final target = PaperMetrics.target(platform);
  final family = font == PaperFont.sans ? 'sans-serif' : 'serif';
  // 末两项是本机预览的表情字体桥接：emoji 身份由系统字体渲染，不去线上取字体。
  final fallback = font == PaperFont.sans
      ? const [
          'Segoe UI',
          'Microsoft YaHei',
          'PingFang SC',
          'Noto Sans CJK SC',
          'Segoe UI Emoji',
          'Noto Color Emoji',
        ]
      : const [
          'Times New Roman',
          'Songti SC',
          'SimSun',
          'Segoe UI Emoji',
          'Noto Color Emoji',
        ];
  final colors = dark ? PaperColors.dark : PaperColors.light;
  final cs =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF55524B),
        brightness: brightness,
      ).copyWith(
        primary: Color(dark ? 0xFFD5CEBD : 0xFF55524B),
        onPrimary: Color(dark ? 0xFF25231F : 0xFFFBFAF7),
        primaryContainer: Color(dark ? 0xFF34312B : 0xFFECE9E3),
        onPrimaryContainer: Color(dark ? 0xFFF2F0E9 : 0xFF1F1E1B),
        surface: Color(dark ? 0xFF1C1B19 : 0xFFF2F0EC),
        surfaceContainerLow: Color(dark ? 0xFF252420 : 0xFFF9F8F5),
        surfaceContainerHigh: Color(dark ? 0xFF302E29 : 0xFFF9F8F5),
        surfaceContainerHighest: Color(dark ? 0xFF302E29 : 0xFFEDEAE4),
        onSurface: Color(dark ? 0xFFF2F0E9 : 0xFF1F1E1B),
        onSurfaceVariant: Color(dark ? 0xFFB8B3A8 : 0xFF66635B),
        outline: Color(dark ? 0xFF948D80 : 0xFF8A867E),
        outlineVariant: Color(dark ? 0xFF48453E : 0xFFE3E0DA),
        error: Color(dark ? 0xFFF2A69D : 0xFFA4362F),
      );
  TextStyle primaryText(
    double size, {
    FontWeight weight = FontWeight.w400,
    double height = 1.5,
  }) => TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: size,
    fontWeight: weight,
    height: height,
    color: cs.onSurface,
  );
  TextStyle secondary(double size, {Color? color}) => TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback,
    fontSize: size,
    height: 1.5,
    color: color ?? cs.onSurface,
  );
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
  return ThemeData(
    useMaterial3: true,
    platform: platform,
    colorScheme: cs,
    scaffoldBackgroundColor: cs.surface,
    fontFamily: family,
    fontFamilyFallback: fallback,
    extensions: [colors],
    textTheme: TextTheme(
      headlineLarge: primaryText(32, weight: FontWeight.w600, height: 1.25),
      headlineSmall: primaryText(24, weight: FontWeight.w600, height: 1.25),
      titleLarge: primaryText(20, weight: FontWeight.w600, height: 1.4),
      titleMedium: primaryText(16, weight: FontWeight.w600),
      titleSmall: primaryText(14, weight: FontWeight.w600),
      bodyLarge: primaryText(14),
      bodyMedium: secondary(14, color: cs.onSurfaceVariant),
      bodySmall: secondary(12, color: cs.onSurfaceVariant),
      labelLarge: primaryText(14),
      labelMedium: secondary(14),
      labelSmall: secondary(12),
    ),
    iconTheme: IconThemeData(
      size: 20,
      weight: 350,
      fill: 0,
      color: cs.onSurfaceVariant,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      isDense: true,
      constraints: BoxConstraints(minHeight: mobile ? target : 44),
      fillColor: cs.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: border(cs.outlineVariant),
      enabledBorder: border(cs.outlineVariant),
      focusedBorder: border(cs.primary, 2),
      errorBorder: border(cs.error),
      focusedErrorBorder: border(cs.error, 2),
      hintStyle: primaryText(14).copyWith(color: cs.onSurfaceVariant),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerLow),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant),
          ),
        ),
        elevation: const WidgetStatePropertyAll(3),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: Size(target, target),
        padding: const EdgeInsets.all(8),
        backgroundColor: Colors.transparent,
        side: BorderSide.none,
        foregroundColor: cs.onSurfaceVariant,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: Size(0, mobile ? target : 40),
        visualDensity: VisualDensity.standard,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        foregroundColor: cs.onSurface,
        side: BorderSide(color: cs.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: Size(0, mobile ? target : 40),
        visualDensity: VisualDensity.standard,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: cs.inverseSurface,
      contentTextStyle: secondary(14).copyWith(color: cs.onInverseSurface),
      actionTextColor: cs.onInverseSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
    ),
    tooltipTheme: TooltipThemeData(
      textStyle: secondary(13).copyWith(color: cs.onPrimary),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? cs.primary
            : cs.surfaceContainerHighest,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? cs.onPrimary
            : cs.onSurfaceVariant,
      ),
      trackOutlineColor: WidgetStatePropertyAll(cs.outline),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 1,
      activeTrackColor: cs.outlineVariant,
      inactiveTrackColor: cs.outlineVariant,
      activeTickMarkColor: cs.outline,
      inactiveTickMarkColor: cs.outline,
      thumbColor: cs.primary,
      overlayColor: cs.primary.withValues(alpha: .10),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
      tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 1.2),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 19),
      showValueIndicator: ShowValueIndicator.never,
    ),
  );
}
