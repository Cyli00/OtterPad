import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/document_lifecycle_provider.dart';
import '../../services/haptics.dart';
import '../../widgets/app_dialog.dart';
import '../../providers/document_task_provider.dart';
import '../../providers/documents_provider.dart';
import '../../providers/selection_provider.dart';
import '../../widgets/selection_pop_scope.dart';
import '../../services/snackbar_service.dart';
import '../../widgets/spring_dismissible.dart';
import '../library/widgets/doc_card_actions.dart';
import '../library/widgets/doc_list_card.dart';
import '../library/widgets/selection_app_bar.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../core/l10n.dart';

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

    return SelectionPopScope(
      sourceContext: _sourceContext,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: isSelectionMode
            ? SelectionAppBar(
                onClose: () => ref.read(selectionProvider.notifier).exit(),
                selectedCount: selection.selectedIds.length,
                allSelected: allSelected,
                onSelectAll: () =>
                    ref.read(selectionProvider.notifier).toggleAll(allIds),
                // 无文件条目没有 PDF，不提供文本提取
                onDownload: () => _downloadSelected(ref, selection),
                onDelete: () => _deleteSelected(context, ref, selection),
              )
            : AppBar(
                backgroundColor: colorScheme.surface,
                title: Text(
                  context.l10n.noFileEntries,
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
                        Symbols.check_circle_rounded,
                        size: 64,
                        color: colorScheme.onSurfaceVariant.withAlpha(80),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        context.l10n.allDocumentsHaveFiles,
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
                    final hasDoi = doc.doi != null && doc.doi!.isNotEmpty;

                    final card = Stack(
                      children: [
                        DocListCard(
                          doc: doc,
                          isSelectionMode: isSelectionMode,
                          isSelected: selection.selectedIds.contains(doc.id),
                          onLongPress: () => ref
                              .read(selectionProvider.notifier)
                              .enter(doc.id, _sourceContext),
                          onSelectionTap: () => ref
                              .read(selectionProvider.notifier)
                              .toggle(doc.id),
                        ),
                        if (!isSelectionMode)
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton.filledTonal(
                                  onPressed: () {
                                    Haptics.soft();
                                    _handleAttachFile(context, ref, doc.id);
                                  },
                                  icon: const Icon(Symbols.attach_file_rounded),
                                  iconSize: 18,
                                  tooltip: context.l10n.attachFile,
                                  style: IconButton.styleFrom(
                                    minimumSize: const Size(36, 36),
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                                if (hasDoi) ...[
                                  const SizedBox(width: 4),
                                  IconButton.filledTonal(
                                    onPressed: () {
                                      Haptics.soft();
                                      _handleOpenDoi(doc.doi!);
                                    },
                                    icon: const Icon(Symbols.language_rounded),
                                    iconSize: 18,
                                    tooltip: context.l10n.viewInBrowser,
                                    style: IconButton.styleFrom(
                                      minimumSize: const Size(36, 36),
                                      padding: EdgeInsets.zero,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton.filledTonal(
                                    onPressed: () {
                                      Haptics.soft();
                                      _handleRedownload(
                                        ref,
                                        doc.id,
                                        doc.title,
                                      );
                                    },
                                    icon: const Icon(Symbols.download_rounded),
                                    iconSize: 18,
                                    tooltip: context.l10n.redownload,
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

                    if (isSelectionMode) return card;

                    final cs = Theme.of(context).colorScheme;
                    final entryDeletedMsg = context.l10n.entryDeleted;
                    return SpringDismissible(
                      key: ValueKey(doc.id),
                      onDismissed: () async {
                        await DocCardActions.delete(ref, doc.id);
                        ref
                            .read(snackBarServiceProvider)
                            .showResult(message: entryDeletedMsg);
                      },
                      background: Container(
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Symbols.delete_rounded,
                              size: 22,
                              color: cs.onErrorContainer,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              context.l10n.delete,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: cs.onErrorContainer,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      child: card,
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
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        title: Text(context.l10n.batchDelete),
        content: Text(context.l10n.confirmDeleteEntries(count)),
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
    ref.read(snackBarServiceProvider).showResult(message: context.l10n.deletedEntries(count));
    ref.read(selectionProvider.notifier).exit();
  }

  /// 批量从公网拉取 PDF：对所有选中项发起下载（无 DOI 的条目会先尝试标题搜索补全）。
  /// 进度与汇总由 [DocumentTaskNotifier.redownloadBatch] 的聚合 snackbar 负责。
  Future<void> _downloadSelected(WidgetRef ref, SelectionState selection) async {
    final selectedIds = selection.selectedIds;
    final selected = ref
        .read(noFileDocsProvider)
        .where((d) => selectedIds.contains(d.id))
        .toList();

    if (selected.isEmpty) return;

    ref.read(selectionProvider.notifier).exit();
    await ref.read(documentTaskProvider.notifier).redownloadBatch(
      [for (final d in selected) (documentId: d.id, title: d.title)],
    );
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
          .read(documentLifecycleProvider)
          .attachPdf(docId, result.files.first.path!);
      if (!context.mounted) return;
      snackBar.showResult(message: context.l10n.fileAttached);
    } catch (e) {
      snackBar.showResult(message: context.l10n.attachFileFailed('$e'));
    }
  }

  void _handleOpenDoi(String doi) {
    final url = doi.startsWith('http') ? doi : 'https://doi.org/$doi';
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _handleRedownload(WidgetRef ref, String docId, String docTitle) {
    ref
        .read(documentTaskProvider.notifier)
        .redownloadPdf(documentId: docId, title: docTitle);
  }
}
