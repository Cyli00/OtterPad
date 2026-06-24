import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/animation_constants.dart';
import 'reader_background.dart';

/// 阅读器内嵌 bottom sheet 宿主。
///
/// 放在 Reader Stack 中底栏 [Positioned] **之前**，z-order 低于底栏。
/// 弹出 sheet 时底栏始终可见可交互。
///
/// 不走 [showModalBottomSheet]（它创建 modal route，z-order 天然高于
/// Scaffold body 内所有内容）。自行管理 [AnimationController] + barrier +
/// slide 动画 + 拖拽关闭。
class ReaderSheetHost extends StatefulWidget {
  /// sheet 弹出时调用（如 `setSheetOpen(true)`）。
  final VoidCallback? onSheetOpen;

  /// sheet 关闭动画结束后调用（如 `setSheetOpen(false)`）。
  final VoidCallback? onSheetClose;

  const ReaderSheetHost({super.key, this.onSheetOpen, this.onSheetClose});

  /// 从 [context] 向上找到最近的 [ReaderSheetHostState] 并关闭 sheet。
  ///
  /// 替代 `Navigator.pop(context, result)` 的语义——sheet 内容不需要
  /// 持有 host 的 GlobalKey，只需通过 context 获取 close 方法。
  static void closeOf(BuildContext context, [dynamic result]) {
    context.findAncestorStateOfType<ReaderSheetHostState>()?.close(result);
  }

  @override
  State<ReaderSheetHost> createState() => ReaderSheetHostState();
}

class ReaderSheetHostState extends State<ReaderSheetHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;

  Completer<dynamic>? _completer;
  WidgetBuilder? _builder;
  double _barrierAlpha = 0.32;
  double _bottomBarHeight = 56;
  bool _enableDrag = true;
  bool _isOpen = false;
  dynamic _pendingResult;
  VoidCallback? _onResume;

  // 拖拽
  final _sheetContentKey = GlobalKey();
  static const _kFlingVelocity = 700.0;
  static const _kCloseThreshold = 0.5;
  static const _kDragHandleHeight = 40.0;

  bool get isOpen => _isOpen;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: kAnimSlow);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(_controller);
    _controller.addStatusListener(_onStatus);
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !_isOpen) {
      _finalize();
    }
  }

  /// 弹出 sheet，返回 [Future]，sheet 关闭后 resolve。
  ///
  /// [onPause] 在 sheet 弹出前调用（如暂停 WebView timer），
  /// [onResume] 在 sheet 关闭动画完成后调用（如恢复 WebView）。
  /// SheetHost 保证 onResume 调用——包括被新 sheet 抢占（forceClose）的场景。
  Future<T?> show<T>({
    required WidgetBuilder builder,
    double barrierAlpha = 0.32,
    double bottomBarHeight = 56,
    bool enableDrag = true,
    VoidCallback? onPause,
    VoidCallback? onResume,
  }) {
    if (_isOpen) _forceClose();

    final completer = Completer<T?>();
    _completer = completer;
    _builder = builder;
    _barrierAlpha = barrierAlpha;
    _bottomBarHeight = bottomBarHeight;
    _enableDrag = enableDrag;
    _isOpen = true;
    _pendingResult = null;
    _onResume = onResume;
    onPause?.call();
    widget.onSheetOpen?.call();

    setState(() {});
    _controller.animateTo(1.0, duration: kAnimSlow, curve: kAnimCurve);

    return completer.future;
  }

  /// 关闭 sheet。[result] 会作为 [show] 返回的 Future 的值。
  void close([dynamic result]) {
    if (!_isOpen) return;
    _isOpen = false;
    _pendingResult = result;
    _controller.animateBack(0.0, duration: kAnim, curve: kAnimCurveReverse);
  }

  void _forceClose() {
    _isOpen = false;
    _controller.value = 0;
    _finalize();
  }

  void _finalize() {
    if (mounted) setState(() => _builder = null);
    final resume = _onResume;
    _onResume = null;
    resume?.call();
    widget.onSheetClose?.call();
    final c = _completer;
    _completer = null;
    if (c != null && !c.isCompleted) c.complete(_pendingResult);
    _pendingResult = null;
  }

  // ── 拖拽 ──

  double get _sheetHeight {
    final box =
        _sheetContentKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.size.height ?? 300;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    // 仅响应下拉（delta > 0），或 controller 已被拉低时允许上推恢复
    if (delta > 0 || _controller.value < 1) {
      _controller.value -= delta / _sheetHeight;
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;
    if (velocity > _kFlingVelocity || _controller.value < _kCloseThreshold) {
      close();
    } else {
      _controller.animateTo(1.0, duration: kAnimFast, curve: kAnimCurve);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _builder != null;

    // 树结构保持稳定（PopScope + IgnorePointer + barrier 始终存在），
    // 避免 SizedBox ↔ 复杂树 切换时 Stack relayout 导致 WebView 闪烁。
    return PopScope(
      canPop: !_isOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isOpen) close();
      },
      child: IgnorePointer(
        ignoring: !active,
        child: Stack(
          children: [
            // barrier —— 始终存在，由 FadeTransition 控制可见性
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: active ? _bottomBarHeight : 0,
              child: GestureDetector(
                onTap: active ? () => close() : null,
                behavior: HitTestBehavior.opaque,
                child: FadeTransition(
                  opacity: _controller,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: _barrierAlpha),
                  ),
                ),
              ),
            ),
            // sheet 内容
            if (active)
              Positioned(
                left: 0,
                right: 0,
                // 顶部内缩状态栏：满高 sheet（如大纲）顶到屏幕顶时，拖拽手势条
                // 不会落进状态栏区域。barrier 仍铺满全屏（top:0）做压暗。
                top: MediaQuery.of(context).padding.top,
                bottom: _bottomBarHeight,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ClipRect(
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: _buildContent(context),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final content = KeyedSubtree(
      key: _sheetContentKey,
      child: ReaderLocalTheme(child: _builder!(context)),
    );

    if (!_enableDrag) return content;

    // 在 sheet 顶部叠加一个透明拖拽感应区（覆盖 grabber 条）。
    // translucent 模式：自己参与手势竞技，同时让触摸事件透传到下方的
    // DraggableScrollableSheet 等。因为 overlay 在 Stack 顶层，
    // 其 recognizer 先进入 arena → 先 accept → 赢得手势。
    return Stack(
      children: [
        content,
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: _kDragHandleHeight,
          child: GestureDetector(
            onVerticalDragUpdate: _handleDragUpdate,
            onVerticalDragEnd: _handleDragEnd,
            behavior: HitTestBehavior.translucent,
          ),
        ),
      ],
    );
  }
}
