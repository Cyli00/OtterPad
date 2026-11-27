import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/collection/favorite.dart';
import '../../services/haptics.dart';
import '../../widgets/app_dialog.dart';
import '../../providers/documents_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/history_provider.dart';
import '../../providers/sync_status_provider.dart';
import '../../router/app_routes.dart';
import '../../utils/doc_paths.dart';
import '../../utils/responsive.dart';
import '../../widgets/masthead.dart';
import '../../widgets/rule_icon_button.dart';
import '../../widgets/staggered_entrance.dart';
import 'widgets/library_menu_item.dart';
import 'widgets/favorite_card.dart';
import 'widgets/create_favorite_dialog.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/l10n.dart';
import '../../core/design_tokens.dart';

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
      await ref
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
      await ref.read(favoritesProvider.notifier).delete(fav.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final favorites = ref.watch(favoritesProvider).value ?? const [];
    final docs = ref.watch(documentsProvider).value ?? const [];
    final historyCount = ref.watch(historyCountProvider);
    final noFileCount = ref.watch(noFileDocsCountProvider);
    final byId = {for (final doc in docs) doc.id: doc};

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpace.pageGutter(context),
              Responsive.showNavigationRail(context)
                  ? AppSpace.x6
                  : AppSpace.x2,
              AppSpace.pageGutter(context),
              AppSpace.x4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 刊头：衬线大标题 + 文献总数（数字滚动）；云同步 / 设置在右
                Masthead(
                  title: context.l10n.myLibrary,
                  count: docs.length,
                  countLabel: context.l10n.favoriteDocumentCount,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _CloudSyncButton(),
                      if (!Responsive.showNavigationRail(context)) ...[
                        const SizedBox(width: AppSpace.x2),
                        RuleIconButton(
                          icon: Symbols.settings_rounded,
                          tooltip: context.l10n.settings,
                          onPressed: () {
                            Haptics.soft();
                            context.push(AppRoutes.settingsOverlay);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.x8),

                // 目录：细线分隔的条目
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(top: AppStroke.side(theme.colorScheme)),
                  ),
                  child: Column(
                    children: [
                      LibraryMenuItem(
                        icon: Symbols.history_rounded,
                        title: context.l10n.readingHistory,
                        count: historyCount,
                        onTap: () => context.push(AppRoutes.shelfHistory),
                      ),
                      LibraryMenuItem(
                        icon: Symbols.description_rounded,
                        title: context.l10n.noFileEntries,
                        count: noFileCount,
                        alert: true,
                        onTap: () => context.push(AppRoutes.shelfNoFileEntries),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.x12),

                // 收藏夹：眉题 + 新建
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      eyebrowText(context.l10n.favorites),
                      style: AppType.eyebrow(context),
                    ),
                    const SizedBox(width: AppSpace.x2),
                    Text(
                      '${favorites.length}',
                      style: AppType.eyebrow(
                        context,
                      ).copyWith(fontFeatures: AppType.tabular),
                    ),
                    const Spacer(),
                    RuleIconButton(
                      icon: Symbols.add_rounded,
                      tooltip: context.l10n.createFavorite,
                      size: 32,
                      onPressed: () async {
                        Haptics.soft();
                        final result = await showCreateFavoriteDialog(context);
                        if (result != null) {
                          await ref
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
                const SizedBox(height: AppSpace.x4),

                LayoutBuilder(
                  builder: (context, constraints) {
                    final maxW = constraints.maxWidth;
                    FavoriteCard cardFor(Favorite fav) {
                      final pdfAssets = [
                        for (final documentId in fav.documentIds)
                          if (byId[documentId]?.contentHash != null)
                            DocPaths.pdf(documentId),
                      ];
                      return FavoriteCard(
                        title: fav.name,
                        subtitle: context.l10n.favoriteDocumentCount(
                          fav.documentIds.length,
                        ),
                        subtitleIcon: Text(
                          fav.emoji,
                          style: const TextStyle(fontSize: 15, height: 1.0),
                        ),
                        pdfAssets: pdfAssets,
                        totalCount: fav.documentIds.length,
                        maxWidth: maxW,
                        margin: maxW >= 900
                            ? EdgeInsets.zero
                            : const EdgeInsets.only(right: 16),
                        onTap: () => _openDetail(context, fav),
                        onEdit: () => _editFavorite(context, ref, fav),
                        onDelete: fav.isDefault
                            ? null
                            : () => _confirmDelete(context, ref, fav),
                      );
                    }

                    if (maxW >= 900) {
                      return Wrap(
                        spacing: AppSpace.x4,
                        runSpacing: Responsive.compactDensity(context)
                            ? AppSpace.x3
                            : AppSpace.x4,
                        children: [
                          for (var i = 0; i < favorites.length; i++)
                            StaggeredEntrance(
                              index: i,
                              child: cardFor(favorites[i]),
                            ),
                        ],
                      );
                    }
                    return SizedBox(
                      height: 380,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        itemCount: favorites.length,
                        itemBuilder: (context, index) => StaggeredEntrance(
                          index: index,
                          child: cardFor(favorites[index]),
                        ),
                      ),
                    );
                  },
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

/// 云同步入口按钮——图标本身就是状态指示器：
/// 未配置远端 = cloud_off；有变更未备份 = cloud_sync + 角标点；
/// 全部已备份 = cloud_done；状态计算中 = 静默云图标。
class _CloudSyncButton extends ConsumerWidget {
  const _CloudSyncButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final status = ref.watch(syncStatusProvider);

    final (icon, showBadge) = status.maybeWhen(
      data: (result) => !result.remoteConfigured
          ? (Symbols.cloud_off_rounded, false)
          : result.hasPendingChanges
          ? (Symbols.cloud_sync_rounded, true)
          : (Symbols.cloud_done_rounded, false),
      orElse: () => (Symbols.cloud_rounded, false),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        RuleIconButton(
          icon: icon,
          tooltip: context.l10n.cloudSync,
          onPressed: () {
            Haptics.soft();
            context.push(AppRoutes.shelfCloudSync);
          },
        ),
        if (showBadge)
          Positioned(
            top: -3,
            right: -3,
            child: IgnorePointer(
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.surface, width: 2),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
