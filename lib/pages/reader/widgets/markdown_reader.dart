import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../../../providers/reader_settings_provider.dart';
import 'md_widget/nr_markdown_config.dart';
import 'md_widget/nr_search_highlight_builder.dart';

/// 虚拟化 Markdown 渲染组件，专用于阅读器。
///
/// 使用 [MarkdownGenerator.buildWidgets] 预构建 widget 列表，
/// 通过 [ListView.builder] 仅构建屏幕可见 widget，大幅提升
/// 首帧渲染速度和窗口 resize 流畅度。
///
/// 搜索高亮通过 [SearchHighlightBuilder] 在 richTextBuilder 层面实现，
/// 跳转通过字符偏移比例估算滚动位置（与 outline 导航一致）。
class ReaderMarkdownBody extends StatefulWidget {
  final String data;
  final ReaderSettingsState settings;
  final ScrollController? scrollController;

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

  /// 通过字符偏移比例估算滚动位置并跳转。
  ///
  /// 双层 postFrameCallback：第一帧 ListView.builder 构建可见 widget，
  /// 第二帧 layout 完成后 maxScrollExtent 可用。
  void _scrollToTarget() {
    if (_hasScrolled) return;
    _hasScrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final controller = widget.scrollController;
        if (controller == null || !controller.hasClients) return;
        final maxExtent = controller.position.maxScrollExtent;
        if (maxExtent <= 0) return;
        final ratio = widget.targetCharOffset! / widget.data.length;
        controller.animateTo(
          (ratio * maxExtent).clamp(0.0, maxExtent),
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      });
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

    if (_isHighlightMode) _scrollToTarget();

    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      itemCount: widgets.length,
      itemBuilder: (_, index) => widgets[index],
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
