import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/settings_keys.dart';
import '../core/app_fonts.dart';
import '../core/storage/storage.dart';

class ThemeState {
  final ThemeMode mode;
  final Color seedColor;
  final bool useDynamicColor;
  final double textScale;
  final String appFont;

  const ThemeState({
    required this.mode,
    required this.seedColor,
    this.useDynamicColor = false,
    this.textScale = 1.0,
    this.appFont = AppFonts.sans,
  });

  ThemeState copyWith({
    ThemeMode? mode,
    Color? seedColor,
    bool? useDynamicColor,
    double? textScale,
    String? appFont,
  }) {
    return ThemeState(
      mode: mode ?? this.mode,
      seedColor: seedColor ?? this.seedColor,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      textScale: textScale ?? this.textScale,
      appFont: appFont ?? this.appFont,
    );
  }
}

class ThemeNotifier extends StateNotifier<ThemeState> {
  static const String _themeModeKey = SettingsKeys.themeMode;
  static const String _seedColorKey = SettingsKeys.seedColor;
  static const String _dynamicColorKey = SettingsKeys.useDynamicColor;
  static const String _textScaleKey = SettingsKeys.textScale;

  /// 系统文字缩放预设：标准 / 大 / 特大
  static const List<double> textScalePresets = [1.0, 1.15, 1.3];

  static const List<Color> presetColors = [
    Colors.blue,
    Colors.indigo,
    Colors.purple,
    Colors.pink,
    Colors.red,
    Colors.lightGreen,
    Colors.green,
    Colors.orange,
    Colors.amber,
  ];

  ThemeNotifier() : super(_loadTheme());

  static ThemeState _loadTheme() {
    final box = GStorage.setting;
    final savedMode = box.get(_themeModeKey, defaultValue: 'system') as String;
    ThemeMode mode = ThemeMode.system;
    if (savedMode == 'light') {
      mode = ThemeMode.light;
    } else if (savedMode == 'dark') {
      mode = ThemeMode.dark;
    }

    final savedColorValue =
        box.get(_seedColorKey, defaultValue: Colors.blue.toARGB32()) as int;
    final useDynamicColor =
        box.get(_dynamicColorKey, defaultValue: false) as bool;
    final textScale = (box.get(_textScaleKey, defaultValue: 1.0) as num)
        .toDouble();

    return ThemeState(
      mode: mode,
      seedColor: Color(savedColorValue),
      useDynamicColor: useDynamicColor,
      textScale: textScale,
      appFont:
          box.get(SettingsKeys.appFont, defaultValue: AppFonts.sans) as String,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(mode: mode);
    String value = 'system';
    if (mode == ThemeMode.light) {
      value = 'light';
    } else if (mode == ThemeMode.dark) {
      value = 'dark';
    }
    await GStorage.setting.put(_themeModeKey, value);
  }

  Future<void> setSeedColor(Color color) async {
    state = state.copyWith(seedColor: color, useDynamicColor: false);
    await GStorage.setting.put(_seedColorKey, color.toARGB32());
    await GStorage.setting.put(_dynamicColorKey, false);
  }

  Future<void> setUseDynamicColor(bool value) async {
    state = state.copyWith(useDynamicColor: value);
    await GStorage.setting.put(_dynamicColorKey, value);
  }

  Future<void> setTextScale(double scale) async {
    state = state.copyWith(textScale: scale);
    await GStorage.setting.put(_textScaleKey, scale);
  }

  void reload() {
    state = _loadTheme();
  }

  Future<void> setAppFont(String value) async {
    await GStorage.setting.put(SettingsKeys.appFont, value);
    if (mounted) state = state.copyWith(appFont: value);
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  return ThemeNotifier();
});
