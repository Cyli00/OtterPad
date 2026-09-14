import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/l10n.dart';
import '../../../core/storage/app_database_provider.dart';
import '../../../services/document_export_service.dart';
import '../../../services/haptics.dart';
import '../../../services/snackbar_service.dart';
import '../../../utils/desktop.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/app_divider.dart';
import '../../../widgets/tactile_press.dart';

enum DocumentExportFormat { markdown, bibtex }

Future<void> showDocumentExport(
  BuildContext context,
  WidgetRef ref,
  Iterable<String> documentIds,
) async {
  final ids = documentIds.toSet();
  if (ids.isEmpty) return;
  final l10n = context.l10n;
  final database = ref.read(appDatabaseProvider);
  final snackbar = ref.read(snackBarServiceProvider);
  final box = context.findRenderObject();
  final origin = box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  final format = await showAppDialog<DocumentExportFormat>(
    context: context,
    builder: (dialogContext) => _DocumentExportDialog(count: ids.length),
  );
  if (format == null || !context.mounted) return;
  try {
    final entries = await DocumentExportService.load(database, ids);
    if (!context.mounted) return;
    if (entries.isEmpty) {
      snackbar.showResult(message: l10n.exportNoDocuments);
      return;
    }
    final markdown = format == DocumentExportFormat.markdown;
    final content = markdown
        ? DocumentExportService.markdown(
            entries,
            highlightsHeading: l10n.highlightsAndNotes,
            noteHeading: l10n.notes,
            emptyMessage: l10n.exportNoNotes,
          )
        : DocumentExportService.bibtex(entries);
    final bytes = Uint8List.fromList(utf8.encode(content));
    final name = 'OtterPad-${markdown ? 'notes.md' : 'references.bib'}';
    if (isDesktopOs) {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: l10n.exportDocuments,
        fileName: name,
        type: FileType.custom,
        allowedExtensions: [markdown ? 'md' : 'bib'],
        lockParentWindow: true,
      );
      if (path == null) return;
      await File(path).writeAsBytes(bytes, flush: true);
      if (context.mounted) {
        snackbar.showResult(message: l10n.documentExportSaved);
      }
    } else {
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: markdown ? 'text/markdown' : 'application/x-bibtex',
          ),
        ],
        fileNameOverrides: [name],
        sharePositionOrigin: origin,
      );
    }
  } catch (e) {
    if (context.mounted) snackbar.showResult(message: l10n.exportFailed('$e'));
  }
}

class _DocumentExportDialog extends StatelessWidget {
  const _DocumentExportDialog({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;
    return Dialog(
      backgroundColor: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.exportDocuments,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.exportSelectionSummary(count),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              Flexible(
                child: SingleChildScrollView(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _choice(
                          context,
                          DocumentExportFormat.markdown,
                          Symbols.note_alt_rounded,
                          l10n.exportNotesMarkdown,
                          l10n.exportNotesDescription,
                        ),
                        const AppDivider(),
                        _choice(
                          context,
                          DocumentExportFormat.bibtex,
                          Symbols.format_quote_rounded,
                          l10n.exportCitationsBibtex,
                          l10n.exportCitationsDescription,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.cancel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _choice(
    BuildContext context,
    DocumentExportFormat format,
    IconData icon,
    String title,
    String description,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    void activate() {
      Haptics.soft();
      Navigator.pop(context, format);
    }

    var focused = false;
    return StatefulBuilder(
      builder: (context, setState) {
        return FocusableActionDetector(
          onShowFocusHighlight: (value) => setState(() => focused = value),
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                activate();
                return null;
              },
            ),
          },
          child: Semantics(
            button: true,
            onTap: activate,
            child: TactilePress(
              onTap: activate,
              haptics: false,
              baseColor: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: focused ? cs.primary : Colors.transparent,
              ),
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: cs.onPrimaryContainer, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
