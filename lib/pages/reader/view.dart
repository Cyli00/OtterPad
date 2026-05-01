import 'dart:async';
import 'dart:io';

import 'package:animations/animations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_routes.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../../data/models/book/document.dart';
import '../../data/models/collection/favorite.dart';
import '../../core/storage/storage.dart';
import '../../providers/api_provider.dart';
import '../../providers/image_generation_config_provider.dart';
import '../../providers/document_translation_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/reader_settings_provider.dart';
import '../../providers/task_provider.dart';
import '../../providers/translation_config_provider.dart';
import '../../services/doc_extract_service.dart';
import '../../utils/doc_paths.dart';
import '../../services/document_summary_image_service.dart';
import '../../services/figure_extract_service.dart';
import '../../services/reader/markdown_document_cache_service.dart';
import '../../services/snackbar_service.dart';
import '../../utils/markdown_translation_weaver.dart';
import 'widgets/figure_viewer.dart';
import 'widgets/markdown_reader.dart';
import 'widgets/outline_panel.dart';
import 'widgets/reader_bottom_bar.dart';
import 'widgets/reader_background.dart';
import 'widgets/reader_document_info_sheet.dart';
import 'widgets/reader_favorite_sheet.dart';
import 'widgets/reader_search_bars.dart';
import 'widgets/reader_search_navigator.dart';
import 'widgets/reader_text_sheet.dart';
import 'widgets/reader_theme_sheet.dart';
import 'widgets/reader_top_toolbar.dart';
import 'widgets/search_overlay.dart';
import 'widgets/selection_toolbar.dart';
import 'widgets/translation_popup.dart';
import '../shelf/widgets/create_favorite_dialog.dart';
import 'package:material_symbols_icons/symbols.dart';

class ReaderPage extends ConsumerStatefulWidget {
  final Document document;

  const ReaderPage({super.key, required this.document});

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _showPreview = false;
  String? _mdPath;
  String? _mdContent;

  // 搜索
  bool _searchActive = false;
  String? _highlightQuery;

  // 搜索结果导航
  List<SearchResult> _searchResults = [];
  int _currentResultIndex = 0;

  // Markdown 滚动控制
  final _scrollController = AutoScrollController();

  // PDF 控制器（用于滚动滑条）
  final _pdfController = PdfViewerController();
  PdfTextSearcher? _pdfSearcher;
  VoidCallback? _disposePdfSearchListener;
  final _pdfSearchController = TextEditingController();
  final _pdfSearchFocusNode = FocusNode();
  String _pdfSearchQuery = '';

  // 缓存加载 Future，避免重复创建相同加载任务
  Future<String>? _loadFuture;
  MarkdownSearchSnapshot? _searchSnapshot;
  String? _markdownCacheKey;

  // 文本选择
  String? _selectedText;
  final _selectedTextNotifier = ValueNotifier<String?>(null);
  String? _textOnPointerDown;
  Offset? _pointerDownPosition;

  // 选择工具栏 Overlay
  final _selectionAreaKey = GlobalKey();
  OverlayEntry? _selectionToolbarEntry;

  // 沉浸式：点击 markdown 内容区切换上下工具栏可见性
  bool _toolbarsVisible = true;
  bool _sheetOpen = false;

  // 桌面端工具栏自动隐藏
  static const _kEdgeTriggerZone = 16.0;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  // 异步初始化状态
  bool _initialized = false;
  bool? _fileExists;
  bool _markdownLoading = false;
  Object? _markdownLoadError;

  // Figure manifest 懒加载：首次点击图片时触发，Future 复用避免重复 IO
  Future<List<FigureManifestEntry>?>? _figuresFuture;

  final _summaryImageState = ValueNotifier<SummaryImagePanelState>(
    const SummaryImagePanelState(),
  );

  // 翻译进度 SnackBar 句柄——点按"翻译"时 show，翻译结束 finish/dismiss。
  SnackBarProgressHandle? _translationProgressHandle;

  @override
  void initState() {
    super.initState();
    _initAsync();
  }

  Future<void> _initAsync() async {
    final filePath = widget.document.filePath;

    final fileExistsFuture = filePath.isNotEmpty
        ? File(filePath).exists()
        : Future.value(false);
    final mdPathFuture = _findMarkdownPath(filePath);
    final summaryPathFuture = filePath.isNotEmpty
        ? () async {
            final sp = DocumentSummaryImageService.imagePathFor(filePath);
            return await File(sp).exists() ? sp : null;
          }()
        : Future<String?>.value();

    final fileExists = await fileExistsFuture;
    final mdPath = await mdPathFuture;
    final summaryPath = await summaryPathFuture;
    if (mdPath != null) {
      _mdPath = mdPath;
    }

    if (!mounted) return;

    final defaultMode = ref.read(readerSettingsProvider).defaultReadingMode;
    final wantMarkdown =
        defaultMode == DefaultReadingMode.markdown && _hasResult;

    setState(() {
      _fileExists = fileExists;
      _showPreview = wantMarkdown;
      _initialized = true;
      _markdownLoading = wantMarkdown && _mdContent == null && _mdPath != null;
      _markdownLoadError = null;
    });
    _summaryImageState.value = SummaryImagePanelState(imagePath: summaryPath);

    if (wantMarkdown) {
      unawaited(_ensureMarkdownReady());
    }
  }

  bool get _hasResult => _mdPath != null || _mdContent != null;

  // ─── 提取逻辑 ───

  void _onExtractPressed() {
    final filePath = widget.document.filePath;
    if (filePath.isEmpty || !File(filePath).existsSync()) {
      ref.read(snackBarServiceProvider).showResult(message: 'PDF 文件不存在');
      return;
    }

    ref
        .read(taskProvider.notifier)
        .extractDocument(
          filePath: filePath,
          title: widget.document.title,
          apiState: ref.read(docExtractApiProvider),
          onSuccess: (mdPath, markdownContent) {
            if (!mounted) return;
            final cacheService = MarkdownDocumentCacheService.instance;
            final cacheKey = cacheService.buildMemoryCacheKey(
              mdPath: mdPath,
              title: widget.document.title,
              markdownContent: markdownContent,
            );
            cacheService.primeResolvedContent(
              cacheKey: cacheKey,
              content: markdownContent,
            );
            setState(() {
              _mdPath = mdPath;
              _mdContent = markdownContent;
              _markdownCacheKey = cacheKey;
              _searchSnapshot = cacheService.getSearchSnapshot(
                cacheKey: cacheKey,
                markdownContent: markdownContent,
              );
              _showPreview = true;
            });
          },
        );
  }

