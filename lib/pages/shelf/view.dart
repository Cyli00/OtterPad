import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/collection/favorite.dart';
import '../../providers/documents_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../router/app_routes.dart';
import 'widgets/library_menu_item.dart';
import 'widgets/favorite_card.dart';
import 'widgets/create_favorite_dialog.dart';

class ShelfPage extends ConsumerWidget {
  const ShelfPage({super.key});

  void _openDetail(BuildContext context, Favorite favorite) {
    context.push(AppRoutes.shelfFavorite, extra: favorite);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Favorite fav,
  ) async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除收藏夹'),
        content: Text('确定要删除「${fav.name}」吗？收藏夹内的文献不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(favoritesProvider.notifier).delete(fav.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final docs = ref.watch(documentsProvider);
    final allDocPaths =
        docs.map((d) => d.filePath).where((p) => p.isNotEmpty).toList();
    final favorites = ref.watch(favoritesProvider);

    // 默认文库：虚拟收藏夹，始终包含全部文档
    final defaultFavorite = Favorite(
      id: Favorite.defaultId,
      emoji: '\u{1F4DA}',
      name: '默认文库',
      docPaths: allDocPaths,
      createdAt: DateTime(2024),
    );

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                // 页面大标题
                Text(
                  '我的库',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 32),
                
                // 菜单列表项
                LibraryMenuItem(
                  icon: Icons.cloud_upload_rounded,
                  title: '已同步',
                  onTap: () {},
                ),
                LibraryMenuItem(
                  icon: Icons.history_rounded,
                  title: '阅读历史',
                  onTap: () {},
                ),
                LibraryMenuItem(
                  icon: Icons.star_outline_rounded,
                  title: '星标条目',
                  onTap: () {},
                ),
                Consumer(
                  builder: (context, ref, _) {
                    final count = ref.watch(noFileDocsCountProvider);
                    return LibraryMenuItem(
                      icon: Icons.description_outlined,
                      title: '无文件条目',
                      trailing: count > 0
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$count',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onErrorContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : null,
                      onTap: () =>
                          context.push(AppRoutes.shelfNoFileEntries),
                    );
                  },
                ),
                
                // 分割线
                Divider(
                  height: 32,
                  thickness: 1,
                  color: theme.colorScheme.outlineVariant.withAlpha(128),
                ),
                const SizedBox(height: 8),
                
                // 收藏夹标题与操作栏
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      '收藏夹',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${favorites.length + 1}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add),
                      color: theme.colorScheme.onSurfaceVariant,
                      onPressed: () async {
                        final result =
                            await showCreateFavoriteDialog(context);
                        if (result != null) {
                          ref.read(favoritesProvider.notifier).create(
                                emoji: result['emoji']!,
                                name: result['name']!,
                              );
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // 水平滚动的卡片列表
                SizedBox(
                  height: 380,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    itemCount: favorites.length + 1, // +1 默认文库
                    itemBuilder: (context, index) {
                      // 第一项始终是默认文库
                      if (index == 0) {
                        return FavoriteCard(
                          title: defaultFavorite.name,
                          subtitle: '包含所有文献',
                          subtitleIcon: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: theme.colorScheme.primaryContainer,
                            ),
                            child: Icon(
                              Icons.menu_book_rounded,
                              size: 14,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          pdfAssets: allDocPaths,
                          totalCount: docs.length,
                          onTap: () => _openDetail(context, defaultFavorite),
                        );
                      }

                      final fav = favorites[index - 1];
                      return FavoriteCard(
                        title: fav.name,
                        subtitle: '${fav.docPaths.length} 篇文献',
                        subtitleIcon: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.colorScheme.primaryContainer,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            fav.emoji,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        pdfAssets: fav.docPaths,
                        totalCount: fav.docPaths.length,
                        onTap: () => _openDetail(context, fav),
                        onDelete: () => _confirmDelete(context, ref, fav),
                      );
                    },
                  ),
                ),
                
                const SizedBox(height: 32), // 底部留白
              ],
            ),
          ),
        ),
      ),
    );
  }
}
