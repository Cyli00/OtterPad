import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import '../../../providers/reader_settings_provider.dart';
import 'md_widget/nr_markdown_config.dart';
import 'md_widget/nr_search_highlight_builder.dart';

/// 虚拟化 Markdown 渲染组件，专用于阅读器。
///
/// 使用 [MarkdownGenerator.buildWidgets] 预构建 widget 列表，
/// 通过 [ListView.builder] + [AutoScrollTag] 仅构建屏幕可见 widget，
/// 支持通过 [AutoScrollController.scrollToIndex] 精确跳转到任意 widget。
class ReaderMarkdownBody extends StatefulWidget {
  final String data;
  final ReaderSettingsState settings;
  final AutoScrollController? scrollController;

  /// 需要高亮的搜索词
  final String? highlightQuery;

  /// 目标段落在原始 Markdown 中的字符偏移
  final int? targetCharOffset;

  const ReaderMarkdownBody({
    super.key,
    required this.data,
    required this.settings,
    this.scrollController,
    this.highlightQuery,
    this.targetCharOffset,
  });

  @override
  State<ReaderMarkdownBody> createState() => _ReaderMarkdownBodyState();
}

class _ReaderMarkdownBodyState extends State<ReaderMarkdownBody> {
  bool _hasScrolled = false;

  List<Widget>? _cachedWidgets;
  _RenderResources? _renderResources;

  @override
  void didUpdateWidget(covariant ReaderMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.targetCharOffset != oldWidget.targetCharOffset ||
        widget.highlightQuery != oldWidget.highlightQuery) {
      _hasScrolled = false;
    }
    if (widget.data != oldWidget.data) {
      _cachedWidgets = null;
    }
    if (widget.settings != oldWidget.settings ||
        widget.highlightQuery != oldWidget.highlightQuery) {
      _disposeRenderResources();
      _cachedWidgets = null;
    }
  }

  bool get _isHighlightMode =>
      widget.highlightQuery != null &&
      widget.highlightQuery!.isNotEmpty &&
      widget.targetCharOffset != null;

  List<Widget> _getWidgets(_RenderResources resources) {
    if (_cachedWidgets != null) return _cachedWidgets!;
    _cachedWidgets = resources.generator.buildWidgets(
      widget.data,
      config: resources.config,
    );
    return _cachedWidgets!;
  }

  /// 搜索高亮跳转：通过 charOffset 计算 widget index，精确滚动。
  void _scrollToTarget() {
    if (_hasScrolled) return;
    _hasScrolled = true;
    final controller = widget.scrollController;
    if (controller == null) return;
    final index = _charOffsetToWidgetIndex(
      widget.data,
      widget.targetCharOffset!,
    );
    final widgets = _cachedWidgets;
    final safeIndex =
        widgets != null ? index.clamp(0, widgets.length - 1) : index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      controller.scrollToIndex(
        safeIndex,
        preferPosition: AutoScrollPosition.begin,
      );
    });
  }

  @override
  void dispose() {
    _disposeRenderResources();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resources = _resolveRenderResources(context);
    final widgets = _getWidgets(resources);
    final controller = widget.scrollController;

    if (_isHighlightMode) _scrollToTarget();

    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      itemCount: widgets.length,
      itemBuilder: (ctx, index) {
        final child = widgets[index];
        if (controller == null) return child;
        return AutoScrollTag(
          key: ValueKey(index),
          controller: controller,
          index: index,
          child: child,
        );
      },
    );
  }

  _RenderResources _resolveRenderResources(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final resources = _renderResources;
    if (resources != null &&
        resources.primary == colorScheme.primary &&
        resources.primaryContainer == colorScheme.primaryContainer &&
        resources.onPrimaryContainer == colorScheme.onPrimaryContainer) {
      return resources;
    }
    final next = _RenderResources.create(
      settings: widget.settings,
      colorScheme: colorScheme,
      highlightQuery: _isHighlightMode ? widget.highlightQuery : null,
    );
    _renderResources = next;
    return next;
  }

  void _disposeRenderResources() {
    _renderResources = null;
  }
}

// ─── charOffset → widget index 映射 ───

/// 将 Markdown 字符偏移转换为 [MarkdownGenerator.buildWidgets] 的 widget 索引。
///
/// 原理：markdown parser 按块级元素分组（段落、标题、图片等），
/// 块间以空行分隔。统计 charOffset 前的空行分隔符数量即为 widget 索引。
int _charOffsetToWidgetIndex(String markdown, int charOffset) {
  final breaks = RegExp(r'\n\n+').allMatches(markdown);
  var index = 0;
  for (final brk in breaks) {
    if (brk.start >= charOffset) break;
    index++;
  }
  return index;
}

// ─── 渲染资源管理 ───

class _RenderResources {
  final MarkdownConfig config;
  final MarkdownGenerator generator;
  final Color primary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final SearchHighlightBuilder? searchBuilder;

  const _RenderResources({
    required this.config,
    required this.generator,
    required this.primary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    this.searchBuilder,
  });

  factory _RenderResources.create({
    required ReaderSettingsState settings,
    required ColorScheme colorScheme,
    required String? highlightQuery,
  }) {
    SearchHighlightBuilder? searchBuilder;
    if (highlightQuery != null && highlightQuery.isNotEmpty) {
      searchBuilder = SearchHighlightBuilder(
        searchQuery: highlightQuery,
        cs: colorScheme,
      );
    }

    final config = buildReaderMarkdownConfig(
      settings: settings,
      colorScheme: colorScheme,
    );

    final generator = buildReaderMarkdownGenerator(
      settings: settings,
      searchRichTextBuilder:
          searchBuilder?.hasHighlights == true ? searchBuilder!.call : null,
    );

    return _RenderResources(
      config: config,
      generator: generator,
      primary: colorScheme.primary,
      primaryContainer: colorScheme.primaryContainer,
      onPrimaryContainer: colorScheme.onPrimaryContainer,
      searchBuilder: searchBuilder,
    );
  }
}
