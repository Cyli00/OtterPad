import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart' hide Block;
import 'package:material_symbols_icons/symbols.dart';

import '../../core/animation_constants.dart';
import '../../core/folio_look.dart';
import 'package:motor/motor.dart';
import '../../core/l10n.dart';
import '../../core/otter_error_text.dart';
import '../../core/rust_backend.dart';
import '../../core/storage/settings_keys.dart';
import '../../core/storage/storage.dart';
import '../../data/models/book/document.dart';
import '../../data/models/book/highlight.dart';
import '../../providers/doc_extract_api_provider.dart';
import '../../providers/document_task_provider.dart';
import '../../providers/document_translation_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/highlight_provider.dart';
import '../../providers/history_provider.dart';
import '../../providers/reader_settings_provider.dart';
import '../../providers/translation_config_provider.dart';
import '../../router/app_routes.dart';
import '../../services/haptics.dart';
import '../../services/snackbar_service.dart';
import '../../src/rust/api/document.dart';
import '../../src/rust/document.dart';
import '../../utils/desktop.dart';
import '../../utils/doc_paths.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_context_menu.dart';
import '../../widgets/extract_provider_dialog.dart';
import '../library/widgets/doc_card_actions.dart';
import '../reader2/reader_controller.dart';
import '../reader2/reader_layout.dart';
import '../reader2/reader_surface.dart';
import 'chat/document_chat_page.dart';
import 'pdf/pdf_controller.dart';
import 'pdf/pdf_translation.dart';
import 'pdf/pdf_view.dart';
import 'widgets/figure_viewer.dart';
import 'widgets/outline_panel.dart';
import 'widgets/reader_background.dart';
import 'widgets/reader_bottom_bar.dart';
import 'widgets/reader_chat_return_prompt.dart';
import 'widgets/reader_desktop_appearance.dart';
import 'widgets/reader_docked_pane.dart';
import 'widgets/reader_document_info_sheet.dart';
import 'widgets/reader_icon_button.dart';
import 'widgets/reader_notes_sheet.dart';
import 'widgets/reader_search_bars.dart';
import 'widgets/reader_sheet_host.dart';
import 'widgets/reader_theme_sheet.dart';
import 'widgets/translation_popup.dart';

/// 阅读器：解析结果用原生重排正文（Rust 文档模型），也可切换查看原 PDF。
class ReaderPage extends ConsumerStatefulWidget {
  final Document document;

  const ReaderPage({super.key, required this.document});

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage> {
  final _surface = GlobalKey<ReaderSurfaceState>();
  final _query = TextEditingController();
  final _queryFocus = FocusNode();
  final _bodyFocus = FocusNode();
  final _progress = ValueNotifier<double>(0);
  final _pdfSearch = PdfViewController();

  // PDF 译文叠加：按译文表与文档身份缓存。
  Map<String, String>? _overlayTranslations;
  ReaderDocument? _overlayDocument;
  Map<int, List<PdfTextOverlay>> _pdfOverlays = const {};
  final _parsedTranslations = <String, List<InlineRun>>{};
  late final HistoryNotifier _history;

  ReaderController? _controller;
  bool _loading = true;
  Object? _loadError;
  bool _pdfMode = false;
  bool _searching = false;
  bool _toolbars = true;
  final _sheetHost = GlobalKey<ReaderSheetHostState>();
  ReaderSheetType? _sheet;
  DocumentChatPageArgs? _chatReturn;
  int _quoteEpoch = 0;

  // 宽屏右侧停靠栏：大纲、笔记、问 AI 三选一；首次打开后才挂载。
  bool _dockMounted = false;
  bool _dockOpen = false;
  ReaderDockPane _dockPane = ReaderDockPane.outline;

  /// 用户拖拽得到的停靠栏宽度；null 时随窗口自适应。
  double? _sidebarWidth;
  String? _dockQuote;
  Map<String, dynamic>? _dockQuoteAnchor;
  String? _dockFigurePath;

  /// 划词意图条带出的问题，停靠栏聊天页发送后清空。
  String? _dockPrompt;

  /// 桌面端外观设置浮层（窄屏用底部面板）。
  bool _appearanceOpen = false;

  String get _id => widget.document.id;
  bool get _fileExists => File(DocPaths.pdf(_id)).existsSync();
  bool get _hasModel => _controller?.source.blocks.isNotEmpty == true;

  @override
  void initState() {
    super.initState();
    _history = ref.read(historyProvider.notifier);
    _sidebarWidth =
        GStorage.setting.get(SettingsKeys.readerSidebarWidth) as double?;
    _pdfMode =
        ref.read(readerSettingsProvider).defaultReadingMode ==
        DefaultReadingMode.pdf;
    unawaited(_history.record(_id));
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_history.flushProgress());
    _controller?.dispose();
    _pdfSearch.dispose();
    _query.dispose();
    _queryFocus.dispose();
    _bodyFocus.dispose();
    _progress.dispose();
    super.dispose();
  }

