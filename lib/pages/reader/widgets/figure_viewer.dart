import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gal/gal.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;

import '../../../core/animation_constants.dart';
import '../../../data/models/book/document.dart';
import '../../../providers/agent_api_provider.dart';
import '../../../providers/document_translation_provider.dart';
import '../../../router/app_routes.dart';
import '../chat/document_chat_page.dart';
import '../../../services/haptics.dart';
import '../../../providers/translation_config_provider.dart';
import '../../../services/ai_settings_prompt.dart';
import '../../../services/document_translation_service.dart';
import '../../../services/figure_extract_service.dart';
import '../../../services/markdown_paragraph_extractor.dart';
import '../../../services/snackbar_service.dart';
import '../../../core/l10n.dart';
import '../../../services/translation_service.dart';
import '../../../utils/desktop.dart';
import '../../../utils/doc_paths.dart';
import '../../../services/table_parse_service.dart';
import '../../../widgets/app_context_menu.dart';
import 'table_parse_sheet.dart';

/// 以 fade 转场打开 [FigureViewer]。
///
/// 打开前自动截取当前屏幕的超低分辨率缩略图作为模糊背景。
///
/// [figures] 由调用方决定范围：
///  - Outline / 正文可展示图：传 [FigureManifestEntry.forDisplay] 过滤后的列表；
///  - 旧稿残留的匿名 visual：以 singleton 打开，不混入有标题画廊。
/// Viewer 组件本身不区分匿名与否，仅消费传入的列表范围。
Future<void> showFigureViewer(
  BuildContext context,
  List<FigureManifestEntry> figures, {
  int initialIndex = 0,
  String? documentId,
  Document? document,
  LocateQuoteInReader? onLocateQuote,
  void Function(DocumentChatPageArgs args)? onOpenChat,
}) async {
  if (figures.isEmpty) return;

  // 截取背景：找到最外层 RepaintBoundary（阅读器全屏画面）
  Uint8List? bgSnapshot;
  RenderRepaintBoundary? boundary;
  RenderObject? ro = context.findRenderObject();
  while (ro != null) {
    if (ro is RenderRepaintBoundary) boundary = ro;
    ro = ro.parent;
  }
  if (boundary != null && boundary.hasSize) {
    try {
      const targetLongSide = 64.0;
      final ratio = targetLongSide / boundary.size.longestSide;
      final image = await boundary.toImage(pixelRatio: ratio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      bgSnapshot = bytes?.buffer.asUint8List();
    } catch (_) {}
  }

  if (!context.mounted) return;

  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: kAnimSlow,
      reverseTransitionDuration: kAnim,
      pageBuilder: (_, _, _) => FigureViewer(
        figures: figures,
        initialIndex: initialIndex,
        backgroundSnapshot: bgSnapshot,
        documentId: documentId,
        document: document,
        onLocateQuote: onLocateQuote,
        onOpenChat: onOpenChat,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// Figure 全屏查看器：左右切换 + 缩放 + Hero 下滑退出。
class FigureViewer extends ConsumerStatefulWidget {
  final List<FigureManifestEntry> figures;
  final int initialIndex;
  final Uint8List? backgroundSnapshot;
  final String? documentId;
  final Document? document;
  final LocateQuoteInReader? onLocateQuote;
  final void Function(DocumentChatPageArgs args)? onOpenChat;

  const FigureViewer({
    super.key,
    required this.figures,
    this.initialIndex = 0,
    this.backgroundSnapshot,
    this.documentId,
    this.document,
    this.onLocateQuote,
    this.onOpenChat,
  });

  @override
  ConsumerState<FigureViewer> createState() => _FigureViewerState();
}

class _FigureViewerState extends ConsumerState<FigureViewer>
    with TickerProviderStateMixin {
  late int _currentIndex;
  late final ExtendedPageController _pageController;
  late final AnimationController _doubleTapController;
  Animation<double>? _doubleTapAnim;
  VoidCallback? _doubleTapCb;

  bool get _isGallery => widget.figures.length > 1;

  static const _kMinCaptionH = 60.0;

  double _captionHeight = 120.0;
  bool _captionExpanded = true;
  bool _showData = false;
  double _dataOpacity = .96;
  int _imageRevision = 0;
  TableParseService? _tableSource;
  bool _loadingData = false;
  bool _dataError = false;
  bool _exporting = false;
  final Map<int, FigureParsedData> _parsedData = {};

  FigureManifestEntry get _figure => widget.figures[_currentIndex];
  FigureParsedData get _data => _parsedData.putIfAbsent(
    _currentIndex,
    () => _tableSource?.forFigure(_figure) ?? const FigureParsedData(),
  );

  Future<void> _loadData() async {
    final id = widget.documentId ?? widget.document?.id;
    if (id == null) return;
    setState(() {
      _loadingData = true;
      _dataError = false;
    });
    try {
      final source = await TableParseService.read(DocPaths.json(id));
      if (!mounted) return;
      setState(() {
        _tableSource = source;
        _parsedData.clear();
      });
    } catch (_) {
      if (mounted) setState(() => _dataError = true);
    } finally {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  void _changePage(int delta) {
    final index = _currentIndex + delta;
    if (index < 0 || index >= widget.figures.length) return;
    _pageController.animateToPage(index, duration: kAnim, curve: kAnimCurve);
  }

  void _resetZoom() {
    _doubleTapController.stop();
    setState(() {
      _imageRevision++;
      _isZoomed = false;
    });
  }

  /// 放大后禁用 PageView 水平翻页，避免与图片平移手势竞争。
  bool _isZoomed = false;

  // ── 翻译状态（per-figure）──
  /// figureIndex → 翻译结果
  final Map<int, String> _translations = {};

  /// figureIndex → 是否正在请求
  final Map<int, bool> _translating = {};

  /// figureIndex → 当前是否显示译文（false = 原文）
  final Map<int, bool> _showTranslation = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.figures.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.figures.length - 1);
    _pageController = ExtendedPageController(initialPage: _currentIndex);
    _doubleTapController = AnimationController(vsync: this, duration: kAnim);
    _loadData();
  }

  @override
  void dispose() {
    _doubleTapAnim?.removeListener(_doubleTapCb ?? () {});
    _doubleTapController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _handleDoubleTap(ExtendedImageGestureState state) {
    final pos = state.pointerDownPosition;
    final details = state.gestureDetails;
    if (pos == null || details == null) return;

    final cur = details.totalScale ?? 1.0;
    final target = (cur - 1.0).abs() > 0.1 ? 1.0 : 2.5;

    _doubleTapAnim?.removeListener(_doubleTapCb ?? () {});
    _doubleTapController
      ..stop()
      ..reset();

    _doubleTapCb = () => state.handleDoubleTap(
      scale: _doubleTapAnim!.value,
      doubleTapPosition: pos,
    );

    _doubleTapAnim = _doubleTapController.drive(
      Tween(
        begin: cur,
        end: target,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
    )..addListener(_doubleTapCb!);

    _doubleTapController.forward();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.figures.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          leading: CloseButton(
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: Center(child: Text(context.l10n.imageNotFound)),
      );
    }
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
        if (!_showData) ...{
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              _changePage(-1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              _changePage(1),
        },
      },
      child: Focus(
        autofocus: true,
        child: ExtendedImageSlidePage(
          slideAxis: SlideAxis.vertical,
          slideType: SlideType.onlyImage,
          slidePageBackgroundHandler: (_, _) => Colors.transparent,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                // ── 背景：低分辨率截图 + 暗色蒙版 ──
                Positioned.fill(child: _buildBackground()),
                // ── 主体内容 ──
                SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      _buildTopBar(),
                      _buildActionBar(),
                      Expanded(
                        child: Stack(
                          children: [
                            ExtendedImageGesturePageView.builder(
                              controller: _pageController,
                              itemCount: widget.figures.length,
                              canScrollPage: (details) =>
                                  !_isZoomed &&
                                  (details?.totalScale ?? 1.0) <= 1.01,
                              onPageChanged: (i) {
                                _doubleTapController.stop();
                                setState(() {
                                  _currentIndex = i;
                                  _isZoomed = false;
                                  _showData = false;
                                  _imageRevision++;
                                });
                              },
                              itemBuilder: (_, i) =>
                                  _buildImage(widget.figures[i]),
                            ),
                            if (_showData)
                              Positioned.fill(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: _isGallery ? 52 : 12,
                                    vertical: 8,
                                  ),
                                  child: Material(
                                    color: Theme.of(context).colorScheme.surface
                                        .withValues(alpha: _dataOpacity),
                                    borderRadius: BorderRadius.circular(16),
                                    clipBehavior: Clip.antiAlias,
                                    child: _buildDataLayer(),
                                  ),
                                ),
                              ),
                            if (_isGallery && _currentIndex > 0)
                              _buildArrow(
                                true,
                                () => _pageController.previousPage(
                                  duration: kAnimSlow,
                                  curve: Curves.easeInOut,
                                ),
                              ),
                            if (_isGallery &&
                                _currentIndex < widget.figures.length - 1)
                              _buildArrow(
                                false,
                                () => _pageController.nextPage(
                                  duration: kAnimSlow,
                                  curve: Curves.easeInOut,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (widget.figures[_currentIndex].captionText
                          .trim()
                          .isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildCaptionPanel(bottomPadding),
                      ] else
                        SizedBox(height: bottomPadding + 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackground() {
    final snapshot = widget.backgroundSnapshot;
    if (snapshot == null) {
      return const ColoredBox(color: Color(0xF0000000));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(
          snapshot,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
        ),
        const ColoredBox(color: Color(0xB3000000)),
      ],
    );
  }

  Widget _buildTopBar() {
    final theme = Theme.of(context), cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.figureFallback(
                  _figure.kind ?? 'figure',
                  _figure.pageIndex + 1,
                ),
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_isGallery)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '${_currentIndex + 1} / ${widget.figures.length}',
                  style: theme.textTheme.labelMedium,
                ),
              ),
            IconButton(
              icon: const Icon(Symbols.close_rounded),
              tooltip: context.l10n.closeImage,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    final l10n = context.l10n, cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainer,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            if (_figure.kind == 'table' ||
                _figure.kind == 'chart' ||
                _data.hasData)
              TextButton.icon(
                onPressed: () => setState(() => _showData = !_showData),
                icon: Icon(
                  _showData
                      ? Symbols.image_rounded
                      : Symbols.table_view_rounded,
                ),
                label: Text(_showData ? l10n.original : l10n.figureDataLayer),
              ),
            if (!_showData)
              IconButton(
                onPressed: _resetZoom,
                tooltip: l10n.figureFitImage,
                icon: const Icon(Symbols.fit_screen_rounded),
              ),
            if (_showData && _data.hasData)
              Tooltip(
                message: l10n.figureOverlayOpacity,
                child: SizedBox(
                  width: 120,
                  child: Slider(
                    value: _dataOpacity,
                    min: .35,
                    max: 1,
                    label: '${(_dataOpacity * 100).round()}%',
                    semanticFormatterCallback: (v) =>
                        '${l10n.figureOverlayOpacity} ${(v * 100).round()}%',
                    onChanged: (value) => setState(() => _dataOpacity = value),
                  ),
                ),
              ),
            PopupMenuButton<String>(
              tooltip: l10n.copy,
              onSelected: (action) => _performAction(action, _figure),
              itemBuilder: (_) => [
                if (!Platform.isLinux)
                  PopupMenuItem(value: 'copy', child: Text(l10n.copyImage)),
                PopupMenuItem(
                  value: 'caption',
                  enabled: _figure.captionText.trim().isNotEmpty,
                  child: Text(l10n.figureCopyCaption),
                ),
                PopupMenuItem(
                  value: 'tsv',
                  enabled: _data.canCopyTsv,
                  child: Text(l10n.tableCopyTsv),
                ),
                PopupMenuItem(
                  value: 'markdown',
                  enabled: _data.hasData,
                  child: Text(l10n.tableCopyMarkdown),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Symbols.content_copy_rounded, size: 20),
                    const SizedBox(width: 6),
                    Text(l10n.copy),
                  ],
                ),
              ),
            ),
            PopupMenuButton<String>(
              enabled: !_exporting,
              tooltip: l10n.figureExport,
              onSelected: (action) => _performAction(action, _figure),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'save', child: Text(l10n.saveImage)),
                PopupMenuItem(value: 'share', child: Text(l10n.shareImage)),
                PopupMenuItem(
                  value: 'html',
                  enabled: _data.hasData,
                  child: Text(l10n.figureExportHtml),
                ),
                PopupMenuItem(
                  value: 'exportTsv',
                  enabled: _data.canCopyTsv,
                  child: Text(l10n.figureExportTsv),
                ),
                PopupMenuItem(
                  value: 'exportMarkdown',
                  enabled: _data.hasData,
                  child: Text(l10n.figureExportMarkdown),
                ),
              ],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    if (_exporting)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(Symbols.download_rounded, size: 20),
                    const SizedBox(width: 6),
                    Text(l10n.figureExport),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataLayer() {
    final l10n = context.l10n;
    if (_loadingData) return const Center(child: CircularProgressIndicator());
    if (_data.hasData) return FigureDataOverlay(data: _data);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Symbols.table_view_rounded, size: 32),
            const SizedBox(height: 12),
            Text(
              _dataError
                  ? l10n.figureDataLoadFailed
                  : _data.stale
                  ? l10n.figureDataStale
                  : l10n.figureDataUnavailable,
              textAlign: TextAlign.center,
            ),
            if (_dataError)
              TextButton(onPressed: _loadData, child: Text(l10n.retry)),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(FigureManifestEntry fig) {
    // 外层 GestureDetector 只监听 long-press 和右键，不会劫持 pan/scale/double-tap
    // ——这些继续由内部的 ExtendedImage 手势系统处理。
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: (details) {
        Haptics.medium();
        _showSaveMenu(fig, details.globalPosition);
      },
      onSecondaryTapDown: (details) =>
          _showSaveMenu(fig, details.globalPosition),
      child: ExtendedImage.file(
        File(fig.imagePath),
        key: ValueKey('${fig.imagePath}:$_imageRevision'),
        fit: BoxFit.contain,
        mode: ExtendedImageMode.gesture,
        enableSlideOutPage: !_showData && !_isZoomed,
        heroBuilderForSlidingPage: (child) =>
            Hero(tag: 'figure_${fig.imagePath}', child: child),
        initGestureConfigHandler: (_) => GestureConfig(
          minScale: 0.9,
          animationMinScale: 0.7,
          maxScale: 5.0,
          animationMaxScale: 5.5,
          speed: 1.0,
          inertialSpeed: 500.0,
          initialScale: 1.0,
          inPageView: _isGallery && !_isZoomed,
          gestureDetailsIsChanged: _onGestureDetailsChanged,
        ),
        onDoubleTap: _handleDoubleTap,
        loadStateChanged: (state) =>
            state.extendedImageLoadState == LoadState.failed
            ? Center(
                child: Text(
                  context.l10n.imageNotFound,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.white),
                ),
              )
            : null,
      ),
    );
  }

  void _onGestureDetailsChanged(GestureDetails? details) {
    final zoomed = (details?.totalScale ?? 1.0) > 1.01;
    if (zoomed == _isZoomed) return;
    setState(() => _isZoomed = zoomed);
  }

  Future<void> _showSaveMenu(
    FigureManifestEntry fig,
    Offset globalPosition,
  ) async {
    final l10n = context.l10n;
    final selected = await showAppContextMenu<String>(
      context: context,
      globalPosition: globalPosition,
      items: [
        if (!Platform.isLinux)
          AppContextMenuItem(
            value: 'copy',
            label: l10n.copyImage,
            icon: Symbols.content_copy_rounded,
          ),
        AppContextMenuItem(
          value: 'share',
          label: l10n.shareImage,
          icon: Symbols.share_rounded,
        ),
        AppContextMenuItem(
          value: 'save',
          label: l10n.saveImage,
          icon: Symbols.download_rounded,
        ),
        if (fig.captionText.trim().isNotEmpty)
          AppContextMenuItem(
            value: 'caption',
            label: l10n.figureCopyCaption,
            icon: Symbols.title_rounded,
          ),
        if (_data.canCopyTsv)
          AppContextMenuItem(
            value: 'tsv',
            label: l10n.tableCopyTsv,
            icon: Symbols.table_view_rounded,
          ),
        if (_data.hasData) ...[
          AppContextMenuItem(
            value: 'markdown',
            label: l10n.tableCopyMarkdown,
            icon: Symbols.content_copy_rounded,
          ),
          AppContextMenuItem(
            value: 'html',
            label: l10n.figureExportHtml,
            icon: Symbols.download_rounded,
          ),
        ],
      ],
    );
    if (mounted && selected != null) await _performAction(selected, fig);
  }

  Future<void> _performAction(String action, FigureManifestEntry fig) async {
    if (_exporting) return;
    final data = _tableSource?.forFigure(fig) ?? const FigureParsedData();
    switch (action) {
      case 'copy':
        await _copyFigure(fig);
      case 'share':
        await _shareFigure(fig);
      case 'save':
        await _saveFigure(fig);
      case 'caption' || 'tsv' || 'markdown':
        final text = action == 'caption'
            ? fig.captionText
            : action == 'tsv'
            ? data.tsv
            : data.markdown;
        if (text.isEmpty) return;
        try {
          await Clipboard.setData(ClipboardData(text: text));
          if (mounted) {
            ref
                .read(snackBarServiceProvider)
                .showResult(message: context.l10n.copiedToClipboard);
          }
        } catch (e) {
          if (mounted) {
            ref
                .read(snackBarServiceProvider)
                .showResult(message: context.l10n.copyFailed('$e'));
          }
        }
      case 'html' || 'exportTsv' || 'exportMarkdown':
        if (data.hasData) await _exportData(fig, data, action);
    }
  }

  Future<void> _exportData(
    FigureManifestEntry fig,
    FigureParsedData data,
    String format,
  ) async {
    final l10n = context.l10n;
    final extension = format == 'html'
        ? 'html'
        : format == 'exportTsv'
        ? 'tsv'
        : 'md';
    final content = format == 'html'
        ? data.htmlDocument(fig.captionText)
        : format == 'exportTsv'
        ? data.tsv
        : '${fig.captionText}\n\n${data.markdown}';
    final name = '${p.basenameWithoutExtension(fig.imagePath)}.$extension';
    final bytes = Uint8List.fromList(utf8.encode(content));
    setState(() => _exporting = true);
    try {
      if (isDesktopOs) {
        final path = await FilePicker.platform.saveFile(
          dialogTitle: l10n.figureExport,
          fileName: name,
          type: FileType.custom,
          allowedExtensions: [extension],
          lockParentWindow: true,
        );
        if (path == null) return;
        await File(path).writeAsBytes(bytes, flush: true);
        if (mounted) {
          ref
              .read(snackBarServiceProvider)
              .showResult(message: l10n.savedToPath(path));
        }
      } else {
        final box = context.findRenderObject() as RenderBox?;
        await Share.shareXFiles(
          [
            XFile.fromData(
              bytes,
              name: name,
              mimeType: switch (extension) {
                'html' => 'text/html',
                'tsv' => 'text/tab-separated-values',
                _ => 'text/markdown',
              },
            ),
          ],
          fileNameOverrides: [name],
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        );
      }
    } catch (e) {
      if (mounted) {
        ref
            .read(snackBarServiceProvider)
            .showResult(message: l10n.exportFailed('$e'));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _copyFigure(FigureManifestEntry fig) async {
    final snackBar = ref.read(snackBarServiceProvider);
    final source = File(fig.imagePath);
    if (!await source.exists()) {
      if (!mounted) return;
      snackBar.showResult(message: context.l10n.imageNotFound);
      return;
    }
    try {
      final bytes = await source.readAsBytes();
      await Pasteboard.writeImage(bytes);
      if (!mounted) return;
      snackBar.showResult(message: context.l10n.copiedToClipboard);
    } catch (e) {
      if (!mounted) return;
      snackBar.showResult(message: context.l10n.copyFailed('$e'));
    }
  }

  Future<void> _shareFigure(FigureManifestEntry fig) async {
    final snackBar = ref.read(snackBarServiceProvider);
    final source = File(fig.imagePath);
    if (!await source.exists()) {
      if (!mounted) return;
      snackBar.showResult(message: context.l10n.imageNotFound);
      return;
    }
    final fileName = fig.imagePath.split(RegExp(r'[/\\]')).last;
    try {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [XFile(fig.imagePath)],
        subject: fileName,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (e) {
      if (!mounted) return;
      snackBar.showResult(message: context.l10n.shareFailed('$e'));
    }
  }

  Future<void> _saveFigure(FigureManifestEntry fig) async {
    final snackBar = ref.read(snackBarServiceProvider);
    final source = File(fig.imagePath);
    if (!await source.exists()) {
      if (!mounted) return;
      snackBar.showResult(message: context.l10n.imageNotFound);
      return;
    }
    final fileName = fig.imagePath.split(RegExp(r'[/\\]')).last;

    try {
      if (isDesktopOs) {
        if (!mounted) return;
        final targetPath = await FilePicker.platform.saveFile(
          dialogTitle: context.l10n.saveImageTitle,
          fileName: fileName,
          type: FileType.image,
          lockParentWindow: true,
        );
        if (targetPath == null) return;
        final target = File(targetPath);
        if (p.equals(source.absolute.path, target.absolute.path)) return;
        await source.copy(target.path);
        if (!mounted) return;
        snackBar.showResult(message: context.l10n.savedToPath(target.path));
      } else if (Platform.isAndroid || Platform.isIOS) {
        if (!await Gal.hasAccess()) {
          await Gal.requestAccess();
          if (!await Gal.hasAccess()) {
            if (!mounted) return;
            snackBar.showResult(message: context.l10n.galleryAccessDenied);
            return;
          }
        }
        await Gal.putImage(fig.imagePath);
        if (!mounted) return;
        snackBar.showResult(message: context.l10n.savedToGallery);
      }
    } on GalException catch (e) {
      if (!mounted) return;
      final message = e.type == GalExceptionType.accessDenied
          ? context.l10n.galleryAccessDenied
          : context.l10n.saveFailed(e.type.message);
      snackBar.showResult(message: message);
    } catch (e) {
      if (!mounted) return;
      snackBar.showResult(message: context.l10n.saveFailed('$e'));
    }
  }

  Widget _buildArrow(bool isLeft, VoidCallback onTap) {
    return Positioned(
      left: isLeft ? 8 : null,
      right: isLeft ? null : 8,
      top: 0,
      bottom: 0,
      child: Center(
        child: IconButton.filledTonal(
          tooltip: isLeft
              ? context.l10n.figurePrevious
              : context.l10n.figureNext,
          onPressed: () {
            Haptics.soft();
            onTap();
          },
          icon: Icon(
            isLeft
                ? Symbols.chevron_left_rounded
                : Symbols.chevron_right_rounded,
          ),
        ),
      ),
    );
  }

  Widget _buildCaptionPanel(double bottomPadding) {
    final idx = _currentIndex;
    final fig = widget.figures[idx];
    final isTranslated =
        _showTranslation[idx] == true && _translations.containsKey(idx);
    final displayText = isTranslated ? _translations[idx]! : fig.captionText;
    final maxH = math.max(_kMinCaptionH, MediaQuery.sizeOf(context).height / 4);

    final theme = Theme.of(context), cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (d) => setState(() {
                _captionExpanded = true;
                _captionHeight = (_captionHeight - d.delta.dy).clamp(
                  _kMinCaptionH,
                  maxH,
                );
              }),
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l10n.figureCaption,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (widget.document != null) _buildAskAiButton(fig),
                    _buildTranslateButton(idx, fig, isTranslated),
                    IconButton(
                      tooltip: _captionExpanded
                          ? context.l10n.figureHideCaption
                          : context.l10n.figureShowCaption,
                      onPressed: () =>
                          setState(() => _captionExpanded = !_captionExpanded),
                      icon: Icon(
                        _captionExpanded
                            ? Symbols.expand_more_rounded
                            : Symbols.expand_less_rounded,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_captionExpanded)
              SizedBox(
                height: _captionHeight.clamp(_kMinCaptionH, maxH),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SelectionArea(
                    child: SingleChildScrollView(
                      child: Align(
                        alignment: AlignmentDirectional.topStart,
                        child: Text(
                          displayText,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.55,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAskAiButton(FigureManifestEntry fig) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        icon: const Icon(Symbols.auto_awesome_rounded, size: 18, fill: 1),
        style: IconButton.styleFrom(
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest,
          foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: EdgeInsets.zero,
        ),
        tooltip: context.l10n.askAi,
        onPressed: () => _openAskAi(fig),
      ),
    );
  }

  void _openAskAi(FigureManifestEntry fig) {
    final document = widget.document;
    if (document == null) return;
    final quote = fig.captionText.trim();
    if (quote.isEmpty) return;
    Haptics.soft();

    final args = DocumentChatPageArgs(
      document: document,
      initialQuote: quote,
      figureImagePath: fig.imagePath,
      onLocateQuote: widget.onLocateQuote,
    );

    final onOpenChat = widget.onOpenChat;
    final router = GoRouter.of(context);
    Navigator.of(context, rootNavigator: true).pop();
    if (onOpenChat != null) {
      onOpenChat(args);
    } else {
      router.push(AppRoutes.readerChat, extra: args);
    }
  }

  Widget _buildTranslateButton(
    int idx,
    FigureManifestEntry fig,
    bool isTranslated,
  ) {
    final isLoading = _translating[idx] == true;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: SizedBox(
        width: 36,
        height: 36,
        child: isLoading
            ? Padding(
                padding: const EdgeInsets.all(8),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              )
            : IconButton(
                icon: Icon(
                  isTranslated
                      ? Symbols.title_rounded
                      : Symbols.translate_rounded,
                  size: 18,
                  fill: 1,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: isTranslated
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  foregroundColor: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: EdgeInsets.zero,
                ),
                tooltip: _translations.containsKey(idx)
                    ? (isTranslated
                          ? context.l10n.showOriginal
                          : context.l10n.showTranslation)
                    : context.l10n.translateText,
                onPressed: () {
                  Haptics.soft();
                  _handleTranslate(idx, fig);
                },
              ),
      ),
    );
  }

  Future<void> _handleTranslate(int idx, FigureManifestEntry fig) async {
    if (fig.captionText.trim().isEmpty) return;

    // 已有翻译：切换显示
    if (_translations.containsKey(idx)) {
      setState(() => _showTranslation[idx] = !(_showTranslation[idx] ?? false));
      return;
    }

    final translationConfig = ref.read(translationConfigProvider);
    final docId = widget.documentId;
    final hash = MarkdownParagraphExtractor.computeHash(fig.captionText);

    // 优先查 translations.json 共享缓存
    if (docId != null) {
      final cached = DocumentTranslationService.loadTranslations(
        docId,
        translationConfig.targetLanguage,
      )[hash];
      if (cached != null && cached.isNotEmpty) {
        ref
            .read(documentTranslationProvider(docId).notifier)
            .acceptFigureTranslation(
              hash,
              cached,
              translationConfig.targetLanguage,
            );
        setState(() {
          _translations[idx] = cached;
          _showTranslation[idx] = true;
        });
        return;
      }
    }

    final agentState = ref.read(effectiveAgentApiProvider);
    if (!await AiSettingsPrompt.ensureTextModelConfigured(
      context: context,
      agentState: agentState,
    )) {
      return;
    }

    setState(() => _translating[idx] = true);

    try {
      final result = await TranslationService.translate(
        text: fig.captionText,
        agentState: agentState,
        translationConfig: translationConfig,
      );

      // 写回 translations.json 共享缓存
      if (docId != null && result.isNotEmpty) {
        await DocumentTranslationService.saveSingleTranslation(
          docId,
          translationConfig.targetLanguage,
          hash,
          result,
        );
        if (!mounted) return;
        ref
            .read(documentTranslationProvider(docId).notifier)
            .acceptFigureTranslation(
              hash,
              result,
              translationConfig.targetLanguage,
            );
      }

      if (!mounted) return;
      setState(() {
        _translations[idx] = result;
        _showTranslation[idx] = true;
        _translating[idx] = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _translating[idx] = false);
      if (await AiSettingsPrompt.showForConfigError(
        context: context,
        error: e,
      )) {
        return;
      }
      ref
          .read(snackBarServiceProvider)
          .showResult(message: '$e'.replaceFirst('Exception: ', ''));
    }
  }
}
