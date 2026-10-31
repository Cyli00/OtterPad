import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/animation_constants.dart';
import '../core/elevation.dart';
import '../services/haptics.dart';

/// 引导中的一步：高亮 [targetKey] 指向的组件，并在旁边给出说明。
class SpotlightStep {
  const SpotlightStep({
    required this.targetKey,
    required this.message,
    this.borderRadius = 16,
    this.padding = const EdgeInsets.all(8),
  });

  final GlobalKey targetKey;
  final String message;
  final double borderRadius;
  final EdgeInsets padding;
}

/// 全屏遮罩 + 目标镂空 + 说明浮卡的分步引导。
///
/// 多步共用一个浮层：切换时先把下一目标滚入视口，镂空与浮卡从上一目标补间过去。
/// 只有浮卡可交互；Enter 前进，Esc 跳过。[nextLabel]、[skipLabel] 仅多步时使用。
Future<void> showOnboardingSpotlight({
  required BuildContext context,
  required List<SpotlightStep> steps,
  required String doneLabel,
  String? nextLabel,
  String? skipLabel,
}) async {
  assert(steps.length < 2 || (nextLabel != null && skipLabel != null));
  if (steps.isEmpty || steps.first.targetKey.currentContext == null) return;
  await _scrollIntoView(context, steps.first.targetKey);
  if (!context.mounted) return;

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: kAnimSlow,
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: kAnimCurve);
      return FadeTransition(opacity: curved, child: child);
    },
    pageBuilder: (context, animation, secondaryAnimation) => _TourOverlay(
      steps: steps,
      doneLabel: doneLabel,
      nextLabel: nextLabel,
      skipLabel: skipLabel,
    ),
  );
}

Future<void> _scrollIntoView(BuildContext context, GlobalKey key) async {
  final target = key.currentContext;
  if (target == null) return;
  await Scrollable.ensureVisible(
    target,
    alignment: 0.4,
    duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : kAnim,
    curve: kAnimCurve,
  );
}

// ─── Tour Overlay ───────────────────────────────────────────────────────────

class _TourOverlay extends StatefulWidget {
  const _TourOverlay({
    required this.steps,
    required this.doneLabel,
    this.nextLabel,
    this.skipLabel,
  });

