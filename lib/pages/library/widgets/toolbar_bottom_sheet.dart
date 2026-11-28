import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/elevation.dart';
import '../../../core/l10n.dart';
import '../../../widgets/tactile_press.dart';
import '../../../core/design_tokens.dart';

enum ToolbarAction { addFile, addByIdentifier, rebuildLibrary }

Future<ToolbarAction?> showToolbarSheet(BuildContext context) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;

  return showModalBottomSheet<ToolbarAction>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) {
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          // Folio：底部面板是一张纸——纸色底、细线顶边、14 圆角
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            borderRadius: AppRadius.sheetTop,
            border: Border(top: AppStroke.side(colorScheme)),
            boxShadow: AppShadows.sheet,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: AppSpace.x3),
                width: 32,
                height: 3,
                decoration: BoxDecoration(
                  color: colorScheme.outline,
                  borderRadius: BorderRadius.circular(AppRadius.hairline),
                ),
              ),
              const SizedBox(height: AppSpace.x4),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.x6,
                  0,
                  AppSpace.x6,
                  AppSpace.x2,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    eyebrowText(context.l10n.tools),
                    style: AppType.eyebrow(context),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SheetItem(
                        icon: Symbols.note_add_rounded,
                        title: context.l10n.addFiles,
                        subtitle: context.l10n.addFilesSubtitle,
                        onTap: () =>
                            Navigator.pop(context, ToolbarAction.addFile),
                      ),
                      _SheetItem(
                        icon: Symbols.travel_explore_rounded,
                        title: context.l10n.addByIdentifier,
                        subtitle: context.l10n.addByIdentifierSubtitle,
                        onTap: () => Navigator.pop(
                          context,
                          ToolbarAction.addByIdentifier,
                        ),
                      ),
                      _SheetItem(
                        icon: Symbols.refresh_rounded,
                        title: context.l10n.rebuildLibrary,
                        subtitle: context.l10n.rebuildLibrarySubtitle,
                        onTap: () => Navigator.pop(
                          context,
                          ToolbarAction.rebuildLibrary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        ),
      );
    },
  );
}

class _SheetItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SheetItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return TactilePress(
      onTap: onTap,
      baseColor: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: AppRadius.smAll,
              border: Border.all(color: AppStroke.rule(colorScheme)),
            ),
            child: Icon(icon, color: colorScheme.onSurface, size: 20),
          ),
          const SizedBox(width: AppSpace.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Symbols.arrow_forward_rounded,
            color: colorScheme.outline,
            size: 18,
          ),
        ],
      ),
    );
  }
}
