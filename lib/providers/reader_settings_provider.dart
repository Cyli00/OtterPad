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
///
/// 阅读器只渲染长文，不展示代码段，所以仅保留衬线 / 无衬线两套；
/// 之前的 `mono` 已删除。
///
/// 历史遗留：旧版本里 `mono` 占据 `.index = 2`。删除后 `_load()` 用
/// `fontIndex.clamp(0, ReaderFont.values.length - 1)` 把老用户的 2 自动
/// 兜底回 sans（index 1），无需迁移脚本。
enum ReaderFont {
  serif,
  sans;

  String get label => switch (this) {
        ReaderFont.serif => 'Serif',
        ReaderFont.sans => 'Sans',
      };

  /// 映射到实际字体族名（首选字体）。
  ///
  /// `serif` 用 Times New Roman（Windows/macOS 都预装）；`sans` 留 null
  /// 让平台用系统默认无衬线（Windows = Segoe UI、macOS = San Francisco、
  /// Android = Roboto、iOS = San Francisco）。中文回退依赖
  /// [fontFamilyFallback]，以及更上层 CSS（webview_reader_html）的回退链。
  String? get fontFamily => switch (this) {
        ReaderFont.serif => 'Times New Roman',
        ReaderFont.sans => null,
      };

  /// 跨平台备选字体列表（CJK 兜底）。
  List<String>? get fontFamilyFallback => switch (this) {
        ReaderFont.serif => const [
            'Songti SC',
            'STSong',
            'SimSun',
            'Noto Serif CJK SC',
            'Noto Serif',
          ],
        ReaderFont.sans => null,
      };
}

/// 阅读器翻页方式
///
/// [vertical]：传统上下滚动（默认）；[horizontal]：CSS multi-column
/// 横向分栏翻页（鼠标滚轮 / 键盘 ← → / 边缘 30% 点击 / 触摸滑动）。
/// 全局生效，跨文献共享，与字号 / 字体同级。
///
/// 枚举尾追规则：Hive 持久化用 `.index`，删枚举或插中间会让老用户的
/// 保存值错位加载，只能在 `values` 末尾追加。
enum ReaderPaginationMode {
  vertical,
  horizontal;

  String get label => switch (this) {
        ReaderPaginationMode.vertical => '上下翻页',
        ReaderPaginationMode.horizontal => '左右翻页',
      };

  /// JS `setPaginationMode(...)` 接受的字符串 id。
  String get jsId => switch (this) {
        ReaderPaginationMode.vertical => 'vertical',
        ReaderPaginationMode.horizontal => 'horizontal',
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
  final ReaderPaginationMode paginationMode;

  const ReaderSettingsState({
    this.theme = ReaderTheme.themed,
    this.font = ReaderFont.serif,
    this.fontSize = 16.0,
    this.defaultReadingMode = DefaultReadingMode.markdown,
    this.toolbarOpacity = ToolbarOpacity.opaque,
    this.paginationMode = ReaderPaginationMode.vertical,
  });

  ReaderSettingsState copyWith({
    ReaderTheme? theme,
    ReaderFont? font,
    double? fontSize,
    DefaultReadingMode? defaultReadingMode,
    ToolbarOpacity? toolbarOpacity,
    ReaderPaginationMode? paginationMode,
  }) {
    return ReaderSettingsState(
      theme: theme ?? this.theme,
      font: font ?? this.font,
      fontSize: fontSize ?? this.fontSize,
      defaultReadingMode: defaultReadingMode ?? this.defaultReadingMode,
      toolbarOpacity: toolbarOpacity ?? this.toolbarOpacity,
      paginationMode: paginationMode ?? this.paginationMode,
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
  static const _kPaginationMode = 'reader_pagination_mode';

  ReaderSettingsNotifier() : super(_load());

  static ReaderSettingsState _load() {
    final box = GStorage.setting;
    final themeIndex = box.get(_kTheme, defaultValue: 0) as int;
    final fontIndex = box.get(_kFont, defaultValue: 0) as int;
    final fontSize = box.get(_kFontSize, defaultValue: 16.0) as double;
    // markdown = enum index 1, opaque = enum index 0
    final modeIndex =
        box.get(_kDefaultMode, defaultValue: DefaultReadingMode.markdown.index)
            as int;
    final opacityIndex =
        box.get(_kToolbarOpacity, defaultValue: ToolbarOpacity.opaque.index)
            as int;
    final paginationIndex =
        box.get(_kPaginationMode, defaultValue: 0) as int;
    return ReaderSettingsState(
      theme: ReaderTheme
          .values[themeIndex.clamp(0, ReaderTheme.values.length - 1)],
      font: ReaderFont
          .values[fontIndex.clamp(0, ReaderFont.values.length - 1)],
      fontSize: fontSize.clamp(
        ReaderSettingsState.minFontSize,
        ReaderSettingsState.maxFontSize,
      ),
      defaultReadingMode:
          DefaultReadingMode.values[modeIndex.clamp(0, 1)],
      toolbarOpacity: ToolbarOpacity
          .values[opacityIndex.clamp(0, ToolbarOpacity.values.length - 1)],
      paginationMode: ReaderPaginationMode.values[
          paginationIndex.clamp(0, ReaderPaginationMode.values.length - 1)],
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

  void setPaginationMode(ReaderPaginationMode mode) {
    state = state.copyWith(paginationMode: mode);
    GStorage.setting.put(_kPaginationMode, mode.index);
  }

  void reload() {
    state = _load();
  }
}

final readerSettingsProvider =
    StateNotifierProvider<ReaderSettingsNotifier, ReaderSettingsState>(
  (ref) => ReaderSettingsNotifier(),
);
