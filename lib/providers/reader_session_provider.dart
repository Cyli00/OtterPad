import 'dart:async';
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../data/models/book/highlight.dart';
import '../services/document_summary_image_service.dart';
import '../services/reader/markdown_document_cache_service.dart';
import '../utils/doc_paths.dart';
import 'highlight_provider.dart';
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
  final bool markdownLoading;
  final Object? markdownLoadError;
  final MarkdownSearchSnapshot? searchSnapshot;
  final bool searchActive;
  final String? highlightQuery;
  final List<SearchResult> searchResults;
  final int currentResultIndex;
  final bool toolbarsVisible;
  final bool sheetOpen;
  final String? summaryImagePath;

  const ReaderSessionState({
    this.initialized = false,
    this.fileExists = false,
    this.showPreview = false,
    this.markdownPath,
    this.markdownContent,
    this.markdownCacheKey,
    this.markdownLoading = false,
    this.markdownLoadError,
    this.searchSnapshot,
    this.searchActive = false,
    this.highlightQuery,
    this.searchResults = const [],
    this.currentResultIndex = 0,
    this.toolbarsVisible = true,
    this.sheetOpen = false,
    this.summaryImagePath,
  });

  bool get hasResult => markdownPath != null || markdownContent != null;
  bool get hasMarkdownContent => markdownContent != null;
  bool get showingMarkdown => showPreview && hasResult;
  bool get markdownHighlightMode => showPreview && highlightQuery != null;

  ReaderSessionState copyWith({
    bool? initialized,
    bool? fileExists,
    bool? showPreview,
    Object? markdownPath = _sentinel,
    Object? markdownContent = _sentinel,
    Object? markdownCacheKey = _sentinel,
    bool? markdownLoading,
    Object? markdownLoadError = _sentinel,
    Object? searchSnapshot = _sentinel,
    bool? searchActive,
    Object? highlightQuery = _sentinel,
    List<SearchResult>? searchResults,
    int? currentResultIndex,
    bool? toolbarsVisible,
    bool? sheetOpen,
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
      markdownLoading: markdownLoading ?? this.markdownLoading,
      markdownLoadError: identical(markdownLoadError, _sentinel)
          ? this.markdownLoadError
          : markdownLoadError,
      searchSnapshot: identical(searchSnapshot, _sentinel)
          ? this.searchSnapshot
          : searchSnapshot as MarkdownSearchSnapshot?,
      searchActive: searchActive ?? this.searchActive,
      highlightQuery: identical(highlightQuery, _sentinel)
          ? this.highlightQuery
          : highlightQuery as String?,
      searchResults: searchResults ?? this.searchResults,
      currentResultIndex: currentResultIndex ?? this.currentResultIndex,
      toolbarsVisible: toolbarsVisible ?? this.toolbarsVisible,
      sheetOpen: sheetOpen ?? this.sheetOpen,
      summaryImagePath: identical(summaryImagePath, _sentinel)
          ? this.summaryImagePath
          : summaryImagePath as String?,
    );
  }

  int? blockIndexForCharOffset(int charOffset) {
    final md = markdownContent;
    if (md == null || md.isEmpty) return null;
    final safeOffset = charOffset.clamp(0, md.length);
    final breaks = RegExp(r'\n\n+').allMatches(md);
    var blockIndex = 0;
    for (final brk in breaks) {
      if (brk.start >= safeOffset) break;
      blockIndex++;
    }
    return blockIndex;
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
    unawaited(_init());
  }

  final Ref _ref;
  final ReaderSessionArgs args;
  Future<String>? _loadFuture;

  Future<void> _init() async {
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
    if (state.markdownContent != null) {
      _prewarmSearchSnapshot();
      return;
    }
    final mdPath = state.markdownPath;
    if (mdPath == null) return;

    _loadFuture ??= _loadAndResolveMarkdown(mdPath);
    if (!state.markdownLoading) {
      state = state.copyWith(markdownLoading: true, markdownLoadError: null);
    }

    try {
      final content = await _loadFuture!;
      if (!mounted || state.markdownPath != mdPath) return;
      state = state.copyWith(
        markdownContent: content,
        markdownLoading: false,
        markdownLoadError: null,
      );
      _prewarmSearchSnapshot();
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(markdownLoading: false, markdownLoadError: error);
    }
  }

  Future<String> _loadAndResolveMarkdown(String mdPath) async {
    final resolved = await MarkdownDocumentCacheService.instance.loadDocument(
      mdPath: mdPath,
      title: args.title,
    );
    if (mounted && state.markdownPath == mdPath) {
      state = state.copyWith(
        markdownCacheKey: resolved.cacheKey,
        searchSnapshot: null,
      );
    }
    return resolved.content;
  }

  Future<void> _prewarmSearchSnapshot() async {
    final content = state.markdownContent;
    final cacheKey = state.markdownCacheKey;
    if (content == null || cacheKey == null || state.searchSnapshot != null) {
      return;
    }
    final snapshot =
        await MarkdownDocumentCacheService.instance.getSearchSnapshot(
      cacheKey: cacheKey,
      markdownContent: content,
    );
    if (!mounted) return;
    state = state.copyWith(searchSnapshot: snapshot);
  }

  void useExtractedMarkdown({
    required String markdownPath,
    required String markdownContent,
  }) {
    final cacheService = MarkdownDocumentCacheService.instance;
    final cacheKey = cacheService.buildMemoryCacheKey(
      mdPath: markdownPath,
      title: args.title,
      markdownContent: markdownContent,
    );
    cacheService.primeResolvedContent(
      cacheKey: cacheKey,
      content: markdownContent,
    );
    _loadFuture = null;
    state = state.copyWith(
      markdownPath: markdownPath,
      markdownContent: markdownContent,
      markdownCacheKey: cacheKey,
      markdownLoading: false,
      markdownLoadError: null,
      searchSnapshot: null,
      showPreview: true,
      searchActive: false,
      highlightQuery: null,
      searchResults: const [],
      currentResultIndex: 0,
    );
    _prewarmSearchSnapshot();
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

  int selectSearchResult(
    List<SearchResult> results,
    int tappedIndex,
    String query,
  ) {
    final offset = results[tappedIndex].charOffset;
    state = state.copyWith(
      searchActive: false,
      showPreview: true,
      searchResults: results,
      currentResultIndex: tappedIndex,
      highlightQuery: query,
    );
    return offset;
  }

  void clearHighlight() {
    if (state.highlightQuery == null) return;
    state = state.copyWith(
      highlightQuery: null,
      searchResults: const [],
      currentResultIndex: 0,
    );
  }

  int? goToPreviousSearchResult() {
    final results = state.searchResults;
    if (results.isEmpty) return null;
    final next =
        (state.currentResultIndex - 1 + results.length) % results.length;
    state = state.copyWith(currentResultIndex: next);
    return results[next].charOffset;
  }

  int? goToNextSearchResult() {
    final results = state.searchResults;
    if (results.isEmpty) return null;
    final next = (state.currentResultIndex + 1) % results.length;
    state = state.copyWith(currentResultIndex: next);
    return results[next].charOffset;
  }

  void setSheetOpen(bool value) {
    if (state.sheetOpen == value) return;
    state = state.copyWith(sheetOpen: value);
  }

  bool get canReactToReaderScroll =>
      !state.sheetOpen && !state.searchActive && state.highlightQuery == null;

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

  void toggleToolbars() {
    if (!canReactToReaderScroll) return;
    state = state.copyWith(toolbarsVisible: !state.toolbarsVisible);
  }

  void setSummaryImagePath(String imagePath) {
    state = state.copyWith(summaryImagePath: imagePath);
  }

  Highlight? addHighlight(String text, String color) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || args.documentId.isEmpty) return null;

    final before = _ref.read(highlightProvider(args.documentId));
    final beforeIds = before.map((h) => h.id).toSet();
    _ref
        .read(highlightProvider(args.documentId).notifier)
        .add(trimmed, color: color);
    final after = _ref.read(highlightProvider(args.documentId));
    for (final highlight in after.reversed) {
      if (!beforeIds.contains(highlight.id)) return highlight;
    }
    return null;
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
  void reportProgress(double progress) {
    if (args.documentId.isEmpty) return;
    _ref
        .read(historyProvider.notifier)
        .setProgress(args.documentId, progress);
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
