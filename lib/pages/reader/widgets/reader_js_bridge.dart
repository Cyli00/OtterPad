import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../data/models/book/highlight.dart';
import '../../../data/models/book/reader_anchor.dart';
import '../../../providers/reader_settings_provider.dart';
import '../../../utils/js_string_escape.dart';
import 'reader_background.dart';
import 'webview_reader_html.dart';

/// JS 搜索命中结果。
class SearchHit {
  final String heading;
  final String snippet;
  final int matchStart;
  final int matchLength;
  final int hitIndex;

  const SearchHit({
    required this.heading,
    required this.snippet,
    required this.matchStart,
    required this.matchLength,
    required this.hitIndex,
  });
}

/// 阅读器 WebView 滚动条度量。
class ReaderScrollMetrics {
  final double progress;
  final double viewportRatio;
  const ReaderScrollMetrics({
    required this.progress,
    required this.viewportRatio,
  });
}

/// 反向通道：JS → Dart 事件回调集合。
///
/// `WebViewMarkdownReader` 实现此接口（或转发到 widget.onXxx 回调），
/// [ReaderJsBridge] 在 `onWebViewCreated` 注册 handler 时调用对应方法。
abstract class ReaderJsBridgeListener {
  void onContentReady();
  void onSelectionEnd(String text, Map<String, dynamic> rawRect);
  void onSelectionCleared();
  void onHighlightClick(String highlightId, Map<String, dynamic> rawPos);
  void onImageClick(String imageSource);
  void onScrollDirection(ScrollDirection direction);

  /// [anchorBlock] 是视口起始处第一个可见内容块的索引（位置的内容引用），
  /// 横向翻页恢复时优先于比率；JS 侧无法定位时为 null。
  void onScrollProgress(double progress, int? anchorBlock);
  void onReadingParagraph(String? paragraphId);
  void onScrollMetrics(ReaderScrollMetrics metrics);
  void onToggleToolbar();

  /// 横向模式边缘点击成功翻页——Flutter 侧触发 Haptics.light()。
  void onPageFlip();
}

/// 阅读器 WebView 桥——所有 Dart → JS 调用的单一入口。
///
/// 把 15 处散落的 evaluateJavascript 字符串拼接 + 转义收敛到一处；
/// JS handler 注册也集中在 [attachHandlers]。widget 只看到"动词"接口
/// （applyTheme / syncHighlights / scrollToBlock…），不再关心 JS 字符串格式。
///
/// 生命周期：widget 在 `onWebViewCreated` 实例化 bridge 并立即调用
/// [attachHandlers]。bridge 不可重用——controller 失效后丢弃。
class ReaderJsBridge {
  final InAppWebViewController _controller;
  final ReaderJsBridgeListener _listener;
  bool _contentReady = false;

  ReaderJsBridge(this._controller, this._listener);

  static String _jsLiteral(String s) => escapeJsLiteral(s);

