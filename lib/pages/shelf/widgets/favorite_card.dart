import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/l10n.dart';
import '../../../services/haptics.dart';
import '../../../widgets/tactile_press.dart';
import '../../library/widgets/pdf_cover.dart';

class FavoriteCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? subtitleIcon;
  final List<String> pdfAssets;
  final int totalCount;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const FavoriteCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.subtitleIcon,
    required this.pdfAssets,
    required this.totalCount,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasMenu = onEdit != null || onDelete != null;

    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: GestureDetector(
        onLongPressStart: hasMenu
            ? (d) => _showCardMenu(context, d.globalPosition, cs)
            : null,
        child: Container(
          width: _getDynamicWidth(),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(13),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TactilePress(
            baseColor: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            pressedScale: 0.98,
            onTap: onTap,
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (subtitleIcon != null) ...[
                    subtitleIcon!,
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(child: _buildCoverArea(context)),
              const SizedBox(height: 16),
              InkWell(
                onTap: () {
                  Haptics.soft();
                  onTap();
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withAlpha(128),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      context.l10n.viewLibraryTotal(totalCount),
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                      ),
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
    );
  }

  void _showCardMenu(
      BuildContext context, Offset position, ColorScheme cs) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      color: cs.surfaceContainerHigh,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        if (onEdit != null)
          PopupMenuItem<String>(
            value: 'edit',
            height: 44,
            child: Row(
              children: [
                Icon(Symbols.edit_rounded, size: 20, color: cs.onSurfaceVariant),
                const SizedBox(width: 14),
                Text(context.l10n.edit,
                    style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        if (onDelete != null)
          PopupMenuItem<String>(
            value: 'delete',
            height: 44,
            child: Row(
              children: [
                Icon(Symbols.delete_rounded, size: 20, color: cs.error),
                const SizedBox(width: 14),
                Text(context.l10n.delete,
                    style: TextStyle(
                        color: cs.error,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
      ],
    );
    if (result == 'edit') onEdit?.call();
    if (result == 'delete') onDelete?.call();
  }

  // ── 封面布局 ──

  double _getDynamicWidth() {
    final count = pdfAssets.length;
    if (count <= 1) return 200.0;
    if (count == 2) return 330.0;
    if (count == 3) return 280.0;
    if (count == 4) return 200.0;
    return 330.0;
  }

  Widget _emptyCover(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(Symbols.picture_as_pdf_rounded,
            color: cs.onSurfaceVariant.withAlpha(100), size: 24),
      ),
    );
  }

  Widget _cover(BuildContext context, String? path) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 4,
            offset: const Offset(2, 2),
          ),
        ],
      ),
      child: path != null && path.isNotEmpty
          ? PdfCoverRender(assetPath: path)
          : _emptyCover(context),
    );
  }

  Widget _buildCoverArea(BuildContext context) {
    final count = pdfAssets.length;
    if (count == 0) {
      return Center(
          child: AspectRatio(
              aspectRatio: 0.72, child: _emptyCover(context)));
    }
    if (count == 1) {
      return Center(
          child: AspectRatio(
              aspectRatio: 0.72, child: _cover(context, pdfAssets[0])));
    }
    if (count == 2) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
              child: AspectRatio(
                  aspectRatio: 0.72, child: _cover(context, pdfAssets[0]))),
          const SizedBox(width: 8),
          Expanded(
              child: AspectRatio(
                  aspectRatio: 0.72, child: _cover(context, pdfAssets[1]))),
        ],
      );
    }
    if (count == 3) {
      return Row(children: [
        Expanded(
            flex: 2,
            child: AspectRatio(
                aspectRatio: 0.72, child: _cover(context, pdfAssets[0]))),
        const SizedBox(width: 6),
        Expanded(
            flex: 1,
            child: Column(children: [
              Expanded(child: _cover(context, pdfAssets[1])),
              const SizedBox(height: 4),
              Expanded(child: _cover(context, pdfAssets[2])),
            ])),
      ]);
    }
    if (count == 4) {
      return Center(
        child: AspectRatio(
          aspectRatio: 0.72,
          child: Column(children: [
            Expanded(
                child: Row(children: [
              Expanded(child: _cover(context, pdfAssets[0])),
              const SizedBox(width: 4),
              Expanded(child: _cover(context, pdfAssets[1])),
            ])),
            const SizedBox(height: 4),
            Expanded(
                child: Row(children: [
              Expanded(child: _cover(context, pdfAssets[2])),
              const SizedBox(width: 4),
              Expanded(child: _cover(context, pdfAssets[3])),
            ])),
          ]),
        ),
      );
    }
    // count >= 5
    return Row(children: [
      Expanded(
          flex: 12,
          child: AspectRatio(
              aspectRatio: 0.72, child: _cover(context, pdfAssets[0]))),
      const SizedBox(width: 6),
      Expanded(
          flex: 11,
          child: Column(children: [
            Expanded(
                child: Row(children: [
              Expanded(child: _cover(context, pdfAssets[1])),
              const SizedBox(width: 3),
              Expanded(child: _cover(context, pdfAssets[2])),
            ])),
            const SizedBox(height: 3),
            Expanded(
                child: Row(children: [
              Expanded(child: _cover(context, pdfAssets[3])),
              const SizedBox(width: 3),
              Expanded(child: _cover(context, pdfAssets[4])),
            ])),
          ])),
    ]);
  }
}
