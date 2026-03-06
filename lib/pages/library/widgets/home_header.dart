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
        if (result != null) {
          final notifier = ref.read(documentsProvider.notifier);
          for (final file in result.files) {
            if (file.path != null) {
              await notifier.addFile(file.path!);
            }
          }
        }
      case ToolbarAction.addByIdentifier:
        if (!context.mounted) return;
        final identifier = await showIdentifierDialog(context);
        if (identifier != null && context.mounted) {
          // 显示加载中 SnackBar
          final messenger = ScaffoldMessenger.of(context);
          messenger.showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 16),
                  Text('正在解析标识符...'),
                ],
              ),
              duration: Duration(seconds: 30),
            ),
          );

          try {
            final (doc, result) = await ref
                .read(documentsProvider.notifier)
                .addByIdentifier(identifier);
            messenger.hideCurrentSnackBar();
            if (!context.mounted) return;
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
            if (!context.mounted) return;
            messenger.showSnackBar(
              SnackBar(content: Text(e.message)),
            );
          }
        }
      case ToolbarAction.rebuildLibrary:
        await ref.read(documentsProvider.notifier).rebuild();
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