  /// 注册所有 10 个 JS → Dart handler。必须在构造后立即调用。
  void attachHandlers() {
    _controller.addJavaScriptHandler(
      handlerName: 'onContentReady',
      callback: (_) {
        _contentReady = true;
        _listener.onContentReady();
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onSelectionEnd',
      callback: (args) {
        if (args.isEmpty) return;
        final data = args[0] as Map<String, dynamic>;
        final text = data['text'] as String? ?? '';
        if (text.isEmpty) return;
        _listener.onSelectionEnd(text, data);
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onSelectionCleared',
      callback: (_) => _listener.onSelectionCleared(),
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onHighlightClick',
      callback: (args) {
        if (args.isEmpty) return;
        final data = args[0] as Map<String, dynamic>;
        final id = data['id'] as String? ?? '';
        if (id.isEmpty) return;
        _listener.onHighlightClick(id, data);
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onImageClick',
      callback: (args) {
        if (args.isEmpty) return;
        final data = args[0] as Map<String, dynamic>;
        final src = data['src'] as String? ?? '';
        if (src.isNotEmpty) _listener.onImageClick(src);
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onScrollDirection',
      callback: (args) {
        if (args.isEmpty) return;
        final data = args[0] as Map<String, dynamic>;
        final dir = data['direction'] as String? ?? '';
        if (dir == 'down') {
          _listener.onScrollDirection(ScrollDirection.reverse);
        } else if (dir == 'up') {
          _listener.onScrollDirection(ScrollDirection.forward);
        }
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onScrollProgress',
      callback: (args) {
        if (args.isEmpty) return;
        final data = args[0] as Map<String, dynamic>;
        final raw = data['progress'];
        if (raw is num) {
          final anchor = data['anchorBlock'];
          _listener.onReadingParagraph(data['paragraphId'] as String?);
          _listener.onScrollProgress(
            raw.toDouble().clamp(0.0, 1.0),
            anchor is num && anchor >= 0 ? anchor.toInt() : null,
          );
        }
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onScrollMetrics',
      callback: (args) {
        if (args.isEmpty) return;
        final data = args[0] as Map<String, dynamic>;
        final progress = (data['progress'] as num?)?.toDouble() ?? 0;
        final viewportRatio = (data['viewportRatio'] as num?)?.toDouble() ?? 1;
        _listener.onScrollMetrics(
          ReaderScrollMetrics(
            progress: progress.clamp(0.0, 1.0),
            viewportRatio: viewportRatio.clamp(0.05, 1.0),
          ),
        );
      },
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onToggleToolbar',
      callback: (_) => _listener.onToggleToolbar(),
    );

    _controller.addJavaScriptHandler(
      handlerName: 'onPageFlip',
      callback: (_) => _listener.onPageFlip(),
    );
  }

  // ─── Dart → JS：内容相关 ───

  void reloadUrl(String url) {
    _contentReady = false;
    _controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  // ─── 后台资源调度 ───

  void applyViewportWidth(double width) {
    if (!_contentReady || !width.isFinite || width <= 0) return;
    _controller.evaluateJavascript(
      source: 'window.readerSetViewportWidth?.($width)',
    );
  }

  /// 暂停 WebView 内所有 JS timer / 动画 / 媒体——sheet 或 dialog 弹出
  /// 期间调用，释放 CPU 让前景 Flutter UI（IME 动画、TextField）流畅。
  /// 必须配对 [resumeTimers]，否则恢复后 WebView 无响应。
  void pauseTimers() => _controller.pauseTimers();

  void resumeTimers() => _controller.resumeTimers();

  /// 暂停 WebView 的原生绘制（Android `WebView.onPause()`）——比 [pauseTimers]
  /// 更进一步：让 WebView 的 chromium compositor 停转、Surface 冻结成静态帧。
  /// HC 模式下键盘 insets 动画期间，Flutter compositor 不再每帧同步活跃 Surface，
  /// 是消除「编辑笔记弹键盘卡顿」的关键。必须配对 [resumeRendering]。
  void pauseRendering() => _controller.pause();

  void resumeRendering() => _controller.resume();

  /// 截取 WebView 当前可见帧——[WebViewMarkdownReaderState.freeze] 用作占位图，
  /// 在原生 View detach 期间保持画面连续，避免「内容突变成空白」的闪烁。
  Future<Uint8List?> takeScreenshot() => _controller.takeScreenshot();

  // ─── Dart → JS：主题/字体/翻页/翻译样式 ───

  /// 增量更新 palette + 字体相关 CSS 变量——直接 setProperty 改 :root vars。
  /// 浏览器只对受 var(--xxx) 影响的属性重排，零页面重载。
  void applyBilingualLayout(bool enabled) {
    if (!_contentReady) return;
    _controller.evaluateJavascript(
      source: 'window.setBilingualLayout($enabled);',
    );
  }

  void applyDesktopMode(bool desktop) {
    if (!_contentReady) return;
    _controller.evaluateJavascript(
      source: "document.body.dataset.desktop = '$desktop';",
    );
  }

  void applyTheme(ReaderPalette palette, ReaderSettingsState settings) {
    if (!_contentReady) return;
    _controller.evaluateJavascript(
      source: buildThemeCssVars(palette, settings),
    );
  }

  /// 翻页方式增量切换：仅改 body[data-pagination]，JS 侧 setPaginationMode
  /// 内部触发 Overlayer.redraw() + 重发 scroll 让 lazy 图重新评估。
  void applyPagination(ReaderPaginationMode mode) {
    if (!_contentReady) return;
    _controller.evaluateJavascript(
      source: "window.setPaginationMode('${mode.jsId}')",
    );
  }

  void applyTranslationStyle(String styleId) {
    if (!_contentReady) return;
    _controller.evaluateJavascript(
      source: "window.setTranslationStyle('$styleId')",
    );
  }

  void applyTranslations(List<Map<String, dynamic>> entries) {
    if (!_contentReady || entries.isEmpty) return;
    final payload = base64Encode(utf8.encode(jsonEncode(entries)));
    _controller.evaluateJavascript(
      source: "window.applyReaderTranslations('$payload');",
    );
  }

  void holdTranslations(bool value) {
    if (!_contentReady) return;
    _controller.evaluateJavascript(
      source: 'window.holdReaderTranslations($value);',
    );
  }

  /// `--top-inset` 重放：缓存命中的 `.reader.html` 烤的是生成时的工具栏
  /// 高度，跨设备/横竖屏可能过期；ready 时用当前值覆写一次（top-inset
  /// 不进缓存指纹的代价）。
  void applyTopInset(double topInset) {
    if (!_contentReady) return;
    _controller.evaluateJavascript(
      source:
          "document.documentElement.style.setProperty('--top-inset', '${topInset}px')",
    );
  }

  void applyBottomInset(double bottomInset) {
    if (!_contentReady) return;
    _controller.evaluateJavascript(
      source:
          "document.documentElement.style.setProperty('--bottom-inset', '${bottomInset}px')",
    );
  }

  // ─── Dart → JS：搜索 ───

  void applySearchQuery(String? query) {
    if (!_contentReady) return;
    if (query == null || query.isEmpty) {
      _controller.evaluateJavascript(source: 'window.clearSearchHighlight()');
    } else {
      _controller.evaluateJavascript(
        source: "window.highlightSearch('${_jsLiteral(query)}', false, false)",
      );
    }
  }

  Future<List<SearchHit>> searchContent(
    String query, {
    bool caseSensitive = false,
    bool wholeWord = false,
  }) async {
    if (!_contentReady || query.isEmpty) return const [];
    final raw = await _controller.evaluateJavascript(
      source:
          "window.highlightSearch('${_jsLiteral(query)}', $caseSensitive, $wholeWord)",
    );
    if (raw == null) return const [];
    final json = jsonDecode(raw is String ? raw : raw.toString());
    final list = json['results'] as List<dynamic>;
    return [
      for (var i = 0; i < list.length; i++)
        SearchHit(
          heading: (list[i]['heading'] as String?) ?? '',
          snippet: (list[i]['snippet'] as String?) ?? '',
          matchStart: (list[i]['matchStart'] as num?)?.toInt() ?? 0,
          matchLength: (list[i]['matchLength'] as num?)?.toInt() ?? 0,
          hitIndex: i,
        ),
    ];
  }

  // ─── Dart → JS：选区 ───

  /// 清除 WebView 内的文本选区。原生选择手柄绘制在独立的系统窗口层、
  /// 永远浮在 Flutter 之上——弹 dialog 前必须清掉，否则手柄"穿透"对话框。
  void clearSelection() {
    _controller.evaluateJavascript(source: 'window.clearSelection()');
  }

  // ─── Dart → JS：滚动/跳转 ───

  void scrollToRatio(double ratio) {
    final r = ratio.clamp(0.0, 1.0);
    _controller.evaluateJavascript(source: 'window._scrollToRatio($r)');
  }

  void scrollToBlock(int index) {
    _controller.evaluateJavascript(source: 'window.scrollToBlock($index)');
  }

  Future<bool> locateQuote(
    String quote, {
    ReaderAnchor? anchor,
    String? figureName,
  }) async =>
      await _controller.evaluateJavascript(
        source:
            'window.readerLocateQuote(${jsonEncode({'quote': quote, 'anchor': anchor?.toJson(), 'figureName': figureName})})',
      ) ==
      true;

  Future<bool> scrollToParagraph(String id) async =>
      await _controller.evaluateJavascript(
        source: 'window.readerScrollToParagraph(${jsonEncode(id)})',
      ) ==
      true;

  void scrollToFigure(String id) {
    _controller.evaluateJavascript(
      source: "window.scrollToFigure('${_jsLiteral(id)}')",
    );
  }

  void scrollToSearchResult(int index) {
    _controller.evaluateJavascript(
      source: 'window.scrollToSearchResult($index)',
    );
  }

  /// [anchorBlock] 优先于比率（见 JS `_restoreProgress`）；null = 仅按比率。
  /// 返回 Future——widget 的揭幕幕布等 JS 执行完再淡出，避免露出跳变。
  Future<void> restoreScrollProgress(double progress, {int? anchorBlock}) {
    return _controller.evaluateJavascript(
      source: 'window._restoreProgress($progress, ${anchorBlock ?? 'null'})',
    );
  }

  // ─── Dart → JS：图片闪烁 ───

  void flashImage(String filename) {
    _controller.evaluateJavascript(
      source: "window.flashImage('${_jsLiteral(filename)}')",
    );
  }

  // ─── Dart → JS：高亮 ───

  /// 批量恢复所有高亮——一次 IPC + JS 端共享一次 walker 扫描。
  ///
  /// 旧实现是逐个 addHighlight → N 次 evaluateJavascript + N 次完整
  /// TreeWalker 扫描。N=50 高亮在长文献上明显卡。JSON 用 base64 包裹避开
  /// "嵌入 JS 单引号字符串需要逐字符 escape"的坑——高亮文本含换行/反斜杠
  /// /引号都不会破坏 source。
  void restoreAllHighlights(List<Highlight> highlights) {
    if (highlights.isEmpty) return;
    final payload = highlights
        .map(
          (h) => {
            'id': h.id,
            'text': h.text,
            'color': h.color,
            'anchor': h.anchor?.toJson(),
          },
        )
        .toList();
    final encoded = base64Encode(utf8.encode(jsonEncode(payload)));
    _controller.evaluateJavascript(
      source: "window.addHighlightsBatch('$encoded')",
    );
  }

  /// 把 [oldList] → [newList] 的差异同步到 WebView。
  ///
  /// 调用方传入 [skipNewIds]：这些 id 是"用户在 WebView 内通过选择新建"的
  /// 高亮，JS 端已经直接画了 SVG（走 addHighlightFromSelection 路径），
  /// 不需要再次添加；否则会重复绘制。
  void syncHighlights(
    List<Highlight> oldList,
    List<Highlight> newList, {
    Set<String> skipNewIds = const {},
  }) {
    if (!_contentReady) return;
    final oldMap = {for (final h in oldList) h.id: h};
    final newMap = {for (final h in newList) h.id: h};

    final remove = <String>[];
    final add = <Map<String, dynamic>>[];
    final updateColor = <Map<String, String>>[];

    for (final id in oldMap.keys) {
      if (!newMap.containsKey(id)) remove.add(id);
    }
    for (final hl in newList) {
      if (!oldMap.containsKey(hl.id)) {
        if (skipNewIds.contains(hl.id)) continue;
        add.add({
          'id': hl.id,
          'text': hl.text,
          'color': hl.color,
          'anchor': hl.anchor?.toJson(),
        });
      } else if (oldMap[hl.id]!.color != hl.color) {
        updateColor.add({'id': hl.id, 'color': hl.color});
      }
    }

    if (remove.isEmpty && add.isEmpty && updateColor.isEmpty) return;

    final payload = <String, dynamic>{};
    if (remove.isNotEmpty) payload['remove'] = remove;
    if (add.isNotEmpty) payload['add'] = add;
    if (updateColor.isNotEmpty) payload['updateColor'] = updateColor;
    final encoded = base64Encode(utf8.encode(jsonEncode(payload)));
    _controller.evaluateJavascript(
      source: "window.syncHighlightsBatch('$encoded')",
    );
  }

  /// 用户在 WebView 内通过文本选择创建的高亮——JS 直接用 selection range
  /// 画 SVG，无需文本搜索。
  void addHighlightFromSelection(String id, String color) {
    _controller.evaluateJavascript(
      source: "window.addHighlightFromSelection('$id','$color')",
    );
  }
}
