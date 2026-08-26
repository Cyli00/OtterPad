import 'package:flutter/material.dart';

class AppContextMenuItem<T> {
  const AppContextMenuItem({
    required this.value,
    required this.label,
    required this.icon,
    this.destructive = false,
  });

  final T value;
  final String label;
  final IconData icon;
  final bool destructive;
}

/// 与 FavoriteCard 长按菜单像素对齐的弹出菜单。
Future<T?> showAppContextMenu<T>({
  required BuildContext context,
  required Offset globalPosition,
  required List<AppContextMenuItem<T>> items,
}) {
  if (items.isEmpty) return Future<T?>.value();
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final local = overlay.globalToLocal(globalPosition);
  final cs = Theme.of(context).colorScheme;
  final textTheme = Theme.of(context).textTheme;
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromLTRB(
      local.dx,
      local.dy,
      overlay.size.width - local.dx,
      overlay.size.height - local.dy,
    ),
    color: cs.surfaceContainerHigh,
    elevation: 3,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    items: [
      for (final item in items)
        PopupMenuItem<T>(
          value: item.value,
          height: 44,
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 20,
                color: item.destructive ? cs.error : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 14),
              Text(
                item.label,
                style: textTheme.bodyMedium?.copyWith(
                  color: item.destructive ? cs.error : cs.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
