import 'dart:async';
import 'dart:io';
import 'package:animations/animations.dart';
import '../../core/animation_constants.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../data/models/book/document.dart';
import '../../data/models/collection/favorite.dart';
import '../../providers/api_provider.dart';
import '../../providers/document_lifecycle_provider.dart';
import '../../providers/document_task_provider.dart';
import '../../providers/document_translation_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/history_provider.dart';
import '../../providers/reader_settings_provider.dart';
import '../../providers/reader_session_provider.dart';
import '../../providers/summary_image_provider.dart';
import '../../providers/translation_config_provider.dart';
import '../../router/app_routes.dart';
import '../../services/agent_model_capability.dart';
import '../../services/ai_settings_prompt.dart';
import '../../services/doc_extract_service.dart';
import '../../widgets/app_dialog.dart';
import '../../services/document_summary_image_service.dart';
import '../../services/figure_extract_service.dart';
import '../../data/models/book/highlight.dart';
import '../../providers/highlight_provider.dart';
import '../../services/haptics.dart';
import '../../services/snackbar_service.dart';
import '../../utils/doc_paths.dart';
import '../../utils/markdown_translation_weaver.dart';
import 'chat/document_chat_page.dart';
import 'coordinators/reader_summary_image_coordinator.dart';
import 'widgets/figure_viewer.dart';
import 'widgets/webview_markdown_reader.dart';
import 'widgets/outline_panel.dart';
import 'widgets/reader_bottom_bar.dart';
import 'widgets/reader_chat_return_prompt.dart';
import 'widgets/reader_background.dart';
import 'widgets/reader_document_info_sheet.dart';
import 'widgets/reader_notes_sheet.dart';
import 'widgets/reader_outline_sheet.dart';
import 'widgets/reader_favorite_sheet.dart';
import 'widgets/reader_pdf_search_controller.dart';
import 'widgets/reader_search_bars.dart';
import 'widgets/reader_search_navigator.dart';
import 'widgets/reader_sheet_host.dart';
import 'widgets/reader_theme_sheet.dart';
import 'widgets/ai_layout_fix_dialog.dart';
import 'widgets/reader_top_toolbar.dart';
import 'widgets/search_overlay.dart';
import 'widgets/selection_toolbar.dart';
import 'widgets/translation_popup.dart';
import '../shelf/widgets/create_favorite_dialog.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/l10n.dart';

class ReaderPage extends ConsumerStatefulWidget {
  final Document document;

  const ReaderPage({super.key, required this.document});

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

/// 主 build 的 select 返回类型——Dart record 自带 structural ==。
/// 排除 currentResultIndex（由 [_ResultNavigator] 独立消费），
/// markdownContent 用 cacheKey 代替（避免大字符串逐字比较），
/// searchResultCount 只保留 length，error/snapshot 只保留 nullity。
typedef _MainBuildKey = (
  bool initialized,
  bool fileExists,
  bool showPreview,
  bool hasMarkdownContent,
  String? markdownCacheKey,
  bool toolbarsVisible,
  bool searchActive,
  bool isHighlightMode,
  String? summaryImagePath,
  String? highlightQuery,
  int searchResultCount,
  bool markdownLoading,
  bool hasMarkdownLoadError,
  bool hasResult,
  String? markdownPath,
);

class _ReaderPageState extends ConsumerState<ReaderPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _sheetHostKey = GlobalKey<ReaderSheetHostState>();
  late final ReaderSessionArgs _sessionArgs;
  ReaderSheetType? _activeSheet;

  /// 定位原文后暂存的问 AI 返回参数；非空时展示返回引导条。
  DocumentChatPageArgs? _chatReturnArgs;

  static _MainBuildKey _mainBuildSelector(ReaderSessionState s) => (
    s.initialized,
    s.fileExists,
    s.showPreview,
    s.markdownContent != null,
    s.markdownCacheKey,
    s.toolbarsVisible,
    s.searchActive,
    s.markdownHighlightMode,
    s.summaryImagePath,
    s.highlightQuery,
    s.searchResultCount,
    s.markdownLoading,
    s.markdownLoadError != null,
    s.hasResult,
    s.markdownPath,
  );

  // WebView 阅读器引用（通过 GlobalKey 暴露方法）
  final _webViewReaderKey = GlobalKey<WebViewMarkdownReaderState>();

  // PDF 控制器（用于滚动滑条）
  final _pdfController = PdfViewerController();
  final _pdfSearch = ReaderPdfSearchController();

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

  // AI 排版修复后通知 OutlinePanel 重新加载 figures manifest
  final _figuresEpoch = ValueNotifier<int>(0);

  // PDF 进度采集：上一次上报的 pageNumber 缓存，避免每次 controller 通知（包括
  // 滚动 / zoom / fit）都触发一次 reportProgress——只有 pageNumber 真变了才上报。
  int? _lastReportedPdfPage;

  double _markdownScrollProgress = 0;
  int? _markdownAnchorBlock;

  // AI 排版修复后强制 WebView 重载的纪元计数（见 ReaderProps.reloadEpoch）
  int _readerReloadEpoch = 0;

  @override
  void initState() {
    super.initState();
    // 重开文档恢复阅读位置：进度/锚点持久化在 HistoryEntry（事实源），
    // 经 initialScrollProgress / initialAnchorBlock 传入 WebView 在
    // onContentReady 时恢复。横向翻页优先锚点（比率在字号/窗口尺寸
    // 变化后会落错页），纵向按比率。
    final entry = ref
        .read(historyProvider)
        .where((e) => e.docId == widget.document.id)
        .firstOrNull;
    if (entry != null) {
      _markdownScrollProgress = entry.progress;
      _markdownAnchorBlock = entry.anchorBlock;
    }
    _sessionArgs = ReaderSessionArgs(
      documentId: widget.document.id,
      title: widget.document.title,
      defaultReadingMode: ref.read(readerSettingsProvider).defaultReadingMode,
    );
    // 在 initState 中 cache notifier 引用——Riverpod 3.x 禁止在 dispose()
    // 中通过 ref.read 取 provider（widget 已 unmount-pending）。Notifier 实
    // 例的生命周期由 provider 管理、独立于 widget，cache 安全。
    _sessionNotifier = ref.read(readerSessionProvider(_sessionArgs).notifier);
    _pdfController.addListener(_onPdfControllerChanged);
    // searcher / 查询变化即整页 rebuild，与重构前一致。
    _pdfSearch.addListener(_onPdfSearchChanged);
  }

