import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;

import '../../../data/models/book/highlight.dart';
import '../../../providers/reader_settings_provider.dart';
import '../../../services/reader_localhost_server.dart';
import 'reader_background.dart';
import 'webview_reader_html.dart';

class WebViewMarkdownReader extends StatefulWidget {
  final String markdownData;
  final ReaderSettingsState settings;
  final ReaderPalette palette;
  final List<Highlight> highlights;
  final String documentDir;
  final double topInset;
  final double bottomInset;

  final String? highlightQuery;

  final void Function(String text, Rect selectionRect)? onSelectionEnd;
  final VoidCallback? onSelectionCleared;
  final void Function(Highlight highlight, Offset position)?
      onHighlightClick;
  final void Function(String imageSource)? onImageClick;
  final void Function(ScrollDirection direction)? onScrollDirection;

  const WebViewMarkdownReader({
    super.key,
    required this.markdownData,
    required this.settings,
    required this.palette,
    this.highlights = const [],
    required this.documentDir,
    this.topInset = 0,
    this.bottomInset = 0,
    this.highlightQuery,
    this.onSelectionEnd,
    this.onSelectionCleared,
    this.onHighlightClick,
    this.onImageClick,
    this.onScrollDirection,
  });

  @override
  WebViewMarkdownReaderState createState() => WebViewMarkdownReaderState();
}

class WebViewMarkdownReaderState extends State<WebViewMarkdownReader> {
  InAppWebViewController? _controller;
  bool _contentReady = false;
  final _webViewKey = GlobalKey();

  /// HTML 写到文献目录内 `<documentDir>/.reader.html`：
  /// - **自包含**：HTML 缓存随文献目录一起被备份/恢复/删除，无需单独清理；
  ///   旧方案放在 `<dataDir>/._readers/<docKey>.html` 时是孤立文件，删文献
  ///   时容易漏（DocCardActions.delete 没显式清理它）；
  /// - `.reader.html` 的 `.` 前缀让 macOS Finder / iOS Files App 默认隐藏；
  /// - server root 在 OtterPad/ 下，URL 形如
  ///   `http://localhost:PORT/library/<hash>/.reader.html`，与同目录内的
  ///   `figures/Figure_*.png` 共 origin、共 base href，相对路径解析自然。
  String get _htmlFilePath =>
      p.join(widget.documentDir, '.reader.html');

  /// docDir 相对 server root 的子路径（如 `docs/abc123`），写入 HTML 的
  /// `base href` 标签后，相对图片路径仍能解析到 `docs/{hash}/figures/...`。
  /// 注：URL 用 forward slash，Windows 反斜杠路径需转换。
  String get _docBaseHref {
    final root = ReaderLocalhostServer.instance.root;
    final rel = p.relative(widget.documentDir, from: root);
    final segments =
        rel.split(RegExp(r'[/\\]')).map(Uri.encodeComponent).join('/');
    return '/$segments/';
  }

  @override
  void initState() {
    super.initState();
    _writeHtmlFile();
  }

  // dispose 不再清理 HTML——`.reader.html` 在文献目录内，随文献删除一起走。
  // 留着的好处：用户从阅读器返回后再次进入同一文献，HTML 能被复用（虽然
  // initState 总会重写一次，但避免了"删→写→删→写"的瞬时 IO 抖动）；
  // 留下的代价仅几十 KB 磁盘占用，可忽略。

