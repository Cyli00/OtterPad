import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n.dart';
import '../../../data/models/book/document.dart';
import '../../../services/haptics.dart';
import '../../../services/snackbar_service.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/tactile_press.dart';

Future<void> showDocumentInfoDialog({
  required BuildContext context,
  required Document document,
}) {
  return showAppDialog(
    context: context,
    builder: (context) => _DocumentInfoDialog(document: document),
  );
}

class _DocumentInfoDialog extends ConsumerWidget {
  final Document document;

  const _DocumentInfoDialog({required this.document});

  void _copy(BuildContext context, WidgetRef ref, String text) {
    Haptics.soft();
    Clipboard.setData(ClipboardData(text: text));
    ref.read(snackBarServiceProvider).showResult(
      message: context.l10n.copiedToClipboard,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dialogWidth = (screenWidth * 0.85).clamp(320.0, 540.0);

    final rows = <(String, String)>[
      (l10n.author, document.authors.join(', ')),
      (l10n.journal, document.journal ?? ''),
      (l10n.year, document.year ?? ''),
      ('DOI', document.doi ?? ''),
      if (document.keywords.isNotEmpty)
        ('Keywords', document.keywords.join(', ')),
    ];

    return AlertDialog(
      backgroundColor: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      content: SizedBox(
        width: dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            TactilePress(
              baseColor: Colors.transparent,
              onTap: () => _copy(context, ref, document.title),
              borderRadius: BorderRadius.circular(10),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                document.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 信息行
            ...rows
                .where((r) => r.$2.isNotEmpty)
                .map((r) => _InfoRow(
                      label: r.$1,
                      value: r.$2,
                      onCopy: () => _copy(context, ref, r.$2),
                    )),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Haptics.soft();
            Navigator.pop(context);
          },
          child: Text(l10n.close),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onCopy;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: TactilePress(
        onTap: onCopy,
        baseColor: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 68,
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
