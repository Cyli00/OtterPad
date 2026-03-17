import 'package:flutter/material.dart';

/// 在选区下方显示阅读工具栏 Overlay。
///
/// 优先在 [anchorBelow] 正下方展示，空间不足时退到 [anchorAbove] 上方。
OverlayEntry showReadingToolbar({
  required BuildContext context,
  required Offset anchorAbove,
  required Offset anchorBelow,
  required List<ReadingToolbarAction> actions,
  VoidCallback? onDismiss,
}) {
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) {
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                entry.remove();
                onDismiss?.call();
              },
            ),
          ),
          CustomSingleChildLayout(
            delegate: _BelowPreferredDelegate(
              anchorAbove: anchorAbove,
              anchorBelow: anchorBelow,
            ),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 6 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: _ToolbarBar(
                actions: actions,
                onActionTap: () {
                  entry.remove();
                  onDismiss?.call();
                },
              ),
            ),
          ),
        ],
      );
    },
  );
  Overlay.of(context).insert(entry);
  return entry;
}

class ReadingToolbarAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const ReadingToolbarAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class _ToolbarBar extends StatelessWidget {
  final List<ReadingToolbarAction> actions;
  final VoidCallback onActionTap;

  const _ToolbarBar({required this.actions, required this.onActionTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      color: const Color(0xF0303030),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: actions.map((action) {
            return _ToolbarButton(
              action: action,
              onActionTap: onActionTap,
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  final ReadingToolbarAction action;
  final VoidCallback onActionTap;

  const _ToolbarButton({required this.action, required this.onActionTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        action.onTap();
        onActionTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(action.icon, color: Colors.white, size: 22),
            const SizedBox(height: 2),
            Text(
              action.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 优先在 [anchorBelow] 下方放置工具栏，空间不足时退回 [anchorAbove] 上方。
class _BelowPreferredDelegate extends SingleChildLayoutDelegate {
  final Offset anchorAbove;
  final Offset anchorBelow;

  _BelowPreferredDelegate({
    required this.anchorAbove,
    required this.anchorBelow,
  });

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return constraints.loosen();
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    // 优先放在 anchorBelow 下方
    if (anchorBelow.dy + childSize.height <= size.height) {
      return Offset(
        (anchorBelow.dx - childSize.width / 2)
            .clamp(0.0, size.width - childSize.width),
        anchorBelow.dy,
      );
    }
    // 空间不足时放在 anchorAbove 上方
    return Offset(
      (anchorAbove.dx - childSize.width / 2)
          .clamp(0.0, size.width - childSize.width),
      (anchorAbove.dy - childSize.height)
          .clamp(0.0, size.height - childSize.height),
    );
  }

  @override
  bool shouldRelayout(_BelowPreferredDelegate oldDelegate) {
    return anchorAbove != oldDelegate.anchorAbove ||
        anchorBelow != oldDelegate.anchorBelow;
  }
}
