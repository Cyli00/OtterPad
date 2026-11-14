import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/animation_constants.dart';
import '../../../core/l10n.dart';
import '../../../services/haptics.dart';

/// 图表查看器中的一项：位图路径与题注（含已有的题注译文）。
class FigureView {
  const FigureView({
    required this.path,
    required this.caption,
    this.translation,
  });

  final String path;
  final String caption;
  final String? translation;
}

/// 打开查看器的入口位置；同一路由里阅读正文与大纲可能同时显示同一张图，
/// Hero 标签按入口区分，关闭时飞回点开它的那一处。
enum FigureHeroSource { reader, outline }

String figureHeroTag(FigureHeroSource source, String path) =>
    'figure:${source.name}:$path';

/// 全屏查看图表：左右翻页、双击/双指/滚轮缩放、下滑或 Esc 关闭，可就当前图问 AI。
Future<void> showFigureViewer(
  BuildContext context,
  List<FigureView> figures, {
  int initialIndex = 0,
  FigureHeroSource? heroSource,
  void Function(FigureView figure)? onAskAi,
}) {
  if (figures.isEmpty) return Future.value();
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: kAnimSlow,
      reverseTransitionDuration: kAnim,
      pageBuilder: (_, _, _) => _FigureViewer(
        figures: figures,
        initialIndex: initialIndex.clamp(0, figures.length - 1),
        heroSource: heroSource,
        onAskAi: onAskAi,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _FigureViewer extends StatefulWidget {
  const _FigureViewer({
    required this.figures,
    required this.initialIndex,
    this.heroSource,
    this.onAskAi,
  });

  final List<FigureView> figures;
  final int initialIndex;
  final FigureHeroSource? heroSource;
  final void Function(FigureView figure)? onAskAi;

  @override
  State<_FigureViewer> createState() => _FigureViewerState();
}

class _FigureViewerState extends State<_FigureViewer>
    with SingleTickerProviderStateMixin {
  late final _pages = ExtendedPageController(initialPage: widget.initialIndex);
  late final _zoom = AnimationController(vsync: this, duration: kAnim);
  late int _index = widget.initialIndex;
  Animation<double>? _zoomAnimation;
  VoidCallback? _zoomListener;

  /// 放大后禁止翻页和下滑关闭，拖动只用于平移。
  bool _zoomed = false;
  bool _showTranslation = false;

  bool get _isGallery => widget.figures.length > 1;

  @override
  void dispose() {
    _zoom.dispose();
    _pages.dispose();
    super.dispose();
  }

  void _close() {
    Haptics.soft();
    Navigator.of(context).maybePop();
  }

  void _turn(int delta) {
    final index = _index + delta;
    if (index < 0 || index >= widget.figures.length) return;
    _pages.animateToPage(index, duration: kAnimSlow, curve: kAnimCurve);
  }

  void _onDoubleTap(ExtendedImageGestureState state) {
    final position = state.pointerDownPosition;
    final current = state.gestureDetails?.totalScale ?? 1.0;
    if (position == null) return;
    final target = (current - 1.0).abs() > 0.1 ? 1.0 : 2.5;
    if (_zoomListener case final listener?) {
      _zoomAnimation?.removeListener(listener);
    }
    _zoom
      ..stop()
      ..reset();
    final animation = _zoom.drive(
      Tween(begin: current, end: target).chain(CurveTween(curve: kAnimCurve)),
    );
    void listener() => state.handleDoubleTap(
      scale: animation.value,
      doubleTapPosition: position,
    );
    _zoomAnimation = animation..addListener(listener);
    _zoomListener = listener;
    _zoom.forward();
  }

  void _onGesture(GestureDetails? details) {
    final zoomed = (details?.totalScale ?? 1.0) > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _turn(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _turn(1),
      },
      child: Focus(
        autofocus: true,
        child: ExtendedImageSlidePage(
          slideAxis: SlideAxis.vertical,
          slideType: SlideType.onlyImage,
          slidePageBackgroundHandler: (offset, size) => Colors.transparent,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(
              children: [
                const Positioned.fill(
                  child: ColoredBox(color: Color(0x66000000)),
                ),
                SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      _topBar(),
                      Expanded(child: _pageView()),
                      _caption(),
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

  Widget _topBar() {
    final figure = widget.figures[_index];
    final onAskAi = widget.onAskAi;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 48),
          Expanded(
            child: _isGallery
                ? Center(
                    child: Text(
                      '${_index + 1} / ${widget.figures.length}',
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: Colors.white70),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          if (onAskAi != null)
            IconButton(
              tooltip: context.l10n.askAi,
              color: Colors.white70,
              icon: const Icon(Symbols.auto_awesome_rounded, fill: 1),
              onPressed: () {
                Haptics.soft();
                Navigator.of(context).pop();
                onAskAi(figure);
              },
            ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              tooltip: context.l10n.closeImage,
              color: Colors.white70,
              icon: const Icon(Symbols.close_rounded, fill: 1),
              onPressed: _close,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pageView() {
    return Stack(
      children: [
        ExtendedImageGesturePageView.builder(
          controller: _pages,
          itemCount: widget.figures.length,
          canScrollPage: (details) =>
              !_zoomed && (details?.totalScale ?? 1.0) <= 1.01,
          onPageChanged: (i) {
            _zoom.stop();
            setState(() {
              _index = i;
              _zoomed = false;
              _showTranslation = false;
            });
          },
          itemBuilder: (_, i) => _image(widget.figures[i]),
        ),
        if (_isGallery && _index > 0) _arrow(left: true),
        if (_isGallery && _index < widget.figures.length - 1)
          _arrow(left: false),
      ],
    );
  }

  Widget _image(FigureView figure) {
    final source = widget.heroSource;
    return ExtendedImage.file(
      File(figure.path),
      fit: BoxFit.contain,
      mode: ExtendedImageMode.gesture,
      enableSlideOutPage: !_zoomed,
      heroBuilderForSlidingPage: source == null
          ? null
          : (child) =>
                Hero(tag: figureHeroTag(source, figure.path), child: child),
      initGestureConfigHandler: (_) => GestureConfig(
        minScale: 0.9,
        animationMinScale: 0.7,
        maxScale: 5.0,
        animationMaxScale: 5.5,
        inertialSpeed: 500.0,
        inPageView: _isGallery && !_zoomed,
        gestureDetailsIsChanged: _onGesture,
      ),
      onDoubleTap: _onDoubleTap,
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
    );
  }

  Widget _arrow({required bool left}) {
    return Positioned(
      left: left ? 8 : null,
      right: left ? null : 8,
      top: 0,
      bottom: 0,
      child: Center(
        child: IconButton.filledTonal(
          tooltip: left ? context.l10n.figurePrevious : context.l10n.figureNext,
          icon: Icon(
            left ? Symbols.chevron_left_rounded : Symbols.chevron_right_rounded,
          ),
          onPressed: () {
            Haptics.soft();
            _turn(left ? -1 : 1);
          },
        ),
      ),
    );
  }

  Widget _caption() {
    final figure = widget.figures[_index];
    final bottom = MediaQuery.paddingOf(context).bottom;
    final translation = figure.translation;
    final text = _showTranslation && translation != null
        ? translation
        : figure.caption;
    if (text.trim().isEmpty) return SizedBox(height: bottom + 8);
    final maxHeight = MediaQuery.sizeOf(context).height / 4;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 16, bottom + 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectionArea(
                child: SingleChildScrollView(
                  child: Text(
                    text,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
            ),
            if (translation != null && translation.trim().isNotEmpty) ...[
              const SizedBox(width: 12),
              IconButton(
                tooltip: _showTranslation
                    ? context.l10n.showOriginal
                    : context.l10n.showTranslation,
                icon: Icon(
                  _showTranslation
                      ? Symbols.title_rounded
                      : Symbols.translate_rounded,
                  size: 18,
                  fill: 1,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: _showTranslation
                      ? Colors.white24
                      : Colors.white10,
                  foregroundColor: Colors.white60,
                  fixedSize: const Size.square(36),
                  minimumSize: const Size.square(36),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Haptics.soft();
                  setState(() => _showTranslation = !_showTranslation);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
