import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import '../../data/models/book/document.dart';
import '../../data/models/collection/favorite.dart';
import '../../providers/documents_provider.dart';
import '../../router/app_routes.dart';
import '../library/widgets/doc_card_actions.dart';
import '../library/widgets/doc_list_card.dart';

/// 收藏夹详情页：展示书单内所有文献
class FavoriteDetailPage extends ConsumerWidget {
  final Favorite favorite;

  const FavoriteDetailPage({super.key, required this.favorite});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final docs = ref.watch(documentsProvider);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        title: Text(
          favorite.name,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          // 文献列表
          if (favorite.docPaths.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.menu_book_outlined,
                      size: 64,
                      color: colorScheme.onSurfaceVariant.withAlpha(80),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '暂无文献',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.separated(
                itemCount: favorite.docPaths.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final docPath = favorite.docPaths[index];
                  final doc = docs
                          .where((d) => d.filePath == docPath)
                          .firstOrNull ??
                      Document(
                        id: '',
                        title: p.basenameWithoutExtension(docPath),
                        authors: [],
                        filePath: docPath,
                        addedAt: DateTime.now(),
                      );

                  return DocListCard(
                    doc: doc,
                    onTap: () => DocCardActions.openReader(context, doc),
                    onDelete: doc.id.isNotEmpty
                        ? () => DocCardActions.delete(ref, doc.id)
                        : null,
                    onBatchDelete: doc.id.isNotEmpty
                        ? () => context.push(
                              AppRoutes.libraryBatchDelete,
                              extra: <String, String?>{
                                'favoriteId': favorite.id,
                                'initialSelectedId': doc.id,
                              },
                            )
                        : null,
                  );
                },
              ),
            ),

          // 底部留白
          const SliverToBoxAdapter(
            child: SizedBox(height: 32),
          ),
        ],
      ),
    );
  }
}
