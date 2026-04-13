import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import '../../../providers/reader_settings_provider.dart';
import 'md_widget/nr_markdown_config.dart';
import 'md_widget/nr_search_highlight_builder.dart';

/// 虚拟化 Markdown 渲染组件，专用于阅读器。
///
/// 使用 [MarkdownGenerator.buildWidgets] 预构建 widget 列表，
/// 通过 [ListView.builder] + [AutoScrollTag] 仅构建屏幕可见 widget。
/// 搜索高亮通过 [SearchHighlightBuilder] 在 richTextBuilder 层面实现。
/// 跳转由外部通过 [AutoScrollController.scrollToIndex] 直接控制。
class ReaderMarkdownBody extends StatefulWidget {
  final String data;
  final ReaderSettingsState settings;
  final AutoScrollController? scrollController;

  /// 需要高亮的搜索词（仅控制渲染高亮，不触发跳转）
  final String? highlightQuery;

  const ReaderMarkdownBody({
    super.key,
    required this.data,
    required this.settings,
    this.scrollController,
    this.highlightQuery,
  });

  @override
  State<ReaderMarkdownBody> createState() => _ReaderMarkdownBodyState();
}

class _ReaderMarkdownBodyState extends State<ReaderMarkdownBody> {
  List<Widget>? _cachedWidgets;
  _RenderResources? _renderResources;

  @override
  void didUpdateWidget(covariant ReaderMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data != oldWidget.data) {
      _cachedWidgets = null;
    }
    if (widget.settings != oldWidget.settings ||
        widget.highlightQuery != oldWidget.highlightQuery) {
      _disposeRenderResources();
      _cachedWidgets = null;
    }
  }

  bool get _hasHighlight =>
      widget.highlightQuery != null && widget.highlightQuery!.isNotEmpty;

  List<Widget> _getWidgets(_RenderResources resources) {
    if (_cachedWidgets != null) return _cachedWidgets!;
    _cachedWidgets = resources.generator.buildWidgets(
      widget.data,
      config: resources.config,
    );
    return _cachedWidgets!;
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
      highlightQuery: _hasHighlight ? widget.highlightQuery : null,
    );
    _renderResources = next;
    return next;
  }

  void _disposeRenderResources() {
    _renderResources = null;
  }
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
      highlightQuery: highlightQuery,
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