  // ── 数据 ──

  /// 读取 Rust 文档模型；没有解析结果时得到空模型，阅读器停在 PDF。
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final model = await RustBackend.instance.readerDocument(document: _id);
      final notes = await ref.read(highlightProvider(_id).future);
      if (!mounted) return;
      final controller = ReaderController(
        model,
        highlights: _readerHighlights(notes),
        onHighlightSaved: _saveHighlight,
        onHighlightRemoved: (id) =>
            ref.read(highlightProvider(_id).notifier).delete(id),
      )..mode = _readerMode(ref.read(readerSettingsProvider).paginationMode);
      _restoreLocation(controller);
      _controller?.dispose();
      _controller = controller;
      _syncTranslations();
      setState(() {
        _loading = false;
        if (model.blocks.isEmpty) _pdfMode = true;
      });
      unawaited(_relocateHighlights(controller, notes));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e;
        _pdfMode = true;
      });
    }
  }

  void _restoreLocation(ReaderController controller) {
    HistoryEntry? entry;
    for (final h in ref.read(historyProvider).value ?? const <HistoryEntry>[]) {
      if (h.docId == _id) entry = h;
    }
    _progress.value = entry?.progress ?? 0;
    final block = entry?.anchorBlock;
    final index = block == null ? null : controller.indexOfBlock(block);
    if (index != null) controller.location = ReaderLocation(index, 0);
  }

  /// 笔记的 Rust 锚点（`{version: 2, ranges}`）转为阅读器标注；未定位的只留在笔记列表。
  List<ReaderHighlight> _readerHighlights(List<Highlight> notes) => [
    for (final n in notes)
      if (_ranges(n.anchor) case final ranges? when ranges.isNotEmpty)
        ReaderHighlight(
          id: n.id,
          ranges: ranges,
          color: n.color,
          note: n.note,
          createdAt: n.createdAt,
        ),
  ];

  static List<AnchorRange>? _ranges(Map<String, dynamic>? anchor) {
    final raw = anchor?['ranges'];
    if (raw is! List) return null;
    return [
      for (final r in raw)
        if (r is Map)
          AnchorRange(
            blockId: '${r['block_id'] ?? r['paragraphId'] ?? ''}',
            language: '${r['language'] ?? 'source'}',
            revision: '${r['revision'] ?? ''}',
            start: BigInt.from((r['start'] as num?)?.toInt() ?? 0),
            end: BigInt.from((r['end'] as num?)?.toInt() ?? 0),
            quote: '${r['quote'] ?? ''}',
            prefix: '${r['prefix'] ?? ''}',
            suffix: '${r['suffix'] ?? ''}',
          ),
    ];
  }

  static Map<String, dynamic> _anchorJson(List<AnchorRange> ranges) => {
    'version': 2,
    'located': true,
    'ranges': [
      for (final r in ranges)
        {
          'block_id': r.blockId,
          'language': r.language,
          'revision': r.revision,
          'start': r.start.toInt(),
          'end': r.end.toInt(),
          'quote': r.quote,
          'prefix': r.prefix,
          'suffix': r.suffix,
        },
    ],
  };

  void _saveHighlight(ReaderHighlight h) {
    final existing = (ref.read(highlightProvider(_id)).value ?? const [])
        .where((n) => n.id == h.id)
        .firstOrNull;
    unawaited(
      ref
          .read(highlightProvider(_id).notifier)
          .save(
            Highlight(
              id: h.id,
              documentId: _id,
              text: h.text,
              note: h.note,
              color: h.color,
              groupId: existing?.groupId,
              anchor: {...?existing?.anchor, ..._anchorJson(h.ranges)},
              createdAt: h.createdAt,
            ),
          ),
    );
  }

  /// 文档重新解析后块内容可能变化：按引文与上下文重新定位，成功的写回存储。
  Future<void> _relocateHighlights(
    ReaderController controller,
    List<Highlight> notes,
  ) async {
    final blocks = {for (final b in controller.source.blocks) b.id: b};
    for (final note in notes) {
      final ranges = _ranges(note.anchor);
      if (ranges == null || ranges.isEmpty) continue;
      final stale = ranges.any(
        (r) =>
            r.language == 'source' && blocks[r.blockId]?.revision != r.revision,
      );
      if (!stale) continue;
      final relocated = <AnchorRange>[];
      for (final r in ranges) {
        final found = r.language == 'source'
            ? await RustBackend.instance.resolveAnchor(document: _id, anchor: r)
            : r;
        if (found == null) break;
        relocated.add(found);
      }
      if (!mounted || !identical(controller, _controller)) return;
      if (relocated.length != ranges.length) continue;
      final highlight = ReaderHighlight(
        id: note.id,
        ranges: relocated,
        color: note.color,
        note: note.note,
        createdAt: note.createdAt,
      );
      if (controller.highlights.any((h) => h.id == note.id)) {
        controller.updateHighlight(highlight);
      }
    }
  }

  void _syncTranslations() {
    final controller = _controller;
    if (controller == null) return;
    final translation = ref.read(documentTranslationProvider(_id));
    final language = ref.read(translationConfigProvider).targetLanguage;
    controller.setTranslations(
      translation.translations,
      translation.mode,
      language,
      rtl: isRtlTargetLanguage(language),
    );
  }

  // ── 动作 ──

  Future<void> _extract() async {
    if (!_fileExists) {
      ref
          .read(snackBarServiceProvider)
          .showResult(tone: SnackTone.error, message: context.l10n.pdfNotFound);
      return;
    }
    final apiState = await showExtractProviderDialog(
      context: context,
      apiState: ref.read(docExtractApiProvider),
    );
    if (!mounted || apiState == null) return;
    final generation = await ref
        .read(documentTaskProvider.notifier)
        .extractDocument(
          documentId: _id,
          title: widget.document.title,
          apiState: apiState,
        );
    if (generation != null && mounted) await _load();
  }

  void _toggleMode() {
    Haptics.soft();
    _closeSearch();
    setState(() => _pdfMode = !_pdfMode);
  }

  void _openSearch() {
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queryFocus.requestFocus();
      _query.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _query.text.length,
      );
    });
  }

  void _closeSearch() {
    if (!_searching) return;
    _query.clear();
    _controller?.clearSearch();
    _pdfSearch.clearSearch();
    setState(() => _searching = false);
    _bodyFocus.requestFocus();
  }

  void _onQuery(String query) {
    if (_pdfMode) {
      _pdfSearch.search(query);
    } else {
      _controller?.search(query);
    }
    setState(() {});
  }

  void _stepHit(int delta) {
    if (_pdfMode) {
      _pdfSearch.step(delta);
    } else {
      _controller?.stepHit(delta);
    }
  }

  void _onLocation(ReaderLocation location, double progress) {
    _progress.value = progress;
    final blocks = _controller?.model.blocks;
    var id = blocks == null || location.blockIndex >= blocks.length
        ? null
        : blocks[location.blockIndex].id;
    if (id != null && id.endsWith('#t')) id = id.substring(0, id.length - 2);
    unawaited(_history.setProgress(_id, progress, anchorBlock: id));
  }

  Future<void> _translateDocument() async {
    final notifier = ref.read(documentTranslationProvider(_id).notifier);
    await notifier.translate();
    if (!mounted) return;
    final state = ref.read(documentTranslationProvider(_id));
    final l10n = context.l10n;
    final snack = ref.read(snackBarServiceProvider);
    if (state.status == DocTranslationStatus.failed) {
      snack.showResult(
        tone: SnackTone.error,
        message: translationErrorText(l10n, state.error),
      );
    } else if (state.hasResult) {
      snack.showResult(message: l10n.translationDone);
    }
  }

  void _openChat({
    String? quote,
    String? figurePath,
    List<AnchorRange>? anchor,
    String? prompt,
  }) {
    Haptics.soft();
    if (_useDock) {
      setState(() {
        _dockQuote = quote;
        _dockQuoteAnchor = anchor == null ? null : _anchorJson(anchor);
        _dockFigurePath = figurePath;
        _dockPrompt = prompt;
        _quoteEpoch++;
        _chatReturn = null;
        _showDock(ReaderDockPane.askAi);
      });
      return;
    }
    context.push(
      AppRoutes.readerChat,
      extra: DocumentChatPageArgs(
        document: widget.document,
        initialQuote: quote,
        quoteAnchor: anchor == null ? null : _anchorJson(anchor),
        figureImagePath: figurePath,
        onLocateQuote: _locateQuote,
        quoteEpoch: ++_quoteEpoch,
        initialPrompt: prompt,
      ),
    );
  }

  /// 问 AI 的「定位原文」：在正文中找到引文并滚到该处，显示返回问 AI 的入口。
  bool _locateQuote(String quote, DocumentChatPageArgs args) {
    final controller = _controller;
    if (controller == null || !_hasModel) return false;
    String normalize(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
    final needle = normalize(quote);
    if (needle.isEmpty) return false;
    final probe = needle.length > 40 ? needle.substring(0, 40) : needle;
    final blocks = controller.model.blocks;
    for (var i = 0; i < blocks.length; i++) {
      if (!normalize(blocks[i].text).contains(probe)) continue;
      final docked = _dockOpen && _dockPane == ReaderDockPane.askAi;
      setState(() {
        _pdfMode = false;
        if (!docked) {
          _chatReturn = DocumentChatPageArgs(
            document: args.document,
            onLocateQuote: _locateQuote,
            preserveSession: true,
          );
        }
      });
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _surface.currentState?.reveal(ReaderLocation(i, 0)),
      );
      return true;
    }
    return false;
  }

  void _copyText(String text) {
    Haptics.soft();
    Clipboard.setData(ClipboardData(text: text));
    ref
        .read(snackBarServiceProvider)
        .showResult(message: context.l10n.copiedToClipboard);
  }

  void _showTranslation(
    String text,
    Rect anchor,
    void Function(String color, String note) addNote,
  ) {
    unawaited(
      showTranslationPopup(context, sourceText: text, onAddNote: addNote),
    );
  }

  void _openFigure(Block block, FigureHeroSource heroSource) {
    final model = _controller?.source;
    if (model == null) return;
    final translation = ref.read(documentTranslationProvider(_id));
    final keys = {
      for (var i = 0; i < model.blocks.length; i++)
        model.blocks[i].id: model.translationKeys.elementAtOrNull(i) ?? '',
    };
    final views = <FigureView>[];
    var initial = 0;
    for (final image in model.figureImages) {
      final b = model.blocks.where((x) => x.id == image.blockId).firstOrNull;
      if (b == null) continue;
      if (b.id == block.id) initial = views.length;
      views.add(
        FigureView(
          path: image.path,
          caption: b.text,
          translation: translation.translations[keys[b.id]],
        ),
      );
    }
    unawaited(
      showFigureViewer(
        context,
        views,
        initialIndex: initial,
        heroSource: heroSource,
        onAskAi: (f) => _openChat(quote: f.caption, figurePath: f.path),
      ),
    );
  }

  Future<void> _generateSummary() async {
    final path = await ref
        .read(documentTaskProvider.notifier)
        .generateSummaryImage(document: widget.document);
    if (path != null && mounted) _showSummary();
  }

  void _showSummary() {
    unawaited(
      showFigureViewer(context, [
        FigureView(path: DocPaths.summaryImage(_id), caption: ''),
      ], heroSource: FigureHeroSource.outline),
    );
  }

  // ── PDF 译文 ──

  /// PDF 只有原文/译文两态；双语在 PDF 上投影为译文，不改写保存的模式。
  DocTranslationMode _nextPdfTranslationMode(DocumentTranslationState t) =>
      t.mode == DocTranslationMode.off
      ? DocTranslationMode.translated
      : DocTranslationMode.off;

  Map<int, List<PdfTextOverlay>> _pdfTranslationOverlays() {
    final translation = ref.read(documentTranslationProvider(_id));
    final document = _controller?.source;
    if (document == null ||
        translation.mode == DocTranslationMode.off ||
        translation.translations.isEmpty) {
      return const {};
    }
    if (!identical(translation.translations, _overlayTranslations) ||
        !identical(document, _overlayDocument)) {
      _overlayTranslations = translation.translations;
      _overlayDocument = document;
      _pdfOverlays = pdfTranslationOverlays(
        document,
        translation.translations,
        _parsedTranslations,
      );
    }
    return _pdfOverlays;
  }

  // ── 面板：宽屏停靠在右侧，窄屏从底部弹出；外观在桌面端是浮层 ──

  bool get _useDock =>
      MediaQuery.sizeOf(context).width >= Responsive.kReaderDockMinWidth;

  void _showDock(ReaderDockPane pane) {
    _dockMounted = true;
    _dockPane = pane;
    _dockOpen = true;
    _appearanceOpen = false;
  }

  void _toggleDock(ReaderDockPane pane) {
    Haptics.soft();
    setState(() {
      if (_dockOpen && _dockPane == pane) {
        _dockOpen = false;
      } else {
        _showDock(pane);
      }
    });
  }

  void _closeDock() => setState(() => _dockOpen = false);

  void _toggleOutline() => _useDock
      ? _toggleDock(ReaderDockPane.outline)
      : _toggleSheet(ReaderSheetType.outline);

  void _toggleNotes() => _useDock
      ? _toggleDock(ReaderDockPane.notes)
      : _toggleSheet(ReaderSheetType.notes);

  void _toggleAskAi() {
    if (_useDock) {
      _toggleDock(ReaderDockPane.askAi);
    } else {
      _openChat();
    }
  }

  void _toggleAppearance() {
    if (isDesktopOs) {
      Haptics.soft();
      setState(() => _appearanceOpen = !_appearanceOpen);
    } else {
      _toggleSheet(ReaderSheetType.theme);
    }
  }

  Future<void> _toggleSheet(ReaderSheetType type) async {
    final host = _sheetHost.currentState;
    if (host == null) return;
    if (_sheet == type) {
      host.close();
      return;
    }
    Haptics.soft();
    final future = host.show<void>(
      bottomBarHeight: 0,
      barrierAlpha: type == ReaderSheetType.theme ? 0.25 : 0.32,
      builder: (_) => switch (type) {
        ReaderSheetType.outline => ReaderSheetFrame(
          fill: true,
          child: _outline(),
        ),
        ReaderSheetType.notes => ReaderNotesSheetBody(documentId: _id),
        ReaderSheetType.theme => const ReaderSheetFrame(
          child: ReaderThemeSheetBody(),
        ),
      },
    );
    setState(() => _sheet = type);
    await future;
  }

  /// 大纲内容；sheet 与停靠栏共用。总结图生成状态在此订阅，sheet 内也能刷新。
  Widget _outline() => Consumer(
    builder: (context, ref, _) {
      final generating = ref.watch(
        documentTaskProvider.select(
          (tasks) =>
              tasks[DocumentTaskKey(
                    type: DocumentTaskType.generateSummaryImage,
                    documentId: _id,
                  )]
                  ?.isActive ==
              true,
        ),
      );
      final controller = _controller;
      if (controller == null) return const SizedBox.shrink();
      return OutlinePanel(
        model: controller.source,
        summaryPath: DocPaths.summaryImage(_id),
        generatingSummary: generating,
        onNavigate: _revealBlock,
        onOpenFigure: (b) => _openFigure(b, FigureHeroSource.outline),
        onGenerateSummary: _hasModel ? _generateSummary : null,
        onOpenSummary: _showSummary,
      );
    },
  );

  void _revealBlock(String blockId) {
    final index = _controller?.indexOfBlock(blockId);
    if (index == null) return;
    if (_sheet != null) _sheetHost.currentState?.close();
    setState(() => _pdfMode = false);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _surface.currentState?.reveal(ReaderLocation(index, 0)),
    );
  }

  void _onSidebarDrag(DragUpdateDetails details) {
    final width = MediaQuery.sizeOf(context).width;
    final current = Responsive.clampReaderSidebarWidth(
      _sidebarWidth ?? Responsive.readerSidebarWidth(width),
      width,
    );
    final next = Responsive.clampReaderSidebarWidth(
      current - details.delta.dx,
      width,
    );
    if (next != current) setState(() => _sidebarWidth = next);
  }

  void _onSidebarDragEnd() {
    final width = _sidebarWidth;
    if (width != null) {
      unawaited(GStorage.setting.put(SettingsKeys.readerSidebarWidth, width));
    }
  }

  Future<void> _toggleFavorite(bool inFavorite) async {
    if (!inFavorite) {
      await DocCardActions.addToFavorite(context, ref, {_id});
      return;
    }
    final favorites = ref.read(favoritesProvider.notifier);
    for (final f in ref.read(favoritesProvider).value ?? const []) {
      if (f.documentIds.contains(_id)) {
        await favorites.removeDocument(f.id, _id);
      }
    }
    if (mounted) {
      ref
          .read(snackBarServiceProvider)
          .showResult(message: context.l10n.removeFromFavorite);
    }
  }

  // ── 构建 ──

  /// 笔记面板删改后同步到正文；正文自身的写入已在控制器里。
  void _syncHighlights(List<Highlight>? notes) {
    final controller = _controller;
    if (notes == null || controller == null) return;
    final byId = {for (final n in notes) n.id: n};
    final changed = controller.highlights.any((h) {
      final n = byId[h.id];
      return n == null || n.note != h.note || n.color != h.color;
    });
    if (changed) controller.replaceHighlights(_readerHighlights(notes));
  }

  static ReaderMode _readerMode(ReaderPaginationMode mode) => switch (mode) {
    ReaderPaginationMode.vertical => ReaderMode.scroll,
    ReaderPaginationMode.horizontal => ReaderMode.paged,
  };

  @override
  Widget build(BuildContext context) {
    ref.listen(documentTranslationProvider(_id), (_, _) => _syncTranslations());
    ref.listen(
      translationConfigProvider.select((c) => c.targetLanguage),
      (_, _) => _syncTranslations(),
    );
    ref.listen(
      highlightProvider(_id),
      (_, next) => _syncHighlights(next.value),
    );
    ref.listen(readerSettingsProvider.select((s) => s.paginationMode), (
      _,
      mode,
    ) {
      final controller = _controller;
      if (controller == null) return;
      controller
        ..clearSelection()
        ..mode = _readerMode(mode);
    });

    final settings = ref.watch(readerSettingsProvider);
    final theme = buildReaderThemeData(Theme.of(context), settings.theme);
    final cs = theme.colorScheme;
    final palette = resolveReaderPalette(settings.theme, cs);
    final translation = ref.watch(documentTranslationProvider(_id));
    final extracting = ref.watch(
      documentTaskProvider.select(
        (tasks) =>
            tasks[DocumentTaskKey(
                  type: DocumentTaskType.extractDocument,
                  documentId: _id,
                )]
                ?.isActive ==
            true,
      ),
    );
    final inFavorite = (ref.watch(favoritesProvider).value ?? const []).any(
      (f) => f.documentIds.contains(_id),
    );
    final showBottom = _hasModel;
    final useDock = _useDock;
    final windowWidth = MediaQuery.sizeOf(context).width;
    final sidebarWidth = Responsive.clampReaderSidebarWidth(
      _sidebarWidth ?? Responsive.readerSidebarWidth(windowWidth),
      windowWidth,
    );

    // 悬浮玻璃栏打开时，底栏叠在正文上方而不是占一行
    final floatBar = FolioLook.of(context).floatingBars;
    Widget readerBar() => ReaderBottomBar(
      readerSettings: settings,
      translation: translation,
      activeSheet: _appearanceOpen ? ReaderSheetType.theme : _sheet,
      activeDock: useDock && _dockOpen ? _dockPane : null,
      desktop: isDesktopOs,
      pdfView: _pdfMode,
      nextTranslationMode: _pdfMode
          ? _nextPdfTranslationMode(translation)
          : null,
      readingProgress: _progress,
      onOpenOutline: _toggleOutline,
      onTranslate: _translateDocument,
      onCycleTranslationMode: () {
        final notifier = ref.read(documentTranslationProvider(_id).notifier);
        if (_pdfMode) {
          notifier.setMode(_nextPdfTranslationMode(translation));
        } else {
          notifier.cycleMode();
        }
      },
      onAskAi: _toggleAskAi,
      onOpenNotes: _toggleNotes,
      onOpenTheme: _toggleAppearance,
    );

    return Theme(
      data: theme,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
              _openSearch,
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _openSearch,
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (_searching) {
              _closeSearch();
            } else {
              _controller?.clearSelection();
            }
          },
        },
        child: Scaffold(
          backgroundColor: _pdfMode ? cs.surface : palette.background,
          resizeToAvoidBottomInset: false,
          body: SafeArea(
            bottom: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      AnimatedSize(
                        duration: kAnim,
                        curve: kAnimCurve,
                        child: _toolbars || _searching
                            ? ColoredBox(
                                color: cs.surface,
                                child: _toolbar(
                                  context,
                                  inFavorite,
                                  extracting,
                                ),
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: _body(
                                context,
                                palette,
                                settings,
                                extracting,
                              ),
                            ),
                            if (_chatReturn case final args?)
                              Positioned(
                                right: 16,
                                bottom: 16,
                                child: ReaderChatReturnPrompt(
                                  onCancel: () =>
                                      setState(() => _chatReturn = null),
                                  onReturn: () {
                                    setState(() => _chatReturn = null);
                                    context.push(
                                      AppRoutes.readerChat,
                                      extra: args,
                                    );
                                  },
                                ),
                              ),
                            Positioned.fill(
                              child: ReaderSheetHost(
                                key: _sheetHost,
                                onSheetClose: () {
                                  if (mounted) setState(() => _sheet = null);
                                },
                              ),
                            ),
                            Positioned(
                              top: 16,
                              right: 16,
                              bottom: 16,
                              width: 360,
                              child: Align(
                                alignment: Alignment.bottomRight,
                                child: AnimatedSwitcher(
                                  duration: kAnim,
                                  reverseDuration: kAnimFast,
                                  switchInCurve: kAnimCurve,
                                  switchOutCurve: kAnimCurveReverse,
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(
                                        opacity: animation,
                                        child: ScaleTransition(
                                          alignment: Alignment.bottomRight,
                                          scale: Tween(
                                            begin: 0.92,
                                            end: 1.0,
                                          ).animate(animation),
                                          child: child,
                                        ),
                                      ),
                                  child: _appearanceOpen
                                      ? ConstrainedBox(
                                          key: const ValueKey('appearance'),
                                          constraints: const BoxConstraints(
                                            maxHeight: 640,
                                          ),
                                          child: ReaderDesktopAppearance(
                                            pdfView: _pdfMode,
                                            onClose: () => setState(
                                              () => _appearanceOpen = false,
                                            ),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                            ),
                            if (showBottom && floatBar)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: IgnorePointer(
                                  ignoring: !_toolbars,
                                  child: SingleMotionBuilder(
                                    motion: kMotionSpatialFast,
                                    value: _toolbars ? 1.0 : 0.0,
                                    active: !MediaQuery.disableAnimationsOf(
                                      context,
                                    ),
                                    builder: (context, t, child) =>
                                        Transform.translate(
                                          offset: Offset(0, 96 * (1 - t)),
                                          child: Opacity(
                                            opacity: t.clamp(0.0, 1.0),
                                            child: child,
                                          ),
                                        ),
                                    child: SafeArea(
                                      top: false,
                                      child: readerBar(),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (showBottom && !floatBar)
                        AnimatedSize(
                          duration: kAnim,
                          curve: kAnimCurve,
                          child: _toolbars
                              ? SafeArea(top: false, child: readerBar())
                              : const SizedBox(width: double.infinity),
                        ),
                    ],
                  ),
                ),
                if (useDock && _dockMounted)
                  ReaderDockedPane(
                    sidebarWidth: sidebarWidth,
                    open: _dockOpen,
                    pane: _dockPane,
                    onSidebarDragUpdate: _onSidebarDrag,
                    onSidebarDragEnd: _onSidebarDragEnd,
                    outline: _outline(),
                    notes: ReaderNotesPanel(documentId: _id),
                    chat: DocumentChatPage(
                      embedded: true,
                      paneWidth: sidebarWidth,
                      onClose: _closeDock,
                      args: DocumentChatPageArgs(
                        document: widget.document,
                        initialQuote: _dockQuote,
                        quoteAnchor: _dockQuoteAnchor,
                        figureImagePath: _dockFigurePath,
                        onLocateQuote: _locateQuote,
                        quoteEpoch: _quoteEpoch,
                        initialPrompt: _dockPrompt,
                      ),
                      // 意图条的问题只发一次：停靠栏重建时不再重发
                      onQuoteConsumed: () => _dockPrompt = null,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context, bool inFavorite, bool extracting) {
    final l10n = context.l10n;
    if (_searching) {
      final total = _pdfMode
          ? _pdfSearch.matches.length
          : _controller?.hits.length ?? 0;
      final current = _pdfMode
          ? _pdfSearch.currentIndex
          : (_controller?.currentHit ?? -1);
      return ReaderPdfSearchBar(
        controller: _query,
        focusNode: _queryFocus,
        hintText: l10n.searchContent,
        onBack: _closeSearch,
        onClear: _closeSearch,
        onChanged: _onQuery,
        onSubmitted: (_) => _stepHit(1),
        trailing: _query.text.trim().isEmpty
            ? null
            : _SearchCount(
                current: current,
                total: total,
                onPrevious: () => _stepHit(-1),
                onNext: () => _stepHit(1),
              ),
      );
    }
    final translation = ref.read(documentTranslationProvider(_id));
    final generating = ref.watch(
      documentTaskProvider.select(
        (tasks) =>
            tasks[DocumentTaskKey(
                  type: DocumentTaskType.generateSummaryImage,
                  documentId: _id,
                )]
                ?.isActive ==
            true,
      ),
    );
    final canReExtract = _hasModel && _fileExists && !extracting;
    final hasSummary = File(DocPaths.summaryImage(_id)).existsSync();
    final generate = ReaderIconButton(
      icon: Symbols.mindfulness_rounded,
      tooltip: l10n.generateSummary,
      loading: generating,
      onPressed: _generateSummary,
    );
    // PDF 视图与 0.1.x 一致，把重新解析和文档信息放在顶栏；解析视图把生成摘要图放在顶栏。
    final more = <AppContextMenuItem<String>>[
      if (!_pdfMode && hasSummary)
        AppContextMenuItem(
          value: 'viewSummary',
          label: l10n.viewSummary,
          icon: Symbols.image_rounded,
        ),
      if (!_pdfMode)
        AppContextMenuItem(
          value: 'info',
          label: l10n.documentInfo,
          icon: Symbols.info_rounded,
        ),
      if (!_pdfMode && canReExtract)
        AppContextMenuItem(
          value: 'extract',
          label: l10n.reExtract,
          icon: Symbols.sync_rounded,
        ),
      if (translation.hasResult)
        AppContextMenuItem(
          value: 'retranslate',
          label: l10n.reTranslate,
          icon: Symbols.translate_rounded,
        ),
      if (_pdfMode && _hasModel)
        AppContextMenuItem(
          value: 'summary',
          label: l10n.generateSummary,
          icon: Symbols.mindfulness_rounded,
        ),
      if (_pdfMode && hasSummary)
        AppContextMenuItem(
          value: 'viewSummary',
          label: l10n.viewSummary,
          icon: Symbols.image_rounded,
        ),
    ];
    final actions = [
      ReaderIconButton(
        icon: Symbols.search_rounded,
        tooltip: l10n.searchContent,
        onPressed: _loading ? null : _openSearch,
      ),
      ReaderIconButton(
        icon: !_hasModel
            ? Symbols.document_scanner_rounded
            : _pdfMode
            ? Symbols.article_rounded
            : Symbols.picture_as_pdf_rounded,
        tooltip: !_hasModel
            ? l10n.documentExtract
            : _pdfMode
            ? l10n.viewExtractResult
            : l10n.viewPdf,
        loading: extracting,
        onPressed: extracting || _loading
            ? null
            : (_hasModel ? _toggleMode : (_fileExists ? _extract : null)),
      ),
      if (!_pdfMode && _hasModel) generate,
      ReaderIconButton(
        icon: inFavorite
            ? Symbols.bookmark_remove_rounded
            : Symbols.bookmark_add_rounded,
        active: inFavorite,
        tooltip: inFavorite ? l10n.removeFromFavorite : l10n.addToFavorite,
        onPressed: () => _toggleFavorite(inFavorite),
      ),
      if (_pdfMode && canReExtract)
        ReaderIconButton(
          icon: Symbols.sync_rounded,
          tooltip: l10n.reExtract,
          onPressed: _extract,
        ),
      if (_pdfMode)
        ReaderIconButton(
          icon: Symbols.info_rounded,
          tooltip: l10n.documentInfo,
          onPressed: _showInfo,
        ),
      if (more.isNotEmpty)
        Builder(
          builder: (anchor) => ReaderIconButton(
            icon: Symbols.more_vert_rounded,
            tooltip: l10n.more,
            onPressed: () => _showMore(anchor, more),
          ),
        ),
    ];
    return SizedBox(
      height: 48,
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            ReaderIconButton(
              icon: Symbols.arrow_back_rounded,
              tooltip: l10n.back,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Text(
                widget.document.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            // 窄窗时操作区横向滚动，给标题至少留 96。
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (constraints.maxWidth - 48 - 96).clamp(
                  0,
                  double.infinity,
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(mainAxisSize: MainAxisSize.min, children: actions),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  void _showInfo() =>
      showDocumentInfoDialog(context: context, document: widget.document);

  Future<void> _showMore(
    BuildContext anchor,
    List<AppContextMenuItem<String>> items,
  ) async {
    final box = anchor.findRenderObject()! as RenderBox;
    final value = await showAppContextMenu(
      context: anchor,
      globalPosition: box.localToGlobal(Offset(0, box.size.height)),
      items: items,
    );
    if (value == null || !mounted) return;
    Haptics.soft();
    switch (value) {
      case 'info':
        _showInfo();
      case 'extract':
        _extract();
      case 'retranslate':
        ref.read(documentTranslationProvider(_id).notifier).retranslate();
      case 'summary':
        _generateSummary();
      case 'viewSummary':
        _showSummary();
    }
  }

  Widget _body(
    BuildContext context,
    ReaderPalette palette,
    ReaderSettingsState settings,
    bool extracting,
  ) {
    final theme = Theme.of(context);
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: palette.secondaryText,
          strokeWidth: 2,
        ),
      );
    }
    if (_pdfMode) {
      if (!_fileExists) return _message(context, context.l10n.pdfNotFound);
      return RustPdfView(
        documentId: _id,
        controller: _pdfSearch,
        initialProgress: _progress.value,
        matchColor: theme.colorScheme.primaryContainer.withAlpha(150),
        activeMatchColor: theme.colorScheme.primary.withAlpha(72),
        selectionColor: theme.colorScheme.primary.withAlpha(56),
        onCopy: _copyText,
        onPageChanged: (page, total) {
          final progress = total <= 1 ? 1.0 : (page - 1) / (total - 1);
          _progress.value = progress;
          unawaited(_history.setProgress(_id, progress));
        },
        errorBuilder: (context, error) =>
            _message(context, errorText(context.l10n, error)),
        pageLayer: (page, info) {
          final overlays = _pdfTranslationOverlays()[page];
          if (overlays == null) return null;
          return PdfTranslationLayer(
            pageWidth: info.width,
            pageHeight: info.height,
            overlays: overlays,
            rtl: isRtlTargetLanguage(
              ref.read(translationConfigProvider).targetLanguage,
            ),
          );
        },
      );
    }
    final controller = _controller;
    if (controller == null || !_hasModel) {
      return _message(
        context,
        _loadError == null
            ? context.l10n.extractResultEmpty
            : errorText(context.l10n, _loadError!),
        action: _fileExists && !extracting
            ? FilledButton.tonalIcon(
                onPressed: _extract,
                icon: const Icon(Symbols.document_scanner_rounded),
                label: Text(context.l10n.documentExtract),
              )
            : null,
      );
    }
    return Focus(
      focusNode: _bodyFocus,
      autofocus: true,
      child: ReaderSurface(
        key: _surface,
        controller: controller,
        fontSize: settings.fontSize,
        textStyle: TextStyle(
          color: palette.text,
          fontFamily: settings.font.fontFamily,
          fontFamilyFallback: settings.font.fontFamilyFallback,
        ),
        codeBackground: palette.codeBlock,
        translationStyle: ref.watch(
          translationConfigProvider.select((c) => c.displayStyleId),
        ),
        onTranslate: _showTranslation,
        onAskAi: (text, anchor, prompt) =>
            _openChat(quote: text, anchor: anchor, prompt: prompt),
        onCopy: _copyText,
        onFigureTap: (b) => _openFigure(b, FigureHeroSource.reader),
        onTapBlank: () => setState(() => _toolbars = !_toolbars),
        onLocationChanged: _onLocation,
      ),
    );
  }

  Widget _message(BuildContext context, String text, {Widget? action}) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 16), action],
          ],
        ),
      ),
    );
  }
}

class _SearchCount extends StatelessWidget {
  const _SearchCount({
    required this.current,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });

  final int current;
  final int total;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            '${total == 0 ? 0 : current + 1}/$total',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: total == 0 ? cs.error : cs.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Symbols.keyboard_arrow_up_rounded, size: 22),
          tooltip: context.l10n.previousResult,
          onPressed: total == 0 ? null : onPrevious,
        ),
        IconButton(
          icon: const Icon(Symbols.keyboard_arrow_down_rounded, size: 22),
          tooltip: context.l10n.nextResult,
          onPressed: total == 0 ? null : onNext,
        ),
      ],
    );
  }
}
