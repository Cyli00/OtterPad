import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

/// PDF 搜索的单一状态宿主——把原先散落在 `ReaderPage` 里的 PDF 搜索状态
/// （输入框 / 焦点 / 查询串 / pdfrx searcher / 上一处下一处）收拢到一处。
///
/// Markdown 搜索状态由 `ReaderSessionProvider` 持有；PDF 这一路因 pdfrx 的
/// [PdfTextSearcher] 必须绑定到 widget 持有的 [PdfViewerController]，无法进
/// provider，故独立成这个 widget 侧 [ChangeNotifier]。
///
/// 使用方在 initState 里 `addListener` 触发 setState，行为与重构前
/// “searcher / 查询变化即整页 rebuild” 一致。
class ReaderPdfSearchController extends ChangeNotifier {
  final TextEditingController textController = TextEditingController();
  final FocusNode focusNode = FocusNode();

  String _query = '';
  String get query => _query;
  bool get hasQuery => _query.isNotEmpty;

  PdfTextSearcher? _searcher;
  PdfTextSearcher? get searcher => _searcher;
  VoidCallback? _disposeListener;

  /// 绑定 pdfrx searcher——在 `PdfViewer.onViewerReady` 回调里调。
  /// 重新绑定时先释放上一个 searcher 及其监听。
  void bind(PdfViewerController controller) {
    _disposeListener?.call();
    _searcher?.dispose();
    final searcher = PdfTextSearcher(controller);
    _disposeListener = searcher.addListener(notifyListeners);
    _searcher = searcher;
    if (_query.isNotEmpty) {
      // 重新绑定发生在展示层/页序切换后：只重跑查询、跳到首个命中会把刚恢复的
      // 源页位置拉走，命中定位留给用户的上/下一处或重新输入。
      searcher.startTextSearch(_query, searchImmediately: true);
    }
  }

  /// 执行搜索；空串重置。[searchImmediately] 用于回车提交时跳过节流。
  void search(String query, {bool searchImmediately = false}) {
    final normalized = query.trim();
    if (_query != normalized) {
      _query = normalized;
      notifyListeners();
    }
    final searcher = _searcher;
    if (searcher == null) return;
    if (normalized.isEmpty) {
      searcher.resetTextSearch();
      return;
    }
    searcher.startTextSearch(
      normalized,
      goToFirstMatch: true,
      searchImmediately: searchImmediately,
    );
  }

  Future<void> goToPrev() async {
    final searcher = _searcher;
    if (searcher == null || searcher.matches.isEmpty) return;
    await searcher.goToPrevMatch();
    notifyListeners();
  }

  Future<void> goToNext() async {
    final searcher = _searcher;
    if (searcher == null || searcher.matches.isEmpty) return;
    await searcher.goToNextMatch();
    notifyListeners();
  }

  /// 打开搜索时把当前 query 回填输入框、聚焦并全选（postFrame 后调）。
  void focusForSearch() {
    if (textController.text != _query) textController.text = _query;
    focusNode.requestFocus();
    textController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: textController.text.length,
    );
  }

  /// 清空查询与匹配（切到 Markdown 或关闭搜索时调）。
  void clear() {
    textController.clear();
    focusNode.unfocus();
    _searcher?.resetTextSearch();
    if (_query.isNotEmpty) {
      _query = '';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposeListener?.call();
    _searcher?.dispose();
    textController.dispose();
    focusNode.dispose();
    super.dispose();
  }
}
