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

class ApplyBilingualLayout extends ReaderUpdate {
  final bool enabled;
  const ApplyBilingualLayout(this.enabled);
}

class ApplyTranslationStyle extends ReaderUpdate {
  final String styleId;
  const ApplyTranslationStyle(this.styleId);
}

class ApplyTranslations extends ReaderUpdate {
  final List<Map<String, dynamic>> entries;
  const ApplyTranslations(this.entries);
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
  final List<Map<String, dynamic>> readerEntries;
  final int contentRevision;
  final ReaderPalette palette;
  final ReaderSettingsState settings;
  final String translationStyleId;
  final bool bilingualColumns;
  final List<Highlight> highlights;
  final String? highlightQuery;

  const ReaderProps({
    required this.markdownData,
    this.readerEntries = const [],
    this.contentRevision = 0,
    this.bilingualColumns = false,
    required this.palette,
    required this.settings,
    required this.translationStyleId,
    required this.highlights,
    required this.highlightQuery,
  });
}

/// 对比两份 props，返回需要对 WebView 执行的更新清单（纯函数，可无 mock 单测）。
///
/// - 正文或索引版本变化才重写 HTML；译文按段落身份提交差量。
/// - 主题、翻页、翻译样式及高亮单独变化只更新相应 DOM 或 CSS。
///   正文重载会带入这些状态，无需重复提交。
/// - highlightQuery 不受 data 变化约束：无论是否 reload 都应用搜索。
List<ReaderUpdate> planUpdates(ReaderProps oldProps, ReaderProps newProps) {
  final updates = <ReaderUpdate>[];

  final dataChanged =
      newProps.markdownData != oldProps.markdownData ||
      newProps.contentRevision != oldProps.contentRevision;

  if (dataChanged) {
    updates.add(const ReloadContent());
  } else {
    if (newProps.readerEntries != oldProps.readerEntries) {
      final previous = {for (final e in oldProps.readerEntries) e['id']: e};
      final changed = newProps.readerEntries
          .where((e) => !identical(previous[e['id']], e))
          .toList();
      if (changed.isNotEmpty) updates.add(ApplyTranslations(changed));
    }
    if (newProps.bilingualColumns != oldProps.bilingualColumns) {
      updates.add(ApplyBilingualLayout(newProps.bilingualColumns));
    }
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
