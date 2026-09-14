import 'package:flutter/material.dart';
import 'l10n.dart';
import 'paper_surfaces.dart';
import 'paper_theme.dart';

Future<PaperFont?> showPaperDisplaySettings(
  BuildContext context,
  PaperFont current,
) {
  var draft = current;
  final l = context.l10n;
  return showPaperDialog<PaperFont>(
    context,
    (context) => StatefulBuilder(
      builder: (context, update) => PaperDialog(
        title: l.displaySettings,
        children: [
          PaperOptions(
            label: l.interfaceFont,
            availableWidth: (MediaQuery.sizeOf(context).width - 80).clamp(
              0,
              480,
            ),
            help: l.interfaceFontHelp,
            value: draft.name,
            options: {'sans': l.fontSans, 'serif': l.fontSerif},
            onChanged: (value) =>
                update(() => draft = PaperFont.values.byName(value)),
          ),
        ],
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draft),
            child: Text(l.save),
          ),
        ],
      ),
    ),
  );
}
