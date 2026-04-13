import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import '../../data/models/book/document.dart';
import '../../data/models/collection/favorite.dart';
import '../../providers/api_provider.dart';
import '../../providers/documents_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/proxy_provider.dart';
import '../../providers/selection_provider.dart';
import '../../providers/starred_provider.dart';
import '../../services/batch_extract_service.dart';
import '../../services/snackbar_service.dart';
import '../library/widgets/batch_progress_sheet.dart';
import '../library/widgets/doc_card_actions.dart';
import '../library/widgets/doc_list_card.dart';
import '../library/widgets/selection_app_bar.dart';
import 'package:material_symbols_icons/symbols.dart';

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
    final selection = ref.watch(selectionProvider);
    final isSelectionMode =
        selection.isActive && selection.sourceContext == _sourceContext;

    // 解析收藏夹内的文献列表
    final favDocs = <Document>[];
    for (final docPath in favorite.docPaths) {
      final doc = docs.where((d) => d.filePath == docPath).firstOrNull ??
          Document(
            id: '',
            title: p.basenameWithoutExtension(docPath),
            authors: [],
            filePath: docPath,
            addedAt: DateTime.now(),
          );
      favDocs.add(doc);
    }

    final allIds = favDocs.where((d) => d.id.isNotEmpty).map((d) => d.id).toSet();
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
                onStar: () => ref
                    .read(starredProvider.notifier)
                    .toggleMany(selection.selectedIds),
                onRemoveFromFavorite: () =>
                    _removeFromFavorite(context, ref, selection, favDocs),
                onExtract: () =>
                    _extractSelected(context, ref, selection, favDocs),
                onDelete: () =>
                    _deleteSelected(context, ref, selection),
              )
            : AppBar(
                backgroundColor: colorScheme.surface,
                title: Text(
                  favorite.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                leading: IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Symbols.arrow_back_rounded),
                ),
              ),
        body: CustomScrollView(
          slivers: [
            if (favorite.docPaths.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Symbols.menu_book,
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
                  itemCount: favDocs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final doc = favDocs[index];

                    return DocListCard(
                      doc: doc,
                      isSelectionMode: isSelectionMode,
                      isSelected: selection.selectedIds.contains(doc.id),
                      onTap: () => DocCardActions.openReader(context, doc),
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

  /// 从收藏夹中移除选中文献（不删除文献本身）
  void _removeFromFavorite(
    BuildContext context,
    WidgetRef ref,
    SelectionState selection,
    List<Document> favDocs,
  ) {
    final count = selection.selectedIds.length;
    for (final doc in favDocs) {
      if (selection.selectedIds.contains(doc.id) && doc.filePath.isNotEmpty) {
        ref
            .read(favoritesProvider.notifier)
            .removeDoc(favorite.id, doc.filePath);
      }
    }
    ref
        .read(snackBarServiceProvider)
        .showResult(message: '已从收藏夹移除 $count 篇文献');
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
        title: const Text('批量删除'),
        content: Text('确定要删除 $count 篇文献吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    for (final id in selection.selectedIds.toList()) {
      DocCardActions.delete(ref, id);
    }
    ref
        .read(snackBarServiceProvider)
        .showResult(message: '已删除 $count 篇文献');
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
      ref.read(snackBarServiceProvider).showResult(
            message: '请先在设置中配置文档提取 Access Token',
          );
      return;
    }

    final selectedDocs = favDocs
        .where((d) =>
            selection.selectedIds.contains(d.id) && d.filePath.isNotEmpty)
        .toList();

    if (selectedDocs.isEmpty) {
      ref.read(snackBarServiceProvider).showResult(
            message: '所选文献中无本地 PDF 文件，无法提取',
          );
      return;
    }

    final items = selectedDocs
        .map((d) => BatchExtractItem(
              documentId: d.id,
              filePath: d.filePath,
              title: d.title,
            ))
        .toList();

    final proxyState = ref.read(proxyProvider);
    BatchExtractService.instance
        .applyProxy(proxyState.mode, proxyState.host, proxyState.port);

    ref.read(selectionProvider.notifier).exit();

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BatchProgressSheet(
        items: items,
        apiState: apiState,
      ),
    );
  }
}
