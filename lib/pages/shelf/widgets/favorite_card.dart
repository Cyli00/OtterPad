import 'package:flutter/material.dart';
import '../../library/widgets/pdf_cover.dart';

class FavoriteCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? subtitleIcon;
  final List<String> pdfAssets;
  final int totalCount;
  final VoidCallback onTap;

  const FavoriteCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.subtitleIcon,
    required this.pdfAssets,
    required this.totalCount,
    required this.onTap,
  });

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
    final count = pdfAssets.length;
    if (count <= 1) return 200.0;
    if (count == 2) return 330.0;
    if (count == 3) return 280.0;
    if (count == 4) return 200.0;
    return 330.0;
  }

  Widget _buildCoverArea(BuildContext context) {
    final count = pdfAssets.length;
    
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
          child: _buildCover(context, pdfAssets[0]),
        ),
      );
    } else if (count == 2) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 0.72,
              child: _buildCover(context, pdfAssets[0]),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AspectRatio(
              aspectRatio: 0.72,
              child: _buildCover(context, pdfAssets[1]),
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
              child: _buildCover(context, pdfAssets[0]),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 1,
            child: Column(
              children: [
                Expanded(child: _buildCover(context, pdfAssets[1])),
                const SizedBox(height: 4),
                Expanded(child: _buildCover(context, pdfAssets[2])),
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
                    Expanded(child: _buildCover(context, pdfAssets[0])),
                    const SizedBox(width: 4),
                    Expanded(child: _buildCover(context, pdfAssets[1])),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _buildCover(context, pdfAssets[2])),
                    const SizedBox(width: 4),
                    Expanded(child: _buildCover(context, pdfAssets[3])),
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
              child: _buildCover(context, pdfAssets[0]),
            ),
          ),
          const SizedBox(width: 6), // between big and small pattern
          Expanded(
            flex: 11,
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _buildCover(context, pdfAssets[1])),
                      const SizedBox(width: 3),
                      Expanded(child: _buildCover(context, pdfAssets[2])),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(child: _buildCover(context, pdfAssets[3])),
                      const SizedBox(width: 3),
                      Expanded(child: _buildCover(context, pdfAssets[4])),
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

    return Container(
      width: _getDynamicWidth(), // 动态宽度
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface, // 白色或者跟随主题的面色
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
            title,
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
              if (subtitleIcon != null) ...[
                subtitleIcon!,
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  subtitle,
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
          // 封面区域
          Expanded(
            child: _buildCoverArea(context),
          ),
          const SizedBox(height: 16),
          // 底部按钮
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withAlpha(128),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  '查看书单 · $totalCount 本书',
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
    );
  }
}
