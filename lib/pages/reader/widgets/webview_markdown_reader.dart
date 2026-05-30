import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;

import '../../../data/models/book/highlight.dart';
import '../../../providers/reader_settings_provider.dart';
import '../../../services/reader_localhost_server.dart';
import 'reader_background.dart';
import 'reader_js_bridge.dart';
import 'reader_update_plan.dart';
import 'webview_reader_html.dart';

class WebViewMarkdownReader extends StatefulWidget {
  final String markdownData;
  final ReaderSettingsState settings;
  final ReaderPalette palette;
  final List<Highlight> highlights;
  final String documentDir;
  final double topInset;
  final double bottomInset;

  final String translationStyleId;
  final double initialScrollProgress;
  final String? highlightQuery;

  final void Function(String text, Rect selectionRect)? onSelectionEnd;
  final VoidCallback? onSelectionCleared;
  final void Function(Highlight highlight, Offset position)? onHighlightClick;
  final void Function(String imageSource)? onImageClick;
  final void Function(ScrollDirection direction)? onScrollDirection;

  /// 阅读进度上报（0.0–1.0）。WebView JS 侧已做 500ms 节流。
  final void Function(double progress)? onScrollProgress;

  /// 横向翻页模式下点击页面中央触发——view 层据此 toggle 沉浸式工具栏。
  /// vertical 模式下不会被调（JS 侧已 mode 短路）。
  final VoidCallback? onToggleToolbar;

  const WebViewMarkdownReader({
    super.key,
    required this.markdownData,
    required this.settings,
    required this.palette,
    this.highlights = const [],
    required this.documentDir,
    this.translationStyleId = 'themed',
    this.initialScrollProgress = 0,
    this.topInset = 0,
    this.bottomInset = 0,
    this.highlightQuery,
    this.onSelectionEnd,
    this.onSelectionCleared,
    this.onHighlightClick,
    this.onImageClick,
    this.onScrollDirection,
    this.onScrollProgress,
    this.onToggleToolbar,
  });

  @override
  WebViewMarkdownReaderState createState() => WebViewMarkdownReaderState();
}

