import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/animation_constants.dart';
import '../../../core/l10n.dart';
import '../../../services/haptics.dart';

/// 在 [child]（封面/整卡）上悬停时，于右上角显示 [bar]。
class HoverActions extends StatefulWidget {
  const HoverActions({
    super.key,
    required this.child,
    required this.bar,
    this.padding = const EdgeInsets.all(6),
  });

  final Widget child;
  final Widget bar;
  final EdgeInsets padding;

  @override
  State<HoverActions> createState() => _HoverActionsState();
}

class _HoverActionsState extends State<HoverActions> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          Positioned(
            top: widget.padding.top,
            right: widget.padding.right,
            child: AnimatedOpacity(
              opacity: _hover ? 1 : 0,
              duration: kAnimFast,
              curve: kAnimCurve,
              child: IgnorePointer(ignoring: !_hover, child: widget.bar),
            ),
          ),
        ],
      ),
    );
  }
}

class DocHoverButtons extends StatelessWidget {
  const DocHoverButtons({super.key, this.onFavorite, this.onMore});

  final VoidCallback? onFavorite;
  final void Function(Offset globalPosition)? onMore;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onFavorite != null)
          _HoverIconButton(
            icon: Symbols.bookmark_add_rounded,
            tooltip: l10n.addToFavorite,
            onPressed: (_) {
              Haptics.soft();
              onFavorite!();
            },
          ),
        if (onFavorite != null && onMore != null) const SizedBox(width: 4),
        if (onMore != null)
          _HoverIconButton(
            icon: Symbols.more_vert_rounded,
            tooltip: l10n.more,
            onPressed: (pos) {
              Haptics.soft();
              onMore!(pos);
            },
          ),
      ],
    );
  }
}

class _HoverIconButton extends StatelessWidget {
  const _HoverIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final void Function(Offset globalPosition) onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton.filled(
        onPressed: () {
          final box = context.findRenderObject() as RenderBox?;
          final pos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
          onPressed(pos);
        },
        tooltip: tooltip,
        icon: Icon(icon, size: 16),
        style: IconButton.styleFrom(
          backgroundColor: cs.surfaceContainerHigh.withAlpha(230),
          foregroundColor: cs.onSurface,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
