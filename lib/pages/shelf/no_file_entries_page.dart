import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/documents_provider.dart';
import '../library/widgets/doc_list_card.dart';
import '../library/widgets/toolbar_bottom_sheet.dart';

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
                                  _handleRedownload(context, ref, doc.id),
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
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(documentsProvider.notifier)
          .attachFile(docId, result.files.first.path!);
      if (!context.mounted) return;
      messenger.showSnackBar(
        buildResultSnackBar(context: context, message: '文件附加成功'),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        buildResultSnackBar(context: context, message: '附加文件失败: $e'),
      );
    }
  }

  Future<void> _handleRedownload(
    BuildContext context,
    WidgetRef ref,
    String docId,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final cancelToken = CancelToken();

    messenger.showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('正在重新下载...'),
          ],
        ),
        duration: const Duration(seconds: 30),
        action: SnackBarAction(
          label: '取消',
          onPressed: () {
            cancelToken.cancel();
            messenger.hideCurrentSnackBar();
          },
        ),
      ),
    );

    final success = await ref
        .read(documentsProvider.notifier)
        .redownloadPdf(docId, cancelToken: cancelToken);

    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();

    if (cancelToken.isCancelled) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text(success ? '下载成功' : '下载失败，未找到可用的 PDF 源'),
      ),
    );
  }
}
