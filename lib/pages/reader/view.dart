import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../../data/models/book/document.dart';
import '../../data/models/book/highlight.dart';
import '../../providers/api_provider.dart';
import '../../providers/highlight_provider.dart';
import '../../providers/reader_settings_provider.dart';
import '../../providers/task_provider.dart';
import '../../services/reader/markdown_document_cache_service.dart';
import '../../services/snackbar_service.dart';
import '../../utils/markdown_preprocessor.dart';
import 'widgets/appearance_panel.dart';
import 'widgets/markdown_reader.dart';
import 'widgets/search_overlay.dart';
import 'widgets/selection_toolbar.dart';

class ReaderPage extends ConsumerStatefulWidget {
  final Document document;

  const ReaderPage({super.key, required this.document});

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with SingleTickerProviderStateMixin {
  bool _showPreview = false;
  String? _mdPath;
  String? _mdContent;

  // 搜索
  bool _searchActive = false;
  String? _highlightQuery;
  int? _targetCharOffset;

  // 搜索结果导航
  List<SearchResult> _searchResults = [];
  int _currentResultIndex = 0;

  // Markdown 滚动控制
  final _scrollController = ScrollController();

  // PDF 控制器（用于滚动滑条）
  final _pdfController = PdfViewerController();
  PdfTextSearcher? _pdfSearcher;
  VoidCallback? _disposePdfSearchListener;
  final _pdfSearchController = TextEditingController();
  final _pdfSearchFocusNode = FocusNode();
  String _pdfSearchQuery = '';

  // 缓存加载 Future，避免重复创建相同加载任务
  Future<String>? _loadFuture;
  Future<MarkdownSearchSnapshot>? _searchSnapshotFuture;
  String? _markdownCacheKey;

  // 文本选择
  String? _selectedText;
  String? _textOnPointerDown;
  Offset? _pointerDownPosition;
  bool _highlightTapHandled = false;

  // 选择/标记工具栏 Overlay
  final _selectionAreaKey = GlobalKey();
  OverlayEntry? _selectionToolbarEntry;
  OverlayEntry? _highlightToolbarEntry;

  // 外观面板
  final _appearanceKey = GlobalKey();
  OverlayEntry? _appearanceEntry;

  // 异步初始化状态
  bool _initialized = false;
  bool? _fileExists;
  bool _markdownLoading = false;
  Object? _markdownLoadError;

  // Markdown 入场动画（与路由转场 _buildAnimatedPage 保持一致）
  late final AnimationController _enterController;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
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
      onSuccess: (mdPath, markdownContent) async {
        if (!mounted) return;
        _enterController.reset();
        final nextContent = markdownContent;
        final cacheService = MarkdownDocumentCacheService.instance;
        final cacheKey = cacheService.buildMemoryCacheKey(
          mdPath: mdPath,
          title: widget.document.title,
          markdownContent: nextContent,
        );
        cacheService.primeResolvedContent(
          cacheKey: cacheKey,
          content: nextContent,
        );
        setState(() {
          _mdPath = mdPath;
          _mdContent = nextContent;
          _markdownCacheKey = cacheKey;
          _searchSnapshotFuture = cacheService.getSearchSnapshot(
            cacheKey: cacheKey,
            markdownContent: nextContent,
          );
          _showPreview = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _enterController.forward();
        });
      },
    );
  }

  void _togglePreview() {
    _clearHighlight();
    final enteringMarkdown = !_showPreview;
    if (enteringMarkdown) {
      _enterController.reset();
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
        await _ensureMarkdownReady(playAnimation: false);
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
    setState(() {
      _searchActive = false;
      _showPreview = true;
      _searchResults = results;
      _currentResultIndex = tappedIndex;
      _highlightQuery = query;
      _targetCharOffset = results[tappedIndex].charOffset;
    });
  }

  void _clearHighlight() {
    if (_highlightQuery != null || _targetCharOffset != null) {
      setState(() {
        _highlightQuery = null;
        _targetCharOffset = null;
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
      _targetCharOffset = _searchResults[_currentResultIndex].charOffset;
    });
  }

  void _goToNextResult() {
    if (_searchResults.isEmpty) return;
    setState(() {
      _currentResultIndex =
          (_currentResultIndex + 1) % _searchResults.length;
      _targetCharOffset = _searchResults[_currentResultIndex].charOffset;
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

  // ─── 外观面板 ───

  void _toggleAppearancePanel() {
    if (_appearanceEntry != null) {
      _appearanceEntry!.remove();
      _appearanceEntry = null;
      return;
    }
    _appearanceEntry = showAppearancePanel(
      context: context,
      anchorKey: _appearanceKey,
      ref: ref,
      onDismiss: () => _appearanceEntry = null,
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

  Future<void> _ensureMarkdownReady({bool playAnimation = true}) async {
    if (_mdContent != null) {
      _prewarmSearchSnapshot();
      if (playAnimation) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _enterController.forward();
        });
      }
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
      if (playAnimation) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _enterController.forward();
        });
      }
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
    if (content == null || cacheKey == null || _searchSnapshotFuture != null) {
      return;
    }
    final cacheService = MarkdownDocumentCacheService.instance;
    _searchSnapshotFuture = cacheService.getSearchSnapshot(
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
    _searchSnapshotFuture = null;
    return resolved.content;
  }

  // ─── 标记 ───

  /// 将选中文本拆分为与 Markdown 段落对齐的独立片段。
  ///
  /// 用 _mdContent 的段落结构作为基准，通过去空格归一化后的子串匹配
  /// 找出选区覆盖的段落，返回每个段落的 inline 文本（即 InlineSyntax
  /// 实际处理的内容，不含 #、•、> 等 block 标记）。
  List<String> _resolveHighlightFragments(String selectedText) {
    if (_mdContent == null || selectedText.trim().isEmpty) {
      return [selectedText.trim()];
    }

    String norm(String s) => s.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final normalizedSel = norm(selectedText);
    if (normalizedSel.isEmpty) return [selectedText.trim()];

    // 1. 将 markdown 拆分为 block，提取每个 block 的 inline 文本
    final blocks = _mdContent!.split(RegExp(r'\n\n+'));
    final inlineTexts = <String>[];
    for (final block in blocks) {
      final trimmed = block.trim();
      if (trimmed.isEmpty) continue;

      final lines = trimmed.split('\n');
      final isList = lines.length > 1 &&
          lines.every(
            (l) => RegExp(r'^\s*[\-\*•]|\d+\.').hasMatch(l.trim()),
          );

      if (isList) {
        for (final line in lines) {
          var t = line.trim();
          t = t.replaceFirst(RegExp(r'^[\-\*•]\s*'), '');
          t = t.replaceFirst(RegExp(r'^\d+\.\s*'), '');
          t = t.trim();
          if (t.isNotEmpty) inlineTexts.add(t);
        }
      } else {
        var t = trimmed;
        t = t.replaceFirst(RegExp(r'^#{1,6}\s+'), '');
        t = t.replaceFirst(RegExp(r'^[\-\*•]\s+'), '');
        t = t.replaceFirst(RegExp(r'^\d+\.\s+'), '');
        t = t.replaceFirst(RegExp(r'^>\s+'), '');
        t = t.replaceAll('\n', ' ').trim();
        if (t.isNotEmpty) inlineTexts.add(t);
      }
    }

    // 2. 顺序扫描：在归一化选区中按文档顺序匹配段落
    final result = <String>[];
    int scanPos = 0;
    for (final inlineText in inlineTexts) {
      final normalizedBlock = norm(inlineText);
      if (normalizedBlock.isEmpty) continue;
      final idx = normalizedSel.indexOf(normalizedBlock, scanPos);
      if (idx != -1) {
        result.add(inlineText);
        scanPos = idx + normalizedBlock.length;
      }
    }

    // 3. 兜底：markdown 匹配失败时按换行拆分
    if (result.isEmpty) {
      for (final line in selectedText.split(RegExp(r'[\n\r]+'))) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) result.add(trimmed);
      }
    }
    if (result.isEmpty) result.add(selectedText.trim());
    return result;
  }

  void _addHighlight(String text) {
    if (text.trim().isEmpty) return;
    final notifier = ref.read(highlightProvider(widget.document.id).notifier);
    final fragments = _resolveHighlightFragments(text);
    // 多片段共享 groupId，删除时联动
    final groupId = fragments.length > 1
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : null;
    for (final fragment in fragments) {
      notifier.add(fragment, groupId: groupId);
    }
    ref.read(snackBarServiceProvider).showResult(
          message: '已添加标记',
          duration: const Duration(seconds: 1),
        );
  }

  void _removeHighlight(String highlightId) {
    ref.read(highlightProvider(widget.document.id).notifier).remove(highlightId);
    ref.read(snackBarServiceProvider).showResult(
          message: '已删除标记',
          duration: const Duration(seconds: 1),
        );
  }

  void _showNoteDialog({required String text, String? highlightId, String? existingNote}) {
    final controller = TextEditingController(text: existingNote ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final theme = Theme.of(ctx);
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withAlpha(80),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '做笔记',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    text.length > 100 ? '${text.substring(0, 100)}...' : text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 4,
                  minLines: 2,
                  decoration: InputDecoration(
                    hintText: '写下你的想法...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    final note = controller.text.trim();
                    final notifier = ref.read(
                      highlightProvider(widget.document.id).notifier,
                    );
                    if (highlightId != null) {
                      notifier.updateNote(highlightId, note);
                    } else {
                      final fragments = _resolveHighlightFragments(text);
                      final groupId = fragments.length > 1
                          ? DateTime.now().microsecondsSinceEpoch.toString()
                          : null;
                      for (final f in fragments) {
                        notifier.add(f, groupId: groupId);
                      }
                      if (note.isNotEmpty) {
                        final highlights = ref.read(
                          highlightProvider(widget.document.id),
                        );
                        for (final f in fragments) {
                          final matches =
                              highlights.where((h) => h.text == f);
                          if (matches.isNotEmpty) {
                            notifier.updateNote(matches.last.id, note);
                          }
                        }
                      }
                    }
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('保存'),
                ),
              ],
            ),
          ),
        );
      },
    );
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
          icon: Icons.copy_rounded,
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
          icon: Icons.highlight_rounded,
          label: '标记',
          onTap: () {
            if (_selectedText != null && _selectedText!.trim().isNotEmpty) {
              _addHighlight(_selectedText!);
            }
          },
        ),
        ReadingToolbarAction(
          icon: Icons.edit_note_rounded,
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

  /// 点击已标记文本时弹出编辑工具栏
  void _onHighlightTap(Highlight highlight, Offset globalPosition) {
    _highlightTapHandled = true;
    _dismissSelectionToolbar();
    _highlightToolbarEntry?.remove();

    // 定位点击处的段落边界
    final box = _findParagraphAt(globalPosition);
    Rect bounds;
    if (box != null) {
      final topLeft = box.localToGlobal(Offset.zero);
      bounds = topLeft & box.size;
    } else {
      final lh = _lineHeight;
      bounds = Rect.fromLTRB(
        globalPosition.dx - 100,
        globalPosition.dy - lh * 0.3,
        globalPosition.dx + 100,
        globalPosition.dy + lh * 0.7,
      );
    }

    _highlightToolbarEntry = showReadingToolbar(
      context: context,
      anchorAbove: Offset(bounds.center.dx, bounds.top - _kToolbarGap),
      anchorBelow: Offset(bounds.center.dx, bounds.bottom + _kToolbarGap),
      onDismiss: () => _highlightToolbarEntry = null,
      actions: [
        ReadingToolbarAction(
          icon: Icons.copy_rounded,
          label: '复制',
          onTap: () {
            Clipboard.setData(ClipboardData(text: highlight.text));
            ref.read(snackBarServiceProvider).showResult(
                  message: '已复制到剪贴板',
                  duration: const Duration(seconds: 1),
                );
          },
        ),
        ReadingToolbarAction(
          icon: Icons.highlight_off_rounded,
          label: '删除标记',
          onTap: () => _removeHighlight(highlight.id),
        ),
        ReadingToolbarAction(
          icon: Icons.edit_note_rounded,
          label: '做笔记',
          onTap: () => _showNoteDialog(
            text: highlight.text,
            highlightId: highlight.id,
            existingNote: highlight.note,
          ),
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
    _scrollController.dispose();
    _enterController.dispose();
    _appearanceEntry?.remove();
    _selectionToolbarEntry?.remove();
    _highlightToolbarEntry?.remove();
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
        ? readerSettings.backgroundColor
        : cs.surface;

    final isMarkdownHighlightMode = _showPreview && _highlightQuery != null;
    final pdfMatchCount = _pdfSearcher?.matches.length ?? 0;
    final showPdfNavigator = !_showPreview && _pdfSearchQuery.isNotEmpty;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Stack(
          children: [
            // ── 主内容层 ──
            Column(
              children: [
                if (isMarkdownHighlightMode)
                  _buildHighlightSearchBar(cs)
                else if (_searchActive && !_showPreview)
                  _buildPdfSearchBar(cs)
                else
                  _buildToolbar(theme, cs, extracting: extracting),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    color: contentBg,
                    child: fileExists
                        ? _buildBody(theme, cs, readerSettings)
                        : _buildFileNotFound(theme, cs),
                  ),
                ),
              ],
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
            if (_searchActive && _showPreview && _searchSnapshotFuture != null)
              Positioned.fill(
                child: SearchOverlay(
                  readerSettings: readerSettings,
                  searchSnapshotFuture: _searchSnapshotFuture!,
                  onResultTap: _onSearchResultTap,
                  onDismiss: _closeSearch,
                  initialQuery: _highlightQuery,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 工具栏：返回 / 搜索 / PDF切换 / 刷新 / 信息 / 外观
  Widget _buildToolbar(ThemeData theme, ColorScheme cs, {bool extracting = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            // 返回按钮
            IconButton(
              icon: Icon(
                Icons.chevron_left_rounded,
                size: 28,
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
                  Icons.search_rounded,
                  size: 22,
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
                  Icons.sync_rounded,
                  size: 22,
                  color: cs.onSurfaceVariant,
                ),
                tooltip: '重新提取',
                onPressed: _onExtractPressed,
              ),
            // 文献信息 (仅在 PDF 模式下显示)
            if (!_showPreview)
              IconButton(
                icon: Icon(
                  Icons.info_outline_rounded,
                  size: 22,
                  color: cs.onSurfaceVariant,
                ),
                tooltip: '文献信息',
                onPressed: () => _showDocumentInfo(context),
              ),
            // 外观设置（仅 Markdown 预览模式下显示）
            if (_showPreview && _hasResult)
              IconButton(
                key: _appearanceKey,
                icon: Text(
                  'A',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                tooltip: '外观设置',
                onPressed: _toggleAppearancePanel,
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
                Icons.chevron_left_rounded,
                size: 28,
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
                      Icons.search_rounded,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                    suffixIcon: _pdfSearchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.cancel_rounded,
                              size: 18,
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
                Icons.close_rounded,
                size: 22,
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
                Icons.chevron_left_rounded,
                size: 28,
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
                        Icons.search_rounded,
                        size: 18,
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
                Icons.close_rounded,
                size: 22,
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
                Icons.expand_less_rounded,
                size: 24,
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
                Icons.expand_more_rounded,
                size: 24,
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
                Icons.expand_less_rounded,
                size: 24,
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
                Icons.expand_more_rounded,
                size: 24,
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
          _showPreview ? Icons.picture_as_pdf_rounded : Icons.article_rounded,
          size: 22,
          color: cs.onSurfaceVariant,
        ),
        tooltip: _showPreview ? '查看 PDF' : '查看提取结果',
        onPressed: _togglePreview,
      );
    }

    return IconButton(
      icon: Icon(
        Icons.document_scanner_rounded,
        size: 22,
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
    if (_showPreview && _hasResult) {
      return _buildMarkdownPreview(theme, readerSettings);
    }
    return PdfViewer.file(
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
            // 与 Material 系统滚动条尺寸接近
            thumbSize: const Size(8, 48),
            margin: 2,
            thumbBuilder: (context, thumbSize, pageNumber, controller) {
              return _PdfScrollThumb(size: thumbSize);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMarkdownPreview(
    ThemeData theme,
    ReaderSettingsState settings,
  ) {
    final highlights = ref.watch(highlightProvider(widget.document.id));

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

    return Stack(
      children: [
        if (_mdContent == null)
          Positioned.fill(child: _buildMarkdownSkeleton(settings)),
        if (_mdContent != null)
          Positioned.fill(
            child: _buildSlideIn(
              child: _wrapWithSelection(
                ReaderMarkdownBody(
                  key: ValueKey('reader_md_${_mdContent.hashCode}'),
                  data: _mdContent!,
                  settings: settings,
                  scrollController: _scrollController,
                  highlightQuery: _highlightQuery,
                  targetCharOffset: _targetCharOffset,
                  highlights: highlights,
                  onHighlightTap: _onHighlightTap,
                ),
              ),
            ),
          ),
      ],
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
        _highlightTapHandled = false;
        _pointerDownPosition = event.position;
        _textOnPointerDown = _selectedText;
        _dismissSelectionToolbar();
        _highlightToolbarEntry?.remove();
        _highlightToolbarEntry = null;
      },
      onPointerUp: (event) {
        final downPos = _pointerDownPosition ?? event.position;
        Future.delayed(const Duration(milliseconds: 100), () {
          if (!mounted || _highlightTapHandled) return;
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

  /// 入场动画：与路由页面转场 (_buildAnimatedPage) 参数一致
  /// fade(0→1) + slideY(0.04→0)，300ms easeOut
  Widget _buildSlideIn({required Widget child}) {
    final curved = CurvedAnimation(
      parent: _enterController,
      curve: Curves.easeOut,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }

  /// 文档加载中的骨架屏，模拟 Markdown 内容排版
  Widget _buildMarkdownSkeleton(ReaderSettingsState settings) {
    final shimmerBase = settings.textColor.withAlpha(18);
    final shimmerHighlight = settings.textColor.withAlpha(36);

    Widget line(double widthFraction, double height) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: shimmerBase,
          borderRadius: BorderRadius.circular(4),
        ),
        margin: const EdgeInsets.only(bottom: 10),
        width: double.infinity,
      ).animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(
            color: shimmerHighlight,
            duration: const Duration(milliseconds: 1200),
          );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 模拟标题
          FractionallySizedBox(
            widthFactor: 0.6,
            child: line(0.6, 22),
          ),
          const SizedBox(height: 16),
          // 模拟正文段落
          line(1.0, 14),
          line(1.0, 14),
          FractionallySizedBox(
            widthFactor: 0.85,
            child: line(0.85, 14),
          ),
          const SizedBox(height: 12),
          line(1.0, 14),
          line(1.0, 14),
          line(1.0, 14),
          FractionallySizedBox(
            widthFactor: 0.7,
            child: line(0.7, 14),
          ),
          const SizedBox(height: 16),
          // 模拟小标题
          FractionallySizedBox(
            widthFactor: 0.45,
            child: line(0.45, 18),
          ),
          const SizedBox(height: 12),
          line(1.0, 14),
          line(1.0, 14),
          FractionallySizedBox(
            widthFactor: 0.9,
            child: line(0.9, 14),
          ),
        ],
      ),
    );
  }

  Widget _buildFileNotFound(ThemeData theme, ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: cs.error),
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