  void _onPdfSearchChanged() {
    if (mounted) setState(() {});
  }

  /// PDF 控制器变化回调：仅在当前页号变化时上报。pdfrx 的 PdfViewerController
  /// 是 ChangeNotifier，滚动、zoom、fit 都会通知；筛 pageNumber 防抖。
  void _onPdfControllerChanged() {
    if (!_pdfController.isReady) return;
    final pageNumber = _pdfController.pageNumber;
    final totalPages = _pdfController.pages.length;
    if (pageNumber == null || totalPages <= 0) return;
    if (_lastReportedPdfPage == pageNumber) return;
    _lastReportedPdfPage = pageNumber;
    final progress = pageNumber / totalPages;
    _sessionNotifier.reportProgress(progress);
  }

  ReaderSessionState get _session =>
      ref.read(readerSessionProvider(_sessionArgs));

  late final ReaderSessionNotifier _sessionNotifier;

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
    final filePath = DocPaths.pdf(widget.document.id);
    if (widget.document.contentHash == null || !File(filePath).existsSync()) {
      ref
          .read(snackBarServiceProvider)
          .showResult(message: context.l10n.pdfNotFound);
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
            _sessionNotifier.useExtractedMarkdown(
              markdownPath: mdPath,
              markdownContent: markdownContent,
            );
            if (mounted) _figuresFuture = null;
          },
        );
  }

  Future<void> _onReprocessPressed() async {
    final filePath = DocPaths.pdf(widget.document.id);
    if (widget.document.contentHash == null || !File(filePath).existsSync()) {
      ref
          .read(snackBarServiceProvider)
          .showResult(message: context.l10n.pdfNotFound);
      return;
    }

    ref
        .read(snackBarServiceProvider)
        .showResult(message: context.l10n.reformatting);
    try {
      final (mdPath, content) = await DocExtractService.instance
          .reprocessMarkdown(pdfPath: filePath, title: widget.document.title);
      if (!mounted) return;

      // 推迟到下一帧：reprocess 完成那一刻可能还有正在 unmount 的子 Consumer
      // （工具栏 AnimatedSlide、search bar 等），同步发 state 通知会撞上 defunct
      // Element 的断言。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _sessionNotifier.useExtractedMarkdown(
          markdownPath: mdPath,
          markdownContent: content,
        );
        _figuresFuture = null;
        ref
            .read(snackBarServiceProvider)
            .showResult(message: context.l10n.reformatDone);
      });
    } catch (e) {
      if (!mounted) return;
      ref
          .read(snackBarServiceProvider)
          .showResult(message: context.l10n.reformatFailed('$e'));
    }
  }

  void _handleAiLayoutFix(BuildContext context) {
    final agentState = ref.read(effectiveAgentApiProvider);
    final modelId = agentState.defaultModelId;
    if (modelId == null) {
      ref
          .read(snackBarServiceProvider)
          .showResult(message: context.l10n.expertModelNotSet);
      return;
    }
    final cap = AgentModelCapability.infer(
      provider: agentState.provider,
      modelId: modelId,
    );
    if (!cap.imageInput) {
      ref
          .read(snackBarServiceProvider)
          .showResult(message: context.l10n.expertRequiresVision);
      return;
    }
    showAppDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AiLayoutFixDialog(
        documentId: widget.document.id,
        agentState: agentState,
        onComplete: () {
          // AI 修复只改 manifest + 原地覆盖 figures/*.png，md 内容不变——
          // 内容驱动的刷新链路（useExtractedMarkdown → cacheKey）会短路，
          // 用显式 reloadEpoch 强制 WebView 重载以取回新图（server 端
          // 图片已 no-store）；大纲面板自带 manifest 重读 + ImageCache evict。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _readerReloadEpoch++);
            _figuresFuture = null;
            _figuresEpoch.value++;
          });
        },
      ),
    );
  }

  void _togglePreview() {
    final enteringMarkdown = _sessionNotifier.togglePreview();
    if (enteringMarkdown) _pdfSearch.clear();
  }

  // ─── 搜索 ───

  Future<void> _openSearch() async {
    final session = _session;
    if (session.showPreview) {
      await _sessionNotifier.openMarkdownSearch();
      return;
    }

    if (!_sessionNotifier.openPdfSearch()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pdfSearch.focusForSearch();
    });
  }

  void _closeSearch() {
    if (_session.showPreview) {
      _sessionNotifier.closeSearch();
      return;
    }
    _clearPdfSearch();
  }

  void _clearPdfSearch() {
    _pdfSearch.clear();
    _sessionNotifier.closeSearch();
  }

  void _onSearchResultTap(int hitIndex, String query) {
    final count = _session.searchResultCount > 0
        ? _session.searchResultCount
        : hitIndex + 1;
    _sessionNotifier.selectSearchResult(hitIndex, query, count);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _webViewReaderKey.currentState?.scrollToSearchResult(hitIndex);
    });
  }

  void _clearHighlight() {
    _sessionNotifier.clearHighlight();
  }

  void _goToPrevResult() {
    final index = _sessionNotifier.goToPreviousSearchResult();
    if (index != null) {
      _webViewReaderKey.currentState?.scrollToSearchResult(index);
    }
  }

  void _goToNextResult() {
    final index = _sessionNotifier.goToNextSearchResult();
    if (index != null) {
      _webViewReaderKey.currentState?.scrollToSearchResult(index);
    }
  }

  // ─── 底部面板（外观 / 大纲） ───

  void _pauseWebView() => _webViewReaderKey.currentState?.pauseWebView();
  void _resumeWebView() => _webViewReaderKey.currentState?.resumeWebView();

  Future<void> _openThemeSheet() async {
    if (_activeSheet == ReaderSheetType.theme) {
      _sheetHostKey.currentState!.close();
      return;
    }
    final future = _sheetHostKey.currentState!.show(
      builder: (_) => const ReaderThemeSheetBody(),
      barrierAlpha: 0.25,
      onPause: _pauseWebView,
      onResume: _resumeWebView,
    );
    setState(() => _activeSheet = ReaderSheetType.theme);
    await future;
  }

  Future<void> _openNotesSheet() async {
    if (_activeSheet == ReaderSheetType.notes) {
      _sheetHostKey.currentState!.close();
      return;
    }
    final future = _sheetHostKey.currentState!.show(
      builder: (_) => ReaderNotesSheetBody(
        documentId: widget.document.id,
        onEditStart: () async =>
            _webViewReaderKey.currentState?.freeze(capture: false),
        onEditEnd: () => _webViewReaderKey.currentState?.unfreeze(),
      ),
    );
    setState(() => _activeSheet = ReaderSheetType.notes);
    await future;
  }

  void _openOutlineSheet() {
    if (_session.markdownContent == null) return;
    // 桌面端：380px 侧边 Drawer（屏幕够宽，多面板共存体验更好）。
    // 移动端：bottom sheet（Drawer 在窄屏会盖住整个阅读区，sheet 可半透出底层）。
    if (_isDesktop) {
      _scaffoldKey.currentState?.openEndDrawer();
    } else {
      if (_activeSheet == ReaderSheetType.outline) {
        _sheetHostKey.currentState!.close();
        return;
      }
      _showOutlineBottomSheet();
    }
  }

  Future<void> _showOutlineBottomSheet() async {
    final session = _session;
    if (session.markdownContent == null) return;

    final future = _sheetHostKey.currentState!.show(
      barrierAlpha: 0.45,
      builder: (_) => ReaderOutlineSheetBody(
        markdownContent: session.markdownContent!,
        documentId: widget.document.id,
        document: widget.document,
        onLocateQuote: _locateQuoteInReader,
        summaryImageState: _summaryImageState,
        figuresEpoch: _figuresEpoch,
        onNavigate: (offset) {
          _sheetHostKey.currentState!.close();
          _scrollToCharOffset(offset);
          _tryFlashImageAtOffset(offset);
        },
        onUploadSummaryImage: () {
          _summaryCoordinator.uploadFromGallery();
        },
      ),
    );
    setState(() => _activeSheet = ReaderSheetType.outline);
    await future;
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

  void _scrollToCharOffset(int charOffset) {
    final md = _session.markdownContent;
    if (md == null || md.isEmpty) return;
    final safeOffset = charOffset.clamp(0, md.length);
    final breaks = RegExp(r'\n\n+').allMatches(md);
    var blockIndex = 0;
    for (final brk in breaks) {
      if (brk.start >= safeOffset) break;
      blockIndex++;
    }
    _webViewReaderKey.currentState?.scrollToBlockIndex(blockIndex);
  }

  bool _isInAnyFavorite(List<Favorite> favorites) {
    final documentId = widget.document.id;
    return favorites.any((fav) => fav.documentIds.contains(documentId));
  }

  List<Favorite> _favoritesContainingDoc(List<Favorite> favorites) {
    final documentId = widget.document.id;
    return favorites
        .where((fav) => fav.documentIds.contains(documentId))
        .toList();
  }

  Future<void> _showFavoritePicker() async {
    final documentId = widget.document.id;

    final result = await _showFavoritePickerSheet(
      title: context.l10n.moveToFavorite,
      favorites: ref.read(favoritesProvider),
      documentId: documentId,
      mode: ReaderFavoritePickerMode.add,
    );
    if (!mounted || result == null) return;

    final selected = result.favorites
        .where((favorite) => !favorite.documentIds.contains(documentId))
        .toList();
    if (selected.isEmpty) return;

    for (final favorite in selected) {
      await ref
          .read(documentLifecycleProvider)
          .addToFavorite(favorite.id, documentId);
    }
    if (!mounted) return;
    final message = selected.length == 1
        ? context.l10n.addedToFavorite(selected.single.name)
        : context.l10n.addedToFavorites(selected.length);
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
    final documentId = widget.document.id;

    final favorites = _favoritesContainingDoc(ref.read(favoritesProvider));
    if (favorites.isEmpty) {
      ref
          .read(snackBarServiceProvider)
          .showResult(message: context.l10n.documentNotInFavorite);
      return;
    }

    final result = await _showFavoritePickerSheet(
      title: context.l10n.removeFromFavorite,
      favorites: favorites,
      documentId: documentId,
      mode: ReaderFavoritePickerMode.remove,
    );
    if (!mounted) return;
    final selected = result?.favorites ?? const <Favorite>[];
    if (selected.isEmpty) return;

    for (final favorite in selected) {
      await ref
          .read(documentLifecycleProvider)
          .removeFromFavorite(favorite.id, documentId);
    }
    if (!mounted) return;
    final message = selected.length == 1
        ? context.l10n.removedFromFavoriteSingle(selected.single.name)
        : context.l10n.removedFromFavorites(selected.length);
    ref.read(snackBarServiceProvider).showResult(message: message);
  }

  Future<ReaderFavoriteSelectionResult?> _showFavoritePickerSheet({
    required String title,
    required List<Favorite> favorites,
    required String documentId,
    required ReaderFavoritePickerMode mode,
  }) {
    return _sheetHostKey.currentState!.show<ReaderFavoriteSelectionResult>(
      builder: (_) => ReaderFavoritePickerContent(
        title: title,
        favorites: favorites,
        documentId: documentId,
        mode: mode,
        onCreateFavorite: mode == ReaderFavoritePickerMode.add
            ? _createFavoriteFromPicker
            : null,
      ),
    );
  }

  void _showDocumentInfo(BuildContext context) {
    showDocumentInfoDialog(context: context, document: widget.document);
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

  void _handleHighlightTap(Highlight highlight, Rect rect) {
    if (!mounted) return;
    _dismissSelectionToolbar();
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
              message: context.l10n.copiedToClipboard,
              duration: const Duration(seconds: 1),
            );
      },
      onAskAi: () => _openAiChat(quote: highlight.text.trim()),
      onTranslate: () {
        final fullText = _expandToParagraphContext(highlight.text.trim());
        showTranslationPopup(
          context,
          sourceText: highlight.text.trim(),
          fullText: fullText,
          // 已有高亮：换色 + 译文写入注解
          onAddNote: (color, note) {
            _updateHighlightColor(highlight.id, color);
            _sessionNotifier.updateHighlightNote(highlight.id, note);
          },
        );
      },
      onNoteChanged: _sessionNotifier.updateHighlightNote,
      onDelete: () => _removeHighlight(highlight.id),
      onDismiss: () => _selectionToolbarEntry = null,
    );
  }

  void _handleWebViewSelectionEnd(String text, Rect rect) {
    if (!mounted) return;
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
              message: context.l10n.copiedToClipboard,
              duration: const Duration(seconds: 1),
            );
      },
      onAskAi: () => _openAiChat(quote: text.trim()),
      onTranslate: () {
        final trimmed = text.trim();
        final fullText = _expandToParagraphContext(trimmed);
        // 清掉 WebView 选区：原生选择手柄在系统窗口层、会"穿透"弹窗显示
        _webViewReaderKey.currentState?.clearSelection();
        showTranslationPopup(
          context,
          sourceText: trimmed,
          fullText: fullText,
          // 按文本恢复路径建高亮（选区已清，精确 Range 不可用）+ 译文作注解
          onAddNote: (color, note) {
            final h = _sessionNotifier.addHighlight(trimmed, color);
            if (h != null) {
              _sessionNotifier.updateHighlightNote(h.id, note);
            }
          },
        );
      },
      onCreateForNote: () {
        return _sessionNotifier.addHighlight(text, kDefaultHighlightColor);
      },
      onNoteChanged: _sessionNotifier.updateHighlightNote,
      onDismiss: () => _selectionToolbarEntry = null,
    );
  }

  void _handleWebViewSelectionCleared() {
    if (!mounted) return;
    _dismissSelectionToolbar();
  }

  void _handleWebViewScrollDirection(ScrollDirection direction) {
    if (!mounted) return;
    if (!_sessionNotifier.canReactToReaderScroll) return;
    // 横向翻页模式下不让滚动方向驱动工具栏隐藏——翻页时工具栏会频繁
    // 闪烁。横向模式的工具栏 toggle 改由 JS 中央点击触发（onToggleToolbar）。
    final mode = ref.read(readerSettingsProvider).paginationMode;
    if (mode == ReaderPaginationMode.horizontal) return;
    _sessionNotifier.handleReaderScrollDirection(direction);
  }

  void _handleWebViewToggleToolbar() {
    if (!mounted) return;
    _sessionNotifier.toggleToolbars();
  }

  /// 打开问 AI 对话页。[quote] 是划词引用；底栏入口不带引用。
  void _openAiChat({String? quote}) {
    setState(() => _chatReturnArgs = null);
    // 清掉 WebView 选区：原生选择手柄在系统窗口层、会"穿透"新路由显示
    _webViewReaderKey.currentState?.clearSelection();
    context.push(
      AppRoutes.readerChat,
      extra: DocumentChatPageArgs(
        document: widget.document,
        initialQuote: quote,
        onLocateQuote: _locateQuoteInReader,
      ),
    );
  }

  /// 会话历史「定位原文」——按引用文本在 markdown 源里找偏移，复用大纲
  /// 跳转的滚动管线。渲染文本与源文本可能因 Markdown 标记不一致，全文
  /// 匹配失败时退化为引用前 30 字符。
  void _locateQuoteInReader(String quote, DocumentChatPageArgs returnArgs) {
    final md = _session.markdownContent;
    final trimmed = quote.trim();
    if (md == null || trimmed.isEmpty) return;
    var idx = md.indexOf(trimmed);
    if (idx < 0 && trimmed.length > 30) {
      idx = md.indexOf(trimmed.substring(0, 30));
    }
    if (idx >= 0) _scrollToCharOffset(idx);
    setState(() => _chatReturnArgs = returnArgs);
  }

  void _returnToChat() {
    final args = _chatReturnArgs;
    if (args == null) return;
    Haptics.soft();
    setState(() => _chatReturnArgs = null);
    _webViewReaderKey.currentState?.clearSelection();
    context.push(AppRoutes.readerChat, extra: args);
  }

  double _chatReturnPromptBottom(ReaderSessionState session) {
    final padding = MediaQuery.paddingOf(context).bottom;
    const barHeight = 56.0;
    final barVisible = session.showPreview &&
        session.hasResult &&
        session.markdownContent != null &&
        session.toolbarsVisible;
    return (barVisible ? barHeight + padding : padding) + 16;
  }

  // ─── 选择/标记工具栏 ───

  void _dismissSelectionToolbar() {
    _selectionToolbarEntry?.remove();
    _selectionToolbarEntry = null;
  }

  // 旧原生选择基础设施已移除，由 WebView 选择处理替代

  @override
  void dispose() {
    _pdfController.removeListener(_onPdfControllerChanged);
    // 强制把防抖窗口里的最后一次进度落盘；fire-and-forget——dispose 同步路径
    // 不能 await，但 HistoryNotifier 内部用 await _save()，下一帧前会完成。
    unawaited(_sessionNotifier.flushProgress());
    _pdfSearch.dispose();
    _summaryImageState.dispose();
    _figuresEpoch.dispose();
    _selectionToolbarEntry?.remove();
    super.dispose();
  }

  // ─── UI ───

  /// 统一退出入口：先把 WebView 冻结成截图再 pop。
  ///
  /// 平台视图不参与 Flutter 合成——反向转场的 fade/scale 对原生 WebView
  /// 不生效（表现为硬切 + 掉帧）。截图占位后，转场对着普通 Image 动画。
  /// PDF 模式 / WebView 未挂载时 currentState 为 null，直接 pop。
  bool _popping = false;
  Future<void> _handleBack() async {
    if (_popping) return;
    _popping = true;
    final reader = _webViewReaderKey.currentState;
    if (reader != null) {
      await reader.freeze(capture: true);
    }
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final readerSettings = ref.watch(readerSettingsProvider);
    final theme = buildReaderThemeData(Theme.of(context), readerSettings.theme);
    final cs = theme.colorScheme;
    // select 排除 currentResultIndex（由独立的 _ResultNavigator 消费）,
    // 避免搜索导航时整页 rebuild。markdownContent 用 cacheKey 代替全文比较，
    // searchResultCount 只比较 length，error/snapshot 只比较 nullity。
    ref.watch(readerSessionProvider(_sessionArgs).select(_mainBuildSelector));
    // ref.read 获取完整 state 用于数据访问——select 已覆盖所有 rebuild 场景，
    // currentResultIndex 变化时 select 不触发、read 返回的值不被消费，安全。
    final session = ref.read(readerSessionProvider(_sessionArgs));
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
      return Theme(
        data: theme,
        child: Scaffold(
          backgroundColor: cs.surface,
          body: SafeArea(
            child: Column(
              children: [
                _buildToolbar(cs, session),
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
        ),
      );
    }

    final fileExists = session.fileExists;

    final contentBg = (session.showPreview && session.hasResult)
        ? resolveReaderPalette(readerSettings.theme, cs).background
        : cs.surface;

    final isMarkdownHighlightMode = session.markdownHighlightMode;
    final pdfMatchCount = _pdfSearch.searcher?.matches.length ?? 0;
    final showPdfNavigator = !session.showPreview && _pdfSearch.hasQuery;

    return Theme(
      data: theme,
      // 系统返回手势同样走 _handleBack（先冻结 WebView 再 pop）
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _sheetHostKey.currentState?.isOpen != true) {
            _handleBack();
          }
        },
        child: Scaffold(
          key: _scaffoldKey,
          backgroundColor: cs.surface,
          // 键盘弹出时不缩放 body：阅读器搜索框锚在顶部工具栏，笔记/编辑走独立
          // sheet/dialog，正文从不需要为底部键盘让位。设 false 切断 WebView 平台
          // 视图随 viewInsets 每帧 resize（MIUI 的 adjustResize 会逐帧推 inset）。
          resizeToAvoidBottomInset: false,
          endDrawerEnableOpenDragGesture: false,
          // 仅桌面端挂 Drawer——移动端走 _showOutlineBottomSheet。这里直接 null 掉
          // 避免在移动端浪费 OutlinePanel 的 initState（parseReferences 等）。
          endDrawer: (_isDesktop && session.markdownContent != null)
              ? Drawer(
                  width: 380,
                  child: OutlinePanel(
                    key: ValueKey(session.markdownContent.hashCode),
                    markdownContent: session.markdownContent!,
                    documentId: widget.document.id,
                    document: widget.document,
                    onLocateQuote: _locateQuoteInReader,
                    summaryImageState: _summaryImageState,
                    figuresEpoch: _figuresEpoch,
                    onNavigate: (offset) {
                      _scaffoldKey.currentState?.closeEndDrawer();
                      _scrollToCharOffset(offset);
                      _tryFlashImageAtOffset(offset);
                    },
                    onUploadSummaryImage: () {
                      _summaryCoordinator.uploadFromGallery();
                    },
                  ),
                )
              : null,
          body: SafeArea(
            top: false,
            bottom: false,
            child: Listener(
              onPointerHover: _isDesktop ? _onDesktopPointerHover : null,
              child: Stack(
                children: [
                  // ── 主内容层：占满全屏，工具栏 overlay 在上下方 ──
                  Positioned.fill(
                    child: AnimatedContainer(
                      duration: kAnim,
                      curve: Curves.easeInOut,
                      color: contentBg,
                      child: fileExists
                          ? _buildBody(theme, cs, readerSettings, session)
                          : _buildFileNotFound(theme, cs),
                    ),
                  ),
                  // ── 顶部工具栏（沉浸式时向上滑出） ──
                  // ClipRect 必须包在 AnimatedSlide 外：AnimatedSlide 内部 transform
                  // 只动 paint 位移不动 layout box，Stack 的 clipBehavior 按 layout
                  // 边界剪不到。少了 ClipRect 时工具栏向上滑出的部分会透过透明状态栏显示。
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: ClipRect(
                      child: AnimatedSlide(
                        duration: kAnim,
                        curve: kAnimCurve,
                        offset: session.toolbarsVisible
                            ? Offset.zero
                            : const Offset(0, -1),
                        child: Container(
                          color: cs.surface,
                          padding: EdgeInsets.only(
                            top: MediaQuery.of(context).padding.top,
                          ),
                          child: isMarkdownHighlightMode
                              ? _buildHighlightSearchBar(session)
                              : (session.searchActive && !session.showPreview
                                    ? _buildPdfSearchBar()
                                    : _buildToolbar(
                                        cs,
                                        session,
                                        extracting: extracting,
                                      )),
                        ),
                      ),
                    ),
                  ),
                  // ── 内嵌 sheet 宿主（z-order 低于底栏 → 底栏始终可见） ──
                  Positioned.fill(
                    child: ReaderSheetHost(
                      key: _sheetHostKey,
                      onSheetOpen: () => _sessionNotifier.setSheetOpen(true),
                      onSheetClose: () {
                        _sessionNotifier.setSheetOpen(false);
                        setState(() => _activeSheet = null);
                      },
                    ),
                  ),
                  // ── 底部工具栏（仅 Markdown 模式；沉浸式时向下滑出） ──
                  // 同样的 ClipRect 防御：避免向下滑出后透过透明导航栏区域显示。
                  if (session.showPreview &&
                      session.hasResult &&
                      session.markdownContent != null)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: ClipRect(
                        child: AnimatedSlide(
                          duration: kAnim,
                          curve: kAnimCurve,
                          offset: session.toolbarsVisible
                              ? Offset.zero
                              : const Offset(0, 1),
                          child: _buildBottomBar(readerSettings),
                        ),
                      ),
                    ),
                  // ── 定位原文后返回问 AI 引导条 ──
                  if (_chatReturnArgs != null)
                    AnimatedPositioned(
                      duration: kAnim,
                      curve: kAnimCurve,
                      right: 16,
                      bottom: _chatReturnPromptBottom(session),
                      child: ReaderChatReturnPrompt(
                        onCancel: () {
                          Haptics.soft();
                          setState(() => _chatReturnArgs = null);
                        },
                        onReturn: _returnToChat,
                      ),
                    ),
                  // ── 浮动搜索结果导航器 ──
                  if (isMarkdownHighlightMode && session.searchResultCount > 0)
                    Positioned(
                      right: 16,
                      bottom: 32,
                      child: _ResultNavigator(
                        sessionArgs: _sessionArgs,
                        onPrevious: _goToPrevResult,
                        onNext: _goToNextResult,
                      ),
                    ),
                  if (showPdfNavigator)
                    Positioned(
                      right: 16,
                      bottom: 32,
                      child: _buildPdfResultNavigator(pdfMatchCount),
                    ),
                  // ── 搜索遮罩层 ──
                  if (session.searchActive && session.showPreview)
                    Positioned.fill(
                      child: SearchOverlay(
                        readerSettings: readerSettings,
                        onSearch:
                            (
                              String query, {
                              bool caseSensitive = false,
                              bool wholeWord = false,
                            }) async {
                              final results =
                                  await _webViewReaderKey.currentState
                                      ?.searchContent(
                                        query,
                                        caseSensitive: caseSensitive,
                                        wholeWord: wholeWord,
                                      ) ??
                                  const [];
                              if (mounted) {
                                _sessionNotifier.updateSearchResults(
                                  results.length,
                                );
                              }
                              return results;
                            },
                        onResultTap: _onSearchResultTap,
                        onDismiss: _closeSearch,
                        initialQuery: session.highlightQuery,
                      ),
                    ),
                ],
              ),
            ),
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
  Widget _buildToolbar(
    ColorScheme cs,
    ReaderSessionState session, {
    bool extracting = false,
  }) {
    final favorites = ref.watch(favoritesProvider);
    final inFavorite = _isInAnyFavorite(favorites);
    final translation = ref.watch(
      documentTranslationProvider(widget.document.id),
    );
    final summaryImagePath = DocumentSummaryImageService.imagePathFor(
      widget.document.id,
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
      extractButton: _buildExtractButton(session, cs, extracting),
      onBack: _handleBack,
      onSearch: _openSearch,
      onGenerateSummaryImage: _handleGenerateSummaryImage,
      onAddFavorite: _showFavoritePicker,
      onRemoveFavorite: _showFavoriteRemovalPicker,
      onExtract: _onExtractPressed,
      onAiLayoutFix: () => _handleAiLayoutFix(context),
      onShowInfo: () => _showDocumentInfo(context),
      onReprocess: _onReprocessPressed,
      onRetranslate: _handleRetranslate,
      onOpenSummaryImage: () => _summaryCoordinator.openSummaryImage(),
    );
  }

  Widget _buildPdfSearchBar() {
    return ReaderPdfSearchBar(
      controller: _pdfSearch.textController,
      focusNode: _pdfSearch.focusNode,
      onBack: _handleBack,
      onClear: _clearPdfSearch,
      onSubmitted: (value) => _pdfSearch.search(value, searchImmediately: true),
      onChanged: (value) => _pdfSearch.search(value),
    );
  }

  Widget _buildHighlightSearchBar(ReaderSessionState session) {
    return ReaderHighlightSearchBar(
      query: session.highlightQuery ?? '',
      onBack: _handleBack,
      onOpenSearch: _openSearch,
      onClear: _clearHighlight,
    );
  }

  Widget _buildPdfResultNavigator(int total) {
    return ReaderPdfResultNavigator(
      currentIndex: _pdfSearch.searcher?.currentIndex ?? -1,
      total: total,
      progress: _pdfSearch.searcher?.searchProgress,
      searching: _pdfSearch.searcher?.isSearching ?? false,
      onPrevious: _pdfSearch.goToPrev,
      onNext: _pdfSearch.goToNext,
    );
  }

  // _buildResultNavigator 已提取为独立的 [_ResultNavigator] ConsumerWidget，
  // 只 watch (currentResultIndex, searchResultCount.length)，搜索导航不再触发整页 rebuild。

  /// 底部工具栏：大纲 / 翻译 / 问 AI / 笔记 / 外观面板
  ///
  /// 仅在 Markdown 模式显示。工具栏背景用 surface 的半透明色，视觉上浮在
  /// 阅读内容之上；沉浸式状态切换由 [AnimatedSlide] 在 build 里处理。
  Widget _buildBottomBar(ReaderSettingsState readerSettings) {
    final translation = ref.watch(
      documentTranslationProvider(widget.document.id),
    );

    return ReaderBottomBar(
      readerSettings: readerSettings,
      translation: translation,
      activeSheet: _activeSheet,
      onOpenOutline: _openOutlineSheet,
      onTranslate: _handleTranslate,
      onCycleTranslationMode: _handleCycleTranslationMode,
      onAskAi: _openAiChat,
      onOpenNotes: _openNotesSheet,
      onOpenTheme: _openThemeSheet,
    );
  }

  /// 启动全文翻译：show 一个长驻 SnackBar 订阅 provider 的进度 ValueListenable，
  /// 翻译结束（成功/失败/取消）后 finish 关闭。
  Future<void> _handleTranslate() async {
    final markdown = _session.markdownContent;
    if (markdown == null || markdown.isEmpty) return;

    // **必须**在触发翻译前检查 AI 配置：否则配置缺失时 provider 内 AiSettingsPrompt
    // 弹的错误 SnackBar 会被进度 SnackBar 覆盖，用户感受到的是"点了毫无反应"。
    // Provider 内的同一检查保留作 defense in depth。
    if (!await _ensureAgentConfigured()) return;

    final documentId = widget.document.id;
    final notifier = ref.read(documentTranslationProvider(documentId).notifier);

    // 进度 SnackBar 由 notifier 自己 report 到 Task Activity（见
    // DocumentTranslationNotifier.translate）；这里只负责翻完后的结果文案。
    final fullyCached = await notifier.translate(markdown);
    if (!mounted) return;

    final state = ref.read(documentTranslationProvider(documentId));
    if (state.status == DocTranslationStatus.done) {
      ref
          .read(snackBarServiceProvider)
          .showResult(
            message: fullyCached
                ? context.l10n.translationCacheUsed
                : context.l10n.translationDone,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 72),
          );
    } else {
      await _reportTranslationFailure(state);
    }
  }

  /// 三态循环：双语 → 原文 → 译文 → 双语。
  void _handleCycleTranslationMode() {
    ref
        .read(documentTranslationProvider(widget.document.id).notifier)
        .cycleMode();
  }

  /// "更多"菜单里的"重新翻译"——清空缓存重新发起。
  Future<void> _handleRetranslate() async {
    final markdown = _session.markdownContent;
    if (markdown == null || markdown.isEmpty) return;

    // 同 _handleTranslate：必须在触发翻译前检查配置。
    if (!await _ensureAgentConfigured()) return;

    final documentId = widget.document.id;
    final notifier = ref.read(documentTranslationProvider(documentId).notifier);

    // 进度由 notifier 自报 Task Activity；retranslate 内部复用 translate()。
    await notifier.retranslate(markdown);
    if (!mounted) return;

    final state = ref.read(documentTranslationProvider(documentId));
    if (state.status == DocTranslationStatus.done) {
      ref
          .read(snackBarServiceProvider)
          .showResult(message: context.l10n.translationDone);
    } else {
      await _reportTranslationFailure(state);
    }
  }

  Future<void> _handleGenerateSummaryImage({bool openOutline = true}) async {
    await _summaryCoordinator.generate(openOutline: openOutline);
  }

  /// 翻译相关动作的"前置配置守卫"——必须在显示进度 SnackBar 之前调用。
  Future<bool> _ensureAgentConfigured() {
    return AiSettingsPrompt.ensureTextModelConfigured(
      context: context,
      agentState: ref.read(effectiveAgentApiProvider),
    );
  }

  /// 翻译失败时把 state.error 暴露给用户——provider 内 catch 后只更新 state，
  /// 注释明说"交给 UI 层"。优先用 [AiSettingsPrompt.showForConfigError] 识别
  /// "AI 设置"相关错误并附加"前往设置"按钮；其它错误走通用 SnackBar。
  /// 取消（status=idle）和无 error 的情况静默——用户已知道自己点了取消。
  Future<void> _reportTranslationFailure(DocumentTranslationState state) async {
    final error = state.error;
    if (state.status != DocTranslationStatus.failed || error == null) return;

    final handled = await AiSettingsPrompt.showForConfigError(
      context: context,
      error: error,
    );
    if (!mounted) return;
    if (!handled) {
      ref
          .read(snackBarServiceProvider)
          .showResult(
            message: context.l10n.translationFailed(error.toString()),
          );
    }
  }

  Widget _buildExtractButton(
    ReaderSessionState session,
    ColorScheme cs,
    bool extracting,
  ) {
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
        tooltip: session.showPreview
            ? context.l10n.viewPdf
            : context.l10n.viewExtractResult,
        onPressed: () {
          Haptics.soft();
          _togglePreview();
        },
      );
    }

    return IconButton(
      icon: Icon(
        Symbols.document_scanner_rounded,
        size: 22,
        fill: 1,
        color: cs.onSurfaceVariant,
      ),
      tooltip: context.l10n.documentExtract,
      onPressed: () {
        Haptics.soft();
        _onExtractPressed();
      },
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
          duration: kAnimSlow,
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
              : KeyedSubtree(
                  key: const ValueKey('pdf'),
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top,
                      bottom: MediaQuery.of(context).padding.bottom,
                    ),
                    child: PdfViewer.file(
                      DocPaths.pdf(widget.document.id),
                      controller: _pdfController,
                      params: PdfViewerParams(
                        backgroundColor: Colors.transparent,
                        matchTextColor: cs.primaryContainer.withAlpha(150),
                        activeMatchTextColor: cs.primary.withAlpha(72),
                        onViewerReady: (document, controller) =>
                            _pdfSearch.bind(controller),
                        pagePaintCallbacks: _pdfSearch.searcher == null
                            ? null
                            : [_pdfSearch.searcher!.pageTextMatchPaintCallback],
                        viewerOverlayBuilder: (context, size, handleLinkTap) =>
                            [
                              PdfViewerScrollThumb(
                                controller: _pdfController,
                                orientation: ScrollbarOrientation.right,
                                thumbSize: const Size(8, 48),
                                margin: 2,
                                thumbBuilder:
                                    (
                                      context,
                                      thumbSize,
                                      pageNumber,
                                      controller,
                                    ) {
                                      return _PdfScrollThumb(size: thumbSize);
                                    },
                              ),
                            ],
                      ),
                    ),
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
          context.l10n.loadFailed,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      );
    }

    if (session.markdownContent == null) {
      // 与 WebViewMarkdownReader 的揭幕幕布同款 spinner——内容加载 → HTML
      // 生成 → WebView 首帧的整个过程视觉连续，不再多段跳变。
      final palette = resolveReaderPalette(settings.theme, theme.colorScheme);
      return ColoredBox(
        color: palette.background,
        child: Center(
          child: CircularProgressIndicator(
            color: palette.secondaryText,
            strokeWidth: 2,
          ),
        ),
      );
    }

    // 系统安全区（状态栏 / 小白条）由下方 return 的外层 Padding 用**实时**
    // MediaQuery.padding 内缩 WebView 控件负责——滚动视口本身不再覆盖系统栏，
    // 纵向滚到任意位置正文都不会侵占状态栏/小白条，且不依赖会被缓存过期的
    // CSS --top-inset/--bottom-inset 值。
    // 这里的 topInset/bottomInset 只让出工具栏自身高度（顶 48 / 底 56），使首/末
    // 屏正文不被半透明工具栏压住；正文仍可滚到工具栏背后保持沉浸感。
    final topPad = 48.0;
    final bottomPad = 56.0;

    // 翻译完成后按当前模式织入译文；未翻译或进行中保持原文，避免长文档
    // 在翻译过程中反复重建 widget 列表（完成时一次性切换即可）。
    final translation = ref.watch(
      documentTranslationProvider(widget.document.id),
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

    final cs = theme.colorScheme;
    final palette = resolveReaderPalette(settings.theme, cs);
    final highlights = ref.watch(highlightProvider(widget.document.id));
    final documentDir = DocPaths.docDir(widget.document.id);

    // 用实时安全区把 WebView 控件整体内缩——滚动区不覆盖状态栏/小白条。
    // 控件外缘之外由底层 contentBg（Positioned.fill）铺阅读背景色，系统栏
    // 区域始终落在干净的纸张底色上。
    final safe = MediaQuery.of(context).padding;
    return Padding(
      padding: EdgeInsets.only(top: safe.top, bottom: safe.bottom),
      child: WebViewMarkdownReader(
        key: _webViewReaderKey,
        markdownData: effectiveMd,
        settings: settings,
        palette: palette,
        highlights: highlights,
        documentDir: documentDir,
        translationStyleId: displayStyle.id,
        initialScrollProgress: _markdownScrollProgress,
        initialAnchorBlock: _markdownAnchorBlock,
        reloadEpoch: _readerReloadEpoch,
        topInset: topPad,
        bottomInset: bottomPad,
        highlightQuery: session.highlightQuery,
        onSelectionEnd: _handleWebViewSelectionEnd,
        onSelectionCleared: _handleWebViewSelectionCleared,
        onHighlightClick: _handleHighlightTap,
        onImageClick: _handleMarkdownImageTap,
        onScrollDirection: _handleWebViewScrollDirection,
        onScrollProgress: (p, anchor) {
          if (!mounted) return;
          _markdownScrollProgress = p;
          _markdownAnchorBlock = anchor;
          _sessionNotifier.reportProgress(p, anchorBlock: anchor);
        },
        onToggleToolbar: _handleWebViewToggleToolbar,
      ),
    );
  }

  /// 点击 markdown 中的图片 → 加载 figure manifest 后跳转 FigureViewer。
  ///
  /// 匹配策略：从 url 提取 basename（`Figure_N.png`）与 manifest entry
  /// 的 `imagePath` basename 比对，和 outline_panel 保持一致。
  Future<void> _handleMarkdownImageTap(String url) async {
    final documentId = widget.document.id;

    // figure 路径在 _injectImageAttrs 里被附了 `?v=<cacheBuster>`，
    // 必须用 Uri 解析剥离 query 后再取末段，否则 `Figure_1.png?v=123`
    // 与 manifest 的 basename `Figure_1.png` 无法匹配。
    String fileName;
    try {
      if (url.startsWith('file://')) {
        fileName = p.basename(Uri.parse(url).toFilePath());
      } else {
        final segs = Uri.parse(url).pathSegments;
        fileName = segs.isNotEmpty ? segs.last : '';
      }
    } catch (_) {
      final noQuery = url.split('?').first;
      fileName = noQuery.split(RegExp(r'[/\\]')).last;
    }
    if (fileName.isEmpty) return;

    _figuresFuture ??= FigureExtractService.loadManifest(documentId);
    final figures = await _figuresFuture;
    if (!mounted) return;
    if (figures == null || figures.isEmpty) return;

    final index = figures.indexWhere(
      (e) => p.basename(e.imagePath) == fileName,
    );
    if (index < 0) return;

    await showFigureViewer(
      context,
      figures,
      initialIndex: index,
      documentId: documentId,
      document: widget.document,
      onLocateQuote: _locateQuoteInReader,
    );
  }

  // _wrapWithSelection 已移除，由 WebView 内部选择处理替代

  Widget _buildFileNotFound(ThemeData theme, ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.error_rounded, size: 48, color: cs.error),
          const SizedBox(height: 16),
          Text(
            context.l10n.pdfFileNotFoundTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Text(
              DocPaths.pdf(widget.document.id),
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
        duration: kAnimFast,
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

/// 独立 rebuild 的搜索结果导航器——只 watch currentResultIndex 和 searchResultCount.length，
/// 搜索导航（上/下箭头）不再触发 [_ReaderPageState] 的主 build。
class _ResultNavigator extends ConsumerWidget {
  final ReaderSessionArgs sessionArgs;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const _ResultNavigator({
    required this.sessionArgs,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (currentIndex, total) = ref.watch(
      readerSessionProvider(
        sessionArgs,
      ).select((s) => (s.currentResultIndex, s.searchResultCount)),
    );
    return ReaderTextResultNavigator(
      currentIndex: currentIndex,
      total: total,
      onPrevious: onPrevious,
      onNext: onNext,
    );
  }
}
