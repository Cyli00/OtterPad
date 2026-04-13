import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/documents_provider.dart';
import '../../../providers/task_provider.dart';
import '../../../router/app_routes.dart';
import 'identifier_dialog.dart';
import 'toolbar_bottom_sheet.dart';
import 'package:material_symbols_icons/symbols.dart';

class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  Future<void> _handleToolbarAction(
    BuildContext context,
    WidgetRef ref,
    ToolbarAction action,
  ) async {
    final tasks = ref.read(taskProvider.notifier);
    switch (action) {
      case ToolbarAction.addFile:
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf'],
          allowMultiple: true,
        );
        if (result != null) {
          final paths = result.files
              .where((f) => f.path != null)
              .map((f) => f.path!)
              .toList();
          tasks.addFiles(paths);
        }

      case ToolbarAction.addByIdentifier:
        if (!context.mounted) return;
        final identifier = await showIdentifierDialog(context);
        if (identifier != null) {
          tasks.addByIdentifier(identifier);
        }

      case ToolbarAction.rebuildLibrary:
        tasks.rebuildLibrary();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isGrid = ref.watch(viewModeProvider);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 600;

    return Padding(
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
                      Symbols.search_rounded,
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
            icon: isGrid ? Symbols.view_list_rounded : Symbols.grid_view_rounded,
            tooltip: isGrid ? '切换列表视图' : '切换网格视图',
            size: isMobile ? 36 : 40,
            onPressed: () {
              ref.read(viewModeProvider.notifier).state = !isGrid;
            },
          ),
          const SizedBox(width: 8.0),
          _HeaderButton(
            icon: Symbols.add_circle_rounded,
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
              Symbols.person_rounded,
              color: colorScheme.primary,
              size: isMobile ? 20 : 22,
            ),
          ),
        ],
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
