import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../data/models/ocr/doc_extract_config.dart';
import '../services/haptics.dart';
import 'app_dialog.dart';

Future<DocExtractProvider?> showReprocessSourceDialog({
  required BuildContext context,
  required List<DocExtractProvider> sources,
}) => showAppDialog<DocExtractProvider>(
  context: context,
  builder: (context) => AlertDialog(
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    title: Text(context.l10n.reformatSourceChoice),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.reformatSourceChoiceHelp),
        const SizedBox(height: 16),
        for (final source in sources)
          ListTile(
            title: Text(source.label),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onTap: () {
              Haptics.light();
              Navigator.pop(context, source);
            },
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.cancel),
      ),
    ],
  ),
);

Future<DocExtractApiState?> showExtractProviderDialog({
  required BuildContext context,
  required DocExtractApiState apiState,
}) async {
  var selected = apiState.provider;
  final provider = await showAppDialog<DocExtractProvider>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        // 视觉对齐 §3.1 Dialog 规范（titleLarge bold + fromLTRB(24,24,24,20) +
        // 宽度 clamp），不用 Material AlertDialog（其默认 headlineSmall 标题与
        // padding 不符，且在 surfaceContainerLow 上显得笨重）。
        final width = (MediaQuery.of(context).size.width * 0.85).clamp(
          320.0,
          480.0,
        );
        return Material(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: width,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.textExtraction,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.extractProviderChoiceHelp,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<DocExtractProvider>(
                    segments: [
                      for (final option in DocExtractProvider.values)
                        ButtonSegment(value: option, label: Text(option.label)),
                    ],
                    selected: {selected},
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      backgroundColor: cs.surface,
                      selectedBackgroundColor: cs.primaryContainer,
                      foregroundColor: cs.onSurfaceVariant,
                      selectedForegroundColor: cs.onPrimaryContainer,
                      side: BorderSide(color: cs.outlineVariant.withAlpha(100)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onSelectionChanged: (value) {
                      Haptics.soft();
                      setState(() => selected = value.first);
                    },
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.l10n.cancel),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        Haptics.light();
                        Navigator.pop(context, selected);
                      },
                      child: Text(context.l10n.confirm),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  return provider == null ? null : apiState.copyWith(provider: provider);
}
