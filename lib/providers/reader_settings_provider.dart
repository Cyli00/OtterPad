import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/storage.dart';

/// 阅读器主题模式
enum ReaderTheme {
  light,
  sepia,
  dark;

  String get label => switch (this) {
        ReaderTheme.light => 'Light',
        ReaderTheme.sepia => 'Sepia',
        ReaderTheme.dark => 'Dark',
      };
}

/// 默认阅读模式
enum DefaultReadingMode {
  pdf,
  markdown;

  String get label => switch (this) {
        DefaultReadingMode.pdf => 'PDF',
        DefaultReadingMode.markdown => 'Markdown',
      };
}

/// 阅读器字体族
enum ReaderFont {
  serif,
  sans,
  mono;

  String get label => switch (this) {
        ReaderFont.serif => 'Serif',
        ReaderFont.sans => 'Sans',
        ReaderFont.mono => 'Mono',
      };

  /// 映射到实际字体族名（首选字体）
  String? get fontFamily => switch (this) {
        ReaderFont.serif => 'Georgia',
        ReaderFont.sans => null, // 使用系统默认
        ReaderFont.mono => 'Consolas',
      };

  /// 跨平台备选字体列表
  List<String>? get fontFamilyFallback => switch (this) {
        ReaderFont.serif => const [
            'Noto Serif CJK SC',
            'SimSun',
            'STSong',
            'Times New Roman',
            'Noto Serif',
          ],
        ReaderFont.sans => null,
        ReaderFont.mono => const [
            'Cascadia Mono',
            'Courier New',
            'Menlo',
            'Noto Sans Mono',
          ],
      };
}

class ReaderSettingsState {
  final ReaderTheme theme;
  final ReaderFont font;
  final double fontSize;
  final DefaultReadingMode defaultReadingMode;

  const ReaderSettingsState({
    this.theme = ReaderTheme.light,
    this.font = ReaderFont.serif,
    this.fontSize = 16.0,
    this.defaultReadingMode = DefaultReadingMode.pdf,
  });

  ReaderSettingsState copyWith({
    ReaderTheme? theme,
    ReaderFont? font,
    double? fontSize,
    DefaultReadingMode? defaultReadingMode,
  }) {
    return ReaderSettingsState(
      theme: theme ?? this.theme,
      font: font ?? this.font,
      fontSize: fontSize ?? this.fontSize,
      defaultReadingMode: defaultReadingMode ?? this.defaultReadingMode,
    );
  }

  /// 根据阅读器主题返回内容区域背景色
  Color get backgroundColor => switch (theme) {
        ReaderTheme.light => const Color(0xFFFFFFFF),
        ReaderTheme.sepia => const Color(0xFFF5F0E8),
        ReaderTheme.dark => const Color(0xFF1C1B1F),
      };

  /// 根据阅读器主题返回正文文字颜色
  Color get textColor => switch (theme) {
        ReaderTheme.light => const Color(0xFF1C1B1F),
        ReaderTheme.sepia => const Color(0xFF3B3530),
        ReaderTheme.dark => const Color(0xFFE6E1E5),
      };

  /// 次要文字颜色（作者、注释等）
  Color get secondaryTextColor => switch (theme) {
        ReaderTheme.light => const Color(0xFF49454F),
        ReaderTheme.sepia => const Color(0xFF5D5549),
        ReaderTheme.dark => const Color(0xFFCAC4D0),
      };

  /// 链接颜色
  Color get linkColor => switch (theme) {
        ReaderTheme.light => const Color(0xFF1A73E8),
        ReaderTheme.sepia => const Color(0xFF8B6914),
        ReaderTheme.dark => const Color(0xFF93B4FF),
      };

  /// 工具栏/面板背景色
  Color get surfaceColor => switch (theme) {
        ReaderTheme.light => const Color(0xFFF7F2FA),
        ReaderTheme.sepia => const Color(0xFFEDE8DF),
        ReaderTheme.dark => const Color(0xFF2B2930),
      };

  /// 分割线颜色
  Color get dividerColor => switch (theme) {
        ReaderTheme.light => const Color(0xFFE0E0E0),
        ReaderTheme.sepia => const Color(0xFFD5CEBC),
        ReaderTheme.dark => const Color(0xFF49454F),
      };

  static const double minFontSize = 12.0;
  static const double maxFontSize = 28.0;
}

class ReaderSettingsNotifier extends StateNotifier<ReaderSettingsState> {
  static const _kTheme = 'reader_theme';
  static const _kFont = 'reader_font';
  static const _kFontSize = 'reader_font_size';
  static const _kDefaultMode = 'reader_default_mode';

  ReaderSettingsNotifier() : super(_load());

  static ReaderSettingsState _load() {
    final box = GStorage.setting;
    final themeIndex = box.get(_kTheme, defaultValue: 0) as int;
    final fontIndex = box.get(_kFont, defaultValue: 0) as int;
    final fontSize = box.get(_kFontSize, defaultValue: 16.0) as double;
    final modeIndex = box.get(_kDefaultMode, defaultValue: 0) as int;
    return ReaderSettingsState(
      theme: ReaderTheme.values[themeIndex.clamp(0, 2)],
      font: ReaderFont.values[fontIndex.clamp(0, 2)],
      fontSize: fontSize.clamp(
        ReaderSettingsState.minFontSize,
        ReaderSettingsState.maxFontSize,
      ),
      defaultReadingMode:
          DefaultReadingMode.values[modeIndex.clamp(0, 1)],
    );
  }

  void setTheme(ReaderTheme theme) {
    state = state.copyWith(theme: theme);
    GStorage.setting.put(_kTheme, theme.index);
  }

  void setFont(ReaderFont font) {
    state = state.copyWith(font: font);
    GStorage.setting.put(_kFont, font.index);
  }

  void setFontSize(double size) {
    final clamped = size.clamp(
      ReaderSettingsState.minFontSize,
      ReaderSettingsState.maxFontSize,
    );
    state = state.copyWith(fontSize: clamped);
    GStorage.setting.put(_kFontSize, clamped);
  }

  void setDefaultReadingMode(DefaultReadingMode mode) {
    state = state.copyWith(defaultReadingMode: mode);
    GStorage.setting.put(_kDefaultMode, mode.index);
  }
}

final readerSettingsProvider =
    StateNotifierProvider<ReaderSettingsNotifier, ReaderSettingsState>(
  (ref) => ReaderSettingsNotifier(),
);
