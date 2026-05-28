import 'dart:convert';

import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../data/models/book/highlight.dart';
import '../../../providers/reader_settings_provider.dart';
import 'reader_background.dart';
import 'webview_reader_html.dart';

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
  void onScrollProgress(double progress);
  void onScrollMetrics(ReaderScrollMetrics metrics);
  void onToggleToolbar();
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

  /// 注册所有 9 个 JS → Dart handler。必须在构造后立即调用。
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
          _listener.onScrollProgress(raw.toDouble().clamp(0.0, 1.0));
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
  }

  // ─── Dart → JS：内容相关 ───

  void reloadUrl(String url) {
    _contentReady = false;
    _controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  // ─── 后台资源调度 ───

  /// 暂停 WebView 内所有 JS timer / 动画 / 媒体——sheet 或 dialog 弹出
  /// 期间调用，释放 CPU 让前景 Flutter UI（IME 动画、TextField）流畅。
  /// 必须配对 [resumeTimers]，否则恢复后 WebView 无响应。
  void pauseTimers() => _controller.pauseTimers();

  void resumeTimers() => _controller.resumeTimers();

  // ─── Dart → JS：主题/字体/翻页/翻译样式 ───

  /// 增量更新 palette + 字体相关 CSS 变量——直接 setProperty 改 :root vars。
  /// 浏览器只对受 var(--xxx) 影响的属性重排，零页面重载。
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

  // ─── Dart → JS：搜索 ───

  void applySearchQuery(String? query) {
    if (!_contentReady) return;
    if (query == null || query.isEmpty) {
      _controller.evaluateJavascript(source: 'window.clearSearchHighlight()');
    } else {
      final escaped = query.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
      _controller.evaluateJavascript(
        source: "window.highlightSearch('$escaped')",
      );
    }
  }

  // ─── Dart → JS：滚动/跳转 ───

  void scrollToRatio(double ratio) {
    final r = ratio.clamp(0.0, 1.0);
    _controller.evaluateJavascript(source: 'window._scrollToRatio($r)');
  }

  void scrollToBlock(int index) {
    _controller.evaluateJavascript(source: 'window.scrollToBlock($index)');
  }

  void scrollToSearchResult(int index) {
    _controller.evaluateJavascript(
      source: 'window.scrollToSearchResult($index)',
    );
  }

  void activateNearestSearchResult() {
    _controller.evaluateJavascript(
      source: 'window.activateNearestSearchResult()',
    );
  }

  void restoreScrollProgress(double progress) {
    _controller.evaluateJavascript(
      source: 'window._restoreProgress($progress)',
    );
  }

  // ─── Dart → JS：图片闪烁 ───

  void flashImage(String filename) {
    final escaped = filename.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
    _controller.evaluateJavascript(source: "window.flashImage('$escaped')");
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
        .map((h) => {'id': h.id, 'text': h.text, 'color': h.color})
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
    final oldIds = oldList.map((h) => h.id).toSet();
    final newIds = newList.map((h) => h.id).toSet();

    for (final id in oldIds.difference(newIds)) {
      _controller.evaluateJavascript(source: "window.removeHighlight('$id')");
    }

    for (final hl in newList) {
      if (!oldIds.contains(hl.id)) {
        if (skipNewIds.contains(hl.id)) continue;
        _addHighlight(hl);
      } else {
        final old = oldList.firstWhere((h) => h.id == hl.id);
        if (old.color != hl.color) {
          _controller.evaluateJavascript(
            source: "window.updateHighlightColor('${hl.id}','${hl.color}')",
          );
        }
      }
    }
  }

  void _addHighlight(Highlight hl) {
    final escapedText = hl.text
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '');
    _controller.evaluateJavascript(
      source: "window.addHighlight('${hl.id}','$escapedText','${hl.color}')",
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