  Future<void> _onReprocessPressed() async {
    final filePath = widget.document.filePath;
    if (filePath.isEmpty || !File(filePath).existsSync()) {
      ref.read(snackBarServiceProvider).showResult(message: 'PDF 文件不存在');
      return;
    }

    ref.read(snackBarServiceProvider).showResult(message: '正在重新排版…');
    try {
      final (mdPath, content) = await DocExtractService.instance
          .reprocessMarkdown(pdfPath: filePath, title: widget.document.title);
      if (!mounted) return;

      // 刷新缓存和界面
      final cacheService = MarkdownDocumentCacheService.instance;
      final cacheKey = cacheService.buildMemoryCacheKey(
        mdPath: mdPath,
        title: widget.document.title,
        markdownContent: content,
      );
      cacheService.primeResolvedContent(cacheKey: cacheKey, content: content);

      setState(() {
        _mdPath = mdPath;
        _mdContent = content;
        _markdownCacheKey = cacheKey;
        _loadFuture = null;
        _searchSnapshot = cacheService.getSearchSnapshot(
          cacheKey: cacheKey,
          markdownContent: content,
        );
      });
      ref.read(snackBarServiceProvider).showResult(message: '重新排版完成');
    } catch (e) {
      if (!mounted) return;
      ref.read(snackBarServiceProvider).showResult(message: '排版失败: $e');
    }
  }

  void _togglePreview() {
    _clearHighlight();
    final enteringMarkdown = !_showPreview;
    if (enteringMarkdown) {
      _pdfSearchFocusNode.unfocus();
      _pdfSearchController.clear();
      _pdfSearcher?.resetTextSearch();
    }
    setState(() {
      _showPreview = !_showPreview;
      _searchActive = false;
      if (enteringMarkdown) {
        _pdfSearchQuery = '';
      }
    });
    if (enteringMarkdown) {
      unawaited(_ensureMarkdownReady());
    }
  }

  // ─── 搜索 ───

