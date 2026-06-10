import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/collection/favorite.dart';
import '../../services/haptics.dart';
import '../../widgets/app_dialog.dart';
import '../../providers/documents_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/history_provider.dart';
import '../../router/app_routes.dart';
import '../../utils/doc_paths.dart';
import 'widgets/library_menu_item.dart';
import 'widgets/favorite_card.dart';
import 'widgets/create_favorite_dialog.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/l10n.dart';

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
      ref
          .read(favoritesProvider.notifier)
          .rename(fav.id, emoji: result['emoji'], name: result['name']);
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
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        title: Text(context.l10n.deleteFavorite),
        content: Text(context.l10n.confirmDeleteFavorite(fav.name)),
        actions: [
          TextButton(
            onPressed: () {
              Haptics.soft();
              Navigator.of(context).pop(false);
            },
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Haptics.soft();
              Navigator.of(context).pop(true);
            },
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: Text(context.l10n.delete),
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
    final docs = ref.watch(documentsProvider);
    final historyCount = ref.watch(historyCountProvider);
    final noFileCount = ref.watch(noFileDocsCountProvider);
    final byId = {for (final doc in docs) doc.id: doc};

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 16.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                // 页面大标题
                Text(
                  context.l10n.myLibrary,
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 32),

                // 菜单列表项
                LibraryMenuItem(
                  icon: Symbols.cloud_sync_rounded,
                  title: context.l10n.synced,
                  onTap: () {},
                ),
                LibraryMenuItem(
                  icon: Symbols.history_rounded,
                  title: context.l10n.readingHistory,
                  trailing: historyCount > 0
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
                            '$historyCount',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : null,
                  onTap: () => context.push(AppRoutes.shelfHistory),
                ),
                LibraryMenuItem(
                  icon: Symbols.description_rounded,
                  title: context.l10n.noFileEntries,
                  trailing: noFileCount > 0
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
                            '$noFileCount',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : null,
                  onTap: () => context.push(AppRoutes.shelfNoFileEntries),
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
                      context.l10n.favorites,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Symbols.add_rounded),
                      color: theme.colorScheme.onSurfaceVariant,
                      onPressed: () async {
                        Haptics.soft();
                        final result = await showCreateFavoriteDialog(context);
                        if (result != null) {
                          ref
                              .read(favoritesProvider.notifier)
                              .create(
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
                      final pdfAssets = [
                        for (final documentId in fav.documentIds)
                          if (byId[documentId]?.contentHash != null)
                            DocPaths.pdf(documentId),
                      ];
                      return FavoriteCard(
                        title: fav.name,
                        subtitle: context.l10n.favoriteDocumentCount(fav.documentIds.length),
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
                        pdfAssets: pdfAssets,
                        totalCount: fav.documentIds.length,
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
