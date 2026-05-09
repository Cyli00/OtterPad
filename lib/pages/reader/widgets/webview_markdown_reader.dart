import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;

import '../../../data/models/book/highlight.dart';
import '../../../providers/reader_settings_provider.dart';
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
  File? _htmlFile;

  String get _htmlFilePath =>
      p.join(widget.documentDir, '.otterpad_reader.html');

  @override
  void initState() {
    super.initState();
    _writeHtmlFile();
  }

  @override
  void dispose() {
    _cleanupHtmlFile();
    super.dispose();
  }

  void _writeHtmlFile() {
    final html = _buildHtml();
    final file = File(_htmlFilePath);
    file.writeAsStringSync(html);
    _htmlFile = file;
  }

  void _cleanupHtmlFile() {
    try {
      _htmlFile?.deleteSync();
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant WebViewMarkdownReader oldWidget) {
    super.didUpdateWidget(oldWidget);

    final dataChanged = widget.markdownData != oldWidget.markdownData;
    final themeChanged = widget.palette != oldWidget.palette ||
        widget.settings.fontSize != oldWidget.settings.fontSize ||
        widget.settings.font != oldWidget.settings.font ||
        widget.settings.theme != oldWidget.settings.theme;

    if (dataChanged || themeChanged) {
      _reloadContent();
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
    final uri = Uri.file(_htmlFilePath).toString();
    _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(uri)));
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

  void _restoreAllHighlights() {
    for (final hl in widget.highlights) {
      _addHighlightToWebView(hl);
    }
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
      documentDir: widget.documentDir,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fileUri = Uri.file(_htmlFilePath).toString();

    return InAppWebView(
      key: _webViewKey,
      initialUrlRequest: URLRequest(url: WebUri(fileUri)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: false,
        disableContextMenu: true,
        supportZoom: false,
        disableHorizontalScroll: true,
        verticalScrollBarEnabled: true,
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: true,
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
