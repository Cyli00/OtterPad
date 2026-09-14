import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'l10n.dart';

class PaperFavoriteCard extends StatefulWidget {
  const PaperFavoriteCard({
    super.key,
    required this.title,
    required this.count,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    this.identity = Symbols.book,
  });
  final String title;
  final int count;
  final IconData identity;
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
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: l.demoFavoriteMenu,
                      onPressed: () => controller.isOpen
                          ? controller.close()
                          : controller.open(),
                      icon: const Icon(Symbols.more_horiz),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Icon(widget.identity, size: 22, weight: 350),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l.demoPaperCount(widget.count),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
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
                      height: 216,
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
