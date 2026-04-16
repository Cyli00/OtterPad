import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../../data/models/book/document.dart';
import '../../providers/api_provider.dart';
import '../../providers/reader_settings_provider.dart';
import '../../providers/task_provider.dart';
import '../../services/doc_extract_service.dart';
import '../../services/reader/markdown_document_cache_service.dart';
import '../../services/snackbar_service.dart';
import 'widgets/markdown_reader.dart';
import 'widgets/outline_panel.dart';
import 'widgets/reader_background.dart';
import 'widgets/reader_text_sheet.dart';
import 'widgets/reader_theme_sheet.dart';
import 'widgets/search_overlay.dart';
import 'widgets/selection_toolbar.dart';
import 'package:material_symbols_icons/symbols.dart';

class ReaderPage extends ConsumerStatefulWidget {
  final Document document;

  const ReaderPage({super.key, required this.document});

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    {
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
  String? _textOnPointerDown;
  Offset? _pointerDownPosition;

  // 选择工具栏 Overlay
  final _selectionAreaKey = GlobalKey();
  OverlayEntry? _selectionToolbarEntry;

  // 沉浸式：点击 markdown 内容区切换上下工具栏可见性
  bool _toolbarsVisible = true;

  // 桌面端工具栏自动隐藏
  Timer? _toolbarHideTimer;
  static const _kToolbarAutoHideDelay = Duration(seconds: 3);
  static const _kEdgeTriggerZone = 16.0;

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  // 异步初始化状态
  bool _initialized = false;
  bool? _fileExists;
  bool _markdownLoading = false;
  Object? _markdownLoadError;

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

    final fileExists = await fileExistsFuture;
    final mdPath = await mdPathFuture;
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

    ref.read(taskProvider.notifier).extractDocument(
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
      final (mdPath, content) = await DocExtractService.instance.reprocessMarkdown(
        pdfPath: filePath,
        title: widget.document.title,
      );
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
      _currentResultIndex =
          (_currentResultIndex + 1) % _searchResults.length;
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

  void _openTextSheet() {
    if (_mdContent == null) return;
    showReaderTextSheet(context);
  }

  void _openThemeSheet() {
    showReaderThemeSheet(context);
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
    setState(() => _toolbarsVisible = !_toolbarsVisible);
    // 桌面端：显示后自动倒计时隐藏
    if (_isDesktop && _toolbarsVisible) _scheduleToolbarHide();
  }

  /// 桌面端：鼠标悬停时根据位置决定工具栏显隐。
  ///
  /// 鼠标靠近上/下边缘 → 显示工具栏并取消隐藏计时；
  /// 鼠标在内容区 → 启动延迟隐藏。
  void _onDesktopPointerHover(PointerHoverEvent event) {
    if (!_showPreview || !_hasResult || _mdContent == null) return;
    final height = context.size?.height ?? 0;
    final y = event.localPosition.dy;
    if (y < _kEdgeTriggerZone || y > height - _kEdgeTriggerZone) {
      _toolbarHideTimer?.cancel();
      if (!_toolbarsVisible) setState(() => _toolbarsVisible = true);
    } else if (_toolbarsVisible) {
      _scheduleToolbarHide();
    }
  }

  void _scheduleToolbarHide() {
    _toolbarHideTimer?.cancel();
    _toolbarHideTimer = Timer(_kToolbarAutoHideDelay, () {
      if (mounted && _showPreview) {
        setState(() => _toolbarsVisible = false);
      }
    });
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

  void _showDocumentInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DocumentInfoSheet(document: widget.document),
    );
  }

  Future<String?> _findMarkdownPath(String filePath) async {
    if (filePath.isEmpty) return null;
    final mdPath = p.join(
      p.dirname(filePath),
      '${p.basenameWithoutExtension(filePath)}.md',
    );
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
              ref.read(snackBarServiceProvider).showResult(
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
      ],
    );
  }

