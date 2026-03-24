import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/api_provider.dart';
import '../../providers/documents_provider.dart';
import '../../providers/proxy_provider.dart';
import '../../providers/selection_provider.dart';
import '../../providers/starred_provider.dart';
import '../../services/batch_extract_service.dart';
import '../../services/snackbar_service.dart';
import '../library/widgets/batch_progress_sheet.dart';
import '../library/widgets/doc_card_actions.dart';
import '../library/widgets/doc_list_card.dart';
import '../library/widgets/selection_app_bar.dart';

/// 星标条目页面：展示所有星标文献，布局与收藏夹详情页一致
class StarredItemsPage extends ConsumerWidget {
  const StarredItemsPage({super.key});

  static const _sourceContext = 'starred';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final starredDocs = ref.watch(starredDocsProvider);
    final selection = ref.watch(selectionProvider);
    final isSelectionMode =
        selection.isActive && selection.sourceContext == _sourceContext;

    final allIds = starredDocs.map((d) => d.id).toSet();
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
                onStar: () => _unstarSelected(ref, selection),
                onExtract: () =>
                    _extractSelected(context, ref, selection, starredDocs),
                onDelete: () => _deleteSelected(context, ref, selection),
              )
            : AppBar(
                backgroundColor: colorScheme.surface,
                title: Text(
                  '星标条目',
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
            if (starredDocs.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.star_border_rounded,
                        size: 64,
                        color: colorScheme.onSurfaceVariant.withAlpha(80),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '暂无星标条目',
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
                  itemCount: starredDocs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final doc = starredDocs[index];
                    return DocListCard(
                      doc: doc,
                      isSelectionMode: isSelectionMode,
                      isSelected: selection.selectedIds.contains(doc.id),
                      onTap: () => DocCardActions.openReader(context, doc),
                      onLongPress: () => ref
                          .read(selectionProvider.notifier)
                          .enter(doc.id, _sourceContext),
                      onSelectionTap: () => ref
                          .read(selectionProvider.notifier)
                          .toggle(doc.id),
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

  void _unstarSelected(WidgetRef ref, SelectionState selection) {
    final count = selection.selectedIds.length;
    ref.read(starredProvider.notifier).toggleMany(selection.selectedIds);
    ref
        .read(snackBarServiceProvider)
        .showResult(message: '已取消 $count 个星标');
    ref.read(selectionProvider.notifier).exit();
  }

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

  Future<void> _extractSelected(
    BuildContext context,
    WidgetRef ref,
    SelectionState selection,
    List docs,
  ) async {
    final apiState = ref.read(docExtractApiProvider);
    if (apiState.apiKey.isEmpty || apiState.baseUrl.isEmpty) {
      ref.read(snackBarServiceProvider).showResult(
            message: '请先在设置中配置文档提取 API（Base URL 和 Access Token）',
          );
      return;
    }

    final selectedDocs = docs
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
