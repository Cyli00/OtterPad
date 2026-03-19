import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/storage.dart';

class ThemeState {
  final ThemeMode mode;
  final Color seedColor;
  final bool useDynamicColor;

  const ThemeState({
    required this.mode,
    required this.seedColor,
    this.useDynamicColor = false,
  });

  ThemeState copyWith({
    ThemeMode? mode,
    Color? seedColor,
    bool? useDynamicColor,
  }) {
    return ThemeState(
      mode: mode ?? this.mode,
      seedColor: seedColor ?? this.seedColor,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
    );
  }
}

class ThemeNotifier extends StateNotifier<ThemeState> {
  static const String _themeModeKey = 'theme_mode';
  static const String _seedColorKey = 'seed_color';
  static const String _dynamicColorKey = 'use_dynamic_color';

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

    return ThemeState(
      mode: mode,
      seedColor: Color(savedColorValue),
      useDynamicColor: useDynamicColor,
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

  void reload() {
    state = _loadTheme();
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  return ThemeNotifier();
});