  @override
  void dispose() {
    _toolbarHideTimer?.cancel();
    _disposePdfSearchListener?.call();
    _pdfSearcher?.dispose();
    _pdfSearchController.dispose();
    _pdfSearchFocusNode.dispose();
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
    final extracting = ref.watch(taskProvider.select(
      (tasks) => tasks[TaskType.extractDocument]?.status == TaskStatus.running,
    ));

    // 异步初始化完成前显示骨架加载状态
    if (!_initialized) {
      return Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: Column(
            children: [
              _buildToolbar(theme, cs),
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
        ? resolveReaderBackground(readerSettings.theme, cs)
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
                onNavigate: (offset) {
                  _scaffoldKey.currentState?.closeEndDrawer();
                  _scrollToCharOffset(offset);
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
                offset:
                    _toolbarsVisible ? Offset.zero : const Offset(0, -1),
                child: Container(
                  color: cs.surface.withValues(alpha: 0.92),
                  child: isMarkdownHighlightMode
                      ? _buildHighlightSearchBar(cs)
                      : (_searchActive && !_showPreview
                          ? _buildPdfSearchBar(cs)
                          : _buildToolbar(theme, cs,
                              extracting: extracting)),
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
                  offset:
                      _toolbarsVisible ? Offset.zero : const Offset(0, 1),
                  child: _buildBottomBar(theme, cs),
                ),
              ),
            // ── 浮动搜索结果导航器 ──
            if (isMarkdownHighlightMode && _searchResults.isNotEmpty)
              Positioned(
                right: 16,
                bottom: 32,
                child: _buildResultNavigator(cs),
              ),
            if (showPdfNavigator)
              Positioned(
                right: 16,
                bottom: 32,
                child: _buildPdfResultNavigator(cs, pdfMatchCount),
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
  Widget _buildToolbar(ThemeData theme, ColorScheme cs, {bool extracting = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                Symbols.chevron_left_rounded,
                size: 28,
                fill: 1,
                color: cs.onSurface,
              ),
              tooltip: '返回',
              onPressed: () => context.pop(),
            ),
            const Spacer(),
            // 搜索
            if ((_showPreview && _hasResult) || (!_showPreview && (_fileExists ?? false)))
              IconButton(
                icon: Icon(
                  Symbols.search_rounded,
                  size: 22,
                  fill: 1,
                  color: cs.onSurfaceVariant,
                ),
                tooltip: '搜索',
                onPressed: _openSearch,
              ),
            // 提取/切换按钮
            _buildExtractButton(cs, extracting),
            // 重新提取
            if (_hasResult && !extracting)
              IconButton(
                icon: Icon(
                  Symbols.sync_rounded,
                  size: 22,
                  fill: 1,
                  color: cs.onSurfaceVariant,
                ),
                tooltip: '重新提取',
                onPressed: _onExtractPressed,
              ),
            // 更多操作
            PopupMenuButton<String>(
              icon: Icon(
                Symbols.more_vert_rounded,
                size: 22,
                fill: 1,
                color: cs.onSurfaceVariant,
              ),
              tooltip: '更多',
              onSelected: (value) {
                switch (value) {
                  case 'info':
                    _showDocumentInfo(context);
                  case 'reprocess':
                    _onReprocessPressed();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'info',
                  child: Row(
                    children: [
                      Icon(Symbols.info_rounded, size: 20, fill: 1,
                          color: cs.onSurface),
                      const SizedBox(width: 12),
                      const Text('文献信息'),
                    ],
                  ),
                ),
                if (_hasResult)
                  PopupMenuItem(
                    value: 'reprocess',
                    child: Row(
                      children: [
                        Icon(Symbols.refresh_rounded, size: 20, fill: 1,
                            color: cs.onSurface),
                        const SizedBox(width: 12),
                        const Text('重新排版'),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfSearchBar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                Symbols.chevron_left_rounded,
                size: 28,
                fill: 1,
                color: cs.onSurface,
              ),
              tooltip: '返回',
              onPressed: () => context.pop(),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _pdfSearchController,
                  focusNode: _pdfSearchFocusNode,
                  textAlignVertical: TextAlignVertical.center,
                  style: TextStyle(color: cs.onSurface, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: '搜索 PDF 内容',
                    hintStyle: TextStyle(
                      color: cs.onSurfaceVariant.withAlpha(160),
                      fontSize: 15,
                    ),
                    prefixIcon: Icon(
                      Symbols.search_rounded,
                      size: 20,
                      fill: 1,
                      color: cs.onSurfaceVariant,
                    ),
                    suffixIcon: _pdfSearchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Symbols.cancel_rounded,
                              size: 18,
                              fill: 1,
                              color: cs.onSurfaceVariant,
                            ),
                            onPressed: _clearPdfSearch,
                          )
                        : null,
                    filled: true,
                    fillColor: cs.surfaceContainerHigh,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (value) =>
                      _performPdfSearch(value, searchImmediately: true),
                  onChanged: (value) {
                    setState(() {});
                    _performPdfSearch(value);
                  },
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(
                Symbols.close_rounded,
                size: 22,
                fill: 1,
                color: cs.onSurfaceVariant,
              ),
              tooltip: '退出搜索',
              onPressed: _clearPdfSearch,
            ),
          ],
        ),
      ),
    );
  }

  /// 高亮浏览模式下的顶部搜索栏：显示当前查询词，点击可重新搜索，✕ 退出搜索
  Widget _buildHighlightSearchBar(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                Symbols.chevron_left_rounded,
                size: 28,
                fill: 1,
                color: cs.onSurface,
              ),
              tooltip: '返回',
              onPressed: () => context.pop(),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: GestureDetector(
                onTap: _openSearch,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Symbols.search_rounded,
                        size: 18,
                        fill: 1,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _highlightQuery ?? '',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(
                Symbols.close_rounded,
                size: 22,
                fill: 1,
                color: cs.onSurfaceVariant,
              ),
              tooltip: '退出搜索',
              onPressed: _clearHighlight,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfResultNavigator(ColorScheme cs, int total) {
    final current = (_pdfSearcher?.currentIndex ?? -1) + 1;
    final progress = _pdfSearcher?.searchProgress;
    final searching = _pdfSearcher?.isSearching ?? false;

    return Material(
      elevation: 2,
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              icon: Icon(
                Symbols.expand_less_rounded,
                size: 24,
                fill: 1,
                color: cs.onSurface,
              ),
              tooltip: '上一个结果',
              onPressed: total > 0 ? _goToPrevPdfResult : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                Text(
                  total > 0 ? '$current/$total' : '0/0',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (searching && progress != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: SizedBox(
                      width: 28,
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 2,
                        backgroundColor: cs.surfaceContainerHighest,
                        color: cs.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              icon: Icon(
                Symbols.expand_more_rounded,
                size: 24,
                fill: 1,
                color: cs.onSurface,
              ),
              tooltip: '下一个结果',
              onPressed: total > 0 ? _goToNextPdfResult : null,
            ),
          ),
        ],
      ),
    );
  }

  /// 右下角浮动导航器：上/下雪佛龙 + 当前/总数 计数器
  Widget _buildResultNavigator(ColorScheme cs) {
    final current = _currentResultIndex + 1;
    final total = _searchResults.length;

    return Material(
      elevation: 2,
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              icon: Icon(
                Symbols.expand_less_rounded,
                size: 24,
                fill: 1,
                color: cs.onSurface,
              ),
              tooltip: '上一个结果',
              onPressed: _goToPrevResult,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '$current/$total',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              icon: Icon(
                Symbols.expand_more_rounded,
                size: 24,
                fill: 1,
                color: cs.onSurface,
              ),
              tooltip: '下一个结果',
              onPressed: _goToNextResult,
            ),
          ),
        ],
      ),
    );
  }

  /// 底部工具栏：大纲 / 笔记 / 主题面板 / 字体面板
  ///
  /// 仅在 Markdown 模式显示。工具栏背景用 surface 的半透明色，视觉上浮在
  /// 阅读内容之上；沉浸式状态切换由 [AnimatedSlide] 在 build 里处理。
  Widget _buildBottomBar(ThemeData theme, ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.92),
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withAlpha(80), width: 0.5),
        ),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom,
      ),
      child: SizedBox(
        height: 56,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _bottomButton(
              cs,
              icon: Symbols.menu_rounded,
              tooltip: '大纲',
              onTap: _openOutlineSheet,
            ),
            _bottomButton(
              cs,
              icon: Symbols.stylus_note_rounded,
              tooltip: '笔记',
              onTap: _openNotesSheet,
            ),
            _bottomButton(
              cs,
              icon: Symbols.palette_rounded,
              tooltip: '颜色 / 背景',
              onTap: _openThemeSheet,
            ),
            _bottomButton(
              cs,
              icon: Symbols.text_fields_rounded,
              tooltip: '字体',
              onTap: _openTextSheet,
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomButton(
    ColorScheme cs, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return IconButton(
      icon: Icon(icon, size: 24, fill: 1, color: cs.onSurfaceVariant),
      tooltip: tooltip,
      onPressed: onTap,
    );
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
          _showPreview ? Symbols.picture_as_pdf_rounded : Symbols.article_rounded,
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

    return PageTransitionSwitcher(
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
    );
  }

  Widget _buildMarkdownPreview(
    ThemeData theme,
    ReaderSettingsState settings,
  ) {
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

    // 顶/底工具栏高度 + 安全区：给 markdown 内容加 padding，
    // 避免第一行/最后一行被工具栏 overlay 挡住。
    final topPad = 48.0 + MediaQuery.of(context).padding.top * 0;
    final bottomPad = 56.0 + MediaQuery.of(context).padding.bottom;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _toggleToolbars,
      child: Padding(
        padding: EdgeInsets.only(top: topPad, bottom: bottomPad),
        child: _wrapWithSelection(
          ReaderMarkdownBody(
            key: ValueKey('reader_md_${_mdContent.hashCode}'),
            data: _mdContent!,
            settings: settings,
            scrollController: _scrollController,
            highlightQuery: _highlightQuery,
          ),
        ),
      ),
    );
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

// ─── 文献信息底部弹窗 ───

class _DocumentInfoSheet extends StatelessWidget {
  final Document document;

  const _DocumentInfoSheet({required this.document});

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '文献信息',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildInfoRow(
                        context, '作者', document.authors.join(', ')),
                    _buildInfoRow(context, '期刊', document.journal ?? ''),
                    _buildInfoRow(context, '年份', document.year ?? ''),
                    _buildInfoRow(context, 'DOI', document.doi ?? ''),
                    SizedBox(
                      height: MediaQuery.of(context).padding.bottom + 16,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
