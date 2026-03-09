import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../providers/documents_provider.dart';
import '../../../services/identifier_resolver.dart';
import '../search_page.dart';
import 'toolbar_bottom_sheet.dart';
import 'identifier_dialog.dart';

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
          final files = result.files.where((f) => f.path != null).toList();
          final cancelToken = CancelToken();
          int addedCount = 0;
          for (int i = 0; i < files.length; i++) {
            if (cancelToken.isCancelled) break;
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(
              buildProgressSnackBar(
                current: i + 1,
                total: files.length,
                fileName: files[i].name,
                status: '正在解析...',
                onCancel: () {
                  cancelToken.cancel();
                  messenger.hideCurrentSnackBar();
                },
              ),
            );
            try {
              await notifier.addFile(files[i].path!, cancelToken: cancelToken);
              addedCount++;
            } on DioException catch (_) {
              if (cancelToken.isCancelled) break;
              rethrow;
            }
          }
          if (context.mounted) {
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  cancelToken.isCancelled
                      ? '已取消，已添加 $addedCount/${files.length} 篇文献'
                      : '已添加 ${files.length} 篇文献',
                ),
              ),
            );
          }
        }
      case ToolbarAction.addByIdentifier:
        if (!context.mounted) return;
        final identifier = await showIdentifierDialog(context);
        if (identifier != null && context.mounted) {
          final messenger = ScaffoldMessenger.of(context);
          final cancelToken = CancelToken();
          messenger.showSnackBar(
            buildProgressSnackBar(
              current: 1,
              total: 1,
              fileName: identifier,
              status: '正在解析...',
              onCancel: () {
                cancelToken.cancel();
                messenger.hideCurrentSnackBar();
              },
              duration: const Duration(seconds: 30),
            ),
          );

          try {
            final (doc, result) = await ref
                .read(documentsProvider.notifier)
                .addByIdentifier(identifier, cancelToken: cancelToken);
            messenger.hideCurrentSnackBar();
            if (cancelToken.isCancelled || !context.mounted) return;
            if (result == AddByIdentifierResult.duplicate) {
              messenger.showSnackBar(
                const SnackBar(content: Text('该文献已存在于文库中')),
              );
            } else {
              messenger.showSnackBar(
                SnackBar(content: Text('已添加: ${doc.title}')),
              );
            }
          } on IdentifierResolveException catch (e) {
            messenger.hideCurrentSnackBar();
            if (cancelToken.isCancelled || !context.mounted) return;
            messenger.showSnackBar(
              SnackBar(content: Text(e.message)),
            );
          } on DioException catch (_) {
            messenger.hideCurrentSnackBar();
            if (cancelToken.isCancelled || !context.mounted) return;
            messenger.showSnackBar(
              const SnackBar(content: Text('网络请求失败，请稍后重试')),
            );
          }
        }
      case ToolbarAction.rebuildLibrary:
        if (!context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        final cancelToken = CancelToken();
        messenger.showSnackBar(
          buildProgressSnackBar(
            fileName: '正在扫描文库...',
            onCancel: () {
              cancelToken.cancel();
              messenger.hideCurrentSnackBar();
            },
          ),
        );

        RebuildResult? result;
        try {
          result = await ref.read(documentsProvider.notifier).rebuild(
            cancelToken: cancelToken,
            onProgress: (progress) {
              if (!context.mounted || cancelToken.isCancelled) return;
              messenger.hideCurrentSnackBar();
              messenger.showSnackBar(
                buildProgressSnackBar(
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
        } on DioException catch (_) {
          // CancelToken 取消时 Dio 会抛出异常，静默处理
        }

        if (!context.mounted) return;
        messenger.hideCurrentSnackBar();

        String message = cancelToken.isCancelled ? '已取消重构' : '文库重构已结束';
        if (result != null && result.noFileCount > 0) {
          message += '，有 ${result.noFileCount} 个条目被转移到无文件条目';
        }
        messenger.showSnackBar(
          SnackBar(content: Text(message)),
        );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isGrid = ref.watch(viewModeProvider);

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(
          left: 16.0,
          right: 16.0,
          top: 8.0,
          bottom: 16.0,
        ),
        child: Row(
          children: [
            // 搜索框
            Expanded(
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const SearchPage()),
                  );
                },
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest
                        .withAlpha(150),
                    borderRadius: BorderRadius.circular(24.0),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8.0),
                      Expanded(
                        child: Text(
                          '搜索文献、作者、关键词...',
                          style:
                              theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
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

            // 按钮 1：视图切换
            _HeaderButton(
              icon: isGrid
                  ? Icons.view_list_rounded
                  : Icons.grid_view_rounded,
              tooltip: isGrid ? '切换列表视图' : '切换网格视图',
              onPressed: () {
                ref.read(viewModeProvider.notifier).state = !isGrid;
              },
            ),

            const SizedBox(width: 8.0),

            // 按钮 2：工具栏
            _HeaderButton(
              icon: Icons.add_circle_outline_rounded,
              tooltip: '工具',
              onPressed: () async {
                final action = await showToolbarSheet(context);
                if (action != null && context.mounted) {
                  _handleToolbarAction(context, ref, action);
                }
              },
            ),

            const SizedBox(width: 8.0),

            // 用户头像
            CircleAvatar(
              radius: 20,
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(
                Icons.person,
                color: colorScheme.onPrimaryContainer,
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

  const _HeaderButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton.filled(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 20),
        style: IconButton.styleFrom(
          backgroundColor:
              colorScheme.surfaceContainerHighest.withAlpha(150),
          foregroundColor: colorScheme.onSurfaceVariant,
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
