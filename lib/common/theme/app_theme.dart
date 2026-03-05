import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData light(ColorScheme? dynamic) {
    final colorScheme = dynamic ??
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
    );
  }

  static ThemeData dark(ColorScheme? dynamic) {
    final colorScheme = dynamic ??
        ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.dark,
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
    );
  }
}
