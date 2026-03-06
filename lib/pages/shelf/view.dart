import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/collection/favorite.dart';
import '../../providers/documents_provider.dart';
import '../../providers/favorites_provider.dart';
import 'widgets/library_menu_item.dart';
import 'widgets/favorite_card.dart';
import 'widgets/create_favorite_dialog.dart';
import 'favorite_detail_page.dart';

class ShelfPage extends ConsumerWidget {
  const ShelfPage({super.key});

  void _openDetail(BuildContext context, Favorite favorite) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FavoriteDetailPage(favorite: favorite),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final docs = ref.watch(documentsProvider);
    final allDocPaths = docs.map((d) => d.filePath).toList();
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
                  icon: Icons.cloud_upload_outlined,
                  title: '已同步',
                  onTap: () {},
                ),
                LibraryMenuItem(
                  icon: Icons.history, // 历史图标
                  title: '阅读历史',
                  onTap: () {},
                ),
                LibraryMenuItem(
                  icon: Icons.star_border, // 星标
                  title: '星标项目',
                  onTap: () {},
                ),
                
                // 思维导图先不要考虑
                // LibraryMenuItem(
                //   icon: Icons.account_tree_outlined,
                //   title: '思维导图',
                //   onTap: () {},
                // ),

                const SizedBox(height: 16),
                
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
