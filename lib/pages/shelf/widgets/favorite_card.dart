import 'package:flutter/material.dart';
import '../../library/widgets/pdf_cover.dart';

class FavoriteCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final Widget? subtitleIcon;
  final List<String> pdfAssets;
  final int totalCount;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const FavoriteCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.subtitleIcon,
    required this.pdfAssets,
    required this.totalCount,
    required this.onTap,
    this.onDelete,
  });

  @override
  State<FavoriteCard> createState() => _FavoriteCardState();
}

class _FavoriteCardState extends State<FavoriteCard> {
  bool _showDelete = false;

  Widget _buildEmptyCoverLayer(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.picture_as_pdf,
          color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(100),
          size: 24,
        ),
      ),
    );
  }

  Widget _buildCover(BuildContext context, String? assetPath) {
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
      child: assetPath != null && assetPath.isNotEmpty
          ? PdfCoverRender(assetPath: assetPath)
          : _buildEmptyCoverLayer(context),
    );
  }

  double _getDynamicWidth() {
    final count = widget.pdfAssets.length;
    if (count <= 1) return 200.0;
    if (count == 2) return 330.0;
    if (count == 3) return 280.0;
    if (count == 4) return 200.0;
    return 330.0;
  }

  Widget _buildCoverArea(BuildContext context) {
    final count = widget.pdfAssets.length;

    if (count == 0) {
      return Center(
        child: AspectRatio(
          aspectRatio: 0.72,
          child: _buildEmptyCoverLayer(context),
        ),
      );
    } else if (count == 1) {
      return Center(
        child: AspectRatio(
          aspectRatio: 0.72,
          child: _buildCover(context, widget.pdfAssets[0]),
        ),
      );
    } else if (count == 2) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 0.72,
              child: _buildCover(context, widget.pdfAssets[0]),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AspectRatio(
              aspectRatio: 0.72,
              child: _buildCover(context, widget.pdfAssets[1]),
            ),
          ),
        ],
      );
    } else if (count == 3) {
      return Row(
        children: [
          Expanded(
            flex: 2,
            child: AspectRatio(
              aspectRatio: 0.72,
              child: _buildCover(context, widget.pdfAssets[0]),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 1,
            child: Column(
              children: [
                Expanded(child: _buildCover(context, widget.pdfAssets[1])),
                const SizedBox(height: 4),
                Expanded(child: _buildCover(context, widget.pdfAssets[2])),
              ],
            ),
          ),
        ],
      );
    } else if (count == 4) {
      return Center(
        child: AspectRatio(
          aspectRatio: 0.72,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _buildCover(context, widget.pdfAssets[0])),
                    const SizedBox(width: 4),
                    Expanded(child: _buildCover(context, widget.pdfAssets[1])),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _buildCover(context, widget.pdfAssets[2])),
                    const SizedBox(width: 4),
                    Expanded(child: _buildCover(context, widget.pdfAssets[3])),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // count >= 5
      return Row(
        children: [
          Expanded(
            flex: 12,
            child: AspectRatio(
              aspectRatio: 0.72,
              child: _buildCover(context, widget.pdfAssets[0]),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 11,
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                          child: _buildCover(context, widget.pdfAssets[1])),
                      const SizedBox(width: 3),
                      Expanded(
                          child: _buildCover(context, widget.pdfAssets[2])),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                          child: _buildCover(context, widget.pdfAssets[3])),
                      const SizedBox(width: 3),
                      Expanded(
                          child: _buildCover(context, widget.pdfAssets[4])),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: GestureDetector(
        onLongPress: widget.onDelete != null
            ? () => setState(() => _showDelete = !_showDelete)
            : null,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: _getDynamicWidth(),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(13),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (widget.subtitleIcon != null) ...[
                        widget.subtitleIcon!,
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          widget.subtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _buildCoverArea(context),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: widget.onTap,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color:
                            colorScheme.surfaceContainerHighest.withAlpha(128),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          '查看文库 · ${widget.totalCount} 篇文献',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.onDelete != null)
              Positioned(
                top: -8,
                right: -8,
                child: AnimatedScale(
                  scale: _showDelete ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutBack,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onDelete,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: Material(
                          color: colorScheme.error,
                          shape: const CircleBorder(),
                          elevation: 2,
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: Icon(
                              Icons.remove,
                              size: 18,
                              color: colorScheme.onError,
                            ),
                          ),
                        ),
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
}
