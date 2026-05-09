import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/storage.dart';

/// 阅读器背景模式
///
/// [themed] 表示采用当前应用主题色（由 `themeProvider` 管理的 seed color），
/// 其他几项为固定背景：羊皮纸 / 夜间 / 纯黑 / 护眼绿。具体颜色统一走
/// `reader_background.dart` 的 `resolveReaderPalette()`。
///
/// 枚举顺序即 Hive 持久化 `.index` 的序号 API——**只能尾追**，不能插入中间，
/// 否则老用户保存的 theme 会错位加载。如需改变"视觉顺序"，在 UI 层用
/// 显式展示列表替代 `values` 迭代即可。
enum ReaderTheme {
  themed,
  sepia,
  night,
  dark,
  green;

  /// 详细中文名（设置页等需要完整描述的场景）。
  String get label => switch (this) {
        ReaderTheme.themed => '主题色',
        ReaderTheme.sepia => '羊皮纸',
        ReaderTheme.green => '护眼绿',
        ReaderTheme.night => '夜间',
        ReaderTheme.dark => '纯黑',
      };

  /// 阅读器底部面板用的短名（空间紧张、视觉整齐）。
  String get shortLabel => switch (this) {
        ReaderTheme.themed => '白天',
        ReaderTheme.sepia => '羊皮',
        ReaderTheme.green => '护眼',
        ReaderTheme.night => '夜间',
        ReaderTheme.dark => '纯黑',
      };

  /// 该阅读器主题适配的 app 亮度模式。
  ///
  /// UI 切换 reader theme 时，同时把 [themeProvider] 的 `ThemeMode` 刷成
  /// 对应亮度——这样工具栏的 `cs.surface`、文字色、分割线都自然跟着变，
  /// 无需为每个 widget 单独派生 ColorScheme。
  Brightness get brightness => switch (this) {
        ReaderTheme.themed ||
        ReaderTheme.sepia ||
        ReaderTheme.green =>
          Brightness.light,
        ReaderTheme.night || ReaderTheme.dark => Brightness.dark,
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

  /// 映射到实际字体族名（首选字体）。
  ///
  /// 这三个首选字体（思源宋体 / 思源黑体 / Ubuntu Mono）在 Windows/macOS
  /// 默认**不预装**——未安装时会按下面的 [fontFamilyFallback] 退化到平台
  /// 原生 CJK / 等宽字体。如需保证跨平台一致渲染，应把字体文件放进
  /// `assets/fonts/` 并在 pubspec 注册。
  String? get fontFamily => switch (this) {
        ReaderFont.serif => 'Source Han Serif',
        ReaderFont.sans => 'Source Han Sans',
        ReaderFont.mono => 'Ubuntu Mono',
      };

  /// 跨平台备选字体列表。
  ///
  /// Source Han Serif/Sans 在不同发行版下命名不同（Adobe `Source Han ...`、
  /// Google `Noto ... CJK SC`、`-SC` 子集等），全列以提高命中率。
  List<String>? get fontFamilyFallback => switch (this) {
        ReaderFont.serif => const [
            'Source Han Serif SC',
            'Noto Serif CJK SC',
            'Songti SC',
            'STSong',
            'SimSun',
            'Times New Roman',
            'Noto Serif',
          ],
        ReaderFont.sans => const [
            'Source Han Sans SC',
            'Noto Sans CJK SC',
            'PingFang SC',
            'Heiti SC',
            'Microsoft YaHei',
            'Helvetica',
            'Arial',
          ],
        ReaderFont.mono => const [
            'UbuntuMono Nerd Font',
            'Cascadia Mono',
            'Consolas',
            'Menlo',
            'Courier New',
            'Noto Sans Mono',
          ],
      };
}

/// 工具栏透明度预设
enum ToolbarOpacity {
  opaque(1.0, '不透明'),
  slight(0.85, '微透明'),
  glass(0.7, '毛玻璃'),
  half(0.5, '半透明');

  final double value;
  final String label;
  const ToolbarOpacity(this.value, this.label);
}

class ReaderSettingsState {
  final ReaderTheme theme;
  final ReaderFont font;
  final double fontSize;
  final DefaultReadingMode defaultReadingMode;
  final ToolbarOpacity toolbarOpacity;

  const ReaderSettingsState({
    this.theme = ReaderTheme.themed,
    this.font = ReaderFont.serif,
    this.fontSize = 16.0,
    this.defaultReadingMode = DefaultReadingMode.markdown,
    this.toolbarOpacity = ToolbarOpacity.glass,
  });

  ReaderSettingsState copyWith({
    ReaderTheme? theme,
    ReaderFont? font,
    double? fontSize,
    DefaultReadingMode? defaultReadingMode,
    ToolbarOpacity? toolbarOpacity,
  }) {
    return ReaderSettingsState(
      theme: theme ?? this.theme,
      font: font ?? this.font,
      fontSize: fontSize ?? this.fontSize,
      defaultReadingMode: defaultReadingMode ?? this.defaultReadingMode,
      toolbarOpacity: toolbarOpacity ?? this.toolbarOpacity,
    );
  }

  static const double minFontSize = 12.0;
  static const double maxFontSize = 28.0;
}

class ReaderSettingsNotifier extends StateNotifier<ReaderSettingsState> {
  static const _kTheme = 'reader_theme';
  static const _kFont = 'reader_font';
  static const _kFontSize = 'reader_font_size';
  static const _kDefaultMode = 'reader_default_mode';
  static const _kToolbarOpacity = 'reader_toolbar_opacity';

  ReaderSettingsNotifier() : super(_load());

  static ReaderSettingsState _load() {
    final box = GStorage.setting;
    final themeIndex = box.get(_kTheme, defaultValue: 0) as int;
    final fontIndex = box.get(_kFont, defaultValue: 0) as int;
    final fontSize = box.get(_kFontSize, defaultValue: 16.0) as double;
    final modeIndex = box.get(_kDefaultMode, defaultValue: 0) as int;
    final opacityIndex = box.get(_kToolbarOpacity, defaultValue: 2) as int;
    return ReaderSettingsState(
      theme: ReaderTheme
          .values[themeIndex.clamp(0, ReaderTheme.values.length - 1)],
      font: ReaderFont.values[fontIndex.clamp(0, 2)],
      fontSize: fontSize.clamp(
        ReaderSettingsState.minFontSize,
        ReaderSettingsState.maxFontSize,
      ),
      defaultReadingMode:
          DefaultReadingMode.values[modeIndex.clamp(0, 1)],
      toolbarOpacity: ToolbarOpacity
          .values[opacityIndex.clamp(0, ToolbarOpacity.values.length - 1)],
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

  void setToolbarOpacity(ToolbarOpacity opacity) {
    state = state.copyWith(toolbarOpacity: opacity);
    GStorage.setting.put(_kToolbarOpacity, opacity.index);
  }

  void reload() {
    state = _load();
  }
}

final readerSettingsProvider =
    StateNotifierProvider<ReaderSettingsNotifier, ReaderSettingsState>(
  (ref) => ReaderSettingsNotifier(),
);