  void _writeHtmlFile() {
    final html = _buildHtml();
    final file = File(_htmlFilePath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(html);
  }

  @override
  void didUpdateWidget(covariant WebViewMarkdownReader oldWidget) {
    super.didUpdateWidget(oldWidget);

    final dataChanged = widget.markdownData != oldWidget.markdownData;
    final themeChanged = widget.palette != oldWidget.palette ||
        widget.settings.fontSize != oldWidget.settings.fontSize ||
        widget.settings.font != oldWidget.settings.font ||
        widget.settings.theme != oldWidget.settings.theme;

    // 数据变化必须重写 HTML + reload —— DOM 内容不在 CSS 变量控制范围。
    // 主题/字号/字体单独变 → 仅写 CSS 变量，**不销毁** DOM/KaTeX 渲染缓存/
    // 已绘制的 SVG 高亮——这是性能上最大的修正：之前任何主题切换都触发完整
    // 重载，包括 KaTeX CDN 重新加载、所有图片重新下载、所有高亮 redraw。
    if (dataChanged) {
      _reloadContent();
    } else if (themeChanged) {
      _applyTheme();
    }

    if (!dataChanged && widget.highlights != oldWidget.highlights) {
      _syncHighlights(oldWidget.highlights, widget.highlights);
    }

    if (widget.highlightQuery != oldWidget.highlightQuery) {
      _applySearchHighlight();
    }
  }

  void _reloadContent() {
    _contentReady = false;
    _writeHtmlFile();
    // **重要**：reload 必须用带 cache-buster 的 URL。
    // server 已经对 .html 设了 `Cache-Control: no-store`，但部分 WebView
    // 实现（Android System WebView 旧版、WebView2 在某些 IE compatibility
    // 模式下）会忽略 no-store 仍走内部缓存——加 query 让 URL 字符串变化，
    // 是绕过任何 WebView 缓存最稳的兜底。query 不影响 server 路径解析
    // （`_serveFile` 只看 `req.uri.path`，不看 query）。
    final url = _readerUrl(cacheBust: true);
    if (url == null) {
      debugPrint(
        '[WebViewMarkdownReader] localhost server not running or '
        'document outside server root: $_htmlFilePath',
      );
      return;
    }
    _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
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

  /// 主题/字号/字体增量更新——直接 setProperty 改 CSS 变量。
  /// 浏览器只对受 var(--xxx) 影响的属性重排，零页面重载。
  void _applyTheme() {
    if (!_contentReady || _controller == null) return;
    _controller!.evaluateJavascript(
      source: buildThemeCssVars(widget.palette, widget.settings),
    );
  }

  void _applySearchHighlight() {
    if (!_contentReady || _controller == null) return;
    final q = widget.highlightQuery;
    if (q == null || q.isEmpty) {
      _controller!.evaluateJavascript(
          source: 'window.clearSearchHighlight()');
    } else {
      final escaped = q.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
      _controller!.evaluateJavascript(
          source: "window.highlightSearch('$escaped')");
    }
  }

  // ─── 对外暴露的方法（通过 GlobalKey 调用） ───

  void scrollToBlockIndex(int index) {
    _controller?.evaluateJavascript(
      source: 'window.scrollToBlock($index)',
    );
  }

  void scrollToSearchResult(int index) {
    _controller?.evaluateJavascript(
      source: 'window.scrollToSearchResult($index)',
    );
  }

  void activateNearestSearchResult() {
    _controller?.evaluateJavascript(
      source: 'window.activateNearestSearchResult()',
    );
  }

  void flashImage(String filename) {
    final escaped = filename.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
    _controller?.evaluateJavascript(
      source: "window.flashImage('$escaped')",
    );
  }

  // ─── 高亮同步 ───

  void _syncHighlights(List<Highlight> oldList, List<Highlight> newList) {
    if (!_contentReady || _controller == null) return;

    final oldIds = oldList.map((h) => h.id).toSet();
    final newIds = newList.map((h) => h.id).toSet();

    for (final id in oldIds.difference(newIds)) {
      _controller!.evaluateJavascript(
        source: "window.removeHighlight('$id')",
      );
    }

    for (final hl in newList) {
      if (!oldIds.contains(hl.id)) {
        if (_selectionHighlightIds.remove(hl.id)) continue;
        _addHighlightToWebView(hl);
      } else {
        final old = oldList.firstWhere((h) => h.id == hl.id);
        if (old.color != hl.color) {
          _controller!.evaluateJavascript(
            source:
                "window.updateHighlightColor('${hl.id}','${hl.color}')",
          );
        }
      }
    }
  }

  void _addHighlightToWebView(Highlight hl) {
    final escapedText = hl.text
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '');
    _controller?.evaluateJavascript(
      source:
          "window.addHighlight('${hl.id}','$escapedText','${hl.color}')",
    );
  }

  /// 批量恢复所有高亮——一次 IPC + JS 端共享一次 walker 扫描。
  ///
  /// 旧实现是逐个 [_addHighlightToWebView] → N 次 evaluateJavascript +
  /// N 次完整 TreeWalker 扫描（每条都从头扫）。N=50 高亮在长文献上明显卡。
  /// JSON 用 base64 包裹避开"嵌入 JS 单引号字符串需要逐字符 escape"的坑——
  /// `highlight.text` 含换行/反斜杠/引号都不会破坏 source。
  void _restoreAllHighlights() {
    if (widget.highlights.isEmpty) return;
    final payload = widget.highlights
        .map((h) => {'id': h.id, 'text': h.text, 'color': h.color})
        .toList();
    final encoded = base64Encode(utf8.encode(jsonEncode(payload)));
    _controller?.evaluateJavascript(
      source: "window.addHighlightsBatch('$encoded')",
    );
  }

  final _selectionHighlightIds = <String>{};

  void addHighlightFromSelection(String id, String color) {
    _selectionHighlightIds.add(id);
    _controller?.evaluateJavascript(
      source: "window.addHighlightFromSelection('$id','$color')",
    );
  }

  // ─── 坐标转换 ───

  Rect _normalizedToScreen(Map<String, dynamic> data) {
    final box =
        _webViewKey.currentContext?.findRenderObject() as RenderBox?;
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
    final box =
        _webViewKey.currentContext?.findRenderObject() as RenderBox?;
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
    );
  }

