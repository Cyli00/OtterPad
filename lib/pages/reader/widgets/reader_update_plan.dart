import '../../../data/models/book/highlight.dart';
import '../../../providers/reader_settings_provider.dart';
import 'reader_background.dart';

/// `WebViewMarkdownReader` props 变化后需要对 WebView 执行的单个更新动作。
///
/// 配合 [planUpdates]：纯函数决定"做哪些动作"，widget 的 dispatch 决定"怎么做"
/// （注入 controller、实例态等执行细节）。
sealed class ReaderUpdate {
  const ReaderUpdate();
}

/// markdown 数据变化——重写 HTML 并整页重载。
class ReloadContent extends ReaderUpdate {
  const ReloadContent();
}

/// 主题/字号/字体变化——仅改 CSS 变量，不销毁 DOM。
class ApplyTheme extends ReaderUpdate {
  final ReaderPalette palette;
  final ReaderSettingsState settings;
  const ApplyTheme(this.palette, this.settings);
}

class ApplyPagination extends ReaderUpdate {
  final ReaderPaginationMode mode;
  const ApplyPagination(this.mode);
}

class ApplyTranslationStyle extends ReaderUpdate {
  final String styleId;
  const ApplyTranslationStyle(this.styleId);
}

/// 高亮列表变化——把 [oldHighlights] → [newHighlights] 的差异同步到 WebView。
class SyncHighlights extends ReaderUpdate {
  final List<Highlight> oldHighlights;
  final List<Highlight> newHighlights;
  const SyncHighlights(this.oldHighlights, this.newHighlights);
}

/// 搜索高亮 query 变化。
class ApplySearchQuery extends ReaderUpdate {
  final String? query;
  const ApplySearchQuery(this.query);
}

/// [planUpdates] 的纯输入快照——从 widget 抽出参与"该做什么"判断的字段。
class ReaderProps {
  final String markdownData;
  final int contentRevision;
  final ReaderPalette palette;
  final ReaderSettingsState settings;
  final String translationStyleId;
  final List<Highlight> highlights;
  final String? highlightQuery;

  const ReaderProps({
    required this.markdownData,
    this.contentRevision = 0,
    required this.palette,
    required this.settings,
    required this.translationStyleId,
    required this.highlights,
    required this.highlightQuery,
  });
}

/// 对比两份 props，返回需要对 WebView 执行的更新清单（纯函数，可无 mock 单测）。
///
/// 规则与原 didUpdateWidget 完全一致：
/// - data 变化必须重写 HTML + reload —— DOM 内容不在 CSS 变量控制范围。
///   主题/翻页/翻译样式/高亮单独变 → 仅增量更新，**不销毁** DOM/KaTeX 缓存/
///   已绘 SVG 高亮。因此 data 变化时这四项不单独应用（reload 会带新状态重建）。
/// - highlightQuery 不受 data 变化约束：无论是否 reload 都应用搜索。
List<ReaderUpdate> planUpdates(ReaderProps oldProps, ReaderProps newProps) {
  final updates = <ReaderUpdate>[];

  final dataChanged =
      newProps.markdownData != oldProps.markdownData ||
      newProps.contentRevision != oldProps.contentRevision;

  if (dataChanged) {
    updates.add(const ReloadContent());
  } else {
    final themeChanged =
        newProps.palette != oldProps.palette ||
        newProps.settings.fontSize != oldProps.settings.fontSize ||
        newProps.settings.font != oldProps.settings.font ||
        newProps.settings.theme != oldProps.settings.theme;
    if (themeChanged) {
      updates.add(ApplyTheme(newProps.palette, newProps.settings));
    }
    if (newProps.settings.paginationMode != oldProps.settings.paginationMode) {
      updates.add(ApplyPagination(newProps.settings.paginationMode));
    }
    if (newProps.translationStyleId != oldProps.translationStyleId) {
      updates.add(ApplyTranslationStyle(newProps.translationStyleId));
    }
    if (newProps.highlights != oldProps.highlights) {
      updates.add(SyncHighlights(oldProps.highlights, newProps.highlights));
    }
  }

  if (newProps.highlightQuery != oldProps.highlightQuery) {
    updates.add(ApplySearchQuery(newProps.highlightQuery));
  }

  return updates;
}
