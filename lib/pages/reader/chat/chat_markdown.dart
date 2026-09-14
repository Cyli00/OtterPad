import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../providers/reader_settings_provider.dart';
import '../widgets/md_widget/nr_markdown_config.dart';

TextStyle chatBodyStyle(ThemeData theme) =>
    theme.textTheme.bodyMedium!.copyWith(height: 1.4);

class ChatMarkdown extends StatelessWidget {
  final String data;
  const ChatMarkdown({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final body = chatBodyStyle(theme).copyWith(color: cs.onSurface);
    final heading = theme.textTheme.titleSmall!.copyWith(
      fontWeight: FontWeight.w600,
    );
    return MarkdownBlock(
      data: data,
      selectable: true,
      config:
          buildReaderMarkdownConfig(
            settings: const ReaderSettingsState(),
            colorScheme: cs,
          ).copy(
            configs: [
              PConfig(textStyle: body),
              H1Config(
                style: theme.textTheme.titleMedium!.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              H2Config(style: heading),
              H3Config(style: heading),
              H4Config(style: heading),
              H5Config(style: heading),
              H6Config(style: heading),
              const ListConfig(marginLeft: 24, marginBottom: 2),
              LinkConfig(
                style: body.copyWith(color: cs.primary),
                onTap: (url) {
                  final uri = Uri.tryParse(url);
                  if (uri != null && {'https', 'http'}.contains(uri.scheme)) {
                    launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              TableConfig(
                headerStyle: body.copyWith(fontWeight: FontWeight.w600),
                bodyStyle: body,
                headPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                bodyPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                border: TableBorder.all(color: cs.outlineVariant.withAlpha(80)),
                wrapper: (table) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: table,
                ),
              ),
              CodeConfig(
                style: body.copyWith(
                  fontFamily: 'monospace',
                  backgroundColor: cs.surfaceContainerHigh,
                ),
              ),
              PreConfig(
                textStyle: body.copyWith(fontFamily: 'monospace'),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
          ),
      generator: buildReaderMarkdownGenerator(
        settings: const ReaderSettingsState(),
        blockSpacing: 4,
      ),
    );
  }
}
