import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import '../../../core/l10n.dart';
import '../../../services/table_parse_service.dart';

/// 原图之上的本地解析层；不另开弹窗、不加载外部 HTML 资源。
class FigureDataOverlay extends StatelessWidget {
  final FigureParsedData data;
  const FigureDataOverlay({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), cs = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, box) {
        final columns = data.parts
            .expand((p) => p.tables)
            .fold(1, (value, table) => math.max(value, table.columnCount));
        return SelectionArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.figureDataSource,
                  style: theme.textTheme.bodySmall,
                ),
                if (data.incomplete) ...[
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.figureDataIncomplete,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
                  ),
                ],
                for (final part in data.parts) ...[
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.tableSourcePages('${part.pageIndex + 1}'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: math.max(
                        math.max(0, box.maxWidth - 32),
                        columns * 100.0,
                      ),
                      child: HtmlWidget(
                        part.htmlText,
                        textStyle: theme.textTheme.bodyMedium,
                        customStylesBuilder: (element) =>
                            switch (element.localName) {
                              'table' => {
                                'border-collapse': 'collapse',
                                'width': '100%',
                              },
                              'td' || 'th' => {
                                'border':
                                    '1px solid ${_cssColor(cs.outlineVariant)}',
                                'padding': '10px',
                                'white-space': 'pre-wrap',
                              },
                              _ => null,
                            },
                      ),
                    ),
                  ),
                ],
                for (final note in data.notes) ...[
                  const SizedBox(height: 12),
                  Text(note),
                ],
                if (data.canCopyTsv) ...[
                  const SizedBox(height: 16),
                  Text(
                    context.l10n.tableFlattenNote,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _cssColor(Color color) =>
      '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';
}
