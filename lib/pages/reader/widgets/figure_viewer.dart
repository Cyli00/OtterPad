import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:extended_image/extended_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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
/// 使用半透明压暗背景，保留底层阅读界面，不做截图或模糊。
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

  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: kAnimSlow,
      reverseTransitionDuration: kAnim,
      pageBuilder: (_, _, _) => FigureViewer(
        figures: figures,
        initialIndex: initialIndex,
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
  final String? documentId;
  final Document? document;
  final LocateQuoteInReader? onLocateQuote;
  final void Function(DocumentChatPageArgs args)? onOpenChat;

  const FigureViewer({
    super.key,
    required this.figures,
    this.initialIndex = 0,
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
  bool _showData = false;
  int _imageRevision = 0;
  TableParseService? _tableSource;
  bool _loadingData = false;
  bool _dataError = false;
  bool _exporting = false;
  final Map<int, FigureParsedData> _parsedData = {};

  FigureManifestEntry get _figure => widget.figures[_currentIndex];
  FigureParsedData get _data =>
      _parsedData.putIfAbsent(_currentIndex, () => _dataFor(_figure));

  FigureParsedData _dataFor(FigureManifestEntry figure) =>
      figure.kind == 'table'
      ? _tableSource?.forFigure(figure) ?? const FigureParsedData()
      : const FigureParsedData();

  Future<void> _loadData() async {
    final id = widget.documentId ?? widget.document?.id;
    if (id == null || !widget.figures.any((fig) => fig.kind == 'table')) return;
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
                // ── 背景：仅压暗底层阅读界面 ──
                Positioned.fill(child: _buildBackground()),
                // ── 主体内容 ──
                SafeArea(bottom: false, child: _buildContent(bottomPadding)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackground() => const ColoredBox(color: Color(0x66000000));

  Widget _buildContent(double bottomPadding) {
    final hasCaption = _figure.captionText.trim().isNotEmpty;
    return Column(
      children: [
        _buildTopBar(),
        Expanded(child: _buildGallery()),
        if (hasCaption) ...[
          const SizedBox(height: 8),
          _buildCaptionPanel(bottomPadding),
        ] else
          SizedBox(height: bottomPadding + 8),
      ],
    );
  }

  Widget _buildGallery() {
    return Stack(
      key: const ValueKey('figure-gallery'),
      children: [
        ExtendedImageGesturePageView.builder(
          controller: _pageController,
          itemCount: widget.figures.length,
          canScrollPage: (details) =>
              !_isZoomed && (details?.totalScale ?? 1.0) <= 1.01,
          onPageChanged: (i) {
            _doubleTapController.stop();
            setState(() {
              _currentIndex = i;
              _isZoomed = false;
              _showData = false;
              _imageRevision++;
            });
          },
          itemBuilder: (_, i) => _buildImage(widget.figures[i]),
        ),
        if (_showData && _figure.kind == 'table')
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: _isGallery ? 52 : 12,
                vertical: 8,
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapDown: (details) =>
                    _showSaveMenu(_figure, details.globalPosition),
                onLongPressStart: (details) =>
                    _showSaveMenu(_figure, details.globalPosition),
                child: Material(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: .96),
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: _buildDataLayer(),
                ),
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
        if (_isGallery && _currentIndex < widget.figures.length - 1)
          _buildArrow(
            false,
            () => _pageController.nextPage(
              duration: kAnimSlow,
              curve: Curves.easeInOut,
            ),
          ),
      ],
    );
  }

  Widget _buildTopBar() {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 48),
          if (_isGallery)
            Expanded(
              child: Center(
                child: Text(
                  '${_currentIndex + 1} / ${widget.figures.length}',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: Colors.white70),
                ),
              ),
            )
          else
            const Spacer(),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              icon: const Icon(Symbols.close_rounded, fill: 1),
              color: Colors.white70,
              tooltip: context.l10n.closeImage,
              onPressed: () {
                Haptics.soft();
                Navigator.of(context).maybePop();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataLayer() {
    final l10n = context.l10n;
    if (_loadingData) return const Center(child: CircularProgressIndicator());
    if (_data.hasData) {
      final figure = _figure;
      return FigureDataOverlay(
        data: _data,
        onContextMenu: (position) => _showSaveMenu(figure, position),
      );
    }
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
    if (_exporting) return;
    final l10n = context.l10n;
    final data = _dataFor(fig);
    final selected = await showAppContextMenu<String>(
      context: context,
      globalPosition: globalPosition,
      items: [
        if (fig.kind == 'table')
          AppContextMenuItem(
            value: 'overlay',
            label: _showData ? l10n.original : l10n.figureDataLayer,
            icon: _showData
                ? Symbols.image_rounded
                : Symbols.table_view_rounded,
          ),
        if (!_showData)
          AppContextMenuItem(
            value: 'fit',
            label: l10n.figureFitImage,
            icon: Symbols.fit_screen_rounded,
          ),
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
        if (data.canCopyTsv)
          AppContextMenuItem(
            value: 'tsv',
            label: l10n.tableCopyTsv,
            icon: Symbols.table_view_rounded,
          ),
        if (data.hasData) ...[
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
          if (data.canCopyTsv)
            AppContextMenuItem(
              value: 'exportTsv',
              label: l10n.figureExportTsv,
              icon: Symbols.download_rounded,
            ),
          AppContextMenuItem(
            value: 'exportMarkdown',
            label: l10n.figureExportMarkdown,
            icon: Symbols.download_rounded,
          ),
        ],
      ],
    );
    if (mounted && selected != null) await _performAction(selected, fig);
  }

  Future<void> _performAction(String action, FigureManifestEntry fig) async {
    if (_exporting) return;
    final data = _dataFor(fig);
    switch (action) {
      case 'overlay':
        if (fig.kind == 'table' && identical(fig, _figure)) {
          setState(() => _showData = !_showData);
        }
      case 'fit':
        _resetZoom();
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

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 拖拽指示条 ──
          GestureDetector(
            onVerticalDragUpdate: (d) {
              setState(() {
                _captionHeight = (_captionHeight - d.delta.dy).clamp(
                  _kMinCaptionH,
                  maxH,
                );
              });
            },
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0x50FFFFFF),
                    borderRadius: BorderRadius.all(Radius.circular(2)),
                  ),
                  child: SizedBox(width: 32, height: 4),
                ),
              ),
            ),
          ),
          // ── 文本 + 翻译按钮 ──
          SizedBox(
            height: _captionHeight.clamp(_kMinCaptionH, maxH) + bottomPadding,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 16, bottomPadding + 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SelectionArea(
                      child: SingleChildScrollView(
                        child: Text(
                          displayText,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.white70, height: 1.6),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SingleChildScrollView(
                    child: Column(
                      children: [
                        if (widget.document != null) _buildAskAiButton(fig),
                        if (widget.document != null) const SizedBox(height: 8),
                        _buildTranslateButton(idx, fig, isTranslated),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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
          backgroundColor: Colors.white10,
          foregroundColor: Colors.white60,
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
                  color: Colors.white60,
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
                      ? Colors.white24
                      : Colors.white10,
                  foregroundColor: Colors.white60,
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