class WebViewMarkdownReaderState extends State<WebViewMarkdownReader>
    implements ReaderJsBridgeListener {
  ReaderJsBridge? _bridge;
  final _webViewKey = GlobalKey();

  // 覆盖滚动条状态：JS rAF 通道更新 metrics；UI 在 1.5s idle 后淡出。
  // _scrollbarVisible 通过 setState 直接驱动 AnimatedOpacity，不放 ValueNotifier
  // 里——metrics 是高频更新（rAF），visible 是低频两态（show/hide），分开走避免
  // 把整个 thumb 重建塞进每帧。
  final ValueNotifier<ReaderScrollMetrics> _scrollMetrics = ValueNotifier(
    const ReaderScrollMetrics(progress: 0, viewportRatio: 1),
  );
  bool _scrollbarVisible = false;
  Timer? _scrollbarHideTimer;
  bool _scrollbarPointerActive = false;

  /// 用户在 WebView 内通过文本选择创建的高亮 id 集合——JS 已直接画 SVG，
  /// 下一次 syncHighlights 不应再添加，否则重复绘制。bridge.syncHighlights
  /// 接受 skipNewIds 参数，这里维护它的来源。
  final _selectionHighlightIds = <String>{};

  /// HTML 写到文献目录内 `<documentDir>/.reader.html`：
  /// - **自包含**：HTML 缓存随文献目录一起被备份/恢复/删除，无需单独清理；
  ///   旧方案放在 `<dataDir>/._readers/<docKey>.html` 时是孤立文件，删文献
  ///   时容易漏（DocCardActions.delete 没显式清理它）；
  /// - `.reader.html` 的 `.` 前缀让 macOS Finder / iOS Files App 默认隐藏；
  /// - server root 在 OtterPad/ 下，URL 形如
  ///   `http://localhost:PORT/library/<documentId>/.reader.html`，与同目录内的
  ///   `figures/Figure_*.png` 共 origin、共 base href，相对路径解析自然。
  String get _htmlFilePath => p.join(widget.documentDir, '.reader.html');

  /// docDir 相对 server root 的子路径（如 `library/<documentId>`），写入 HTML 的
  /// `base href` 标签后，相对图片路径仍能解析到 `library/<documentId>/figures/...`。
  /// 注：URL 用 forward slash，Windows 反斜杠路径需转换。
  String get _docBaseHref {
    final root = ReaderLocalhostServer.instance.root;
    final rel = p.relative(widget.documentDir, from: root);
    final segments = rel
        .split(RegExp(r'[/\\]'))
        .map(Uri.encodeComponent)
        .join('/');
    return '/$segments/';
  }

  @override
  void initState() {
    super.initState();
    _writeHtmlFileSync();
  }

  @override
  void dispose() {
    _scrollbarHideTimer?.cancel();
    _scrollMetrics.dispose();
    super.dispose();
  }

  // dispose 不再清理 HTML——`.reader.html` 在文献目录内，随文献删除一起走。
  // 留着的好处：用户从阅读器返回后再次进入同一文献，HTML 能被复用（虽然
  // initState 总会重写一次，但避免了"删→写→删→写"的瞬时 IO 抖动）；
  // 留下的代价仅几十 KB 磁盘占用，可忽略。

  /// 覆盖滚动条可见性：每次新事件重置 1.5s 淡出计时器。
  /// 用户在 thumb 上按住期间（[_scrollbarPointerActive]）也保持可见。
  void _showScrollbarTransiently() {
    if (!_scrollbarVisible) {
      setState(() => _scrollbarVisible = true);
    }
    _scrollbarHideTimer?.cancel();
    _scrollbarHideTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      if (_scrollbarPointerActive) return;
      setState(() => _scrollbarVisible = false);
    });
  }

  /// Flutter 拖动覆盖条 → JS scrollTo。ratio ∈ [0,1]。
  void _scrollToRatio(double ratio) => _bridge?.scrollToRatio(ratio);

  void _writeHtmlFileSync() {
    final html = _buildHtml();
    final file = File(_htmlFilePath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(html);
  }

  Future<void> _writeHtmlFile() async {
    final html = _buildHtml();
    final file = File(_htmlFilePath);
    await file.parent.create(recursive: true);
    await file.writeAsString(html);
  }

  @override
  void didUpdateWidget(covariant WebViewMarkdownReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    // "什么变了 → 该做什么"由纯函数 planUpdates 决定（可无 mock 单测）；
    // 这里只负责把每个动作落到 bridge / 实例态上。
    for (final update in planUpdates(_propsOf(oldWidget), _propsOf(widget))) {
      _applyUpdate(update);
    }
  }

  ReaderProps _propsOf(WebViewMarkdownReader w) => ReaderProps(
    markdownData: w.markdownData,
    palette: w.palette,
    settings: w.settings,
    translationStyleId: w.translationStyleId,
    highlights: w.highlights,
    highlightQuery: w.highlightQuery,
  );

  void _applyUpdate(ReaderUpdate update) {
    switch (update) {
      case ReloadContent():
        _reloadContent();
      case ApplyTheme(:final palette, :final settings):
        _bridge?.applyTheme(palette, settings);
      case ApplyPagination(:final mode):
        _bridge?.applyPagination(mode);
      case ApplyTranslationStyle(:final styleId):
        _bridge?.applyTranslationStyle(styleId);
      case SyncHighlights(:final oldHighlights, :final newHighlights):
        _bridge?.syncHighlights(
          oldHighlights,
          newHighlights,
          skipNewIds: _selectionHighlightIds,
        );
        // syncHighlights 已消费过的 selection id 从集合里移除（避免无界增长）。
        _selectionHighlightIds.removeWhere(
          (id) => newHighlights.any((h) => h.id == id),
        );
      case ApplySearchQuery(:final query):
        _bridge?.applySearchQuery(query);
    }
  }

  void _reloadContent() {
    _writeHtmlFile().then((_) {
      if (!mounted) return;
      final url = _readerUrl(cacheBust: true);
      if (url == null) {
        debugPrint(
          '[WebViewMarkdownReader] localhost server not running or '
          'document outside server root: $_htmlFilePath',
        );
        return;
      }
      _bridge?.reloadUrl(url);
    });
  }

  /// HTML 文件经 localhost server 暴露的 URL：
  /// `http://localhost:PORT/data/._readers/<docHash>.html`
  /// 同 origin 内引用的图片自动走相对路径解析，不再有 file:// 跨域问题。
  ///
  /// [cacheBust]=true 时附加 `?v=<timestamp>` query，强制 WebView 不命中缓存。
  /// 初始加载（initialUrlRequest）不需要 bust——首次加载没有缓存可命中。
  String? _readerUrl({bool cacheBust = false}) {
    final base = ReaderLocalhostServer.instance.urlForPath(_htmlFilePath);
    if (base == null || !cacheBust) return base;
    return '$base?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  // ─── 对外暴露的方法（通过 GlobalKey 调用） ───
  // 都是单行转发到 bridge——bridge 字段未初始化时（WebView 未 ready）静默跳过。

  void scrollToBlockIndex(int index) => _bridge?.scrollToBlock(index);

  void scrollToSearchResult(int index) => _bridge?.scrollToSearchResult(index);

  void activateNearestSearchResult() => _bridge?.activateNearestSearchResult();

  void flashImage(String filename) => _bridge?.flashImage(filename);

  void addHighlightFromSelection(String id, String color) {
    _selectionHighlightIds.add(id);
    _bridge?.addHighlightFromSelection(id, color);
  }

  /// 暂停背景 WebView——前景弹出 sheet/dialog 时调用，释放 CPU/GPU。
  /// 必须配对 [resumeWebView] 调用，否则恢复后 WebView 静止。
  void pauseWebView() => _bridge?.pauseTimers();

  void resumeWebView() => _bridge?.resumeTimers();

  // ─── 坐标转换 ───

  Rect _normalizedToScreen(Map<String, dynamic> data) {
    final box = _webViewKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return Rect.zero;

    final size = box.size;
    final offset = box.localToGlobal(Offset.zero);

    return Rect.fromLTRB(
      (data['left'] as num).toDouble() * size.width + offset.dx,
      (data['top'] as num).toDouble() * size.height + offset.dy,
      (data['right'] as num).toDouble() * size.width + offset.dx,
      (data['bottom'] as num).toDouble() * size.height + offset.dy,
    );
  }

  Offset _normalizedToOffset(Map<String, dynamic> data) {
    final box = _webViewKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;

    final size = box.size;
    final offset = box.localToGlobal(Offset.zero);

    return Offset(
      (data['x'] as num).toDouble() * size.width + offset.dx,
      (data['y'] as num).toDouble() * size.height + offset.dy,
    );
  }

  String _buildHtml() {
    return buildReaderHtml(
      markdownContent: widget.markdownData,
      palette: widget.palette,
      settings: widget.settings,
      baseHref: _docBaseHref,
      translationStyleId: widget.translationStyleId,
      imageCacheBuster: _figuresCacheBuster(),
    );
  }

  /// 用 figures.json 的 mtime 当 figure 路径的 cache buster.
  /// localhost server 给 PNG 设了 max-age=300,重新提取后同 URL 5 分钟内拿旧字节;
  /// mtime 变化时 URL 加的 `?v=` 也变,自然 cache miss → 新 PNG.
  String _figuresCacheBuster() {
    try {
      final manifest = File(
        p.join(widget.documentDir, 'figures', 'figures.json'),
      );
      if (manifest.existsSync()) {
        return manifest.lastModifiedSync().millisecondsSinceEpoch.toString();
      }
    } catch (_) {}
    return '';
  }

  @override
  Widget build(BuildContext context) {
    // 走 localhost server，所有平台同 origin 加载——
    // 不再需要 allowFileAccessFromFileURLs / allowUniversalAccessFromFileURLs。
    // server 未启动时退化到 about:blank（理论上不应发生：main.dart 启动时已 start）。
    final url = _readerUrl() ?? 'about:blank';
    final isHorizontal =
        widget.settings.paginationMode == ReaderPaginationMode.horizontal;

    final webView = InAppWebView(
      key: _webViewKey,
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: false,
        // 关掉 hybrid composition：本组件只读、无内嵌输入框，改走 texture 合成
        // 后，键盘/对话框等 Flutter 侧动画期间不再逐帧强制 WebView 重合成，
        // 消除 ART GC 抖动与掉帧。
        useHybridComposition: false,
        disableContextMenu: true,
        supportZoom: false,
        // 必须允许 WebView 横向滚动：horizontal 模式下 #content 通过
        // scrollLeft 翻页；同时 vertical 模式下也让代码块/表格的
        // overflow-x: auto 能正常工作。
        disableHorizontalScroll: false,
        // 关掉原生滚动条——本组件用 Flutter 覆盖层 [_OverlayScrollbar]
        // 接管视觉 + 拖动交互。Android 原生条 OS 层绘制，CSS 无法接管，
        // 且不可触摸拖动（仅指示器）。
        verticalScrollBarEnabled: false,
        horizontalScrollBarEnabled: false,
      ),
      onWebViewCreated: (controller) {
        _bridge = ReaderJsBridge(controller, this)..attachHandlers();
      },
    );

    // horizontal 翻页模式不需要覆盖滚动条——那边有页号 / 边缘点击翻页 UI。
    if (isHorizontal) return webView;

    return Stack(
      children: [
        webView,
        Positioned(
          top: widget.topInset,
          bottom: widget.bottomInset,
          right: 0,
          child: IgnorePointer(
            ignoring: !_scrollbarVisible,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _scrollbarVisible ? 1 : 0,
              child: _OverlayScrollbar(
                metrics: _scrollMetrics,
                onJumpTo: _scrollToRatio,
                onInteractionStart: () {
                  _scrollbarPointerActive = true;
                  _showScrollbarTransiently();
                },
                onInteractionEnd: () {
                  _scrollbarPointerActive = false;
                  _showScrollbarTransiently();
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── ReaderJsBridgeListener 实现 ───
  //
  // Bridge 把 JS 端的 9 路 handler 全部归一到这些方法。widget 自己实现，
  // 而不是再绕一层"listener 适配器"——本来 widget 就是回调的天然消费者。

  @override
  void onContentReady() {
    // 翻页方式必须在首屏注入：JS 默认 body 没 data-pagination 属性，
    // 视为 vertical；horizontal 时若不注入会以 vertical 渲染首屏，
    // 直到第一次 didUpdateWidget 才切，造成"先看到 vertical 一闪"。
    _bridge?.applyPagination(widget.settings.paginationMode);
    _bridge?.restoreAllHighlights(widget.highlights);
    _bridge?.applySearchQuery(widget.highlightQuery);
    if (widget.initialScrollProgress > 0) {
      _bridge?.restoreScrollProgress(widget.initialScrollProgress);
    }
  }

  @override
  void onSelectionEnd(String text, Map<String, dynamic> rawRect) {
    widget.onSelectionEnd?.call(text, _normalizedToScreen(rawRect));
  }

  @override
  void onSelectionCleared() => widget.onSelectionCleared?.call();

  @override
  void onHighlightClick(String highlightId, Map<String, dynamic> rawPos) {
    final hl = widget.highlights.where((h) => h.id == highlightId).firstOrNull;
    if (hl == null) return;
    widget.onHighlightClick?.call(hl, _normalizedToOffset(rawPos));
  }

  @override
  void onImageClick(String imageSource) =>
      widget.onImageClick?.call(imageSource);

  @override
  void onScrollDirection(ScrollDirection direction) =>
      widget.onScrollDirection?.call(direction);

  @override
  void onScrollProgress(double progress) =>
      widget.onScrollProgress?.call(progress);

  @override
  void onScrollMetrics(ReaderScrollMetrics metrics) {
    _scrollMetrics.value = metrics;
    _showScrollbarTransiently();
  }

  @override
  void onToggleToolbar() => widget.onToggleToolbar?.call();
}

// ─── 覆盖滚动条 ─────────────────────────────────────────────────
//
// 12px 宽柱形布局：触摸热区 12px（手指友好），thumb 视觉 6px 居中（精致）。
// 拖动时按 localPosition.dy / trackHeight 反算 ratio，调 onJumpTo。
// thumb min-height 48 防止超长文档下 thumb 缩成针线。
class _OverlayScrollbar extends StatelessWidget {
  final ValueListenable<ReaderScrollMetrics> metrics;
  final ValueChanged<double> onJumpTo;
  final VoidCallback onInteractionStart;
  final VoidCallback onInteractionEnd;

  const _OverlayScrollbar({
    required this.metrics,
    required this.onJumpTo,
    required this.onInteractionStart,
    required this.onInteractionEnd,
  });

  static const double _trackWidth = 12;
  static const double _thumbWidth = 6;
  static const double _minThumbHeight = 48;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackHeight = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            onInteractionStart();
            final ratio = (d.localPosition.dy / trackHeight).clamp(0.0, 1.0);
            onJumpTo(ratio);
          },
          onTapUp: (_) => onInteractionEnd(),
          onTapCancel: onInteractionEnd,
          onVerticalDragStart: (_) => onInteractionStart(),
          onVerticalDragUpdate: (d) {
            final ratio = (d.localPosition.dy / trackHeight).clamp(0.0, 1.0);
            onJumpTo(ratio);
          },
          onVerticalDragEnd: (_) => onInteractionEnd(),
          onVerticalDragCancel: onInteractionEnd,
          child: SizedBox(
            width: _trackWidth,
            child: ValueListenableBuilder<ReaderScrollMetrics>(
              valueListenable: metrics,
              builder: (context, m, _) {
                final thumbHeight = math.max(
                  _minThumbHeight,
                  trackHeight * m.viewportRatio,
                );
                final maxTop = math.max(0.0, trackHeight - thumbHeight);
                final thumbTop = m.progress * maxTop;
                return Stack(
                  children: [
                    Positioned(
                      top: thumbTop,
                      left: (_trackWidth - _thumbWidth) / 2,
                      width: _thumbWidth,
                      height: thumbHeight,
                      child: Container(
                        decoration: BoxDecoration(
                          color: cs.onSurfaceVariant.withAlpha(140),
                          borderRadius: BorderRadius.circular(_thumbWidth / 2),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}
