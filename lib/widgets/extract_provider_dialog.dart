import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../providers/api_provider.dart';
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
        final cs = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: Text(context.l10n.textExtraction),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.extractProviderChoiceHelp),
                const SizedBox(height: 16),
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
                      side: BorderSide(color: cs.outlineVariant.withAlpha(100)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onSelectionChanged: (value) {
                      Haptics.soft();
                      setState(() => selected = value.first);
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.cancel),
            ),
            TextButton(
              onPressed: () {
                Haptics.light();
                Navigator.pop(context, selected);
              },
              child: Text(context.l10n.confirm),
            ),
          ],
        );
      },
    ),
  );
  return provider == null ? null : apiState.copyWith(provider: provider);
}
