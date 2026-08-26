import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n.dart';
import '../../../services/haptics.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/tactile_press.dart';
import '../../../providers/documents_provider.dart';
import '../../../providers/task_provider.dart';
import '../../../router/app_routes.dart';
import 'identifier_dialog.dart';
import 'toolbar_bottom_sheet.dart';
import 'package:material_symbols_icons/symbols.dart';

class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  static final toolsButtonKey = GlobalKey(debugLabel: 'toolsButton');

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
            child: TactilePress(
              onTap: () {
                context.push(AppRoutes.librarySearch);
              },
              baseColor: Colors.transparent,
              borderRadius: BorderRadius.circular(24.0),
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
                        isMobile
                            ? context.l10n.searchDocumentsHint
                            : context.l10n.searchDocumentsHintDesktop,
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
            icon: isGrid
                ? Symbols.view_list_rounded
                : Symbols.grid_view_rounded,
            tooltip: isGrid ? context.l10n.listView : context.l10n.gridView,
            size: isMobile ? 36 : 40,
            onPressed: () {
              Haptics.soft();
              ref.read(viewModeProvider.notifier).toggle();
            },
          ),
          const SizedBox(width: 8.0),
          if (Responsive.showNavigationRail(context))
            _ToolsMenuButton(
              size: isMobile ? 36 : 40,
              onAction: (action) => _handleToolbarAction(context, ref, action),
            )
          else
            _HeaderButton(
              key: toolsButtonKey,
              icon: Symbols.note_add_rounded,
              tooltip: context.l10n.tools,
              size: isMobile ? 36 : 40,
              onPressed: () async {
                Haptics.soft();
                final action = await showToolbarSheet(context);
                if (action != null && context.mounted) {
                  _handleToolbarAction(context, ref, action);
                }
              },
            ),
        ],
      ),
    );
  }
}

class _ToolsMenuButton extends StatelessWidget {
  const _ToolsMenuButton({required this.size, required this.onAction});

  final double size;
  final ValueChanged<ToolbarAction> onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerHigh),
        elevation: const WidgetStatePropertyAll(3),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      builder: (context, controller, _) {
        return _HeaderButton(
          key: HomeHeader.toolsButtonKey,
          icon: Symbols.note_add_rounded,
          tooltip: l10n.tools,
          size: size,
          onPressed: () {
            Haptics.soft();
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        );
      },
      menuChildren: [
        MenuItemButton(
          onPressed: () => onAction(ToolbarAction.addFile),
          leadingIcon: const Icon(Symbols.note_add_rounded, size: 20),
          child: Text(l10n.addFiles),
        ),
        MenuItemButton(
          onPressed: () => onAction(ToolbarAction.addByIdentifier),
          leadingIcon: const Icon(Symbols.travel_explore_rounded, size: 20),
          child: Text(l10n.addByIdentifier),
        ),
        MenuItemButton(
          onPressed: () => onAction(ToolbarAction.rebuildLibrary),
          leadingIcon: const Icon(Symbols.refresh_rounded, size: 20),
          child: Text(l10n.rebuildLibrary),
        ),
      ],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;

  const _HeaderButton({
    super.key,
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
