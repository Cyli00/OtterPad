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
      body: CustomScrollView(
        slivers: [
          // 顶部：返回按钮 + 标题
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded),
                      style: IconButton.styleFrom(
                        foregroundColor: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        '无文件条目',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),

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

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DocListCard(doc: doc),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () =>
                                _handleAttachFile(context, ref, doc.id),
                            icon: const Icon(Icons.attach_file_rounded,
                                size: 18),
                            label: const Text('附加文件'),
                          ),
                          if (hasDoi) ...[
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _handleRedownload(ref, doc.id, doc.title),
                              icon: const Icon(Icons.download_rounded,
                                  size: 18),
                              label: const Text('重新下载'),
                            ),
                          ],
                        ],
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
