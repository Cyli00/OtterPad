import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n.dart';
import '../../../services/haptics.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/masthead.dart';
import '../../../widgets/rule_icon_button.dart';
import '../../../widgets/tactile_press.dart';
import '../../../providers/documents_provider.dart';
import '../../../providers/task_provider.dart';
import '../../../router/app_routes.dart';
import 'identifier_dialog.dart';
import 'toolbar_bottom_sheet.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../core/design_tokens.dart';

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
    final l10n = context.l10n;
    final isGrid = ref.watch(viewModeProvider);
    final count = ref.watch(validDocsProvider.select((d) => d.length));
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final gutter = AppSpace.pageGutter(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final today = DateFormat.MMMMEEEEd(locale).format(DateTime.now());

    final buttonSize = isMobile ? 36.0 : 34.0;
    final viewToggle = RuleIconButton(
      icon: isGrid ? Symbols.view_list_rounded : Symbols.grid_view_rounded,
      tooltip: isGrid ? l10n.listView : l10n.gridView,
      size: buttonSize,
      onPressed: () {
        Haptics.soft();
        ref.read(viewModeProvider.notifier).toggle();
      },
    );
    final tools = Responsive.showNavigationRail(context)
        ? _ToolsMenuButton(
            size: buttonSize,
            onAction: (action) => _handleToolbarAction(context, ref, action),
          )
        : RuleIconButton(
            key: toolsButtonKey,
            icon: Symbols.add_rounded,
            tooltip: l10n.tools,
            size: buttonSize,
            onPressed: () async {
              Haptics.soft();
              final action = await showToolbarSheet(context);
              if (action != null && context.mounted) {
                _handleToolbarAction(context, ref, action);
              }
            },
          );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        viewToggle,
        const SizedBox(width: AppSpace.x2),
        tools,
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        gutter,
        isMobile ? AppSpace.x2 : AppSpace.x6,
        gutter,
        isMobile ? AppSpace.x3 : AppSpace.x4,
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Masthead(
                  eyebrow: today,
                  eyebrowTrailing: actions,
                  title: l10n.myLibrary,
                  count: count,
                  countLabel: l10n.favoriteDocumentCount,
                ),
                const SizedBox(height: AppSpace.x4),
                const _SearchField(height: 40),
              ],
            )
          : Masthead(
              eyebrow: today,
              title: l10n.myLibrary,
              count: count,
              countLabel: l10n.favoriteDocumentCount,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 320,
                    child: _SearchField(height: 34, desktop: true),
                  ),
                  const SizedBox(width: AppSpace.x2),
                  actions,
                ],
              ),
            ),
    );
  }
}

/// 搜索入口：一条细线框，不再是灰色胶囊。点击进入搜索页。
class _SearchField extends StatelessWidget {
  const _SearchField({required this.height, this.desktop = false});

  final double height;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return TactilePress(
      onTap: () => context.push(AppRoutes.librarySearch),
      baseColor: cs.surfaceContainerLowest,
      borderRadius: AppRadius.smAll,
      border: Border.all(color: AppStroke.rule(cs)),
      pressedScale: 0.99,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.x3),
          child: Row(
            children: [
              Icon(
                Symbols.search_rounded,
                color: cs.onSurfaceVariant,
                size: 18,
              ),
              const SizedBox(width: AppSpace.x2),
              Expanded(
                child: Text(
                  desktop
                      ? context.l10n.searchDocumentsHintDesktop
                      : context.l10n.searchDocumentsHint,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
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
    final l10n = context.l10n;
    return MenuAnchor(
      alignmentOffset: const Offset(0, AppSpace.x1),
      builder: (context, controller, _) {
        return RuleIconButton(
          key: HomeHeader.toolsButtonKey,
          icon: Symbols.add_rounded,
          tooltip: l10n.tools,
          size: size,
          selected: controller.isOpen,
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
          leadingIcon: const Icon(Symbols.note_add_rounded, size: 18),
          child: Text(l10n.addFiles),
        ),
        MenuItemButton(
          onPressed: () => onAction(ToolbarAction.addByIdentifier),
          leadingIcon: const Icon(Symbols.travel_explore_rounded, size: 18),
          child: Text(l10n.addByIdentifier),
        ),
        MenuItemButton(
          onPressed: () => onAction(ToolbarAction.rebuildLibrary),
          leadingIcon: const Icon(Symbols.refresh_rounded, size: 18),
          child: Text(l10n.rebuildLibrary),
        ),
      ],
    );
  }
}