  Future<void> _openSearch() async {
    if (_showPreview) {
      if (_mdContent == null && _mdPath != null) {
        await _ensureMarkdownReady();
      }
      if (!mounted || _mdContent == null) return;
      setState(() => _searchActive = true);
      return;
    }

    if (!(_fileExists ?? false)) return;
    if (_pdfSearchController.text != _pdfSearchQuery) {
      _pdfSearchController.text = _pdfSearchQuery;
    }
    setState(() => _searchActive = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pdfSearchFocusNode.requestFocus();
      _pdfSearchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _pdfSearchController.text.length,
      );
    });
  }

  void _closeSearch() {
    if (_showPreview) {
      setState(() => _searchActive = false);
      return;
    }
    _clearPdfSearch();
  }

  void _bindPdfSearcher(PdfDocument document, PdfViewerController controller) {
    _disposePdfSearchListener?.call();
    _pdfSearcher?.dispose();

    final searcher = PdfTextSearcher(controller);
    _disposePdfSearchListener = searcher.addListener(() {
      if (mounted) setState(() {});
    });
    _pdfSearcher = searcher;

    if (_pdfSearchQuery.isNotEmpty) {
      searcher.startTextSearch(_pdfSearchQuery, searchImmediately: true);
    }
  }

  void _performPdfSearch(String query, {bool searchImmediately = false}) {
    final normalized = query.trim();
    if (_pdfSearchQuery != normalized) {
      setState(() => _pdfSearchQuery = normalized);
    }

    final searcher = _pdfSearcher;
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

  void _clearPdfSearch() {
    _pdfSearchController.clear();
    _pdfSearchFocusNode.unfocus();
    _pdfSearcher?.resetTextSearch();
    setState(() {
      _searchActive = false;
      _pdfSearchQuery = '';
    });
  }

  void _onSearchResultTap(
    List<SearchResult> results,
    int tappedIndex,
    String query,
  ) {
    final offset = results[tappedIndex].charOffset;
    setState(() {
      _searchActive = false;
      _showPreview = true;
      _searchResults = results;
      _currentResultIndex = tappedIndex;
      _highlightQuery = query;
    });
    // 等 highlightQuery 触发 widget 重建后再跳转
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToCharOffset(offset);
    });
  }

  void _clearHighlight() {
    if (_highlightQuery != null) {
      setState(() {
        _highlightQuery = null;
        _searchResults = [];
        _currentResultIndex = 0;
      });
    }
  }

  void _goToPrevResult() {
    if (_searchResults.isEmpty) return;
    setState(() {
      _currentResultIndex =
          (_currentResultIndex - 1 + _searchResults.length) %
          _searchResults.length;
    });
    _scrollToCharOffset(_searchResults[_currentResultIndex].charOffset);
  }

  void _goToNextResult() {
    if (_searchResults.isEmpty) return;
    setState(() {
      _currentResultIndex = (_currentResultIndex + 1) % _searchResults.length;
    });
    _scrollToCharOffset(_searchResults[_currentResultIndex].charOffset);
  }

  Future<void> _goToPrevPdfResult() async {
    final searcher = _pdfSearcher;
    if (searcher == null || searcher.matches.isEmpty) return;
    await searcher.goToPrevMatch();
    if (mounted) setState(() {});
  }

  Future<void> _goToNextPdfResult() async {
    final searcher = _pdfSearcher;
    if (searcher == null || searcher.matches.isEmpty) return;
    await searcher.goToNextMatch();
    if (mounted) setState(() {});
  }

  // ─── 底部面板（字体 / 主题 / 大纲） ───

  Future<void> _openTextSheet() async {
    if (_mdContent == null) return;
    _sheetOpen = true;
    await showReaderTextSheet(context);
    _sheetOpen = false;
  }

  Future<void> _openThemeSheet() async {
    _sheetOpen = true;
    await showReaderThemeSheet(context);
    _sheetOpen = false;
  }

  void _openNotesSheet() {
    // TODO: 笔记查看功能待实现
  }

  void _openOutlineSheet() {
    if (_mdContent == null) return;
    _scaffoldKey.currentState?.openEndDrawer();
  }

  // ─── 沉浸式 ───

  /// Markdown 区域单击 → 切换上下工具栏显隐。
  /// 拖拽选择不会触发 onTap（GestureDetector 默认行为）。
  void _toggleToolbars() {
    if (_sheetOpen) return;
    setState(() => _toolbarsVisible = !_toolbarsVisible);
  }

  /// Markdown 滚动方向 → 自动隐藏/显示工具栏。
  ///
  /// 向下阅读（reverse）隐藏，向上回翻（forward）显示。
  /// [UserScrollNotification] 只在用户主动拖拽时触发，惯性阶段不会触发，
  /// 避免 fling 结束时的方向抖动。
  bool _handleMarkdownScrollNotification(UserScrollNotification notification) {
    if (_sheetOpen || _searchActive || _highlightQuery != null) return false;

    _handleReaderScrollDirection(notification.direction);
    return false;
  }

  bool _handlePdfScrollNotification(UserScrollNotification notification) {
    if (_showPreview || _sheetOpen || _searchActive) return false;

    _handleReaderScrollDirection(notification.direction);
    return false;
  }

  void _handlePdfPointerSignal(PointerSignalEvent event) {
    if (_showPreview || _sheetOpen || _searchActive) return;
    if (event is! PointerScrollEvent) return;

    if (event.scrollDelta.dy > 0) {
      _handleReaderScrollDirection(ScrollDirection.reverse);
    } else if (event.scrollDelta.dy < 0) {
      _handleReaderScrollDirection(ScrollDirection.forward);
    }
  }

  void _handlePdfPointerMove(PointerMoveEvent event) {
    if (_showPreview || _sheetOpen || _searchActive) return;

    if (event.delta.dy < -1) {
      _handleReaderScrollDirection(ScrollDirection.reverse);
    } else if (event.delta.dy > 1) {
      _handleReaderScrollDirection(ScrollDirection.forward);
    }
  }

  void _handleReaderScrollDirection(ScrollDirection direction) {
    switch (direction) {
      case ScrollDirection.reverse:
        if (_toolbarsVisible) setState(() => _toolbarsVisible = false);
      case ScrollDirection.forward:
        if (!_toolbarsVisible) setState(() => _toolbarsVisible = true);
      case ScrollDirection.idle:
        break;
    }
  }

  /// 桌面端：鼠标靠近上下边缘时显示工具栏。
  ///
  /// 隐藏仍由滚动方向或点击内容区触发，不再按无交互时长自动隐藏。
  void _onDesktopPointerHover(PointerHoverEvent event) {
    final canShowToolbars =
        (_showPreview && _hasResult && _mdContent != null) ||
        (!_showPreview && (_fileExists ?? false));
    if (!canShowToolbars || _sheetOpen) return;
    final height = context.size?.height ?? 0;
    final y = event.localPosition.dy;
    if (y < _kEdgeTriggerZone || y > height - _kEdgeTriggerZone) {
      if (!_toolbarsVisible) setState(() => _toolbarsVisible = true);
    }
  }

  // ─── 段落上下文扩展（翻译用）───

  String? _expandToParagraphContext(String selectedText) {
    final md = _mdContent;
    if (md == null || md.isEmpty) return null;

    final plainText = _stripBasicMarkdown(md);

    final paragraphs = plainText
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (paragraphs.isEmpty) return null;

    // 跨段落选择时 SelectionArea 会丢失 \n\n，需要用空白规范化匹配
    String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
    final normSelected = norm(selectedText);
    final normParagraphs = paragraphs.map(norm).toList();

    int startIdx = -1;
    int endIdx = -1;

    for (final chunkLen in [60, 30, 15]) {
      if (startIdx >= 0 && endIdx >= 0) break;
      final len = normSelected.length.clamp(1, chunkLen);

      if (startIdx < 0) {
        final chunk = normSelected.substring(0, len);
        for (int i = 0; i < normParagraphs.length; i++) {
          if (normParagraphs[i].contains(chunk)) {
            startIdx = i;
            break;
          }
        }
      }

      if (endIdx < 0) {
        final chunk = normSelected.substring(normSelected.length - len);
        for (int i = normParagraphs.length - 1; i >= 0; i--) {
          if (normParagraphs[i].contains(chunk)) {
            endIdx = i;
            break;
          }
        }
      }
    }

    if (startIdx < 0 && endIdx < 0) return null;
    if (startIdx < 0) startIdx = endIdx;
    if (endIdx < 0) endIdx = startIdx;
    if (endIdx < startIdx) endIdx = startIdx;

    final expanded = paragraphs.sublist(startIdx, endIdx + 1).join('\n\n');
    return norm(expanded) == normSelected ? null : expanded;
  }

  static String _stripBasicMarkdown(String md) {
    return md
        .replaceAll(RegExp(r'!\[([^\]]*)\]\([^)]*\)'), r'$1')
        .replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1')
        .replaceAll(RegExp(r'\*{2}(.+?)\*{2}'), r'$1')
        .replaceAll(RegExp(r'_{2}(.+?)_{2}'), r'$1')
        .replaceAll(
          RegExp(r'(?<![a-zA-Z0-9])\*(?!\s)(.+?)(?<!\s)\*(?![a-zA-Z0-9])'),
          r'$1',
        )
        .replaceAll(
          RegExp(r'(?<![a-zA-Z0-9])_(?!\s)(.+?)(?<!\s)_(?![a-zA-Z0-9])'),
          r'$1',
        )
        .replaceAll(RegExp(r'`([^`]+)`'), r'$1')
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^>\s?', multiLine: true), '');
  }

  // ─── 大纲导航 ───

  /// 统一跳转：charOffset → widget index → scrollToIndex。
  ///
  /// outline "在文中查看"、搜索结果导航、prev/next 全部走这条路径。
  void _scrollToCharOffset(int charOffset) {
    if (_mdContent == null || _mdContent!.isEmpty) return;
    final breaks = RegExp(r'\n\n+').allMatches(_mdContent!);
    var widgetIndex = 0;
    for (final brk in breaks) {
      if (brk.start >= charOffset) break;
      widgetIndex++;
    }
    _scrollController.scrollToIndex(
      (widgetIndex - 1).clamp(0, widgetIndex),
      preferPosition: AutoScrollPosition.begin,
    );
  }

  bool _isInAnyFavorite(List<Favorite> favorites) {
    final docPath = widget.document.filePath;
    if (docPath.isEmpty) return false;
    return favorites.any((fav) => fav.docPaths.contains(docPath));
  }

  List<Favorite> _favoritesContainingDoc(List<Favorite> favorites) {
    final docPath = widget.document.filePath;
    if (docPath.isEmpty) return const [];
    return favorites.where((fav) => fav.docPaths.contains(docPath)).toList();
  }

  Future<void> _showFavoritePicker() async {
    final docPath = widget.document.filePath;
    if (docPath.isEmpty) {
      ref
          .read(snackBarServiceProvider)
          .showResult(message: '此文献无本地文件，无法添加到收藏夹');
      return;
    }

    final result = await _showFavoritePickerSheet(
      title: '移入收藏夹',
      favorites: ref.read(favoritesProvider),
      docPath: docPath,
      mode: ReaderFavoritePickerMode.add,
    );
    if (!mounted || result == null) return;

    final selected = result.favorites
        .where((favorite) => !favorite.docPaths.contains(docPath))
        .toList();
    if (selected.isEmpty) return;

    for (final favorite in selected) {
      await ref.read(favoritesProvider.notifier).addDoc(favorite.id, docPath);
    }
    if (!mounted) return;
    final message = selected.length == 1
        ? '已添加到「${selected.single.name}」'
        : '已添加到 ${selected.length} 个收藏夹';
    ref.read(snackBarServiceProvider).showResult(message: message);
  }

  Future<Favorite?> _createFavoriteFromPicker() async {
    final created = await showCreateFavoriteDialog(context);
    if (!mounted || created == null) return null;

    return ref
        .read(favoritesProvider.notifier)
        .create(emoji: created['emoji']!, name: created['name']!);
  }

  Future<void> _showFavoriteRemovalPicker() async {
    final docPath = widget.document.filePath;
    if (docPath.isEmpty) return;

    final favorites = _favoritesContainingDoc(ref.read(favoritesProvider));
    if (favorites.isEmpty) {
      ref.read(snackBarServiceProvider).showResult(message: '此文献不在收藏夹中');
      return;
    }

    final result = await _showFavoritePickerSheet(
      title: '移出收藏夹',
      favorites: favorites,
      docPath: docPath,
      mode: ReaderFavoritePickerMode.remove,
    );
    if (!mounted) return;
    final selected = result?.favorites ?? const <Favorite>[];
    if (selected.isEmpty) return;

    for (final favorite in selected) {
      await ref
          .read(favoritesProvider.notifier)
          .removeDoc(favorite.id, docPath);
    }
    if (!mounted) return;
    final message = selected.length == 1
        ? '已从「${selected.single.name}」移出'
        : '已从 ${selected.length} 个收藏夹移出';
    ref.read(snackBarServiceProvider).showResult(message: message);
  }

  Future<ReaderFavoriteSelectionResult?> _showFavoritePickerSheet({
    required String title,
    required List<Favorite> favorites,
    required String docPath,
    required ReaderFavoritePickerMode mode,
  }) {
    return showReaderFavoritePickerSheet(
      context: context,
      title: title,
      favorites: favorites,
      docPath: docPath,
      mode: mode,
      onCreateFavorite: mode == ReaderFavoritePickerMode.add
          ? _createFavoriteFromPicker
          : null,
    );
  }

  void _showDocumentInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ReaderDocumentInfoSheet(document: widget.document),
    );
  }

  Future<String?> _findMarkdownPath(String filePath) async {
    if (filePath.isEmpty) return null;
    final mdPath = DocPaths.md(filePath);
    return await File(mdPath).exists() ? mdPath : null;
  }

  Future<void> _ensureMarkdownReady() async {
    if (_mdContent != null) {
      _prewarmSearchSnapshot();
      return;
    }
    if (_mdPath == null) return;

    _loadFuture ??= _loadAndResolveMarkdown();

    final shouldSetLoading = !_markdownLoading;
    if (shouldSetLoading && mounted) {
      setState(() {
        _markdownLoading = true;
        _markdownLoadError = null;
      });
    }

    try {
      final content = await _loadFuture!;
      if (!mounted) return;
      setState(() {
        _mdContent = content;
        _markdownLoading = false;
        _markdownLoadError = null;
      });
      _prewarmSearchSnapshot();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _markdownLoading = false;
        _markdownLoadError = error;
      });
    }
  }

  void _prewarmSearchSnapshot() {
    final content = _mdContent;
    final cacheKey = _markdownCacheKey;
    if (content == null || cacheKey == null || _searchSnapshot != null) {
      return;
    }
    final cacheService = MarkdownDocumentCacheService.instance;
    _searchSnapshot = cacheService.getSearchSnapshot(
      cacheKey: cacheKey,
      markdownContent: content,
    );
  }

  Future<String> _loadAndResolveMarkdown() async {
    final resolved = await MarkdownDocumentCacheService.instance.loadDocument(
      mdPath: _mdPath!,
      title: widget.document.title,
    );
    _markdownCacheKey = resolved.cacheKey;
    _searchSnapshot = null;
    return resolved.content;
  }

  // ─── 标记（功能待重新设计） ───

  void _addHighlight(String text) {
    // TODO: 重新设计标记功能
  }

  void _showNoteDialog({required String text}) {
    // TODO: 重新设计做笔记功能
  }

  // ─── 选择/标记工具栏 ───

  void _dismissSelectionToolbar() {
    _selectionToolbarEntry?.remove();
    _selectionToolbarEntry = null;
  }

  static const _kToolbarGap = 8.0;

  double get _lineHeight => ref.read(readerSettingsProvider).fontSize * 1.7;

  /// 通过 hit test 定位给定全局坐标处最外层的 [RenderParagraph]。
  RenderBox? _findParagraphAt(Offset globalPos) {
    final ro = _selectionAreaKey.currentContext?.findRenderObject();
    if (ro is! RenderBox) return null;
    final local = ro.globalToLocal(globalPos);
    final result = BoxHitTestResult();
    if (!ro.hitTest(result, position: local)) return null;
    // result.path 从 innermost → outermost；取最外层段落级别的 RenderParagraph
    RenderBox? found;
    for (final entry in result.path) {
      if (entry.target is RenderParagraph) found = entry.target as RenderBox;
    }
    return found;
  }

  /// 选择完成后在选中段落正下方弹出工具栏
  void _showSelectionToolbarOverlay(Offset downPos, Offset upPos) {
    _dismissSelectionToolbar();

    // 通过 hit test 定位选区起止处的段落 RenderBox，取其渲染边界
    final startBox = _findParagraphAt(downPos);
    final endBox = _findParagraphAt(upPos);

    Rect? bounds;
    for (final box in [startBox, endBox]) {
      if (box == null) continue;
      final topLeft = box.localToGlobal(Offset.zero);
      final rect = topLeft & box.size;
      bounds = bounds?.expandToInclude(rect) ?? rect;
    }

    // 兜底：无法定位段落时使用指针位置估算
    if (bounds == null) {
      final lh = _lineHeight;
      final topY = (downPos.dy < upPos.dy ? downPos.dy : upPos.dy) - lh * 0.3;
      final bottomY =
          (downPos.dy > upPos.dy ? downPos.dy : upPos.dy) + lh * 0.7;
      final cx = (downPos.dx + upPos.dx) / 2;
      bounds = Rect.fromLTRB(cx - 50, topY, cx + 50, bottomY);
    }

    _selectionToolbarEntry = showReadingToolbar(
      context: context,
      anchorAbove: Offset(bounds.center.dx, bounds.top - _kToolbarGap),
      anchorBelow: Offset(bounds.center.dx, bounds.bottom + _kToolbarGap),
      onDismiss: () => _selectionToolbarEntry = null,
      actions: [
        ReadingToolbarAction(
          icon: Symbols.content_copy_rounded,
          label: '复制',
          onTap: () {
            if (_selectedText != null) {
              Clipboard.setData(ClipboardData(text: _selectedText!));
              ref
                  .read(snackBarServiceProvider)
                  .showResult(
                    message: '已复制到剪贴板',
                    duration: const Duration(seconds: 1),
                  );
            }
          },
        ),
        ReadingToolbarAction(
          icon: Symbols.highlight_rounded,
          label: '标记',
          onTap: () {
            if (_selectedText != null && _selectedText!.trim().isNotEmpty) {
              _addHighlight(_selectedText!);
            }
          },
        ),
        ReadingToolbarAction(
          icon: Symbols.edit_note_rounded,
          label: '做笔记',
          onTap: () {
            final text = _selectedText;
            if (text != null && text.trim().isNotEmpty) {
              _showNoteDialog(text: text.trim());
            }
          },
        ),
        ReadingToolbarAction(
          icon: Symbols.translate_rounded,
          label: '翻译',
          onTap: () {
            final text = _selectedText;
            if (text != null && text.trim().isNotEmpty) {
              final trimmed = text.trim();
              final fullText = _expandToParagraphContext(trimmed);
              showTranslationPopup(
                context,
                sourceText: trimmed,
                fullText: fullText,
              );
            }
          },
        ),
      ],
    );
  }

  @override
  void dispose() {
    _disposePdfSearchListener?.call();
    _pdfSearcher?.dispose();
    _pdfSearchController.dispose();
    _pdfSearchFocusNode.dispose();
    _selectedTextNotifier.dispose();
    _summaryImageState.dispose();
    _scrollController.dispose();
    _selectionToolbarEntry?.remove();
    super.dispose();
  }

  // ─── UI ───

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final readerSettings = ref.watch(readerSettingsProvider);
    final extracting = ref.watch(
      taskProvider.select(
        (tasks) =>
            tasks[TaskType.extractDocument]?.status == TaskStatus.running,
      ),
    );

    // 异步初始化完成前显示骨架加载状态
    if (!_initialized) {
      return Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: Column(
            children: [
              _buildToolbar(cs),
              Expanded(
                child: Center(
                  child: CircularProgressIndicator(
                    color: cs.primary.withAlpha(120),
                    strokeWidth: 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final fileExists = _fileExists ?? false;

    final contentBg = (_showPreview && _hasResult)
        ? resolveReaderPalette(readerSettings.theme, cs).background
        : cs.surface;

    final isMarkdownHighlightMode = _showPreview && _highlightQuery != null;
    final pdfMatchCount = _pdfSearcher?.matches.length ?? 0;
    final showPdfNavigator = !_showPreview && _pdfSearchQuery.isNotEmpty;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: cs.surface,
      endDrawerEnableOpenDragGesture: false,
      endDrawer: _mdContent != null
          ? Drawer(
              width: 380,
              child: OutlinePanel(
                key: ValueKey(_mdContent.hashCode),
                markdownContent: _mdContent!,
                pdfPath: widget.document.filePath,
                summaryImageState: _summaryImageState,
                onNavigate: (offset) {
                  _scaffoldKey.currentState?.closeEndDrawer();
                  _scrollToCharOffset(offset);
                },
                onRegenerateSummary: () {
                  _handleGenerateSummaryImage(openOutline: false);
                },
              ),
            )
          : null,
      body: SafeArea(
        child: Listener(
          onPointerHover: _isDesktop ? _onDesktopPointerHover : null,
          child: Stack(
            children: [
              // ── 主内容层：占满全屏，工具栏 overlay 在上下方 ──
              Positioned.fill(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  color: contentBg,
                  child: fileExists
                      ? _buildBody(theme, cs, readerSettings)
                      : _buildFileNotFound(theme, cs),
                ),
              ),
              // ── 顶部工具栏（沉浸式时向上滑出） ──
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  offset: _toolbarsVisible ? Offset.zero : const Offset(0, -1),
                  child: Container(
                    color: cs.surface.withValues(
                      alpha: readerSettings.toolbarOpacity.value,
                    ),
                    child: isMarkdownHighlightMode
                        ? _buildHighlightSearchBar()
                        : (_searchActive && !_showPreview
                              ? _buildPdfSearchBar()
                              : _buildToolbar(cs, extracting: extracting)),
                  ),
                ),
              ),
              // ── 底部工具栏（仅 Markdown 模式；沉浸式时向下滑出） ──
              if (_showPreview && _hasResult && _mdContent != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    offset: _toolbarsVisible ? Offset.zero : const Offset(0, 1),
                    child: _buildBottomBar(readerSettings),
                  ),
                ),
              // ── 浮动搜索结果导航器 ──
              if (isMarkdownHighlightMode && _searchResults.isNotEmpty)
                Positioned(
                  right: 16,
                  bottom: 32,
                  child: _buildResultNavigator(),
                ),
              if (showPdfNavigator)
                Positioned(
                  right: 16,
                  bottom: 32,
                  child: _buildPdfResultNavigator(pdfMatchCount),
                ),
              // ── 搜索遮罩层 ──
              if (_searchActive && _showPreview && _searchSnapshot != null)
                Positioned.fill(
                  child: SearchOverlay(
                    readerSettings: readerSettings,
                    searchSnapshot: _searchSnapshot!,
                    onResultTap: _onSearchResultTap,
                    onDismiss: _closeSearch,
                    initialQuery: _highlightQuery,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 顶部工具栏：返回 / 搜索 / PDF↔MD 切换 / 重新提取 / 信息
  ///
  /// 大纲、外观（颜色/背景）、字体面板 3 个按钮已挪到 [_buildBottomBar]。
  Widget _buildToolbar(ColorScheme cs, {bool extracting = false}) {
    final favorites = ref.watch(favoritesProvider);
    final inFavorite = _isInAnyFavorite(favorites);
    final translation = ref.watch(
      documentTranslationProvider(widget.document.filePath),
    );
    final summaryImagePath = DocumentSummaryImageService.imagePathFor(
      widget.document.filePath,
    );

    return ReaderTopToolbar(
      showPreview: _showPreview,
      hasResult: _hasResult,
      hasMarkdownContent: _mdContent != null,
      fileExists: _fileExists ?? false,
      inFavorite: inFavorite,
      extracting: extracting,
      canRetranslate: translation.hasResult && _mdContent != null,
      hasSummaryImage: File(summaryImagePath).existsSync(),
      extractButton: _buildExtractButton(cs, extracting),
      onBack: () => context.pop(),
      onSearch: _openSearch,
      onGenerateSummaryImage: _handleGenerateSummaryImage,
      onAddFavorite: _showFavoritePicker,
      onRemoveFavorite: _showFavoriteRemovalPicker,
      onExtract: _onExtractPressed,
      onShowInfo: () => _showDocumentInfo(context),
      onReprocess: _onReprocessPressed,
      onRetranslate: _handleRetranslate,
      onOpenSummaryImage: _openSummaryImage,
    );
  }

  Widget _buildPdfSearchBar() {
    return ReaderPdfSearchBar(
      controller: _pdfSearchController,
      focusNode: _pdfSearchFocusNode,
      onBack: () => context.pop(),
      onClear: _clearPdfSearch,
      onSubmitted: (value) => _performPdfSearch(value, searchImmediately: true),
      onChanged: (value) {
        setState(() {});
        _performPdfSearch(value);
      },
    );
  }

  /// 高亮浏览模式下的顶部搜索栏：显示当前查询词，点击可重新搜索，✕ 退出搜索
  Widget _buildHighlightSearchBar() {
    return ReaderHighlightSearchBar(
      query: _highlightQuery ?? '',
      onBack: () => context.pop(),
      onOpenSearch: _openSearch,
      onClear: _clearHighlight,
    );
  }

  Widget _buildPdfResultNavigator(int total) {
    return ReaderPdfResultNavigator(
      currentIndex: _pdfSearcher?.currentIndex ?? -1,
      total: total,
      progress: _pdfSearcher?.searchProgress,
      searching: _pdfSearcher?.isSearching ?? false,
      onPrevious: _goToPrevPdfResult,
      onNext: _goToNextPdfResult,
    );
  }

  /// 右下角浮动导航器：上/下雪佛龙 + 当前/总数 计数器
  Widget _buildResultNavigator() {
    return ReaderTextResultNavigator(
      currentIndex: _currentResultIndex,
      total: _searchResults.length,
      onPrevious: _goToPrevResult,
      onNext: _goToNextResult,
    );
  }

  /// 底部工具栏：大纲 / 笔记 / 主题面板 / 字体面板
  ///
  /// 仅在 Markdown 模式显示。工具栏背景用 surface 的半透明色，视觉上浮在
  /// 阅读内容之上；沉浸式状态切换由 [AnimatedSlide] 在 build 里处理。
  Widget _buildBottomBar(ReaderSettingsState readerSettings) {
    final translation = ref.watch(
      documentTranslationProvider(widget.document.filePath),
    );

    return ReaderBottomBar(
      readerSettings: readerSettings,
      translation: translation,
      onOpenOutline: _openOutlineSheet,
      onTranslate: _handleTranslate,
      onCycleTranslationMode: _handleCycleTranslationMode,
      onOpenNotes: _openNotesSheet,
      onOpenTheme: _openThemeSheet,
      onOpenText: _openTextSheet,
    );
  }

  /// 启动全文翻译：show 一个长驻 SnackBar 订阅 provider 的进度 ValueListenable，
  /// 翻译结束（成功/失败/取消）后 finish 关闭。
  Future<void> _handleTranslate() async {
    if (_mdContent == null || _mdContent!.isEmpty) return;

    final pdfPath = widget.document.filePath;
    final notifier = ref.read(documentTranslationProvider(pdfPath).notifier);

    // 先显示 SnackBar 让用户立即看到反馈——translate 内部异步开始后才有第一次
    // onProgress，避免短暂的"点了没反应"观感。
    _translationProgressHandle?.dismiss();
    _translationProgressHandle = ref
        .read(snackBarServiceProvider)
        .showListenableProgress(
          listenable: _adaptProgress(notifier.progress),
          onCancel: () {
            notifier.cancel();
            _translationProgressHandle?.dismiss();
            _translationProgressHandle = null;
          },
        );

    await notifier.translate(_mdContent!);
    if (!mounted) return;

    final state = ref.read(documentTranslationProvider(pdfPath));
    final handle = _translationProgressHandle;
    _translationProgressHandle = null;
    if (state.status == DocTranslationStatus.done) {
      handle?.finish(message: '翻译完成');
    } else {
      handle?.dismiss();
    }
  }

  /// 把 `TranslationProgress` 的 ValueListenable 适配到 SnackBar 需要的
  /// `ListenableProgress` 类型——让 snackbar_service 不必依赖业务类型。
  ValueListenable<ListenableProgress> _adaptProgress(
    ValueListenable<TranslationProgress> source,
  ) {
    final adapter = ValueNotifier<ListenableProgress>(
      ListenableProgress(
        current: source.value.current,
        total: source.value.total,
        status: source.value.status,
      ),
    );
    void listener() {
      final v = source.value;
      adapter.value = ListenableProgress(
        current: v.current,
        total: v.total,
        status: v.status,
      );
    }

    source.addListener(listener);
    // 适配器随翻译结束一起被 GC——SnackBar 关闭后 ValueListenableBuilder 不再
    // 调用 build，listener 也不再被唤醒，无泄漏风险。
    return adapter;
  }

  /// 三态循环：双语 → 原文 → 译文 → 双语。
  void _handleCycleTranslationMode() {
    ref
        .read(documentTranslationProvider(widget.document.filePath).notifier)
        .cycleMode();
  }

  /// "更多"菜单里的"重新翻译"——清空缓存重新发起。
  Future<void> _handleRetranslate() async {
    if (_mdContent == null || _mdContent!.isEmpty) return;

    final pdfPath = widget.document.filePath;
    final notifier = ref.read(documentTranslationProvider(pdfPath).notifier);

    _translationProgressHandle?.dismiss();
    _translationProgressHandle = ref
        .read(snackBarServiceProvider)
        .showListenableProgress(
          listenable: _adaptProgress(notifier.progress),
          onCancel: () {
            notifier.cancel();
            _translationProgressHandle?.dismiss();
            _translationProgressHandle = null;
          },
        );

    await notifier.retranslate(_mdContent!);
    if (!mounted) return;

    final state = ref.read(documentTranslationProvider(pdfPath));
    final handle = _translationProgressHandle;
    _translationProgressHandle = null;
    if (state.status == DocTranslationStatus.done) {
      handle?.finish(message: '翻译完成');
    } else {
      handle?.dismiss();
    }
  }

  static const _kSummaryImageCostDismissed = 'summary_image_cost_dismissed';

  Future<void> _handleGenerateSummaryImage({bool openOutline = true}) async {
    final imageRole = AgentApiNotifier.globalImageRole;
    if (imageRole.provider == null || imageRole.modelId == null) {
      _scaffoldKey.currentState?.closeEndDrawer();
      ref
          .read(snackBarServiceProvider)
          .showResult(
            message: '请先在「AI 设置」中选择生图模型',
            action: SnackBarAction(
              label: '前往设置',
              onPressed: () => context.push(AppRoutes.settingsApi),
            ),
          );
      return;
    }

    final dismissed =
        GStorage.setting.get(_kSummaryImageCostDismissed, defaultValue: false)
            as bool;
    if (!dismissed) {
      final confirmed = await _showSummaryImageCostDialog();
      if (confirmed != true) return;
    }

    if (openOutline) _openOutlineSheet();

    final alreadyRunning =
        ref.read(taskProvider)[TaskType.generateSummaryImage]?.status ==
        TaskStatus.running;
    final current = _summaryImageState.value;
    if (alreadyRunning) {
      if (!current.generating) {
        _summaryImageState.value = SummaryImagePanelState(
          imagePath: current.imagePath,
          revision: current.revision,
          generating: true,
        );
      }
      return;
    }

    _summaryImageState.value = SummaryImagePanelState(
      imagePath: current.imagePath,
      revision: current.revision,
      generating: true,
    );

    await ref
        .read(taskProvider.notifier)
        .generateSummaryImage(
          document: widget.document,
          onSuccess: (imagePath) {
            unawaited(FileImage(File(imagePath)).evict());
            if (!mounted) return;
            final revision = _summaryImageState.value.revision + 1;
            setState(() {});
            _summaryImageState.value = SummaryImagePanelState(
              imagePath: imagePath,
              revision: revision,
            );
          },
        );

    if (!mounted || !_summaryImageState.value.generating) return;
    final latest = _summaryImageState.value;
    _summaryImageState.value = SummaryImagePanelState(
      imagePath: latest.imagePath,
      revision: latest.revision,
    );
  }

  Future<bool?> _showSummaryImageCostDialog() async {
    var dontAskAgain = false;
    final cfg = ref.read(imageGenerationConfigProvider);
    final role = AgentApiNotifier.globalImageRole;
    final cost = role.provider == AgentApiProvider.openai
        ? estimateOpenAICost(
            aspectRatio: cfg.aspectRatio,
            fidelity: cfg.fidelity,
          )
        : null;
    final costLine = cost != null
        ? '当前设置预估费用约 \$${cost.toStringAsFixed(3)} / 张'
        : '';

    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final theme = Theme.of(ctx);
            final cs = theme.colorScheme;
            return AlertDialog(
              backgroundColor: cs.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              title: Text(
                '生成总结图',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '总结图由第三方生图模型生成，可能产生 API 调用费用。',
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (costLine.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      costLine,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () =>
                        setDialogState(() => dontAskAgain = !dontAskAgain),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            value: dontAskAgain,
                            onChanged: (v) =>
                                setDialogState(() => dontAskAgain = v ?? false),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '不再提醒',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () {
                    if (dontAskAgain) {
                      GStorage.setting.put(_kSummaryImageCostDismissed, true);
                    }
                    Navigator.of(ctx).pop(true);
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openSummaryImage([String? imagePath]) async {
    final path =
        imagePath ??
        DocumentSummaryImageService.imagePathFor(widget.document.filePath);
    if (!await File(path).exists()) {
      ref.read(snackBarServiceProvider).showResult(message: '总结图文件不存在');
      return;
    }
    if (!mounted) return;
    final entry = FigureManifestEntry(
      imagePath: path,
      captionText: 'Graphical Summary',
      pageIndex: 0,
      blockIds: const [],
    );
    await showFigureViewer(context, [entry]);
  }

  Widget _buildExtractButton(ColorScheme cs, bool extracting) {
    if (extracting) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_hasResult) {
      return IconButton(
        icon: Icon(
          _showPreview
              ? Symbols.picture_as_pdf_rounded
              : Symbols.article_rounded,
          size: 22,
          fill: 1,
          color: cs.onSurfaceVariant,
        ),
        tooltip: _showPreview ? '查看 PDF' : '查看提取结果',
        onPressed: _togglePreview,
      );
    }

    return IconButton(
      icon: Icon(
        Symbols.document_scanner_rounded,
        size: 22,
        fill: 1,
        color: cs.onSurfaceVariant,
      ),
      tooltip: '文档提取',
      onPressed: _onExtractPressed,
    );
  }

  Widget _buildBody(
    ThemeData theme,
    ColorScheme cs,
    ReaderSettingsState readerSettings,
  ) {
    final showMarkdown = _showPreview && _hasResult;

    return NotificationListener<UserScrollNotification>(
      onNotification: _handlePdfScrollNotification,
      child: Listener(
        onPointerSignal: _handlePdfPointerSignal,
        onPointerMove: _handlePdfPointerMove,
        child: PageTransitionSwitcher(
          duration: const Duration(milliseconds: 300),
          reverse: !showMarkdown,
          transitionBuilder: (child, animation, secondaryAnimation) {
            return SharedAxisTransition(
              animation: animation,
              secondaryAnimation: secondaryAnimation,
              transitionType: SharedAxisTransitionType.horizontal,
              fillColor: Colors.transparent,
              child: child,
            );
          },
          child: showMarkdown
              ? KeyedSubtree(
                  key: const ValueKey('markdown'),
                  child: _buildMarkdownPreview(theme, readerSettings),
                )
              : PdfViewer.file(
                  key: const ValueKey('pdf'),
                  widget.document.filePath,
                  controller: _pdfController,
                  params: PdfViewerParams(
                    backgroundColor: Colors.transparent,
                    matchTextColor: cs.primaryContainer.withAlpha(150),
                    activeMatchTextColor: cs.primary.withAlpha(72),
                    onViewerReady: _bindPdfSearcher,
                    pagePaintCallbacks: _pdfSearcher == null
                        ? null
                        : [_pdfSearcher!.pageTextMatchPaintCallback],
                    viewerOverlayBuilder: (context, size, handleLinkTap) => [
                      PdfViewerScrollThumb(
                        controller: _pdfController,
                        orientation: ScrollbarOrientation.right,
                        thumbSize: const Size(8, 48),
                        margin: 2,
                        thumbBuilder:
                            (context, thumbSize, pageNumber, controller) {
                              return _PdfScrollThumb(size: thumbSize);
                            },
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildMarkdownPreview(ThemeData theme, ReaderSettingsState settings) {
    if (_markdownLoadError != null) {
      return Center(
        child: Text(
          '加载失败',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      );
    }

    if (_mdContent == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // 工具栏高度通过 topInset/bottomInset 传入 ListView padding，
    // 使内容全屏渲染、可滚动到半透明工具栏背后，消除工具栏隐藏后的空白。
    final topPad = 48.0;
    final bottomPad = 56.0 + MediaQuery.of(context).padding.bottom;

    // 翻译完成后按当前模式织入译文；未翻译或进行中保持原文，避免长文档
    // 在翻译过程中反复重建 widget 列表（完成时一次性切换即可）。
    final translation = ref.watch(
      documentTranslationProvider(widget.document.filePath),
    );
    final displayStyle = ref.watch(
      translationConfigProvider.select((c) => c.displayStyle),
    );
    final effectiveMd = translation.hasResult
        ? applyTranslationToMarkdown(
            markdown: _mdContent!,
            paragraphs: translation.paragraphs,
            translations: translation.translations,
            mode: translation.mode,
            style: displayStyle,
          )
        : _mdContent!;

    return NotificationListener<UserScrollNotification>(
      onNotification: _handleMarkdownScrollNotification,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _toggleToolbars,
        child: _wrapWithSelection(
          ReaderMarkdownBody(
            key: ValueKey('reader_md_${effectiveMd.hashCode}'),
            data: effectiveMd,
            settings: settings,
            translationStyleId: displayStyle.id,
            scrollController: _scrollController,
            selectedTextListenable: _selectedTextNotifier,
            highlightQuery: _highlightQuery,
            topInset: topPad,
            bottomInset: bottomPad,
            onImageTap: _handleMarkdownImageTap,
          ),
        ),
      ),
    );
  }

  /// 点击 markdown 中的图片 → 加载 figure manifest 后跳转 FigureViewer。
  ///
  /// 匹配策略：从 url 提取 basename（`Figure_N.png`）与 manifest entry
  /// 的 `imagePath` basename 比对，和 outline_panel 保持一致。
  Future<void> _handleMarkdownImageTap(String url) async {
    final pdfPath = widget.document.filePath;
    if (pdfPath.isEmpty) return;

    // 从 url 提取文件名：file:// URI 走 Uri 解析，否则直接取最后一段
    String fileName;
    try {
      fileName = url.startsWith('file://')
          ? p.basename(Uri.parse(url).toFilePath())
          : url.split(RegExp(r'[/\\]')).last;
    } catch (_) {
      fileName = url.split(RegExp(r'[/\\]')).last;
    }
    if (fileName.isEmpty) return;

    _figuresFuture ??= FigureExtractService.loadManifest(pdfPath);
    final figures = await _figuresFuture;
    if (!mounted) return;
    if (figures == null || figures.isEmpty) return;

    final index = figures.indexWhere(
      (e) => p.basename(e.imagePath) == fileName,
    );
    if (index < 0) return;

    await showFigureViewer(context, figures, initialIndex: index);
  }

  /// 用 SelectionArea + Listener 包裹 Markdown 内容。
  ///
  /// 选择完成后（pointer up + 新文本被选中）自动在选中文本下方弹出工具栏，
  /// 无需右键。contextMenuBuilder 返回空以禁用系统默认菜单。
  Widget _wrapWithSelection(Widget child) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _pointerDownPosition = event.position;
        _textOnPointerDown = _selectedText;
        _dismissSelectionToolbar();
      },
      onPointerUp: (event) {
        final downPos = _pointerDownPosition ?? event.position;
        Future.delayed(const Duration(milliseconds: 100), () {
          if (!mounted) return;
          if (_selectedText != null &&
              _selectedText!.isNotEmpty &&
              _selectedText != _textOnPointerDown) {
            _showSelectionToolbarOverlay(downPos, event.position);
          }
        });
      },
      child: SelectionArea(
        key: _selectionAreaKey,
        contextMenuBuilder: (_, _) => const SizedBox.shrink(),
        onSelectionChanged: (content) {
          _selectedText = content?.plainText;
          _selectedTextNotifier.value = _selectedText;
          if (content == null || content.plainText.isEmpty) {
            _dismissSelectionToolbar();
          }
        },
        child: child,
      ),
    );
  }

  Widget _buildFileNotFound(ThemeData theme, ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.error_rounded, size: 48, color: cs.error),
          const SizedBox(height: 16),
          Text('找不到该文献的 PDF 文件', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Text(
              widget.document.filePath,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── PDF 滚动条（模拟 Material 系统滚动条外观） ───

class _PdfScrollThumb extends StatefulWidget {
  final Size size;
  const _PdfScrollThumb({required this.size});

  @override
  State<_PdfScrollThumb> createState() => _PdfScrollThumbState();
}

class _PdfScrollThumbState extends State<_PdfScrollThumb> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 与 Material Scrollbar 一致：默认半透明，悬停时加深
    final color = _hovered
        ? cs.onSurface.withAlpha(128)
        : cs.onSurface.withAlpha(66);
    final width = _hovered ? widget.size.width + 4 : widget.size.width;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: width,
        height: widget.size.height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(width / 2),
        ),
      ),
    );
  }
}
