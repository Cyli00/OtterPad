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
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.exportDocuments),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final format in DocumentExportFormat.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  format == DocumentExportFormat.markdown
                      ? Symbols.note_alt_rounded
                      : Symbols.format_quote_rounded,
                ),
                title: Text(
                  format == DocumentExportFormat.markdown
                      ? l10n.exportNotesMarkdown
                      : l10n.exportCitationsBibtex,
                ),
                onTap: () {
                  Haptics.soft();
                  Navigator.pop(dialogContext, format);
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(l10n.cancel),
        ),
      ],
    ),
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
