import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';

import '../../../services/figure_extract_service.dart';

/// Figure 全屏查看器：左右切换 + 缩放 + 下滑退出。
///
/// 基于 `extended_image` 实现：
/// - `ExtendedImageGesturePageView` 处理左右滑动切换
/// - `ExtendedImageSlidePage` 处理下滑退出 + 背景透明度渐变
/// - `ExtendedImage.file` + `ExtendedImageMode.gesture` 处理缩放/平移
/// - 双击智能缩放（1x ↔ 2.5x，easeOutCubic 动画）
///
/// 通过 [showFigureViewer] 以模态路由打开。
class FigureViewer extends StatefulWidget {
  final List<FigureManifestEntry> figures;
  final int initialIndex;

  const FigureViewer({
    super.key,
    required this.figures,
    this.initialIndex = 0,
  });

  @override
  State<FigureViewer> createState() => _FigureViewerState();
}

/// 以 fade 转场打开 [FigureViewer]。
void showFigureViewer(
  BuildContext context,
  List<FigureManifestEntry> figures, {
  int initialIndex = 0,
}) {
  Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => FigureViewer(
        figures: figures,
        initialIndex: initialIndex,
      ),
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}

class _FigureViewerState extends State<FigureViewer>
    with TickerProviderStateMixin {
  late int _currentIndex;
  late final ExtendedPageController _pageController;

  // ── 双击缩放动画 ──
  late final AnimationController _doubleTapController;
  Animation<double>? _doubleTapAnimation;
  VoidCallback? _doubleTapListener;

  bool get _hasPrevious => _currentIndex > 0;
  bool get _hasNext => _currentIndex < widget.figures.length - 1;
  bool get _isGallery => widget.figures.length > 1;
  FigureManifestEntry get _currentFigure => widget.figures[_currentIndex];

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
    _doubleTapAnimation?.removeListener(_doubleTapListener ?? () {});
    _doubleTapController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _goToPrevious() {
    if (!_hasPrevious) return;
    _pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _goToNext() {
    if (!_hasNext) return;
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _handleDoubleTap(ExtendedImageGestureState state) {
    final position = state.pointerDownPosition;
    if (position == null) return;
    final details = state.gestureDetails;
    if (details == null) return;

    final currentScale = details.totalScale ?? 1.0;
    final targetScale = (currentScale - 1.0).abs() > 0.1 ? 1.0 : 2.5;

    _doubleTapAnimation?.removeListener(_doubleTapListener ?? () {});
    _doubleTapController.stop();
    _doubleTapController.reset();

    _doubleTapListener = () {
      state.handleDoubleTap(
        scale: _doubleTapAnimation!.value,
        doubleTapPosition: position,
      );
    };

    _doubleTapAnimation = _doubleTapController.drive(
      Tween<double>(begin: currentScale, end: targetScale)
          .chain(CurveTween(curve: Curves.easeOutCubic)),
    );
    _doubleTapAnimation!.addListener(_doubleTapListener!);
    _doubleTapController.forward();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return ExtendedImageSlidePage(
      slideAxis: SlideAxis.vertical,
      slideType: SlideType.onlyImage,
      slidePageBackgroundHandler: (offset, pageSize) {
        final progress = offset.dy.abs() / (pageSize.height / 2);
        return Colors.black
            .withValues(alpha: (1.0 - progress).clamp(0.0, 1.0));
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ── 顶栏 ──
              SizedBox(
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
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white70,
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: '关闭',
                      ),
                    ),
                  ],
                ),
              ),
              // ── 图片区域（PageView + 左右箭头）──
              Expanded(
                child: Stack(
                  children: [
                    // 图片 PageView
                    ExtendedImageGesturePageView.builder(
                      controller: _pageController,
                      itemCount: widget.figures.length,
                      onPageChanged: (index) {
                        setState(() => _currentIndex = index);
                      },
                      itemBuilder: (context, index) {
                        final fig = widget.figures[index];
                        return ExtendedImage.file(
                          File(fig.imagePath),
                          fit: BoxFit.contain,
                          mode: ExtendedImageMode.gesture,
                          enableSlideOutPage: true,
                          initGestureConfigHandler: (state) => GestureConfig(
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
                      },
                    ),
                    // 左箭头
                    if (_isGallery && _hasPrevious)
                      Positioned(
                        left: 8,
                        top: 0,
                        bottom: 0,
                        child: Center(child: _NavArrow(
                          icon: Icons.chevron_left_rounded,
                          onTap: _goToPrevious,
                        )),
                      ),
                    // 右箭头
                    if (_isGallery && _hasNext)
                      Positioned(
                        right: 8,
                        top: 0,
                        bottom: 0,
                        child: Center(child: _NavArrow(
                          icon: Icons.chevron_right_rounded,
                          onTap: _goToNext,
                        )),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // ── 标题面板（过长可滚动）──
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 140),
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  16,
                  bottomPadding + 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(
                          _currentFigure.captionText,
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
                          icon: const Icon(
                            Icons.translate_rounded,
                            size: 18,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.1),
                            foregroundColor: Colors.white60,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 导航箭头按钮 ───

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _NavArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white70, size: 28),
      ),
    );
  }
}
