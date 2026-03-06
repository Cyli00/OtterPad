import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/book/document.dart';
import '../../../providers/documents_provider.dart';
import '../../library/widgets/pdf_cover.dart';

/// 文献库列表视图（类似收藏夹详情页的排版，但无标题头）
class BookshelfList extends ConsumerWidget {
  const BookshelfList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(documentsProvider);

    if (docs.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Center(child: Text('暂无文献')),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      sliver: SliverList.separated(
        itemCount: docs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final doc = docs[index];
          return _DocListCard(doc: doc);
        },
      ),
    );
  }
}

class _DocListCard extends StatelessWidget {
  final Document doc;

  const _DocListCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          // TODO: 跳转到 PDF 阅读器
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧 PDF 缩略图
              if (doc.filePath.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 100,
                    height: 140,
                    child: PdfCoverRender(
                            assetPath: doc.filePath,
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
              const SizedBox(width: 16),
              // 右侧文献信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      doc.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                        height: 1.3,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (doc.authors.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        doc.authors.join(', '),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (doc.journal != null &&
                        doc.journal!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        doc.journal!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant
                              .withAlpha(180),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (doc.year != null && doc.year!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        doc.year!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant
                              .withAlpha(140),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
