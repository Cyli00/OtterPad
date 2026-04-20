import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/collection/favorite.dart';
import '../../providers/documents_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/history_provider.dart';
import '../../router/app_routes.dart';
import 'widgets/library_menu_item.dart';
import 'widgets/favorite_card.dart';
import 'widgets/create_favorite_dialog.dart';
import 'package:material_symbols_icons/symbols.dart';

class ShelfPage extends ConsumerWidget {
  const ShelfPage({super.key});

  Future<void> _editFavorite(
    BuildContext context,
    WidgetRef ref,
    Favorite fav,
  ) async {
    final result = await showCreateFavoriteDialog(
      context,
      initialEmoji: fav.emoji,
      initialName: fav.name,
    );
    if (result != null) {
      ref.read(favoritesProvider.notifier).rename(
            fav.id,
            emoji: result['emoji'],
            name: result['name'],
          );
    }
  }

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
    final favorites = ref.watch(favoritesProvider);

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
                  icon: Symbols.cloud_sync,
                  title: '已同步',
                  onTap: () {},
                ),
                Consumer(
                  builder: (context, ref, _) {
                    final count = ref.watch(historyCountProvider);
                    return LibraryMenuItem(
                      icon: Symbols.history,
                      title: '阅读历史',
                      trailing: count > 0
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$count',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSecondaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : null,
                      onTap: () => context.push(AppRoutes.shelfHistory),
                    );
                  },
                ),
                Consumer(
                  builder: (context, ref, _) {
                    final count = ref.watch(noFileDocsCountProvider);
                    return LibraryMenuItem(
                      icon: Symbols.description,
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
                                  color: theme.colorScheme.error,
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
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Symbols.add),
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
                    itemCount: favorites.length,
                    itemBuilder: (context, index) {
                      final fav = favorites[index];
                      return FavoriteCard(
                        title: fav.name,
                        subtitle: '${fav.docPaths.length} 篇文献',
                        subtitleIcon: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: theme.colorScheme.primaryContainer,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            fav.emoji,
                            style: const TextStyle(fontSize: 13, height: 1.0),
                          ),
                        ),
                        pdfAssets: fav.docPaths,
                        totalCount: fav.docPaths.length,
                        onTap: () => _openDetail(context, fav),
                        onEdit: () => _editFavorite(context, ref, fav),
                        onDelete: fav.isDefault
                            ? null
                            : () => _confirmDelete(context, ref, fav),
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
