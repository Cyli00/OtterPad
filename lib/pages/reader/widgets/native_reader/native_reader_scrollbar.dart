import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/animation_constants.dart';
import '../reader_js_bridge.dart' show ReaderScrollMetrics;

/// 原生阅读器的覆盖滚动条：位置变化时浮现，静止 1.5 秒后淡出，可点按或拖动跳转。
///
/// 懒加载列表的像素总高是估算值，这里按 [ReaderScrollMetrics] 的内容比例定位。
class NativeReaderScrollbar extends StatefulWidget {
  const NativeReaderScrollbar({
    super.key,
    required this.metrics,
    required this.onJumpTo,
  });

  final ValueListenable<ReaderScrollMetrics> metrics;

  /// 跳到全文的 [0, 1] 比例处。
  final ValueChanged<double> onJumpTo;

  @override
  State<NativeReaderScrollbar> createState() => _NativeReaderScrollbarState();
}

class _NativeReaderScrollbarState extends State<NativeReaderScrollbar> {
  static const double _trackWidth = 12;
  static const double _thumbWidth = 6;
  static const double _minThumbHeight = 48;

  bool _visible = false;
  bool _active = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    widget.metrics.addListener(_show);
  }

  @override
  void didUpdateWidget(NativeReaderScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.metrics != widget.metrics) {
      oldWidget.metrics.removeListener(_show);
      widget.metrics.addListener(_show);
    }
  }

  @override
  void dispose() {
    widget.metrics.removeListener(_show);
    _hideTimer?.cancel();
    super.dispose();
  }

  void _show() {
    if (!_visible) setState(() => _visible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted && !_active) setState(() => _visible = false);
    });
  }

  void _setActive(bool value) {
    _active = value;
    _show();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(140);
    return IgnorePointer(
      ignoring: !_visible,
      child: AnimatedOpacity(
        duration: kAnim,
        opacity: _visible ? 1 : 0,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final trackHeight = constraints.maxHeight;
            void jump(Offset position) {
              if (trackHeight <= 0) return;
              widget.onJumpTo((position.dy / trackHeight).clamp(0.0, 1.0));
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                _setActive(true);
                jump(details.localPosition);
              },
              onTapUp: (_) => _setActive(false),
              onTapCancel: () => _setActive(false),
              onVerticalDragStart: (_) => _setActive(true),
              onVerticalDragUpdate: (details) => jump(details.localPosition),
              onVerticalDragEnd: (_) => _setActive(false),
              onVerticalDragCancel: () => _setActive(false),
              child: SizedBox(
                width: _trackWidth,
                child: ValueListenableBuilder<ReaderScrollMetrics>(
                  valueListenable: widget.metrics,
                  builder: (context, metrics, _) {
                    final thumbHeight = math.max(
                      _minThumbHeight,
                      trackHeight * metrics.viewportRatio,
                    );
                    final top =
                        metrics.progress *
                        math.max(0.0, trackHeight - thumbHeight);
                    return Stack(
                      children: [
                        Positioned(
                          top: top,
                          left: (_trackWidth - _thumbWidth) / 2,
                          width: _thumbWidth,
                          height: thumbHeight,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(
                                _thumbWidth / 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
