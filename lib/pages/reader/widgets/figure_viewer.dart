import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/animation_constants.dart';
import '../../../providers/api_provider.dart';
import '../../../services/haptics.dart';
import '../../../providers/translation_config_provider.dart';
import '../../../router/app_router.dart';
import '../../../router/app_routes.dart';
import '../../../services/ai_settings_prompt.dart';
import '../../../services/figure_extract_service.dart';
import '../../../services/snackbar_service.dart';
import '../../../core/l10n.dart';
import '../../../services/translation_service.dart';

/// 以 fade 转场打开 [FigureViewer]。
///
/// 打开前自动截取当前屏幕的超低分辨率缩略图作为模糊背景。
Future<void> showFigureViewer(
  BuildContext context,
  List<FigureManifestEntry> figures, {
  int initialIndex = 0,
}) async {
  // 截取背景：找到最外层 RepaintBoundary（包含阅读器 + Drawer 全屏画面）
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
      pageBuilder: (_, __, ___) => FigureViewer(
        figures: figures,
        initialIndex: initialIndex,
        backgroundSnapshot: bgSnapshot,
      ),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// Figure 全屏查看器：左右切换 + 缩放 + Hero 下滑退出。
class FigureViewer extends ConsumerStatefulWidget {
  final List<FigureManifestEntry> figures;
  final int initialIndex;
  final Uint8List? backgroundSnapshot;

  const FigureViewer({
    super.key,
    required this.figures,
    this.initialIndex = 0,
    this.backgroundSnapshot,
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
    _doubleTapController = AnimationController(
      vsync: this,
      duration: kAnim,
    );
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
        scale: _doubleTapAnim!.value, doubleTapPosition: pos);

    _doubleTapAnim = _doubleTapController.drive(
      Tween(begin: cur, end: target)
          .chain(CurveTween(curve: Curves.easeOutCubic)),
    )..addListener(_doubleTapCb!);

    _doubleTapController.forward();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return ExtendedImageSlidePage(
      slideAxis: SlideAxis.vertical,
      slideType: SlideType.onlyImage,
      slidePageBackgroundHandler: (_, __) => Colors.transparent,
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
                          onPageChanged: (i) =>
                              setState(() => _currentIndex = i),
                          itemBuilder: (_, i) =>
                              _buildImage(widget.figures[i]),
                        ),
                        if (_isGallery && _currentIndex > 0)
                          _buildArrow(true, () => _pageController.previousPage(
                              duration: kAnimSlow,
                              curve: Curves.easeInOut)),
                        if (_isGallery &&
                            _currentIndex < widget.figures.length - 1)
                          _buildArrow(false, () => _pageController.nextPage(
                              duration: kAnimSlow,
                              curve: Curves.easeInOut)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildCaptionPanel(bottomPadding),
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
              icon: const Icon(Symbols.close_rounded),
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
          inPageView: _isGallery,
        ),
        onDoubleTap: _handleDoubleTap,
      ),
    );
  }

  Future<void> _showSaveMenu(
      FigureManifestEntry fig, Offset globalPosition) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
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
        PopupMenuItem<String>(
          value: 'copy',
          height: 40,
          child: Row(
            children: [
              const Icon(Symbols.content_copy_rounded, size: 18, color: Colors.white70),
              const SizedBox(width: 12),
              Text(context.l10n.copyImage,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'save',
          height: 40,
          child: Row(
            children: [
              const Icon(Symbols.download_rounded, size: 18, color: Colors.white70),
              const SizedBox(width: 12),
              Text(context.l10n.saveImage,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
            ],
          ),
        ),
      ],
    );
    if (selected == 'copy') await _copyFigure(fig);
    if (selected == 'save') await _saveFigure(fig);
  }

  Future<void> _copyFigure(FigureManifestEntry fig) async {
    final snackBar = ref.read(snackBarServiceProvider);
    final source = File(fig.imagePath);
    if (!await source.exists()) {
      snackBar.showResult(message: context.l10n.imageNotFound);
      return;
    }
    try {
      final bytes = await source.readAsBytes();
      await Pasteboard.writeImage(bytes);
      snackBar.showResult(message: context.l10n.copiedToClipboard);
    } catch (e) {
      snackBar.showResult(message: context.l10n.copyFailed('$e'));
    }
  }

  Future<void> _saveFigure(FigureManifestEntry fig) async {
    final snackBar = ref.read(snackBarServiceProvider);
    final source = File(fig.imagePath);
    if (!await source.exists()) {
      snackBar.showResult(message: context.l10n.imageNotFound);
      return;
    }
    final fileName = fig.imagePath.split(RegExp(r'[/\\]')).last;

    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        // 桌面：系统保存对话框 + File.copy
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
        snackBar.showResult(message: context.l10n.savedToPath(target.path));
      } else {
        // 移动：交给系统分享面板，用户从中选"保存到相册"/"保存到文件"
        await Share.shareXFiles(
          [XFile(fig.imagePath)],
          subject: fileName,
        );
      }
    } catch (e) {
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
              isLeft ? Symbols.chevron_left_rounded : Symbols.chevron_right_rounded,
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
    final isTranslated = _showTranslation[idx] == true &&
        _translations.containsKey(idx);
    final displayText =
        isTranslated ? _translations[idx]! : fig.captionText;
    final maxH = MediaQuery.sizeOf(context).height / 4;

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
                _captionHeight =
                    (_captionHeight - d.delta.dy).clamp(_kMinCaptionH, maxH);
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
                  _buildTranslateButton(idx, fig, isTranslated),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranslateButton(
      int idx, FigureManifestEntry fig, bool isTranslated) {
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
                ),
                style: IconButton.styleFrom(
                  backgroundColor: isTranslated
                      ? const Color(0x33FFFFFF)
                      : const Color(0x1AFFFFFF),
                  foregroundColor: Colors.white60,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: EdgeInsets.zero,
                ),
                tooltip: _translations.containsKey(idx)
                    ? (isTranslated ? context.l10n.showOriginal : context.l10n.showTranslation)
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
    // 已有翻译：切换显示
    if (_translations.containsKey(idx)) {
      setState(() => _showTranslation[idx] = !(_showTranslation[idx] ?? false));
      return;
    }

    final agentState = ref.read(effectiveAgentApiProvider);
    final snackBar = ref.read(snackBarServiceProvider);
    if (!AiSettingsPrompt.ensureTextModelConfigured(
      agentState: agentState,
      snackBar: snackBar,
      onOpenSettings: () =>
          ref.read(routerProvider).push(AppRoutes.settingsApi),
    )) {
      return;
    }

    setState(() => _translating[idx] = true);

    try {
      final translationConfig = ref.read(translationConfigProvider);
      final result = await TranslationService.translate(
        text: fig.captionText,
        agentState: agentState,
        translationConfig: translationConfig,
      );

      if (!mounted) return;
      setState(() {
        _translations[idx] = result;
        _showTranslation[idx] = true;
        _translating[idx] = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _translating[idx] = false);
      if (AiSettingsPrompt.showForConfigError(
        error: e,
        snackBar: ref.read(snackBarServiceProvider),
        onOpenSettings: () =>
            ref.read(routerProvider).push(AppRoutes.settingsApi),
      )) {
        return;
      }
      ref.read(snackBarServiceProvider).showResult(
            message: '$e'.replaceFirst('Exception: ', ''),
          );
    }
  }
}
