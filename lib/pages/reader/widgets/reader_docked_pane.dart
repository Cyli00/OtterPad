import 'package:flutter/material.dart';

import '../../../core/animation_constants.dart';
import '../../../widgets/app_divider.dart';
import '../../../widgets/layout/fade_through_branches.dart';
import '../../../widgets/spring_reveal.dart';
import 'reader_background.dart';

enum ReaderDockPane { outline, notes, askAi }

/// 阅读器右侧互斥停靠栏。开合交给 [SpringReveal]：只改外层裁切宽度，
/// 子树始终按 [sidebarWidth] 布局。
///
/// 传入 [onSidebarDragUpdate] 后，左缘分隔线变为可拖拽把手：9px 命中域 +
/// 居中 grabber，拖拽实时调 [sidebarWidth]（范围由 Responsive.clampReaderSidebarWidth 管）
class ReaderDockedPane extends StatefulWidget {
  final double sidebarWidth;
  final bool open;
  final bool animate;
  final ReaderDockPane pane;
  final Widget outline;
  final Widget notes;
  final Widget chat;
  final ValueChanged<DragUpdateDetails>? onSidebarDragUpdate;
  final VoidCallback? onSidebarDragEnd;
  final VoidCallback? onAnimationEnd;

  const ReaderDockedPane({
    super.key,
    required this.sidebarWidth,
    required this.open,
    this.animate = true,
    required this.pane,
    required this.outline,
    required this.notes,
    required this.chat,
    this.onSidebarDragUpdate,
    this.onSidebarDragEnd,
    this.onAnimationEnd,
  });

  @override
  State<ReaderDockedPane> createState() => _ReaderDockedPaneState();
}

class _ReaderDockedPaneState extends State<ReaderDockedPane> {
  final _mountedPanes = <ReaderDockPane>{};

  @override
  Widget build(BuildContext context) {
    final sidebarW = widget.sidebarWidth;
    final open = widget.open;
    if (open) _mountedPanes.add(widget.pane);
    final cs = Theme.of(context).colorScheme;

    Widget buildPaneContent() {
      return SizedBox(
        width: sidebarW,
        child: ColoredBox(
          color: cs.surfaceContainer,
          child: Row(
            children: [
              _DockResizeDivider(
                onDragUpdate: widget.onSidebarDragUpdate,
                onDragEnd: widget.onSidebarDragEnd,
              ),
              Expanded(
                child: ReaderLocalTheme(
                  child: SafeArea(
                    left: false,
                    right: false,
                    // 切换面板走 Material fade through（与主导航 tab 同一实现），
                    // 已挂载的面板常驻以保留状态；停靠栏收起时停掉全部 ticker。
                    child: TickerMode(
                      enabled: open,
                      child: FadeThroughBranches(
                        currentIndex: widget.pane.index,
                        children: [
                          for (final pane in ReaderDockPane.values)
                            if (_mountedPanes.contains(pane))
                              switch (pane) {
                                ReaderDockPane.outline => widget.outline,
                                ReaderDockPane.notes => widget.notes,
                                ReaderDockPane.askAi => widget.chat,
                              }
                            else
                              const SizedBox.shrink(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SpringReveal(
      open: open,
      animate: widget.animate,
      animateOnMount: true,
      onSettled: widget.onAnimationEnd,
      child: buildPaneContent(),
    );
  }
}

/// 停靠栏左缘分隔线。不可拖拽时仅为 1px 竖线；拖拽模式下扩为 9px 命中域
/// （视觉不变宽：线仍贴左缘，命中区向右探入 pane 背景），垂直居中常驻 4×32
/// grabber（沿用底栏 Grabber token），桌面 hover / 拖拽转 primary。
class _DockResizeDivider extends StatefulWidget {
  final ValueChanged<DragUpdateDetails>? onDragUpdate;
  final VoidCallback? onDragEnd;

  const _DockResizeDivider({this.onDragUpdate, this.onDragEnd});

  @override
  State<_DockResizeDivider> createState() => _DockResizeDividerState();
}

class _DockResizeDividerState extends State<_DockResizeDivider> {
  bool _hovering = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lineColor = cs.outlineVariant.withAlpha(AppDivider.kAlpha);

    if (widget.onDragUpdate == null) {
      return VerticalDivider(thickness: 1, width: 1, color: lineColor);
    }

    final active = _hovering || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragUpdate: widget.onDragUpdate,
        onHorizontalDragEnd: (_) {
          setState(() => _dragging = false);
          widget.onDragEnd?.call();
        },
        onHorizontalDragCancel: () => setState(() => _dragging = false),
        child: SizedBox(
          width: 9,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 1, color: lineColor),
              ),
              Center(
                child: AnimatedContainer(
                  duration: kAnimFast,
                  curve: kAnimCurve,
                  width: 4,
                  height: 32,
                  decoration: BoxDecoration(
                    color: active
                        ? cs.primary
                        : cs.onSurfaceVariant.withAlpha(80),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
