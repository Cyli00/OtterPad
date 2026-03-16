import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/documents_provider.dart';
import '../../providers/task_provider.dart';
import '../../services/snackbar_service.dart';
import '../library/widgets/doc_list_card.dart';

/// 无文件条目详情页
class NoFileEntriesPage extends ConsumerWidget {
  const NoFileEntriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final noFileDocs = ref.watch(noFileDocsProvider);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
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
          // 空状态
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
                      DocListCard(doc: doc),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton.filledTonal(
                              onPressed: () =>
                                  _handleAttachFile(context, ref, doc.id),
                              icon: const Icon(Icons.attach_file_rounded),
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
                                onPressed: () => _handleRedownload(
                                    ref, doc.id, doc.title),
                                icon:
                                    const Icon(Icons.download_rounded),
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
          .read(documentsProvider.notifier)
          .attachFile(docId, result.files.first.path!);
      snackBar.showResult(message: '文件附加成功');
    } catch (e) {
      snackBar.showResult(message: '附加文件失败: $e');
    }
  }

  void _handleRedownload(WidgetRef ref, String docId, String docTitle) {
    ref.read(taskProvider.notifier).redownloadPdf(docId, docTitle);
  }
}
