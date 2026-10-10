import '../../../data/models/book/reader_anchor.dart';
import 'reader_js_bridge.dart' show SearchHit;

/// 阅读页对 Markdown 正文渲染器的调用面，WebView 与原生两种实现共用。
abstract interface class ReaderContentHandle {
  Future<bool> locateQuote(
    String quote, {
    ReaderAnchor? anchor,
    String? figureName,
  });

  void scrollToFigure(String id);

  void scrollToSearchResult(int index);

  Future<List<SearchHit>> searchContent(
    String query, {
    bool caseSensitive = false,
    bool wholeWord = false,
  });

  void clearSelection();

  /// 工具栏或搜索打开期间暂缓提交译文，避免操作中的正文移位。
  void holdTranslations(bool value);

  void flashImage(String filename);

  void addHighlightFromSelection(String id, String color);
}
