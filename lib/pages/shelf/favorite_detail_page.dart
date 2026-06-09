import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/book/document.dart';
import '../../services/haptics.dart';
import '../../data/models/collection/favorite.dart';
import '../../providers/api_provider.dart';
import '../../providers/document_lifecycle_provider.dart';
import '../../providers/documents_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/history_provider.dart';
import '../../providers/proxy_provider.dart';
import '../../providers/selection_provider.dart';
import '../../services/batch_extract_service.dart';
import '../../services/snackbar_service.dart';
import '../../utils/doc_paths.dart';
import '../../router/app_routes.dart';
import '../library/widgets/batch_progress_sheet.dart';
import '../library/widgets/doc_card_actions.dart';
import '../library/widgets/doc_list_card.dart';
import '../library/widgets/selection_app_bar.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/l10n.dart';

/// 收藏夹详情页：展示书单内所有文献
class FavoriteDetailPage extends ConsumerWidget {
  final Favorite favorite;

  const FavoriteDetailPage({super.key, required this.favorite});

  String get _sourceContext => 'favorite:${favorite.id}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final docs = ref.watch(documentsProvider);
    final favorites = ref.watch(favoritesProvider);
    final history = ref.watch(historyProvider);
    final progressByDoc = {for (final e in history) e.docId: e.progress};
    final currentFavorite = favorites.firstWhere(
      (f) => f.id == favorite.id,
      orElse: () => favorite,
    );
    final selection = ref.watch(selectionProvider);
    final isSelectionMode =
        selection.isActive && selection.sourceContext == _sourceContext;

    final byId = {for (final doc in docs) doc.id: doc};
    final favDocs = [
      for (final documentId in currentFavorite.documentIds)
        if (byId[documentId] != null) byId[documentId]!,
    ];

    final allIds = favDocs
        .where((d) => d.id.isNotEmpty)
        .map((d) => d.id)
        .toSet();
    final allSelected =
        allIds.isNotEmpty && selection.selectedIds.containsAll(allIds);

    return PopScope(
      canPop: !isSelectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          ref.read(selectionProvider.notifier).exit();
        }
      },
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: isSelectionMode
            ? SelectionAppBar(
                onClose: () => ref.read(selectionProvider.notifier).exit(),
                selectedCount: selection.selectedIds.length,
                allSelected: allSelected,
                onSelectAll: () =>
                    ref.read(selectionProvider.notifier).toggleAll(allIds),
                onRemoveFromFavorite: () =>
                    _removeFromFavorite(context, ref, selection, favDocs),
                onExtract: () =>
                    _extractSelected(context, ref, selection, favDocs),
                onDelete: () => _deleteSelected(context, ref, selection),
              )
            : AppBar(
                backgroundColor: colorScheme.surface,
                title: Text(
                  currentFavorite.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                leading: IconButton(
                  onPressed: () {
                    Haptics.soft();
                    context.pop();
                  },
                  icon: const Icon(Symbols.arrow_back_rounded),
                ),
                actions: [
                  IconButton(
                    onPressed: () {
                      Haptics.soft();
                      _openAddDocumentsPage(
                        context,
                        currentFavorite,
                      );
                    },
                    icon: const Icon(Symbols.bookmark_add_rounded),
                    tooltip: context.l10n.addDocument,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
        body: CustomScrollView(
          slivers: [
            if (currentFavorite.documentIds.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Symbols.menu_book_rounded,
                        size: 64,
                        color: colorScheme.onSurfaceVariant.withAlpha(80),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        context.l10n.noDocuments,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Haptics.soft();
                          _openAddDocumentsPage(context, currentFavorite);
                        },
                        icon: const Icon(Symbols.bookmark_add_rounded, size: 20),
                        label: Text(context.l10n.addDocument),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.separated(
                  itemCount: favDocs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final doc = favDocs[index];

                    return DocListCard(
                      doc: doc,
                      progress: progressByDoc[doc.id] ?? 0.0,
                      isSelectionMode: isSelectionMode,
                      isSelected: selection.selectedIds.contains(doc.id),
                      onTap: () => DocCardActions.openReader(context, ref, doc),
                      onLongPress: doc.id.isNotEmpty
                          ? () => ref
                                .read(selectionProvider.notifier)
                                .enter(doc.id, _sourceContext)
                          : null,
                      onSelectionTap: doc.id.isNotEmpty
                          ? () => ref
                                .read(selectionProvider.notifier)
                                .toggle(doc.id)
                          : null,
                    );
                  },
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  /// 跳转到"添加文献"页面——全屏多选列表，已含文献灰显不可选，右下确认/取消。
  /// 入页面后内部直接调用 lifecycleProvider 完成批量加入，调用方不接收返回值。
  void _openAddDocumentsPage(BuildContext context, Favorite currentFavorite) {
    context.push(AppRoutes.shelfFavoriteAddDocs, extra: currentFavorite);
  }

  /// 从收藏夹中移除选中文献（不删除文献本身）
  Future<void> _removeFromFavorite(
    BuildContext context,
    WidgetRef ref,
    SelectionState selection,
    List<Document> favDocs,
  ) async {
    var count = 0;
    for (final doc in favDocs) {
      if (selection.selectedIds.contains(doc.id)) {
        await ref
            .read(documentLifecycleProvider)
            .removeFromFavorite(favorite.id, doc.id);
        count++;
      }
    }
    ref.read(snackBarServiceProvider).showResult(message: context.l10n.removedFromFavoriteCount(count));
    ref.read(selectionProvider.notifier).exit();
  }

  /// 批量删除选中文献（真正删除）
  Future<void> _deleteSelected(
    BuildContext context,
    WidgetRef ref,
    SelectionState selection,
  ) async {
    final count = selection.selectedIds.length;
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.batchDelete),
        content: Text(context.l10n.confirmDeleteDocuments(count)),
        actions: [
          TextButton(
            onPressed: () {
              Haptics.soft();
              Navigator.pop(context, false);
            },
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Haptics.soft();
              Navigator.pop(context, true);
            },
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    for (final id in selection.selectedIds.toList()) {
      await DocCardActions.delete(ref, id);
    }
    ref.read(snackBarServiceProvider).showResult(message: context.l10n.deletedDocuments(count));
    ref.read(selectionProvider.notifier).exit();
  }

  /// 批量提取选中文献
  Future<void> _extractSelected(
    BuildContext context,
    WidgetRef ref,
    SelectionState selection,
    List<Document> favDocs,
  ) async {
    final apiState = ref.read(docExtractApiProvider);
    if (!apiState.isConfigured) {
      ref
          .read(snackBarServiceProvider)
          .showResult(message: context.l10n.configureExtractToken);
      return;
    }

    final selectedDocs = favDocs
        .where(
          (d) => selection.selectedIds.contains(d.id) && d.contentHash != null,
        )
        .toList();

    if (selectedDocs.isEmpty) {
      ref
          .read(snackBarServiceProvider)
          .showResult(message: context.l10n.noPdfFilesSelected);
      return;
    }

    final items = selectedDocs
        .map(
          (d) => BatchExtractItem(
            documentId: d.id,
            filePath: DocPaths.pdf(d.id),
            title: d.title,
          ),
        )
        .toList();

    final proxyState = ref.read(proxyProvider);
    BatchExtractService.instance.applyProxy(
      proxyState.mode,
      proxyState.host,
      proxyState.port,
    );

    ref.read(selectionProvider.notifier).exit();

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BatchProgressSheet(items: items, apiState: apiState),
    );
  }
}