  final List<SpotlightStep> steps;
  final String doneLabel;
  final String? nextLabel;
  final String? skipLabel;

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay>
    with TickerProviderStateMixin {
  /// 浮卡与屏幕边缘、目标之间的间距。
  static const double _gap = 16;
  static const double _cardMaxWidth = 360;

  // 呼吸光晕；同时驱动逐帧重建，镂空实时跟随目标（滚动、布局变化）
  late final AnimationController _pulse = AnimationController(
    duration: kAnimPulse,
    vsync: this,
  )..repeat(reverse: true);

  // 步骤切换的补间进度
  late final AnimationController _move = AnimationController(
    duration: kAnimSlow,
    vsync: this,
    value: 1,
  );

  int _index = 0;

  /// 上一帧实际绘制的镂空，切换步骤时作为补间起点，目标短暂 unmount 时兜底
  Rect? _shownRect;
  double _shownRadius = 16;
  Rect? _fromRect;
  double _fromRadius = 16;

  bool get _isLast => _index == widget.steps.length - 1;
  bool get _multiStep => widget.steps.length > 1;

  @override
  void dispose() {
    _pulse.dispose();
    _move.dispose();
    super.dispose();
  }

  /// 以 Navigator 为参照量取目标：浮层铺满 Navigator，而桌面端 Navigator
  /// 上方还有自定义标题栏，用窗口全局坐标会整体错位一个标题栏高度。
  Rect? _measure(SpotlightStep step) {
    final target = step.targetKey.currentContext?.findRenderObject();
    final navigator = Navigator.of(context).context.findRenderObject();
    if (target is! RenderBox || !target.hasSize || !target.attached) {
      return null;
    }
    if (navigator is! RenderBox) return null;
    final offset = target.localToGlobal(Offset.zero, ancestor: navigator);
    return step.padding.inflateRect(offset & target.size);
  }

  void _next() {
    Haptics.soft();
    if (_isLast) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _fromRect = _shownRect;
      _fromRadius = _shownRadius;
      _index++;
    });
    if (MediaQuery.disableAnimationsOf(context)) {
      _move.value = 1;
    } else {
      _move.forward(from: 0);
    }
    _scrollIntoView(context, widget.steps[_index].targetKey);
  }

  void _skip() {
    Haptics.soft();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final cs = Theme.of(context).colorScheme;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _next,
        const SingleActivator(LogicalKeyboardKey.escape): _skip,
      },
      child: Focus(
        autofocus: true,
        child: Material(
          type: MaterialType.transparency,
          child: AnimatedBuilder(
            animation: Listenable.merge([_pulse, _move]),
            builder: (context, _) {
              final step = widget.steps[_index];
              final target = _measure(step) ?? _shownRect;
              if (target == null) return const SizedBox.shrink();

              final t = kAnimCurve.transform(_move.value);
              final rect = _fromRect == null
                  ? target
                  : Rect.lerp(_fromRect, target, t)!;
              final radius = _fromRect == null
                  ? step.borderRadius
                  : lerpDouble(_fromRadius, step.borderRadius, t)!;
              _shownRect = rect;
              _shownRadius = radius;

              return LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.biggest;
                  final cardWidth = (size.width - _gap * 2).clamp(
                    0.0,
                    _cardMaxWidth,
                  );
                  // 浮卡左缘对齐目标，夹在屏幕内；下方空间不足时放到上方
                  final cardLeft = rect.left.clamp(
                    _gap,
                    size.width - cardWidth - _gap,
                  );
                  final below = size.height - rect.bottom >= rect.top;

                  return Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _SpotlightPainter(
                            targetRect: rect,
                            borderRadius: radius,
                            scrimColor: cs.scrim.withAlpha(140),
                            ringColor: cs.primary,
                            pulseValue: reduceMotion ? 0.5 : _pulse.value,
                          ),
                        ),
                      ),
                      Positioned(
                        left: cardLeft,
                        width: cardWidth,
                        top: below ? rect.bottom + _gap : null,
                        bottom: below ? null : size.height - rect.top + _gap,
                        child: _buildCard(reduceMotion),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCard(bool reduceMotion) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final step = widget.steps[_index];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.dialog,
      ),
      child: AnimatedSize(
        duration: reduceMotion ? Duration.zero : kAnim,
        curve: kAnimCurve,
        alignment: Alignment.topLeft,
        child: AnimatedSwitcher(
          duration: reduceMotion ? Duration.zero : kAnimFast,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topLeft,
            children: [...previous, ?current],
          ),
          child: Padding(
            key: ValueKey(_index),
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_multiStep) ...[
                  Text(
                    '${_index + 1} / ${widget.steps.length}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    step.message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (_multiStep && !_isLast)
                      TextButton(
                        onPressed: _skip,
                        child: Text(widget.skipLabel!),
                      ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _next,
                      child: Text(
                        _isLast ? widget.doneLabel : widget.nextLabel!,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── CustomPainter ──────────────────────────────────────────────────────────

class _SpotlightPainter extends CustomPainter {
  final Rect targetRect;
  final double borderRadius;
  final Color scrimColor;
  final Color ringColor;
  final double pulseValue;

  _SpotlightPainter({
    required this.targetRect,
    required this.borderRadius,
    required this.scrimColor,
    required this.ringColor,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      targetRect,
      Radius.circular(borderRadius),
    );

    // 遮罩 + even-odd 镂空
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = scrimColor);

    // 外圈呼吸光晕，只向外扩散，不盖住目标内容
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = ringColor.withAlpha((40 + 60 * pulseValue).round())
        ..maskFilter = MaskFilter.blur(BlurStyle.outer, 6 + 6 * pulseValue),
    );
    // 清晰描边，标出镂空边界
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.pulseValue != pulseValue ||
      old.targetRect != targetRect ||
      old.borderRadius != borderRadius ||
      old.scrimColor != scrimColor ||
      old.ringColor != ringColor;
}

// ─── Pulse Wrapper ──────────────────────────────────────────────────────────

/// 非阻塞式脉冲发光，包裹目标 widget 吸引注意力。
class OnboardingPulse extends StatefulWidget {
  final Widget child;
  final double borderRadius;

  const OnboardingPulse({
    super.key,
    required this.child,
    this.borderRadius = 20,
  });

  @override
  State<OnboardingPulse> createState() => _OnboardingPulseState();
}

class _OnboardingPulseState extends State<OnboardingPulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: kAnimPulse, vsync: this)
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final v = _ctrl.value;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withAlpha((50 + 80 * v).round()),
                blurRadius: 6 + 10 * v,
                spreadRadius: 1 + 3 * v,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
