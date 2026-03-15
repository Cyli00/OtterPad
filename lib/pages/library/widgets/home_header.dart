import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/documents_provider.dart';
import '../../../router/app_routes.dart';
import '../../../services/identifier_resolver.dart';
import 'identifier_dialog.dart';
import 'toolbar_bottom_sheet.dart';

class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  Future<void> _handleToolbarAction(
    BuildContext context,
    WidgetRef ref,
    ToolbarAction action,
  ) async {
    switch (action) {
      case ToolbarAction.addFile:
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf'],
          allowMultiple: true,
        );
        if (result != null && context.mounted) {
          final notifier = ref.read(documentsProvider.notifier);
          final messenger = ScaffoldMessenger.of(context);
          final files = result.files
              .where((file) => file.path != null)
              .toList();
          final cancelToken = CancelToken();
          var importedCount = 0;
          var duplicateCount = 0;
          var completeMetadataCount = 0;
          var partialMetadataCount = 0;

          AddFileResult? lastResult;
          for (int i = 0; i < files.length; i++) {
            if (cancelToken.isCancelled || !context.mounted) break;

            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(
              buildProgressSnackBar(
                context: context,
                current: i + 1,
                total: files.length,
                fileName: files[i].name,
                status: '正在提取 PDF 元数据...',
                onCancel: () {
                  cancelToken.cancel();
                  messenger.hideCurrentSnackBar();
                },
              ),
            );

            lastResult = await notifier.addFile(
              files[i].path!,
              cancelToken: cancelToken,
            );

            if (lastResult.type == AddFileResultType.duplicate) {
              duplicateCount++;
              continue;
            }

            importedCount++;
            if (lastResult.metadataStatus == MetadataStatus.complete) {
              completeMetadataCount++;
            } else if (lastResult.metadataStatus == MetadataStatus.partial) {
              partialMetadataCount++;
            }
          }

          if (!context.mounted) return;
          messenger.hideCurrentSnackBar();

          final unresolvedMetadataCount =
              importedCount - completeMetadataCount - partialMetadataCount;
          final message = _buildAddFileMessage(
            cancelToken: cancelToken,
            totalFiles: files.length,
            importedCount: importedCount,
            duplicateCount: duplicateCount,
            completeMetadataCount: completeMetadataCount,
            partialMetadataCount: partialMetadataCount,
            unresolvedMetadataCount: unresolvedMetadataCount,
            lastResult: lastResult,
          );

          messenger.showSnackBar(
            buildResultSnackBar(context: context, message: message),
          );
        }

      case ToolbarAction.addByIdentifier:
        if (!context.mounted) return;
        final identifier = await showIdentifierDialog(context);
        if (identifier != null && context.mounted) {
          final messenger = ScaffoldMessenger.of(context);
          final cancelToken = CancelToken();
          messenger.showSnackBar(
            buildProgressSnackBar(
              context: context,
              current: 1,
              total: 1,
              fileName: identifier,
              status: '正在解析标识符...',
              onCancel: () {
                cancelToken.cancel();
                messenger.hideCurrentSnackBar();
              },
              duration: const Duration(seconds: 30),
            ),
          );

          try {
            final (doc, addResult) = await ref
                .read(documentsProvider.notifier)
                .addByIdentifier(identifier, cancelToken: cancelToken);
            messenger.hideCurrentSnackBar();
            if (cancelToken.isCancelled || !context.mounted) return;
            if (addResult == AddByIdentifierResult.duplicate) {
              messenger.showSnackBar(
                buildResultSnackBar(context: context, message: '该文献已存在于文库中'),
              );
            } else if (doc.filePath.isEmpty) {
              messenger.showSnackBar(
                buildResultSnackBar(
                  context: context,
                  message: '已添加「${doc.title}」，但未获取到关联 PDF',
                  duration: const Duration(seconds: 6),
                  action: SnackBarAction(
                    label: '去添加',
                    onPressed: () {
                      if (context.mounted) {
                        context.push(AppRoutes.shelfNoFileEntries);
                      }
                    },
                  ),
                ),
              );
            } else {
              messenger.showSnackBar(
                buildResultSnackBar(
                  context: context,
                  message: '已添加: ${doc.title}',
                ),
              );
            }
          } on IdentifierResolveException catch (error) {
            messenger.hideCurrentSnackBar();
            if (cancelToken.isCancelled || !context.mounted) return;
            messenger.showSnackBar(
              buildResultSnackBar(context: context, message: error.message),
            );
          } on DioException {
            messenger.hideCurrentSnackBar();
            if (cancelToken.isCancelled || !context.mounted) return;
            messenger.showSnackBar(
              buildResultSnackBar(context: context, message: '网络请求失败，请稍后重试'),
            );
          }
        }

      case ToolbarAction.batchExtract:
        if (!context.mounted) return;
        await context.push(AppRoutes.libraryBatchExtract);

      case ToolbarAction.rebuildLibrary:
        if (!context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        final cancelToken = CancelToken();
        messenger.showSnackBar(
          buildProgressSnackBar(
            context: context,
            fileName: 'NightReader 文库',
            status: '准备重构文库...',
            onCancel: () {
              cancelToken.cancel();
              messenger.hideCurrentSnackBar();
            },
          ),
        );

        RebuildResult? result;
        try {
          result = await ref
              .read(documentsProvider.notifier)
              .rebuild(
                cancelToken: cancelToken,
                onProgress: (progress) {
                  if (!context.mounted || cancelToken.isCancelled) return;
                  messenger.hideCurrentSnackBar();
                  messenger.showSnackBar(
                    buildProgressSnackBar(
                      context: context,
                      current: progress.current,
                      total: progress.total,
                      fileName: progress.fileName,
                      status: progress.status,
                      onCancel: () {
                        cancelToken.cancel();
                        messenger.hideCurrentSnackBar();
                      },
                    ),
                  );
                },
              );
        } on DioException {
          // CancelToken 取消时 Dio 会抛异常，这里静默处理。
        }

        if (!context.mounted) return;
        messenger.hideCurrentSnackBar();

        var message = cancelToken.isCancelled ? '已取消重构文库' : '文库重构完成';
        if (result != null) {
          final parts = <String>[];
          if (result.addedCount > 0) {
            parts.add('新增 ${result.addedCount} 篇');
          }
          if (result.removedCount > 0) {
            parts.add('清理 ${result.removedCount} 篇');
          }
          if (result.downloadedCount > 0) {
            parts.add('补回 PDF ${result.downloadedCount} 篇');
          }
          if (result.repairedCount > 0) {
            parts.add('修复元数据 ${result.repairedCount} 篇');
          }
          if (result.unresolvedCount > 0) {
            parts.add('仍有 ${result.unresolvedCount} 篇待补全元数据');
          }
          if (result.noFileCount > 0) {
            parts.add('${result.noFileCount} 个无文件条目');
          }
          if (parts.isEmpty) {
            message += '，文库状态正常';
          } else {
            message += '：${parts.join('，')}';
          }
        }

        messenger.showSnackBar(
          buildResultSnackBar(context: context, message: message),
        );
    }
  }

  String _buildAddFileMessage({
    required CancelToken cancelToken,
    required int totalFiles,
    required int importedCount,
    required int duplicateCount,
    required int completeMetadataCount,
    required int partialMetadataCount,
    required int unresolvedMetadataCount,
    required AddFileResult? lastResult,
  }) {
    if (totalFiles == 1 && lastResult?.document != null) {
      final doc = lastResult!.document!;
      if (lastResult.type == AddFileResultType.duplicate) {
        return '文库中已存在: ${doc.title}';
      }
      switch (lastResult.metadataStatus) {
        case MetadataStatus.complete:
          return '已导入并提取元数据: ${doc.title}';
        case MetadataStatus.partial:
          return '已导入 ${doc.title}，仅提取到部分元数据';
        case MetadataStatus.none:
          return '已导入 ${doc.title}，未识别到可用元数据';
      }
    }

    final parts = <String>[];
    if (importedCount > 0) parts.add('导入 $importedCount 篇');
    if (duplicateCount > 0) parts.add('重复 $duplicateCount 篇');
    if (completeMetadataCount > 0) parts.add('完整元数据 $completeMetadataCount 篇');
    if (partialMetadataCount > 0) parts.add('部分元数据 $partialMetadataCount 篇');
    if (unresolvedMetadataCount > 0) {
      parts.add('未识别元数据 $unresolvedMetadataCount 篇');
    }
    if (parts.isEmpty) {
      return cancelToken.isCancelled ? '已取消导入' : '未导入任何文件';
    }
    final prefix = cancelToken.isCancelled ? '已取消导入' : '导入完成';
    return '$prefix：${parts.join('，')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isGrid = ref.watch(viewModeProvider);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 600;

    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16.0,
          right: 16.0,
          top: isMobile ? 4.0 : 8.0,
          bottom: 16.0,
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => context.push(AppRoutes.librarySearch),
                child: Container(
                  height: isMobile ? 44 : 48,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withAlpha(150),
                    borderRadius: BorderRadius.circular(24.0),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withAlpha(100),
                      width: 1,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        color: colorScheme.onSurfaceVariant,
                        size: isMobile ? 20 : 24,
                      ),
                      const SizedBox(width: 8.0),
                      Expanded(
                        child: Text(
                          isMobile ? '搜索文献...' : '搜索文献、作者、关键词...',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: isMobile ? 14 : 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8.0),
            _HeaderButton(
              icon: isGrid ? Icons.view_list_rounded : Icons.grid_view_rounded,
              tooltip: isGrid ? '切换列表视图' : '切换网格视图',
              size: isMobile ? 36 : 40,
              onPressed: () {
                ref.read(viewModeProvider.notifier).state = !isGrid;
              },
            ),
            const SizedBox(width: 8.0),
            _HeaderButton(
              icon: Icons.add_circle_outline_rounded,
              tooltip: '工具',
              size: isMobile ? 36 : 40,
              onPressed: () async {
                final action = await showToolbarSheet(context);
                if (action != null && context.mounted) {
                  _handleToolbarAction(context, ref, action);
                }
              },
            ),
            const SizedBox(width: 8.0),
            Container(
              width: isMobile ? 36 : 40,
              height: isMobile ? 36 : 40,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_outline_rounded,
                color: colorScheme.primary,
                size: isMobile ? 20 : 22,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;

  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: size,
      height: size,
      child: IconButton.filled(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: size * 0.5),
        style: IconButton.styleFrom(
          backgroundColor: colorScheme.primaryContainer,
          foregroundColor: colorScheme.primary,
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
