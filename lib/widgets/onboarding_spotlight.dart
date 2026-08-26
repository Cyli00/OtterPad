import 'package:flutter/material.dart';

import '../core/animation_constants.dart';

/// 全屏遮罩 + 目标区域镂空 + 脉冲发光 + tooltip 浮卡。
///
/// 用 [showGeneralDialog] 实现模态遮挡，只有 tooltip 卡片可交互。
Future<void> showOnboardingSpotlight({
  required BuildContext context,
  required GlobalKey targetKey,
  required String message,
  required String actionLabel,
  EdgeInsets targetPadding = const EdgeInsets.all(8),
  double borderRadius = 16,
}) async {
  if (_measureRect(targetKey, targetPadding) == null || !context.mounted) {
    return;
  }

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: kAnimSlow,
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: kAnimCurve);
      return FadeTransition(opacity: curved, child: child);
    },
    pageBuilder: (context, animation, secondaryAnimation) {
      return _SpotlightOverlay(
        targetKey: targetKey,
        targetPadding: targetPadding,
        borderRadius: borderRadius,
        message: message,
        actionLabel: actionLabel,
        onDismiss: () => Navigator.of(context).pop(),
      );
    },
  );
}

/// 从 [targetKey] 实时量取目标区域（全局坐标）。
/// 禁止在 dialog 弹出前快照一次就定死——弹出转场 / 布局调整期间目标会动，
/// 快照会导致镂空与卡片脱开。
Rect? _measureRect(GlobalKey targetKey, EdgeInsets padding) {
  final renderBox = targetKey.currentContext?.findRenderObject();
  if (renderBox is! RenderBox || !renderBox.hasSize) return null;
  final offset = renderBox.localToGlobal(Offset.zero);
  return Rect.fromLTRB(
    offset.dx - padding.left,
    offset.dy - padding.top,
    offset.dx + renderBox.size.width + padding.right,
    offset.dy + renderBox.size.height + padding.bottom,
  );
}

// ─── Spotlight Overlay ──────────────────────────────────────────────────────

class _SpotlightOverlay extends StatefulWidget {
  final GlobalKey targetKey;
  final EdgeInsets targetPadding;
  final double borderRadius;
  final String message;
  final String actionLabel;
  final VoidCallback onDismiss;

  const _SpotlightOverlay({
    required this.targetKey,
    required this.targetPadding,
    required this.borderRadius,
    required this.message,
    required this.actionLabel,
    required this.onDismiss,
  });

  @override
  State<_SpotlightOverlay> createState() => _SpotlightOverlayState();
}

class _SpotlightOverlayState extends State<_SpotlightOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  /// 上一帧的目标区域——目标已 unmount 的极端时刻兜底，避免闪烁。
  Rect? _lastRect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Material(
      type: MaterialType.transparency,
      // 随脉搏动画逐帧重建，镂空/浮卡跟随目标卡片实时位置
      child: AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (context, _) {
          final rect =
              _measureRect(widget.targetKey, widget.targetPadding) ?? _lastRect;
          if (rect == null) return const SizedBox.shrink();
          _lastRect = rect;

          final screenSize = MediaQuery.sizeOf(context);
          final showBelow = rect.center.dy < screenSize.height * 0.5;

          return Stack(
            children: [
              // 遮罩 + 镂空
              Positioned.fill(
                child: CustomPaint(
                  painter: _SpotlightPainter(
                    targetRect: rect,
                    borderRadius: widget.borderRadius,
                    primaryColor: cs.primary,
                    pulseValue: _pulseCtrl.value,
                  ),
                ),
              ),
              // Tooltip 卡片
              Positioned(
                left: 24,
                right: 24,
                top: showBelow ? rect.bottom + 20 : null,
                bottom: showBelow ? null : screenSize.height - rect.top + 20,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Card(
                      elevation: 8,
                      color: cs.surfaceContainerHigh,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.message,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurface,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton(
                                onPressed: widget.onDismiss,
                                child: Text(widget.actionLabel),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── CustomPainter ──────────────────────────────────────────────────────────

class _SpotlightPainter extends CustomPainter {
  final Rect targetRect;
  final double borderRadius;
  final Color primaryColor;
  final double pulseValue;

  _SpotlightPainter({
    required this.targetRect,
    required this.borderRadius,
    required this.primaryColor,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      targetRect,
      Radius.circular(borderRadius),
    );

    // 半透明遮罩 + even-odd 镂空
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = Colors.black.withAlpha(150));

    // 脉冲发光边框
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = primaryColor.withAlpha((80 + 100 * pulseValue).round())
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 + 2 * pulseValue
        ..maskFilter = MaskFilter.blur(BlurStyle.outer, 6 + 8 * pulseValue),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.pulseValue != pulseValue || old.targetRect != targetRect;
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
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
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
