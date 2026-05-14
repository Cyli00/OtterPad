import 'dart:io';

import 'package:animations/animations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../../data/models/book/document.dart';
import '../../data/models/collection/favorite.dart';
import '../../providers/api_provider.dart';
import '../../providers/document_task_provider.dart';
import '../../providers/document_translation_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/reader_settings_provider.dart';
import '../../providers/reader_session_provider.dart';
import '../../providers/summary_image_provider.dart';
import '../../providers/translation_config_provider.dart';
import '../../services/doc_extract_service.dart';
import '../../services/document_summary_image_service.dart';
import '../../services/figure_extract_service.dart';
import '../../services/reader/markdown_document_cache_service.dart';
import '../../data/models/book/highlight.dart';
import '../../providers/highlight_provider.dart';
import '../../services/snackbar_service.dart';
import '../../utils/markdown_translation_weaver.dart';
import 'coordinators/reader_summary_image_coordinator.dart';
import 'widgets/figure_viewer.dart';
import 'widgets/webview_markdown_reader.dart';
import 'widgets/outline_panel.dart';
import 'widgets/reader_bottom_bar.dart';
import 'widgets/reader_background.dart';
import 'widgets/reader_document_info_sheet.dart';
import 'widgets/reader_notes_sheet.dart';
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
  late final ReaderSessionArgs _sessionArgs;

  // WebView 阅读器引用（通过 GlobalKey 暴露方法）
  final _webViewReaderKey = GlobalKey<WebViewMarkdownReaderState>();

  // PDF 控制器（用于滚动滑条）
  final _pdfController = PdfViewerController();
  PdfTextSearcher? _pdfSearcher;
  VoidCallback? _disposePdfSearchListener;
  final _pdfSearchController = TextEditingController();
  final _pdfSearchFocusNode = FocusNode();
  String _pdfSearchQuery = '';

  // 选择工具栏 Overlay（WebView 选择走 JS 桥接）
  OverlayEntry? _selectionToolbarEntry;

  // 桌面端工具栏自动隐藏
  static const _kEdgeTriggerZone = 16.0;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  // Figure manifest 懒加载：首次点击图片时触发，Future 复用避免重复 IO
  Future<List<FigureManifestEntry>?>? _figuresFuture;

  final _summaryImageState = ValueNotifier<SummaryImageState>(
    const SummaryImageState(),
  );

  // 翻译进度 SnackBar 句柄——点按"翻译"时 show，翻译结束 finish/dismiss。
  SnackBarProgressHandle? _translationProgressHandle;

  @override
  void initState() {
    super.initState();
    _sessionArgs = ReaderSessionArgs(
      documentId: widget.document.filePath,
      title: widget.document.title,
      defaultReadingMode: ref.read(readerSettingsProvider).defaultReadingMode,
    );
  }

  ReaderSessionState get _session =>
      ref.read(readerSessionProvider(_sessionArgs));

  ReaderSessionNotifier get _sessionNotifier =>
      ref.read(readerSessionProvider(_sessionArgs).notifier);

  ReaderSummaryImageCoordinator get _summaryCoordinator =>
      ReaderSummaryImageCoordinator(
        context: context,
        ref: ref,
        document: widget.document,
        scaffoldKey: _scaffoldKey,
        summaryImageState: _summaryImageState,
        sessionNotifier: _sessionNotifier,
        openOutlineSheet: _openOutlineSheet,
      );

  // ─── 提取逻辑 ───

  void _onExtractPressed() {
    final filePath = widget.document.filePath;
    if (filePath.isEmpty || !File(filePath).existsSync()) {
      ref.read(snackBarServiceProvider).showResult(message: 'PDF 文件不存在');
      return;
    }

    ref
        .read(documentTaskProvider.notifier)
        .extractDocument(
          documentId: widget.document.id,
          filePath: filePath,
          title: widget.document.title,
          apiState: ref.read(docExtractApiProvider),
          onSuccess: (mdPath, markdownContent) {
            if (!mounted) return;
            _sessionNotifier.useExtractedMarkdown(
              markdownPath: mdPath,
              markdownContent: markdownContent,
            );
            _figuresFuture = null;
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

      _sessionNotifier.useExtractedMarkdown(
        markdownPath: mdPath,
        markdownContent: content,
      );
      _figuresFuture = null;
      ref.read(snackBarServiceProvider).showResult(message: '重新排版完成');
    } catch (e) {
      if (!mounted) return;
      ref.read(snackBarServiceProvider).showResult(message: '排版失败: $e');
    }
  }

  void _togglePreview() {
    final enteringMarkdown = _sessionNotifier.togglePreview();
    if (enteringMarkdown) {
      _pdfSearchFocusNode.unfocus();
      _pdfSearchController.clear();
      _pdfSearcher?.resetTextSearch();
      _pdfSearchQuery = '';
    }
  }

  // ─── 搜索 ───

  Future<void> _openSearch() async {
    final session = _session;
    if (session.showPreview) {
      await _sessionNotifier.openMarkdownSearch();
      return;
    }

    if (!_sessionNotifier.openPdfSearch()) return;
    if (_pdfSearchController.text != _pdfSearchQuery) {
      _pdfSearchController.text = _pdfSearchQuery;
    }
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
    if (_session.showPreview) {
      _sessionNotifier.closeSearch();
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
    _sessionNotifier.closeSearch();
    setState(() {
      _pdfSearchQuery = '';
    });
  }

  void _onSearchResultTap(
    List<SearchResult> results,
    int tappedIndex,
    String query,
  ) {
    final offset = _sessionNotifier.selectSearchResult(
      results,
      tappedIndex,
      query,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToCharOffset(offset);
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) {
          _webViewReaderKey.currentState?.activateNearestSearchResult();
        }
      });
    });
  }

  void _clearHighlight() {
    _sessionNotifier.clearHighlight();
  }

  void _goToPrevResult() {
    final offset = _sessionNotifier.goToPreviousSearchResult();
    if (offset == null) return;
    _scrollToCharOffset(offset);
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) {
        _webViewReaderKey.currentState?.activateNearestSearchResult();
      }
    });
  }

  void _goToNextResult() {
    final offset = _sessionNotifier.goToNextSearchResult();
    if (offset == null) return;
    _scrollToCharOffset(offset);
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) {
        _webViewReaderKey.currentState?.activateNearestSearchResult();
      }
    });
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
    if (_session.markdownContent == null) return;
    _sessionNotifier.setSheetOpen(true);
    await showReaderTextSheet(context);
    _sessionNotifier.setSheetOpen(false);
  }

  Future<void> _openThemeSheet() async {
    _sessionNotifier.setSheetOpen(true);
    await showReaderThemeSheet(context);
    _sessionNotifier.setSheetOpen(false);
  }

  void _openNotesSheet() {
    if (widget.document.filePath.isEmpty) return;
    showReaderNotesSheet(context, documentId: widget.document.filePath);
  }

  void _openOutlineSheet() {
    if (_session.markdownContent == null) return;
    _scaffoldKey.currentState?.openEndDrawer();
  }

  // ─── 沉浸式 ───

  // _toggleToolbars / _handleMarkdownScrollNotification 已移除，
  // WebView 内部 JS 检测滚动方向并通过 onScrollDirection 回调。

  bool _handlePdfScrollNotification(UserScrollNotification notification) {
    final session = _session;
    if (session.showPreview || !(_sessionNotifier.canReactToReaderScroll)) {
      return false;
    }

    _sessionNotifier.handleReaderScrollDirection(notification.direction);
    return false;
  }

  void _handlePdfPointerSignal(PointerSignalEvent event) {
    final session = _session;
    if (session.showPreview || !(_sessionNotifier.canReactToReaderScroll)) {
      return;
    }
    if (event is! PointerScrollEvent) return;

    if (event.scrollDelta.dy > 0) {
      _sessionNotifier.handleReaderScrollDirection(ScrollDirection.reverse);
    } else if (event.scrollDelta.dy < 0) {
      _sessionNotifier.handleReaderScrollDirection(ScrollDirection.forward);
    }
  }

  void _handlePdfPointerMove(PointerMoveEvent event) {
    final session = _session;
    if (session.showPreview || !(_sessionNotifier.canReactToReaderScroll)) {
      return;
    }

    if (event.delta.dy < -1) {
      _sessionNotifier.handleReaderScrollDirection(ScrollDirection.reverse);
    } else if (event.delta.dy > 1) {
      _sessionNotifier.handleReaderScrollDirection(ScrollDirection.forward);
    }
  }

  /// 桌面端：鼠标靠近上下边缘时显示工具栏。
  ///
  /// 隐藏仍由滚动方向或点击内容区触发，不再按无交互时长自动隐藏。
  void _onDesktopPointerHover(PointerHoverEvent event) {
    final session = _session;
    final canShowToolbars =
        (session.showPreview &&
            session.hasResult &&
            session.markdownContent != null) ||
        (!session.showPreview && session.fileExists);
    if (!canShowToolbars || session.sheetOpen) return;
    final height = context.size?.height ?? 0;
    final y = event.localPosition.dy;
    if (y < _kEdgeTriggerZone || y > height - _kEdgeTriggerZone) {
      _sessionNotifier.revealToolbars();
    }
  }

  // ─── 段落上下文扩展（翻译用）───

  String? _expandToParagraphContext(String selectedText) {
    return _session.expandToParagraphContext(selectedText);
  }

  // ─── 大纲导航 ───

  void _tryFlashImageAtOffset(int charOffset) {
    final filename = _session.imageFilenameNearOffset(charOffset);
    if (filename == null) return;
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _webViewReaderKey.currentState?.flashImage(filename);
    });
  }

  /// 统一跳转：charOffset → block index → WebView scrollToBlock。
  ///
  /// `\n\n+` 分割数 = `#content > *` 直接子元素数（顶层块 1:1 对应）。
  void _scrollToCharOffset(int charOffset) {
    final blockIndex = _session.blockIndexForCharOffset(charOffset);
    if (blockIndex == null) return;
    _webViewReaderKey.currentState?.scrollToBlockIndex(blockIndex);
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

  // ─── 高亮标记 ───

  void _addHighlight(String text, String color) {
    final created = _sessionNotifier.addHighlight(text, color);
    if (created != null) {
      _webViewReaderKey.currentState?.addHighlightFromSelection(
        created.id,
        color,
      );
    }
  }

  void _removeHighlight(String highlightId) {
    _sessionNotifier.removeHighlight(highlightId);
  }

  void _updateHighlightColor(String highlightId, String color) {
    _sessionNotifier.updateHighlightColor(highlightId, color);
  }

  void _handleHighlightTap(Highlight highlight, Offset position) {
    _dismissSelectionToolbar();
    final rect = Rect.fromCenter(center: position, width: 4, height: 4);
    _selectionToolbarEntry = showReaderContextMenu(
      context: context,
      selectionRect: rect,
      selectedText: highlight.text,
      existingHighlight: highlight,
      onHighlight: (color) => _updateHighlightColor(highlight.id, color),
      onCopy: () {
        Clipboard.setData(ClipboardData(text: highlight.text));
        ref
            .read(snackBarServiceProvider)
            .showResult(
              message: '已复制到剪贴板',
              duration: const Duration(seconds: 1),
            );
      },
      onTranslate: () {
        final fullText = _expandToParagraphContext(highlight.text.trim());
        showTranslationPopup(
          context,
          sourceText: highlight.text.trim(),
          fullText: fullText,
        );
      },
      onNoteChanged: _sessionNotifier.updateHighlightNote,
      onDelete: () => _removeHighlight(highlight.id),
      onDismiss: () => _selectionToolbarEntry = null,
    );
  }

  void _handleWebViewSelectionEnd(String text, Rect rect) {
    _dismissSelectionToolbar();
    if (text.trim().isEmpty) return;
    _selectionToolbarEntry = showReaderContextMenu(
      context: context,
      selectionRect: rect,
      selectedText: text,
      onHighlight: (color) => _addHighlight(text, color),
      onCopy: () {
        Clipboard.setData(ClipboardData(text: text));
        ref
            .read(snackBarServiceProvider)
            .showResult(
              message: '已复制到剪贴板',
              duration: const Duration(seconds: 1),
            );
      },
      onTranslate: () {
        final trimmed = text.trim();
        final fullText = _expandToParagraphContext(trimmed);
        showTranslationPopup(context, sourceText: trimmed, fullText: fullText);
      },
      onCreateForNote: () {
        return _sessionNotifier.addHighlight(text, kDefaultHighlightColor);
      },
      onNoteChanged: _sessionNotifier.updateHighlightNote,
      onDismiss: () => _selectionToolbarEntry = null,
    );
  }

  void _handleWebViewSelectionCleared() {
    _dismissSelectionToolbar();
  }

  void _handleWebViewScrollDirection(ScrollDirection direction) {
    if (!_sessionNotifier.canReactToReaderScroll) return;
    // 横向翻页模式下不让滚动方向驱动工具栏隐藏——翻页时工具栏会频繁
    // 闪烁。横向模式的工具栏 toggle 改由 JS 中央点击触发（onToggleToolbar）。
    final mode = ref.read(readerSettingsProvider).paginationMode;
    if (mode == ReaderPaginationMode.horizontal) return;
    _sessionNotifier.handleReaderScrollDirection(direction);
  }

  void _handleWebViewToggleToolbar() {
    _sessionNotifier.toggleToolbars();
  }

  // ─── 选择/标记工具栏 ───

  void _dismissSelectionToolbar() {
    _selectionToolbarEntry?.remove();
    _selectionToolbarEntry = null;
  }

  // 旧原生选择基础设施已移除，由 WebView 选择处理替代

  @override
  void dispose() {
    _disposePdfSearchListener?.call();
    _pdfSearcher?.dispose();
    _pdfSearchController.dispose();
    _pdfSearchFocusNode.dispose();
    _summaryImageState.dispose();
    _selectionToolbarEntry?.remove();
    super.dispose();
  }

  // ─── UI ───

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final readerSettings = ref.watch(readerSettingsProvider);
    final session = ref.watch(readerSessionProvider(_sessionArgs));
    final extractTaskKey = DocumentTaskKey(
      type: DocumentTaskType.extractDocument,
      documentId: widget.document.id,
    );
    final extracting = ref.watch(
      documentTaskProvider.select(
        (tasks) => tasks[extractTaskKey]?.isActive == true,
      ),
    );
    _syncInitialSummaryImage(session);

    // 异步初始化完成前显示骨架加载状态
    if (!session.initialized) {
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

    final fileExists = session.fileExists;

    final contentBg = (session.showPreview && session.hasResult)
        ? resolveReaderPalette(readerSettings.theme, cs).background
        : cs.surface;

    final isMarkdownHighlightMode = session.markdownHighlightMode;
    final pdfMatchCount = _pdfSearcher?.matches.length ?? 0;
    final showPdfNavigator = !session.showPreview && _pdfSearchQuery.isNotEmpty;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: cs.surface,
      endDrawerEnableOpenDragGesture: false,
      endDrawer: session.markdownContent != null
          ? Drawer(
              width: 380,
              child: OutlinePanel(
                key: ValueKey(session.markdownContent.hashCode),
                markdownContent: session.markdownContent!,
                pdfPath: widget.document.filePath,
                summaryImageState: _summaryImageState,
                onNavigate: (offset) {
                  _scaffoldKey.currentState?.closeEndDrawer();
                  _scrollToCharOffset(offset);
                  _tryFlashImageAtOffset(offset);
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
                      ? _buildBody(theme, cs, readerSettings, session)
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
                  offset: session.toolbarsVisible
                      ? Offset.zero
                      : const Offset(0, -1),
                  child: Container(
                    color: cs.surface.withValues(
                      alpha: readerSettings.toolbarOpacity.value,
                    ),
                    child: isMarkdownHighlightMode
                        ? _buildHighlightSearchBar()
                        : (session.searchActive && !session.showPreview
                              ? _buildPdfSearchBar()
                              : _buildToolbar(cs, extracting: extracting)),
                  ),
                ),
              ),
              // ── 底部工具栏（仅 Markdown 模式；沉浸式时向下滑出） ──
              if (session.showPreview &&
                  session.hasResult &&
                  session.markdownContent != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    offset: session.toolbarsVisible
                        ? Offset.zero
                        : const Offset(0, 1),
                    child: _buildBottomBar(readerSettings),
                  ),
                ),
              // ── 浮动搜索结果导航器 ──
              if (isMarkdownHighlightMode && session.searchResults.isNotEmpty)
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
              if (session.searchActive &&
                  session.showPreview &&
                  session.searchSnapshot != null)
                Positioned.fill(
                  child: SearchOverlay(
                    readerSettings: readerSettings,
                    searchSnapshot: session.searchSnapshot!,
                    onResultTap: _onSearchResultTap,
                    onDismiss: _closeSearch,
                    initialQuery: session.highlightQuery,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _syncInitialSummaryImage(ReaderSessionState session) {
    final imagePath = session.summaryImagePath;
    final current = _summaryImageState.value;
    if (imagePath == null || current.imagePath != null || current.generating) {
      return;
    }
    _summaryImageState.value = SummaryImageState(imagePath: imagePath);
  }

  /// 顶部工具栏：返回 / 搜索 / PDF↔MD 切换 / 重新提取 / 信息
  ///
  /// 大纲、外观（颜色/背景）、字体面板 3 个按钮已挪到 [_buildBottomBar]。
  Widget _buildToolbar(ColorScheme cs, {bool extracting = false}) {
    final session = ref.watch(readerSessionProvider(_sessionArgs));
    final favorites = ref.watch(favoritesProvider);
    final inFavorite = _isInAnyFavorite(favorites);
    final translation = ref.watch(
      documentTranslationProvider(widget.document.filePath),
    );
    final summaryImagePath = DocumentSummaryImageService.imagePathFor(
      widget.document.filePath,
    );

    return ReaderTopToolbar(
      showPreview: session.showPreview,
      hasResult: session.hasResult,
      hasMarkdownContent: session.markdownContent != null,
      fileExists: session.fileExists,
      inFavorite: inFavorite,
      extracting: extracting,
      canRetranslate: translation.hasResult && session.markdownContent != null,
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
      onOpenSummaryImage: () => _summaryCoordinator.openSummaryImage(),
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
    final session = ref.watch(readerSessionProvider(_sessionArgs));
    return ReaderHighlightSearchBar(
      query: session.highlightQuery ?? '',
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
    final session = ref.watch(readerSessionProvider(_sessionArgs));
    return ReaderTextResultNavigator(
      currentIndex: session.currentResultIndex,
      total: session.searchResults.length,
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
    final markdown = _session.markdownContent;
    if (markdown == null || markdown.isEmpty) return;

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

    final fullyCached = await notifier.translate(markdown);
    if (!mounted) return;

    final state = ref.read(documentTranslationProvider(pdfPath));
    final handle = _translationProgressHandle;
    _translationProgressHandle = null;
    if (state.status == DocTranslationStatus.done) {
      // 完全命中文件缓存：本次点击没有真的翻译（也没有花 API 配额），
      // 用户可能困惑"为什么这么快/翻得跟上次一样"——明确提示并指引
      // 重新翻译路径（顶栏省略号 → 重新翻译）。文案较长所以延长展示时间。
      handle?.finish(
        message: fullyCached ? '使用了之前的翻译缓存，如需重新翻译请点击右上角省略号里的重新翻译' : '翻译完成',
        duration: fullyCached ? const Duration(seconds: 6) : null,
      );
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
    final markdown = _session.markdownContent;
    if (markdown == null || markdown.isEmpty) return;

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

    await notifier.retranslate(markdown);
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

  Future<void> _handleGenerateSummaryImage({bool openOutline = true}) async {
    await _summaryCoordinator.generate(openOutline: openOutline);
  }

  Widget _buildExtractButton(ColorScheme cs, bool extracting) {
    final session = ref.watch(readerSessionProvider(_sessionArgs));
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

    if (session.hasResult) {
      return IconButton(
        icon: Icon(
          session.showPreview
              ? Symbols.picture_as_pdf_rounded
              : Symbols.article_rounded,
          size: 22,
          fill: 1,
          color: cs.onSurfaceVariant,
        ),
        tooltip: session.showPreview ? '查看 PDF' : '查看提取结果',
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
    ReaderSessionState session,
  ) {
    final showMarkdown = session.showPreview && session.hasResult;

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
                  child: _buildMarkdownPreview(theme, readerSettings, session),
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

  Widget _buildMarkdownPreview(
    ThemeData theme,
    ReaderSettingsState settings,
    ReaderSessionState session,
  ) {
    if (session.markdownLoadError != null) {
      return Center(
        child: Text(
          '加载失败',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      );
    }

    if (session.markdownContent == null) {
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
    final markdownContent = session.markdownContent!;
    final effectiveMd = translation.hasResult
        ? applyTranslationToMarkdown(
            markdown: markdownContent,
            paragraphs: translation.paragraphs,
            translations: translation.translations,
            mode: translation.mode,
            style: displayStyle,
          )
        : markdownContent;

    final cs = Theme.of(context).colorScheme;
    final palette = resolveReaderPalette(settings.theme, cs);
    final highlights = ref.watch(highlightProvider(widget.document.filePath));
    final documentDir = p.dirname(widget.document.filePath);

    return WebViewMarkdownReader(
      key: _webViewReaderKey,
      markdownData: effectiveMd,
      settings: settings,
      palette: palette,
      highlights: highlights,
      documentDir: documentDir,
      topInset: topPad,
      bottomInset: bottomPad,
      highlightQuery: session.highlightQuery,
      onSelectionEnd: _handleWebViewSelectionEnd,
      onSelectionCleared: _handleWebViewSelectionCleared,
      onHighlightClick: _handleHighlightTap,
      onImageClick: _handleMarkdownImageTap,
      onScrollDirection: _handleWebViewScrollDirection,
      onToggleToolbar: _handleWebViewToggleToolbar,
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

  // _wrapWithSelection 已移除，由 WebView 内部选择处理替代

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
