import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'l10n.dart';

/// 收藏夹卡片头部：标题行（含更多操作）与 emoji＋篇数身份行。
///
/// 卡片本身与收藏夹编辑器的效果预览共用同一实现，避免预览再画一份。
class PaperFavoriteHeader extends StatelessWidget {
  const PaperFavoriteHeader({
    super.key,
    required this.title,
    required this.count,
    this.emoji = '\u{1F4DA}',
    this.titleColor,
    this.onMenu,
  });
  final String title;
  final int count;
  final String emoji;
  final Color? titleColor;

  /// 为空时只画更多操作图标：预览里它是示意，不提供菜单。
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: titleColor ?? cs.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onMenu == null)
              ExcludeSemantics(
                child: Icon(Symbols.more_horiz, color: cs.onSurfaceVariant),
              )
            else
              IconButton(
                tooltip: l.demoFavoriteMenu,
                onPressed: onMenu,
                icon: const Icon(Symbols.more_horiz),
              ),
          ],
        ),
        Row(
          children: [
            // 与生产收藏夹卡片一致：emoji 放在 primaryContainer 小徽标里。
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                emoji,
                style: const TextStyle(fontSize: 13, height: 1.0),
                strutStyle: const StrutStyle(
                  forceStrutHeight: true,
                  height: 1.0,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l.demoPaperCount(count),
                style: theme.textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class PaperFavoriteCard extends StatefulWidget {
  const PaperFavoriteCard({
    super.key,
    required this.title,
    required this.count,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    this.emoji = '\u{1F4DA}',
  });
  final String title;
  final int count;
  final String emoji;
  final VoidCallback onOpen, onEdit, onDelete;
  @override
  State<PaperFavoriteCard> createState() => _PaperFavoriteCardState();
}

class _PaperFavoriteCardState extends State<PaperFavoriteCard> {
  final _menu = MenuController();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = context.l10n;
    return MenuAnchor(
      controller: _menu,
      menuChildren: [
        MenuItemButton(
          onPressed: widget.onEdit,
          leadingIcon: const Icon(Symbols.edit),
          child: Text(l.editFavorite),
        ),
        MenuItemButton(
          onPressed: widget.onDelete,
          leadingIcon: Icon(Symbols.delete, color: cs.error),
          child: Text(l.delete),
        ),
      ],
      builder: (context, controller, _) => GestureDetector(
        onSecondaryTapDown: (_) => controller.open(),
        child: Material(
          color: cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cs.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PaperFavoriteHeader(
                  title: widget.title,
                  count: widget.count,
                  emoji: widget.emoji,
                  onMenu: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                ),
                const SizedBox(height: 16),
                Semantics(
                  button: true,
                  label: l.viewLibraryTotal(widget.count),
                  child: InkWell(
                    onTap: widget.onOpen,
                    onLongPress: () => controller.open(),
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 180,
                      width: double.infinity,
                      child: ExcludeSemantics(child: _covers(context)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: widget.onOpen,
                    child: Text(
                      l.viewLibraryTotal(widget.count),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cover(BuildContext context, int index) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(3),
      ),
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(
        builder: (context, c) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Symbols.description,
              size: c.maxWidth < 60 ? 14 : 20,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Container(height: 3, width: c.maxWidth * .82, color: cs.outline),
            const SizedBox(height: 5),
            Container(height: 3, width: c.maxWidth * .6, color: cs.outline),
            if (c.maxHeight > 100) ...[
              const SizedBox(height: 14),
              Container(
                height: c.maxHeight * .25,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  border: Border.all(color: cs.outlineVariant),
                ),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Container(
                    height: 2,
                    width: c.maxWidth * (i == 2 ? .55 : 1),
                    color: cs.outlineVariant,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _covers(BuildContext context) {
    final count = widget.count;
    if (count == 0)
      return Center(
        child: AspectRatio(
          aspectRatio: .72,
          child: Container(
            color: Theme.of(context).colorScheme.surface,
            child: Icon(
              Symbols.picture_as_pdf,
              size: 28,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
      );
    if (count == 1)
      return Center(
        child: AspectRatio(aspectRatio: .72, child: _cover(context, 0)),
      );
    if (count == 2)
      return Row(
        children: [
          for (var i = 0; i < 2; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: AspectRatio(aspectRatio: .72, child: _cover(context, i)),
            ),
          ],
        ],
      );
    if (count == 3)
      return Row(
        children: [
          Expanded(flex: 2, child: _cover(context, 0)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              children: [
                Expanded(child: _cover(context, 1)),
                const SizedBox(height: 4),
                Expanded(child: _cover(context, 2)),
              ],
            ),
          ),
        ],
      );
    Widget grid(int start) => Column(
      children: [
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: 4),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _cover(context, start + row * 2)),
                const SizedBox(width: 4),
                Expanded(child: _cover(context, start + row * 2 + 1)),
              ],
            ),
          ),
        ],
      ],
    );
    if (count == 4)
      return Center(child: AspectRatio(aspectRatio: .72, child: grid(0)));
    return Row(
      children: [
        Expanded(flex: 12, child: _cover(context, 0)),
        const SizedBox(width: 6),
        Expanded(flex: 11, child: grid(1)),
      ],
    );
  }
}
