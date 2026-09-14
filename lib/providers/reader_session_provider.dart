import 'dart:async';
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../data/models/book/highlight.dart';
import '../data/models/book/reader_anchor.dart';
import '../services/document_summary_image_service.dart';
import '../services/reader/markdown_document_cache_service.dart';
import '../utils/doc_paths.dart';
import 'highlight_provider.dart';
import 'document_task_provider.dart';
import 'history_provider.dart';
import 'reader_settings_provider.dart';

class ReaderSessionArgs {
  final String documentId;
  final String title;
  final DefaultReadingMode defaultReadingMode;

  const ReaderSessionArgs({
    required this.documentId,
    required this.title,
    required this.defaultReadingMode,
  });

  @override
  bool operator ==(Object other) {
    return other is ReaderSessionArgs &&
        other.documentId == documentId &&
        other.title == title &&
        other.defaultReadingMode == defaultReadingMode;
  }

  @override
  int get hashCode => Object.hash(documentId, title, defaultReadingMode);
}

class ReaderSessionState {
  final bool initialized;
  final bool fileExists;
  final bool showPreview;
  final String? markdownPath;
  final String? markdownContent;
  final String? markdownCacheKey;
  final int contentRevision;
  final bool markdownLoading;
  final Object? markdownLoadError;
  final bool searchActive;
  final String? highlightQuery;
  final int searchResultCount;
  final int currentResultIndex;
  final bool toolbarsVisible;
  final bool sheetOpen;
  final bool dockOpen;
  final String? summaryImagePath;

  const ReaderSessionState({
    this.initialized = false,
    this.fileExists = false,
    this.showPreview = false,
    this.markdownPath,
    this.markdownContent,
    this.markdownCacheKey,
    this.contentRevision = 0,
    this.markdownLoading = false,
    this.markdownLoadError,
    this.searchActive = false,
    this.highlightQuery,
    this.searchResultCount = 0,
    this.currentResultIndex = 0,
    this.toolbarsVisible = true,
    this.sheetOpen = false,
    this.dockOpen = false,
    this.summaryImagePath,
  });

  bool get hasResult => markdownPath != null || markdownContent != null;
  bool get hasMarkdownContent => markdownContent != null;
  bool get markdownHighlightMode => showPreview && highlightQuery != null;

  ReaderSessionState copyWith({
    bool? initialized,
    bool? fileExists,
    bool? showPreview,
    Object? markdownPath = _sentinel,
    Object? markdownContent = _sentinel,
    Object? markdownCacheKey = _sentinel,
    int? contentRevision,
    bool? markdownLoading,
    Object? markdownLoadError = _sentinel,
    bool? searchActive,
    Object? highlightQuery = _sentinel,
    int? searchResultCount,
    int? currentResultIndex,
    bool? toolbarsVisible,
    bool? sheetOpen,
    bool? dockOpen,
    Object? summaryImagePath = _sentinel,
  }) {
    return ReaderSessionState(
      initialized: initialized ?? this.initialized,
      fileExists: fileExists ?? this.fileExists,
      showPreview: showPreview ?? this.showPreview,
      markdownPath: identical(markdownPath, _sentinel)
          ? this.markdownPath
          : markdownPath as String?,
      markdownContent: identical(markdownContent, _sentinel)
          ? this.markdownContent
          : markdownContent as String?,
      markdownCacheKey: identical(markdownCacheKey, _sentinel)
          ? this.markdownCacheKey
          : markdownCacheKey as String?,
      contentRevision: contentRevision ?? this.contentRevision,
      markdownLoading: markdownLoading ?? this.markdownLoading,
      markdownLoadError: identical(markdownLoadError, _sentinel)
          ? this.markdownLoadError
          : markdownLoadError,
      searchActive: searchActive ?? this.searchActive,
      highlightQuery: identical(highlightQuery, _sentinel)
          ? this.highlightQuery
          : highlightQuery as String?,
      searchResultCount: searchResultCount ?? this.searchResultCount,
      currentResultIndex: currentResultIndex ?? this.currentResultIndex,
      toolbarsVisible: toolbarsVisible ?? this.toolbarsVisible,
      sheetOpen: sheetOpen ?? this.sheetOpen,
      dockOpen: dockOpen ?? this.dockOpen,
      summaryImagePath: identical(summaryImagePath, _sentinel)
          ? this.summaryImagePath
          : summaryImagePath as String?,
    );
  }

