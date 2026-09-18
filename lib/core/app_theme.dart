import 'package:flutter/material.dart';

const appSliderTheme = SliderThemeData(
  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8),
  overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
  trackHeight: 3,
);

ThemeData buildAppTheme(
  ColorScheme colorScheme, {
  String? fontFamily,
  List<String>? fontFamilyFallback,
}) => ThemeData(
  colorScheme: colorScheme,
  useMaterial3: true,
  fontFamily: fontFamily,
  fontFamilyFallback: fontFamilyFallback,
  dialogTheme: const DialogThemeData(elevation: 0),
  sliderTheme: appSliderTheme,
  pageTransitionsTheme: const PageTransitionsTheme(
    builders: {TargetPlatform.android: PredictiveBackPageTransitionsBuilder()},
  ),
);
