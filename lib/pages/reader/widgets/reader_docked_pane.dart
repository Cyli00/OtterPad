import 'package:flutter/material.dart';

import '../../../core/animation_constants.dart';
import 'reader_background.dart';

enum ReaderDockPane { outline, notes, askAi }

/// 阅读器右侧互斥停靠栏。关舱只改外层 clip 宽，子树始终按 [sidebarWidth] layout。
class ReaderDockedPane extends StatefulWidget {
  final double sidebarWidth;
  final bool open;
  final ReaderDockPane pane;
  final Widget outline;
  final Widget notes;
  final Widget chat;

  const ReaderDockedPane({
    super.key,
    required this.sidebarWidth,
    required this.open,
    required this.pane,
    required this.outline,
    required this.notes,
    required this.chat,
  });

  @override
  State<ReaderDockedPane> createState() => _ReaderDockedPaneState();
}

class _ReaderDockedPaneState extends State<ReaderDockedPane>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: kAnimSlow);
    if (widget.open) {
      _controller.animateTo(1.0, duration: kAnimSlow, curve: kAnimCurve);
    }
  }

  @override
  void didUpdateWidget(covariant ReaderDockedPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open == oldWidget.open) return;
    if (widget.open) {
      _controller.animateTo(1.0, duration: kAnimSlow, curve: kAnimCurve);
    } else {
      _controller.animateBack(0.0, duration: kAnim, curve: kAnimCurveReverse);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _paneIndex => switch (widget.pane) {
    ReaderDockPane.outline => 0,
    ReaderDockPane.notes => 1,
    ReaderDockPane.askAi => 2,
  };

  @override
  Widget build(BuildContext context) {
    final sidebarW = widget.sidebarWidth;
    final cs = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final clipWidth = sidebarW * _controller.value;
        return IgnorePointer(
          ignoring: clipWidth < 1,
          child: SizedBox(
            width: clipWidth,
            child: ClipRect(
              child: OverflowBox(
                minWidth: sidebarW,
                maxWidth: sidebarW,
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: sidebarW,
                  child: ColoredBox(
                    color: cs.surfaceContainer,
                    child: Row(
                      children: [
                        const VerticalDivider(thickness: 1, width: 1),
                        Expanded(
                          child: ReaderLocalTheme(
                            child: SafeArea(
                              left: false,
                              right: false,
                              child: IndexedStack(
                                index: _paneIndex,
                                children: [
                                  widget.outline,
                                  widget.notes,
                                  widget.chat,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
