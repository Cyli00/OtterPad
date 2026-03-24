import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/documents_provider.dart';
import '../../providers/selection_provider.dart';
import '../../providers/starred_provider.dart';
import '../../providers/task_provider.dart';
import '../../services/snackbar_service.dart';
import '../library/widgets/doc_card_actions.dart';
import '../library/widgets/doc_list_card.dart';
import '../library/widgets/selection_app_bar.dart';

/// 无文件条目详情页
class NoFileEntriesPage extends ConsumerWidget {
  const NoFileEntriesPage({super.key});

  static const _sourceContext = 'nofile';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final noFileDocs = ref.watch(noFileDocsProvider);
    final selection = ref.watch(selectionProvider);
    final isSelectionMode =
        selection.isActive && selection.sourceContext == _sourceContext;

    final allIds = noFileDocs.map((d) => d.id).toSet();
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
                // 无文件条目没有 PDF，不提供文本提取
                onDelete: () => _deleteSelected(context, ref, selection),
              )
            : AppBar(
                backgroundColor: colorScheme.surface,
                title: Text(
                  '无文件条目',
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
            if (noFileDocs.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 64,
                        color: colorScheme.onSurfaceVariant.withAlpha(80),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '所有文献都有对应文件',
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
                  itemCount: noFileDocs.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final doc = noFileDocs[index];
                    final hasDoi =
                        doc.doi != null && doc.doi!.isNotEmpty;

                    return Stack(
                      children: [
                        DocListCard(
                          doc: doc,
                          isSelectionMode: isSelectionMode,
                          isSelected:
                              selection.selectedIds.contains(doc.id),
                          onLongPress: () => ref
                              .read(selectionProvider.notifier)
                              .enter(doc.id, _sourceContext),
                          onSelectionTap: () => ref
                              .read(selectionProvider.notifier)
                              .toggle(doc.id),
                        ),
                        // 选择模式下隐藏操作按钮
                        if (!isSelectionMode)
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton.filledTonal(
                                  onPressed: () => _handleAttachFile(
                                      context, ref, doc.id),
                                  icon: const Icon(
                                      Icons.attach_file_rounded),
                                  iconSize: 18,
                                  tooltip: '附加文件',
                                  style: IconButton.styleFrom(
                                    minimumSize: const Size(36, 36),
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                                if (hasDoi) ...[
                                  const SizedBox(width: 4),
                                  IconButton.filledTonal(
                                    onPressed: () =>
                                        _handleOpenDoi(doc.doi!),
                                    icon: const Icon(
                                        Icons.language_rounded),
                                    iconSize: 18,
                                    tooltip: '在浏览器中查看',
                                    style: IconButton.styleFrom(
                                      minimumSize: const Size(36, 36),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton.filledTonal(
                                    onPressed: () => _handleRedownload(
                                        ref, doc.id, doc.title),
                                    icon: const Icon(
                                        Icons.download_rounded),
                                    iconSize: 18,
                                    tooltip: '重新下载',
                                    style: IconButton.styleFrom(
                                      minimumSize: const Size(36, 36),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
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
        content: Text('确定要删除 $count 个无文件条目吗？'),
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
        .showResult(message: '已删除 $count 个条目');
    ref.read(selectionProvider.notifier).exit();
  }

  Future<void> _handleAttachFile(
    BuildContext context,
    WidgetRef ref,
    String docId,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.first.path == null) return;

    final snackBar = ref.read(snackBarServiceProvider);
    try {
      await ref
          .read(documentsProvider.notifier)
          .attachFile(docId, result.files.first.path!);
      snackBar.showResult(message: '文件附加成功');
    } catch (e) {
      snackBar.showResult(message: '附加文件失败: $e');
    }
  }

  void _handleOpenDoi(String doi) {
    final url = doi.startsWith('http') ? doi : 'https://doi.org/$doi';
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _handleRedownload(WidgetRef ref, String docId, String docTitle) {
    ref.read(taskProvider.notifier).redownloadPdf(docId, docTitle);
  }
}