  String? imageFilenameNearOffset(int charOffset) {
    final md = markdownContent;
    if (md == null || md.isEmpty) return null;
    final start = charOffset.clamp(0, md.length);
    final around = md.substring(start, (start + 200).clamp(0, md.length));
    final match = RegExp(
      r'!\[.*?\]\(.*?([^/\\)]+\.(?:png|jpg|jpeg|gif|webp))',
    ).firstMatch(around);
    return match?.group(1);
  }

  String? expandToParagraphContext(String selectedText) {
    final md = markdownContent;
    if (md == null || md.isEmpty) return null;

    final plainText = _stripBasicMarkdown(md);
    final paragraphs = plainText
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (paragraphs.isEmpty) return null;

    String normalize(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
    final normalizedSelected = normalize(selectedText);
    final normalizedParagraphs = paragraphs.map(normalize).toList();

    var startIdx = -1;
    var endIdx = -1;

    for (final chunkLen in [60, 30, 15]) {
      if (startIdx >= 0 && endIdx >= 0) break;
      final len = normalizedSelected.length.clamp(1, chunkLen);

      if (startIdx < 0) {
        final chunk = normalizedSelected.substring(0, len);
        for (var i = 0; i < normalizedParagraphs.length; i++) {
          if (normalizedParagraphs[i].contains(chunk)) {
            startIdx = i;
            break;
          }
        }
      }

      if (endIdx < 0) {
        final chunk = normalizedSelected.substring(
          normalizedSelected.length - len,
        );
        for (var i = normalizedParagraphs.length - 1; i >= 0; i--) {
          if (normalizedParagraphs[i].contains(chunk)) {
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
    return normalize(expanded) == normalizedSelected ? null : expanded;
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
}

const _sentinel = Object();

class ReaderSessionNotifier extends StateNotifier<ReaderSessionState> {
  ReaderSessionNotifier(this._ref, this.args)
    : super(const ReaderSessionState()) {
    _ref.listen(
      documentTaskProvider.select(
        (tasks) =>
            tasks[DocumentTaskKey(
              type: DocumentTaskType.extractDocument,
              documentId: args.documentId,
            )],
      ),
      (previous, next) {
        if (next?.status == DocumentTaskStatus.completed &&
            !identical(previous, next) &&
            next?.result is String) {
          unawaited(_reloadExtraction(next!.result as String));
        }
      },
    );
    unawaited(_init());
  }

  final Ref _ref;
  final ReaderSessionArgs args;
  Future<String>? _loadFuture;
  int _loadEpoch = 0;

  Future<void> _init() async {
    final epoch = _loadEpoch;
    final pdfPath = DocPaths.pdf(args.documentId);
    final fileExistsFuture = args.documentId.isNotEmpty
        ? File(pdfPath).exists()
        : Future.value(false);
    final markdownPathFuture = _findMarkdownPath(args.documentId);
    final summaryPathFuture = args.documentId.isNotEmpty
        ? _findSummaryImagePath(args.documentId)
        : Future<String?>.value();

    final fileExists = await fileExistsFuture;
    final markdownPath = await markdownPathFuture;
    final summaryImagePath = await summaryPathFuture;
    if (!mounted) return;

    if (epoch != _loadEpoch) {
      state = state.copyWith(
        initialized: true,
        fileExists: fileExists,
        summaryImagePath: summaryImagePath,
      );
      return;
    }
    final wantMarkdown =
        args.defaultReadingMode == DefaultReadingMode.markdown &&
        markdownPath != null;
    state = state.copyWith(
      initialized: true,
      fileExists: fileExists,
      markdownPath: markdownPath,
      showPreview: wantMarkdown,
      markdownLoading: wantMarkdown,
      markdownLoadError: null,
      summaryImagePath: summaryImagePath,
    );

    if (wantMarkdown) {
      unawaited(ensureMarkdownReady());
    }
  }

  Future<String?> _findMarkdownPath(String documentId) async {
    if (documentId.isEmpty) return null;
    final mdPath = DocPaths.md(documentId);
    return await File(mdPath).exists() ? mdPath : null;
  }

  Future<String?> _findSummaryImagePath(String documentId) async {
    final path = DocumentSummaryImageService.imagePathFor(documentId);
    return await File(path).exists() ? path : null;
  }

  Future<void> ensureMarkdownReady() async {
    if (state.markdownContent != null) return;
    final mdPath = state.markdownPath;
    if (mdPath == null) return;

    final epoch = _loadEpoch;
    _loadFuture ??= _loadAndResolveMarkdown(mdPath, epoch);
    if (!state.markdownLoading) {
      state = state.copyWith(markdownLoading: true, markdownLoadError: null);
    }

    try {
      final content = await _loadFuture!;
      if (!mounted || epoch != _loadEpoch || state.markdownPath != mdPath) {
        return;
      }
      state = state.copyWith(
        markdownContent: content,
        markdownLoading: false,
        markdownLoadError: null,
      );
    } catch (error) {
      if (!mounted || epoch != _loadEpoch) return;
      state = state.copyWith(markdownLoading: false, markdownLoadError: error);
    }
  }

  Future<String> _loadAndResolveMarkdown(String mdPath, int epoch) async {
    final resolved = await MarkdownDocumentCacheService.instance.loadDocument(
      mdPath: mdPath,
      title: args.title,
    );
    if (mounted && epoch == _loadEpoch && state.markdownPath == mdPath) {
      state = state.copyWith(markdownCacheKey: resolved.cacheKey);
    }
    return resolved.content;
  }

  Future<void> _reloadExtraction(String mdPath) async {
    final epoch = ++_loadEpoch;
    try {
      final content = await File(mdPath).readAsString();
      if (!mounted || epoch != _loadEpoch) return;
      useExtractedMarkdown(markdownPath: mdPath, markdownContent: content);
    } catch (error) {
      if (!mounted || epoch != _loadEpoch) return;
      if (state.markdownContent == null) {
        state = state.copyWith(
          markdownLoading: false,
          markdownLoadError: error,
        );
      }
    }
  }

  void useExtractedMarkdown({
    required String markdownPath,
    required String markdownContent,
  }) {
    if (!mounted) return;
    ++_loadEpoch;
    final revision = state.contentRevision + 1;
    final cacheService = MarkdownDocumentCacheService.instance;
    final contentKey = cacheService.buildMemoryCacheKey(
      mdPath: markdownPath,
      title: args.title,
      markdownContent: markdownContent,
    );
    final cacheKey = '$contentKey|revision=$revision';
    cacheService.primeResolvedContent(
      cacheKey: cacheKey,
      content: markdownContent,
    );
    _loadFuture = null;
    state = state.copyWith(
      markdownPath: markdownPath,
      markdownContent: markdownContent,
      markdownCacheKey: cacheKey,
      contentRevision: revision,
      markdownLoading: false,
      markdownLoadError: null,
      showPreview: true,
      searchActive: false,
      highlightQuery: null,
      searchResultCount: 0,
      currentResultIndex: 0,
    );
  }

  bool togglePreview() {
    clearHighlight();
    final enteringMarkdown = !state.showPreview;
    state = state.copyWith(showPreview: enteringMarkdown, searchActive: false);
    if (enteringMarkdown) {
      unawaited(ensureMarkdownReady());
    }
    return enteringMarkdown;
  }

  Future<bool> openMarkdownSearch() async {
    if (state.markdownContent == null && state.markdownPath != null) {
      await ensureMarkdownReady();
    }
    if (!mounted || state.markdownContent == null) return false;
    state = state.copyWith(searchActive: true);
    return true;
  }

  bool openPdfSearch() {
    if (!state.fileExists) return false;
    state = state.copyWith(searchActive: true);
    return true;
  }

  void closeSearch() {
    state = state.copyWith(searchActive: false);
  }

  void updateSearchResults(int totalResults) {
    state = state.copyWith(searchResultCount: totalResults);
  }

  void selectSearchResult(int hitIndex, String query, int totalResults) {
    state = state.copyWith(
      searchActive: false,
      showPreview: true,
      searchResultCount: totalResults,
      currentResultIndex: hitIndex,
      highlightQuery: query,
    );
  }

  void clearHighlight() {
    if (state.highlightQuery == null) return;
    state = state.copyWith(
      highlightQuery: null,
      searchResultCount: 0,
      currentResultIndex: 0,
    );
  }

  int? goToPreviousSearchResult() {
    final count = state.searchResultCount;
    if (count == 0) return null;
    final next = (state.currentResultIndex - 1 + count) % count;
    state = state.copyWith(currentResultIndex: next);
    return next;
  }

  int? goToNextSearchResult() {
    final count = state.searchResultCount;
    if (count == 0) return null;
    final next = (state.currentResultIndex + 1) % count;
    state = state.copyWith(currentResultIndex: next);
    return next;
  }

  void setSheetOpen(bool value) {
    if (state.sheetOpen == value) return;
    state = state.copyWith(sheetOpen: value);
  }

  void setDockOpen(bool value) {
    if (state.dockOpen == value) return;
    state = state.copyWith(dockOpen: value);
  }

  bool get canReactToReaderScroll =>
      !state.sheetOpen &&
      !state.dockOpen &&
      !state.searchActive &&
      state.highlightQuery == null;

  void handleReaderScrollDirection(ScrollDirection direction) {
    switch (direction) {
      case ScrollDirection.reverse:
        if (state.toolbarsVisible) {
          state = state.copyWith(toolbarsVisible: false);
        }
      case ScrollDirection.forward:
        if (!state.toolbarsVisible) {
          state = state.copyWith(toolbarsVisible: true);
        }
      case ScrollDirection.idle:
        break;
    }
  }

  void revealToolbars() {
    if (!state.toolbarsVisible) {
      state = state.copyWith(toolbarsVisible: true);
    }
  }

  void toggleToolbars({bool allowDockOpen = false}) {
    if (state.sheetOpen ||
        state.searchActive ||
        state.highlightQuery != null ||
        (state.dockOpen && !allowDockOpen)) {
      return;
    }
    state = state.copyWith(toolbarsVisible: !state.toolbarsVisible);
  }

  void setSummaryImagePath(String imagePath) {
    state = state.copyWith(summaryImagePath: imagePath);
  }

  Highlight? addHighlight(String text, String color, {ReaderAnchor? anchor}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || args.documentId.isEmpty) return null;
    // 非乐观（ADR-0001）：add 返回它构造的 Highlight，不靠流即时反映做 diff。
    return _ref
        .read(highlightProvider(args.documentId).notifier)
        .add(trimmed, color: color, anchor: anchor);
  }

  void removeHighlight(String highlightId) {
    if (args.documentId.isEmpty) return;
    _ref.read(highlightProvider(args.documentId).notifier).remove(highlightId);
  }

  void updateHighlightColor(String highlightId, String color) {
    if (args.documentId.isEmpty) return;
    _ref
        .read(highlightProvider(args.documentId).notifier)
        .updateColor(highlightId, color);
  }

  void updateHighlightNote(String highlightId, String note) {
    if (args.documentId.isEmpty) return;
    _ref
        .read(highlightProvider(args.documentId).notifier)
        .updateNote(highlightId, note);
  }

  /// 上报阅读进度 (0.0–1.0)。
  ///
  /// 写盘节流走 [HistoryNotifier.setProgress] 内的 2s 防抖；session 自己不持有
  /// progress state（事实源是 HistoryEntry，UI 直接 watch historyProvider）。
  /// PDF 翻页 + Markdown WebView 滚动两条路都把数据汇到这里。
  /// [anchorBlock] 仅 Markdown 路径提供（内容块锚点），PDF 传 null。
  void reportProgress(double progress, {int? anchorBlock}) {
    if (args.documentId.isEmpty) return;
    _ref
        .read(historyProvider.notifier)
        .setProgress(args.documentId, progress, anchorBlock: anchorBlock);
  }

  /// reader 退出时调，强制把防抖窗口里的最后一次进度落盘。
  Future<void> flushProgress() async {
    await _ref.read(historyProvider.notifier).flushProgress();
  }
}

final readerSessionProvider =
    StateNotifierProvider.family<
      ReaderSessionNotifier,
      ReaderSessionState,
      ReaderSessionArgs
    >((ref, args) => ReaderSessionNotifier(ref, args));
