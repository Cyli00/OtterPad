import 'package:flutter/material.dart';

import '../core/animation_constants.dart';
import '../core/design_tokens.dart';

/// Folio 图标按钮：透明底 + 1px 细线方框（6 圆角），悬停时细线加深、底色微染。
///
/// 替代原来的 `IconButton.filled(primaryContainer, CircleBorder)`：
/// 页面上的工具按钮不再抢刊头的戏。
class RuleIconButton extends StatefulWidget {
  const RuleIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 36,
    this.selected = false,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;

  /// 选中态（如当前视图）：墨色反白。
  final bool selected;

  /// 破坏性操作（删除）：图标用错误色，细线不变。
  final bool danger;

  @override
  State<RuleIconButton> createState() => _RuleIconButtonState();
}

class _RuleIconButtonState extends State<RuleIconButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null;
    final bg = widget.selected
        ? cs.inverseSurface
        : _down
        ? cs.onSurface.withAlpha(20)
        : _hover
        ? cs.onSurface.withAlpha(10)
        : Colors.transparent;
    final border = widget.selected
        ? cs.inverseSurface
        : (_hover || _down)
        ? AppStroke.ruleStrong(cs)
        : AppStroke.rule(cs);
    final fg = widget.selected
        ? cs.onInverseSurface
        : !enabled
        ? cs.onSurface.withAlpha(97)
        : widget.danger
        ? cs.error
        : cs.onSurface;

    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.tooltip,
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled ? (_) => setState(() => _down = true) : null,
            onTapUp: enabled ? (_) => setState(() => _down = false) : null,
            onTapCancel: enabled ? () => setState(() => _down = false) : null,
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: kAnimFast,
              curve: kAnimCurve,
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: AppRadius.smAll,
                border: Border.all(color: border, width: AppStroke.hairline),
              ),
              alignment: Alignment.center,
              child: Icon(widget.icon, size: widget.size * 0.5, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}
