import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../services/figure_extract_service.dart';
import 'package:material_symbols_icons/symbols.dart';

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
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 200),
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
class FigureViewer extends StatefulWidget {
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
  State<FigureViewer> createState() => _FigureViewerState();
}

class _FigureViewerState extends State<FigureViewer>
    with TickerProviderStateMixin {
  late int _currentIndex;
  late final ExtendedPageController _pageController;
  late final AnimationController _doubleTapController;
  Animation<double>? _doubleTapAnim;
  VoidCallback? _doubleTapCb;

  bool get _isGallery => widget.figures.length > 1;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = ExtendedPageController(initialPage: _currentIndex);
    _doubleTapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
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
    final fig = widget.figures[_currentIndex];

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
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut)),
                        if (_isGallery &&
                            _currentIndex < widget.figures.length - 1)
                          _buildArrow(false, () => _pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildCaptionPanel(fig, bottomPadding),
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
              onPressed: () => Navigator.of(context).pop(),
              tooltip: '关闭',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImage(FigureManifestEntry fig) {
    return ExtendedImage.file(
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
    );
  }

  Widget _buildArrow(bool isLeft, VoidCallback onTap) {
    return Positioned(
      left: isLeft ? 8 : null,
      right: isLeft ? null : 8,
      top: 0,
      bottom: 0,
      child: Center(
        child: GestureDetector(
          onTap: onTap,
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

  Widget _buildCaptionPanel(FigureManifestEntry fig, double bottomPadding) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 140),
      padding: EdgeInsets.fromLTRB(20, 16, 16, bottomPadding + 16),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                fig.captionText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.55,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SizedBox(
              width: 36,
              height: 36,
              child: IconButton(
                icon: const Icon(Symbols.translate_rounded, size: 18),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0x1AFFFFFF),
                  foregroundColor: Colors.white60,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: EdgeInsets.zero,
                ),
                tooltip: '翻译',
                onPressed: () {
                  // TODO: 翻译功能
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
