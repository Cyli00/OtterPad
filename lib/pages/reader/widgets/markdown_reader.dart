import 'dart:async';

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

  /// 工具栏占位：合并到 ListView padding，使首尾内容不被 overlay 遮挡
  final double topInset;
  final double bottomInset;

  /// 点击图片回调（传入原始 url），用于跳转到 FigureViewer 等行为。
  /// 回调身份变化不会触发已构建 widget 的重建——State 用闭包包一层稳定引用。
  final void Function(String url)? onImageTap;

  const ReaderMarkdownBody({
    super.key,
    required this.data,
    required this.settings,
    this.scrollController,
    this.highlightQuery,
    this.topInset = 0,
    this.bottomInset = 0,
    this.onImageTap,
  });

  @override
  State<ReaderMarkdownBody> createState() => _ReaderMarkdownBodyState();
}

class _ReaderMarkdownBodyState extends State<ReaderMarkdownBody> {
  List<Widget>? _cachedWidgets;
  _RenderResources? _renderResources;

  /// 上一次构建 widget 时使用的亮度。`ThemeData.lerp` 在 dark↔light 过渡
  /// 动画里让 brightness 在 t=0.5 处瞬切，用它做失效信号比较 primary 颜色
  /// 更稳——primary 每帧都变会让整个文档每帧重建，性能塌方。
  Brightness? _lastBrightness;

  /// brightness 翻转时抓到的 cs 还是 AnimatedTheme 的中途插值（灰紫色），
  /// 用定时器等动画完全跑完（200ms）再失效一次，拿到稳定的最终 cs 重建。
  Timer? _themeSettleTimer;

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

  /// 稳定的图片点击入口：始终调用最新的 [widget.onImageTap]，
  /// 避免父层闭包重建时 widget 列表被迫重新构建。
  void _handleImageTap(String url) => widget.onImageTap?.call(url);

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
    _themeSettleTimer?.cancel();
    _disposeRenderResources();
    super.dispose();
  }

  /// Flutter 内置 `kThemeAnimationDuration` = 200ms；多给 60ms 安全裕度，
  /// 兼容慢机上动画完成时间的抖动。`Duration + Duration` 不是 const，
  /// 故用 `static final`——惰性初始化一次，成本等同 const。
  static final _themeSettleDelay =
      kThemeAnimationDuration + const Duration(milliseconds: 60);

  /// AnimatedTheme 跑完后再强制清一次缓存，确保拿到稳定的最终 cs。
  void _scheduleThemeSettleRebuild() {
    _themeSettleTimer?.cancel();
    _themeSettleTimer = Timer(_themeSettleDelay, () {
      if (!mounted) return;
      setState(() {
        _renderResources = null;
        _cachedWidgets = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // brightness 翻转意味着 widget 树里烘焙的颜色全部失效——立即清一次缓存
    // 保证视觉上先跟上（用 AnimatedTheme 当前的中途插值重建），再安排一次
    // 动画结束后的二次失效，用稳定的最终 cs 重建一次——这是 ReaderTheme.themed
    // 从夜间切到白天时不再"发灰发亮"的关键。
    if (_lastBrightness != null &&
        _lastBrightness != colorScheme.brightness) {
      _renderResources = null;
      _cachedWidgets = null;
      _scheduleThemeSettleRebuild();
    }
    _lastBrightness = colorScheme.brightness;

    final resources = _resolveRenderResources(colorScheme);
    final widgets = _getWidgets(resources);
    final controller = widget.scrollController;

    return ListView.builder(
      controller: controller,
      padding: EdgeInsets.fromLTRB(
        20, 8 + widget.topInset, 20, 40 + widget.bottomInset,
      ),
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

  _RenderResources _resolveRenderResources(ColorScheme colorScheme) {
    final resources = _renderResources;
    // 用整个 ColorScheme 值等式比较做 cache key：`ColorScheme` 的 `==` 覆盖
    // 所有色槽字段（surface / onSurface / outline 等），不只原来的 3 色，
    // 能捕获 seed color 变更导致的次要颜色漂移；`==` 在 const 情形下 O(1)、
    // 动态情形下 O(字段数) 无分配，单帧开销可忽略。
    if (resources != null && resources.colorScheme == colorScheme) {
      return resources;
    }
    final next = _RenderResources.create(
      settings: widget.settings,
      colorScheme: colorScheme,
      highlightQuery: _hasHighlight ? widget.highlightQuery : null,
      onImageTap: _handleImageTap,
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
  final ColorScheme colorScheme;
  final SearchHighlightBuilder? searchBuilder;

  const _RenderResources({
    required this.config,
    required this.generator,
    required this.colorScheme,
    this.searchBuilder,
  });

  factory _RenderResources.create({
    required ReaderSettingsState settings,
    required ColorScheme colorScheme,
    required String? highlightQuery,
    void Function(String url)? onImageTap,
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
      onImageTap: onImageTap,
    );

    final generator = buildReaderMarkdownGenerator(
      settings: settings,
      searchRichTextBuilder:
          searchBuilder?.hasHighlights == true ? searchBuilder!.call : null,
      translatedColor: colorScheme.primary,
    );

    return _RenderResources(
      config: config,
      generator: generator,
      colorScheme: colorScheme,
      searchBuilder: searchBuilder,
    );
  }
}
