import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:motor/motor.dart';

import '../../../core/animation_constants.dart';
import '../../../services/haptics.dart';

/// 阅读器工具栏图标按钮。
///
/// - 悬停 / 按压：圆形底色渐显（onSurface 8% / 12%），按压弹簧缩放到 0.88。
/// - 激活态：primaryContainer 底色从中心弹出，图标转 onPrimaryContainer。
/// - 图标切换（含 [loading] 的 spinner）：缩放 + 淡入交叉切换，不硬切。
/// - 保留键盘焦点与 Enter / Space 触发；减弱动态效果时全部瞬时完成。
class ReaderIconButton extends StatefulWidget {
  const ReaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.loading = false,
    this.iconSize = 22,
    this.extent = 48,
  });

  final IconData icon;
  final String tooltip;

  /// 为 null 时禁用（图标 38% 透明度，无悬停反馈）。
  final VoidCallback? onPressed;
  final bool active;

  /// 为 true 时图标换成 spinner，并禁用点击。
  final bool loading;
  final double iconSize;

  /// 点击区域边长；可视底色为其中心 40×40 的圆。
  final double extent;

  @override
  State<ReaderIconButton> createState() => _ReaderIconButtonState();
}

class _ReaderIconButtonState extends State<ReaderIconButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  void _activate() {
    if (!_enabled) return;
    Haptics.soft();
    widget.onPressed!();
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final animate = !MediaQuery.disableAnimationsOf(context);
    final duration = animate ? kAnimFast : Duration.zero;

    final overlay = !_enabled
        ? 0.0
        : _pressed
        ? 0.12
        : (_hovered || _focused)
        ? 0.08
        : 0.0;
    final iconColor = !_enabled && !widget.loading
        ? cs.onSurfaceVariant.withValues(alpha: 0.38)
        : widget.active
        ? cs.onPrimaryContainer
        : cs.onSurfaceVariant;

    final Widget glyph = widget.loading
        ? SizedBox.square(
            key: const ValueKey('loading'),
            dimension: widget.iconSize - 2,
            child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
          )
        : TweenAnimationBuilder<Color?>(
            key: ValueKey(widget.icon),
            tween: ColorTween(end: iconColor),
            duration: duration,
            curve: kAnimCurve,
            builder: (context, color, _) =>
                Icon(widget.icon, size: widget.iconSize, fill: 1, color: color),
          );

    final visual = SizedBox.square(
      dimension: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 激活底色：弹簧从中心放大，带轻微过冲。
          SingleMotionBuilder(
            motion: kMotionSpatialFast,
            value: widget.active ? 1.0 : 0.0,
            active: animate,
            builder: (context, v, _) => Opacity(
              opacity: v.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.6 + 0.4 * v,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          // 悬停 / 按压 / 焦点底色。
          AnimatedContainer(
            duration: duration,
            curve: kAnimCurve,
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: overlay),
              shape: BoxShape.circle,
              border: _focused ? Border.all(color: cs.primary, width: 2) : null,
            ),
          ),
          AnimatedSwitcher(
            duration: animate ? kAnim : Duration.zero,
            switchInCurve: kAnimCurve,
            switchOutCurve: kAnimCurveReverse,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween(begin: 0.6, end: 1.0).animate(animation),
                child: child,
              ),
            ),
            child: glyph,
          ),
        ],
      ),
    );

    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: _enabled,
        label: widget.tooltip,
        child: FocusableActionDetector(
          enabled: _enabled,
          mouseCursor: _enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onShowFocusHighlight: (v) => setState(() => _focused = v),
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          },
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                _activate();
                return null;
              },
            ),
          },
          // 悬停用 MouseRegion：FocusableActionDetector 的 hover 回调在触摸
          // 高亮模式下不触发，鼠标与触屏混用的设备上会丢失悬停反馈。
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: _enabled ? (_) => _setPressed(true) : null,
              onTapUp: _enabled ? (_) => _setPressed(false) : null,
              onTapCancel: _enabled ? () => _setPressed(false) : null,
              onTap: _enabled ? _activate : null,
              child: SizedBox.square(
                dimension: widget.extent,
                child: Center(
                  child: SingleMotionBuilder(
                    motion: kMotionSpatialFast,
                    value: _pressed ? 0.88 : 1.0,
                    active: animate,
                    builder: (context, s, child) =>
                        Transform.scale(scale: s, child: child),
                    child: visual,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