  @override
  Widget build(BuildContext context) {
    // 走 localhost server，所有平台同 origin 加载——
    // 不再需要 allowFileAccessFromFileURLs / allowUniversalAccessFromFileURLs。
    // server 未启动时退化到 about:blank（理论上不应发生：main.dart 启动时已 start）。
    final url = _readerUrl() ?? 'about:blank';

    return InAppWebView(
      key: _webViewKey,
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: false,
        disableContextMenu: true,
        supportZoom: false,
        disableHorizontalScroll: true,
        verticalScrollBarEnabled: true,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;

        controller.addJavaScriptHandler(
          handlerName: 'onContentReady',
          callback: (_) {
            _contentReady = true;
            _restoreAllHighlights();
            _applySearchHighlight();
          },
        );

        controller.addJavaScriptHandler(
          handlerName: 'onSelectionEnd',
          callback: (args) {
            if (args.isEmpty) return;
            final data = args[0] as Map<String, dynamic>;
            final text = data['text'] as String? ?? '';
            if (text.isEmpty) return;
            final rect = _normalizedToScreen(data);
            widget.onSelectionEnd?.call(text, rect);
          },
        );

        controller.addJavaScriptHandler(
          handlerName: 'onSelectionCleared',
          callback: (_) => widget.onSelectionCleared?.call(),
        );

        controller.addJavaScriptHandler(
          handlerName: 'onHighlightClick',
          callback: (args) {
            if (args.isEmpty) return;
            final data = args[0] as Map<String, dynamic>;
            final id = data['id'] as String? ?? '';
            if (id.isEmpty) return;
            final hl = widget.highlights
                .where((h) => h.id == id)
                .firstOrNull;
            if (hl == null) return;
            final pos = _normalizedToOffset(data);
            widget.onHighlightClick?.call(hl, pos);
          },
        );

        controller.addJavaScriptHandler(
          handlerName: 'onImageClick',
          callback: (args) {
            if (args.isEmpty) return;
            final data = args[0] as Map<String, dynamic>;
            final src = data['src'] as String? ?? '';
            if (src.isNotEmpty) widget.onImageClick?.call(src);
          },
        );

        controller.addJavaScriptHandler(
          handlerName: 'onScrollDirection',
          callback: (args) {
            if (args.isEmpty) return;
            final data = args[0] as Map<String, dynamic>;
            final dir = data['direction'] as String? ?? '';
            if (dir == 'down') {
              widget.onScrollDirection?.call(ScrollDirection.reverse);
            } else if (dir == 'up') {
              widget.onScrollDirection?.call(ScrollDirection.forward);
            }
          },
        );
      },
    );
  }
}
