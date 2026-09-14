import 'package:flutter/material.dart';

// 示例复现项目时长；集成时直接引用项目 animation_constants.dart。
const kAnimFast = Duration(milliseconds: 180);
const kAnim = Duration(milliseconds: 240);
const kAnimCurve = Curves.easeOutCubic;

@immutable
class PaperColors extends ThemeExtension<PaperColors> {
  const PaperColors({
    required this.selected,
    required this.hover,
    required this.track,
  });
  final Color selected;
  final Color hover;
  final Color track;

  static const light = PaperColors(
    selected: Color(0xFFDFDBD4),
    hover: Color(0xFFEBE8E2),
    track: Color(0xFFF4F2EE),
  );
  static const dark = PaperColors(
    selected: Color(0xFF454137),
    hover: Color(0xFF39362F),
    track: Color(0xFF211F1B),
  );

  @override
  PaperColors copyWith({Color? selected, Color? hover, Color? track}) =>
      PaperColors(
        selected: selected ?? this.selected,
        hover: hover ?? this.hover,
        track: track ?? this.track,
      );
  @override
  PaperColors lerp(covariant PaperColors? other, double t) => other == null
      ? this
      : PaperColors(
          selected: Color.lerp(selected, other.selected, t)!,
          hover: Color.lerp(hover, other.hover, t)!,
          track: Color.lerp(track, other.track, t)!,
        );
}

ThemeData paperTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
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
  TextStyle serif(
    double size, {
    FontWeight weight = FontWeight.w400,
    double height = 1.5,
  }) => TextStyle(
    fontFamily: 'serif',
    fontFamilyFallback: const ['Times New Roman', 'Songti SC', 'SimSun'],
    fontSize: size,
    fontWeight: weight,
    height: height,
    color: cs.onSurface,
  );
  TextStyle secondary(double size, {Color? color}) => TextStyle(
    fontFamily: 'serif',
    fontFamilyFallback: const ['Times New Roman', 'Songti SC', 'SimSun'],
    fontSize: size,
    height: 1.6,
    color: color ?? cs.onSurface,
  );
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: cs.surface,
    fontFamily: 'serif',
    fontFamilyFallback: const ['Times New Roman', 'Songti SC', 'SimSun'],
    extensions: [colors],
    textTheme: TextTheme(
      headlineLarge: serif(44, weight: FontWeight.w700, height: 1.3),
      headlineSmall: serif(32, weight: FontWeight.w700, height: 1.3),
      titleLarge: serif(26, weight: FontWeight.w700, height: 1.35),
      titleMedium: serif(20, weight: FontWeight.w600),
      titleSmall: serif(18, weight: FontWeight.w600),
      bodyLarge: serif(18),
      bodyMedium: secondary(14, color: cs.onSurfaceVariant),
      bodySmall: secondary(12, color: cs.onSurfaceVariant),
      labelLarge: serif(16),
      labelMedium: secondary(14),
      labelSmall: secondary(12),
    ),
    iconTheme: IconThemeData(
      size: 21,
      weight: 350,
      fill: 0,
      color: cs.onSurfaceVariant,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerLow,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: border(cs.outlineVariant),
      enabledBorder: border(cs.outlineVariant),
      focusedBorder: border(cs.primary, 2),
      errorBorder: border(cs.error),
      focusedErrorBorder: border(cs.error, 2),
      hintStyle: serif(16).copyWith(color: cs.onSurfaceVariant),
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
        minimumSize: const Size(48, 48),
        foregroundColor: cs.onSurfaceVariant,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        visualDensity: VisualDensity.standard,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        foregroundColor: cs.onSurface,
        side: BorderSide(color: cs.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        visualDensity: VisualDensity.standard,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
      tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 1.2),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 19),
      showValueIndicator: ShowValueIndicator.never,
    ),
  );
}
