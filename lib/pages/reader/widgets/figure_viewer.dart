import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gal/gal.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:share_plus/share_plus.dart';

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

  static const _kCaptionStyle = TextStyle(
    color: Colors.white,
    fontSize: 15,
    height: 1.55,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
  );
  static const _kMinCaptionH = 60.0;

  double _captionHeight = 120.0;

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
    _currentIndex = widget.initialIndex;
    _pageController = ExtendedPageController(initialPage: _currentIndex);
    _doubleTapController = AnimationController(vsync: this, duration: kAnim);
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
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return ExtendedImageSlidePage(
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
                  Expanded(
                    child: Stack(
                      children: [
                        ExtendedImageGesturePageView.builder(
                          controller: _pageController,
                          itemCount: widget.figures.length,
                          canScrollPage: (details) =>
                              !_isZoomed &&
                              (details?.totalScale ?? 1.0) <= 1.01,
                          onPageChanged: (i) => setState(() {
                            _currentIndex = i;
                            _isZoomed = false;
                          }),
                          itemBuilder: (_, i) => _buildImage(widget.figures[i]),
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
                  // 无 caption 时不占底部栏（匿名 visualOnly / 空标题）
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
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
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
              onPressed: () {
                Haptics.soft();
                Navigator.of(context).pop();
              },
              tooltip: context.l10n.closeImage,
            ),
          ),
        ],
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
        fit: BoxFit.contain,
        mode: ExtendedImageMode.gesture,
        enableSlideOutPage: true,
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
      ),
    );
  }

  void _onGestureDetailsChanged(GestureDetails? details) {
    if (!_isGallery) return;
    final zoomed = (details?.totalScale ?? 1.0) > 1.01;
    if (zoomed == _isZoomed) return;
    setState(() => _isZoomed = zoomed);
  }

  Future<void> _showSaveMenu(
    FigureManifestEntry fig,
    Offset globalPosition,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      color: const Color(0xFF2C2C2E),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        overlay.size.width - globalPosition.dx,
        overlay.size.height - globalPosition.dy,
      ),
      items: [
        if (isDesktopOs)
          PopupMenuItem<String>(
            value: 'copy',
            height: 40,
            child: Row(
              children: [
                const Icon(
                  Symbols.content_copy_rounded,
                  size: 18,
                  color: Colors.white70,
                ),
                const SizedBox(width: 12),
                Text(
                  context.l10n.copyImage,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          )
        else
          PopupMenuItem<String>(
            value: 'share',
            height: 40,
            child: Row(
              children: [
                const Icon(
                  Symbols.share_rounded,
                  size: 18,
                  color: Colors.white70,
                ),
                const SizedBox(width: 12),
                Text(
                  context.l10n.shareImage,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'save',
          height: 40,
          child: Row(
            children: [
              const Icon(
                Symbols.download_rounded,
                size: 18,
                color: Colors.white70,
              ),
              const SizedBox(width: 12),
              Text(
                context.l10n.saveImage,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
    if (selected == 'copy') await _copyFigure(fig);
    if (selected == 'share') await _shareFigure(fig);
    if (selected == 'save') await _saveFigure(fig);
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
      await Share.shareXFiles([XFile(fig.imagePath)], subject: fileName);
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
        if (await target.exists()) await target.delete();
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
        child: GestureDetector(
          onTap: () {
            Haptics.soft();
            onTap();
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Color(0x59000000),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isLeft
                  ? Symbols.chevron_left_rounded
                  : Symbols.chevron_right_rounded,
              color: Colors.white70,
              size: 28,
            ),
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
            height: _captionHeight.clamp(_kMinCaptionH, maxH),
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 16, bottomPadding + 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SelectionArea(
                      child: SingleChildScrollView(
                        child: Text(displayText, style: _kCaptionStyle),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    children: [
                      if (widget.document != null) _buildAskAiButton(fig),
                      if (widget.document != null) const SizedBox(height: 8),
                      _buildTranslateButton(idx, fig, isTranslated),
                    ],
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
          backgroundColor: const Color(0x1AFFFFFF),
          foregroundColor: Colors.white60,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
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
            ? const Padding(
                padding: EdgeInsets.all(8),
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
                      ? const Color(0x33FFFFFF)
                      : const Color(0x1AFFFFFF),
                  foregroundColor: Colors.white60,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
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
