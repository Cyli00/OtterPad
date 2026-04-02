import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../../../providers/reader_settings_provider.dart';
import 'md_widget/nr_markdown_config.dart';
import 'md_widget/nr_search_highlight_builder.dart';

/// 可配置外观的 Markdown 渲染组件，专用于阅读器。
///
/// 支持两种渲染模式：
/// - **普通模式**：单个 [MarkdownBlock] 渲染全部内容（性能最优）
/// - **高亮模式**：按段落拆分为独立 block，目标 block 挂载 [GlobalKey]，
///   用 [Scrollable.ensureVisible] 精准滚动到段落顶部。
///
/// 搜索高亮通过 [SearchHighlightBuilder] 在渲染后后处理。
class ReaderMarkdownBody extends StatefulWidget {
  final String data;
  final ReaderSettingsState settings;
  final ScrollController? scrollController;

  /// 需要高亮的搜索词（null 则普通模式）
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
  final _targetKey = GlobalKey();
  bool _hasScrolled = false;

  /// 进入高亮模式后锁定 block-based 渲染，避免取消高亮时切换 widget 树导致闪屏
  bool _useBlockMode = false;

  List<_MdBlock>? _cachedBlocks;
  String? _cachedBlockSource;
  _RenderResources? _renderResources;

  // ── 高亮预处理缓存 ──
  bool _isHighlightModeFor(ReaderMarkdownBody widget) {
    return widget.highlightQuery != null &&
        widget.highlightQuery!.isNotEmpty &&
        widget.targetCharOffset != null;
  }

  @override
  void didUpdateWidget(covariant ReaderMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldHighlightMode = _isHighlightModeFor(oldWidget);
    if (widget.targetCharOffset != oldWidget.targetCharOffset ||
        widget.highlightQuery != oldWidget.highlightQuery) {
      _hasScrolled = false;
      if (_isHighlightMode) _useBlockMode = true;
      if (!_isHighlightMode && oldHighlightMode && _useBlockMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _isHighlightMode || !_useBlockMode) return;
          setState(() => _useBlockMode = false);
        });
      }
    }
    if (widget.data != oldWidget.data) {
      _cachedBlockSource = null;
      _cachedBlocks = null;
    }
    if (widget.settings != oldWidget.settings ||
        widget.highlightQuery != oldWidget.highlightQuery) {
      _disposeRenderResources();
    }
  }

  bool get _isHighlightMode =>
      widget.highlightQuery != null &&
      widget.highlightQuery!.isNotEmpty &&
      widget.targetCharOffset != null;

  void _scheduleScrollToTarget() {
    if (_hasScrolled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _hasScrolled) return;
      final ctx = _targetKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
        _hasScrolled = true;
      }
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
    final useBlockMode = _useBlockMode || _isHighlightMode;
    if (useBlockMode) {
      return _buildBlockBased(resources);
    }
    return _buildSingleBody(resources);
  }

  // ─── 普通模式：单 MarkdownBlock ───

  Widget _buildSingleBody(_RenderResources resources) {
    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: _markdownBody(data: widget.data, resources: resources),
    );
  }

  // ─── 高亮模式：按段落拆分 + 精准跳转 ───

  Widget _buildBlockBased(_RenderResources resources) {
    final blocks = _getBlocks(widget.data);
    final targetIndex = widget.targetCharOffset != null
        ? _findTargetBlock(blocks, widget.targetCharOffset!)
        : -1;

    if (targetIndex >= 0) _scheduleScrollToTarget();

    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(blocks.length, (i) {
          final block = blocks[i];
          Widget child = _markdownBody(
            data: block.text,
            resources: resources,
          );
          if (i == targetIndex) {
            child = Container(key: _targetKey, child: child);
          }
          return child;
        }),
      ),
    );
  }

  // ─── 共享的 MarkdownBlock 构造 ───

  Widget _markdownBody({
    required String data,
    required _RenderResources resources,
  }) {
    // selectable: false — 外层 view.dart 已经用 SelectionArea 包裹
    return MarkdownBlock(
      key: ValueKey(data.hashCode),
      data: data,
      selectable: false,
      config: resources.config,
      generator: resources.generator,
    );
  }

  List<_MdBlock> _getBlocks(String content) {
    if (_cachedBlockSource != content || _cachedBlocks == null) {
      _cachedBlockSource = content;
      _cachedBlocks = _splitIntoBlocks(content);
    }
    return _cachedBlocks!;
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

// ─── 段落拆分工具 ───

class _MdBlock {
  final String text;
  final int charOffset;
  const _MdBlock({required this.text, required this.charOffset});
}

List<_MdBlock> _splitIntoBlocks(String markdown) {
  final blocks = <_MdBlock>[];
  final matches = RegExp(r'\n\n+').allMatches(markdown).toList();

  var start = 0;
  for (final match in matches) {
    final text = markdown.substring(start, match.start).trim();
    if (text.isNotEmpty) {
      blocks.add(_MdBlock(text: text, charOffset: start));
    }
    start = match.end;
  }

  if (start < markdown.length) {
    final text = markdown.substring(start).trim();
    if (text.isNotEmpty) {
      blocks.add(_MdBlock(text: text, charOffset: start));
    }
  }

  return blocks;
}

int _findTargetBlock(List<_MdBlock> blocks, int charOffset) {
  var low = 0;
  var high = blocks.length - 1;
  var result = 0;

  while (low <= high) {
    final mid = low + ((high - low) >> 1);
    final offset = blocks[mid].charOffset;
    if (offset <= charOffset) {
      result = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }

  return result;
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
    // 构建搜索高亮
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
