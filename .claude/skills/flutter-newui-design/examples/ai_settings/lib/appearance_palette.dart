import 'package:flutter/material.dart';
import 'paper_theme.dart';

enum DemoPaper { follow, white, sepia, green, night, black }

@immutable
class AppearancePaper {
  const AppearancePaper(
    this.background,
    this.ink,
    this.muted,
    this.line,
    this.brightness,
  );
  final Color background, ink, muted, line;
  final Brightness brightness;

  static AppearancePaper get original {
    final white = resolve(DemoPaper.white, Brightness.light);
    return AppearancePaper(
      Colors.white,
      white.ink,
      white.muted,
      white.line,
      white.brightness,
    );
  }

  static AppearancePaper resolve(DemoPaper paper, Brightness appBrightness) {
    if (paper == DemoPaper.follow) {
      final cs = paperTheme(appBrightness).colorScheme;
      return AppearancePaper(
        cs.surfaceContainerLow,
        cs.onSurface,
        cs.onSurfaceVariant,
        cs.outlineVariant,
        appBrightness,
      );
    }
    return switch (paper) {
      DemoPaper.white => const AppearancePaper(
        Color(0xFFFBFAF7),
        Color(0xFF25231F),
        Color(0xFF68645C),
        Color(0xFFE1DDD4),
        Brightness.light,
      ),
      DemoPaper.sepia => const AppearancePaper(
        Color(0xFFF3EBDD),
        Color(0xFF3B342B),
        Color(0xFF6D6050),
        Color(0xFFDACFBB),
        Brightness.light,
      ),
      DemoPaper.green => const AppearancePaper(
        Color(0xFFE7EDE3),
        Color(0xFF293B2D),
        Color(0xFF526750),
        Color(0xFFCCD7C7),
        Brightness.light,
      ),
      DemoPaper.night => const AppearancePaper(
        Color(0xFF232321),
        Color(0xFFE7E3D9),
        Color(0xFFB9B5AA),
        Color(0xFF48483F),
        Brightness.dark,
      ),
      DemoPaper.black => const AppearancePaper(
        Color(0xFF0D0D0D),
        Color(0xFFE4E1D9),
        Color(0xFFB2AEA5),
        Color(0xFF34332F),
        Brightness.dark,
      ),
      DemoPaper.follow => throw StateError('Follow is resolved above'),
    };
  }
}

double appearanceContrast(Color a, Color b) {
  final first = a.computeLuminance(), second = b.computeLuminance();
  return first > second
      ? (first + .05) / (second + .05)
      : (second + .05) / (first + .05);
}
