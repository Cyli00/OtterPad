import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html;

import 'document_structure.dart';
import 'figure_extract_service.dart';
import 'table_parse_result.dart';

class FigureDataPart {
  final int pageIndex;
  final String blockId;
  final List<TableParseResult> tables;
  final String text;

  const FigureDataPart({
    required this.pageIndex,
    required this.blockId,
    required this.tables,
    required this.text,
  });

  String get markdown => [
    ...tables.map((t) => t.markdown),
    if (text.isNotEmpty) text,
  ].join('\n\n');
  String get htmlText => [
    ...tables.map((t) => t.htmlText),
    if (text.isNotEmpty) '<pre>${const HtmlEscape().convert(text)}</pre>',
  ].join('\n');
}

class FigureParsedData {
  final List<FigureDataPart> parts;
  final List<String> notes;
  final bool stale;
  final bool incomplete;
  const FigureParsedData({
    this.parts = const [],
    this.notes = const [],
    this.stale = false,
    this.incomplete = false,
  });

  bool get hasData => parts.isNotEmpty;
  bool get canCopyTsv => hasData && parts.every((p) => p.tables.isNotEmpty);
  String get tsv =>
      parts.expand((p) => p.tables).map((t) => t.tsv).join('\n\n');
  String get markdown =>
      [...parts.map((p) => p.markdown), ...notes].join('\n\n');

  String htmlDocument(String caption) =>
      '<!doctype html><html><head><meta charset="utf-8">'
      '<title>${const HtmlEscape().convert(caption)}</title>'
      '<style>body{font-family:system-ui;margin:24px}'
      'table{border-collapse:collapse;margin-bottom:24px}'
      'th,td{border:1px solid #888;padding:8px;white-space:pre-wrap}'
      'pre{white-space:pre-wrap}</style></head><body>'
      '<h1>${const HtmlEscape().convert(caption)}</h1>'
      '${parts.map((p) => p.htmlText).join('\n')}'
      '${notes.map((n) => '<p>${const HtmlEscape().convert(n)}</p>').join()}'
      '</body></html>';
}

/// 只读 extract.json；不依赖模型、网络、API Key 或旧的 LLM 缓存。
class TableParseService {
  final DocumentStructure structure;
  late final String _version = sha256
      .convert(utf8.encode(jsonEncode(structure.toJson())))
      .toString();

  TableParseService(this.structure);

  static Future<TableParseService> read(String jsonPath) async {
    final structure = DocumentStructure.parse(
      await File(jsonPath).readAsString(),
    );
    if (structure.isEmpty) throw const FormatException('extract_structure');
    return TableParseService(structure);
  }

  FigureParsedData forFigure(FigureManifestEntry figure) {
    if (figure.sourceVersion != null && figure.sourceVersion != _version) {
      return const FigureParsedData(stale: true);
    }
    final parts = <FigureDataPart>[];
    final visited = <(int, String)>{};
    var incomplete = false;
    for (final region in figure.regions) {
      final page = structure.pages
          .where((page) => page.pageIndex == region.pageIndex)
          .firstOrNull;
      // 同页 blockId 才有意义，绝不退回「最近一张表」。
      final ids = {
        ...region.blockIds,
        ...figure.sourceRefs
            .where((ref) => ref['page_idx'] == region.pageIndex)
            .map((ref) => ref['block_id'])
            .whereType<String>(),
      };
      if (page == null) {
        incomplete = true;
        continue;
      }
      if (ids.any((id) => !page.blocks.any((block) => block.blockId == id))) {
        incomplete = true;
      }
      for (final block in page.blocks) {
        if (!ids.contains(block.blockId) ||
            !const {'table', 'chart'}.contains(block.blockLabel) ||
            !visited.add((page.pageIndex, block.blockId))) {
          continue;
        }
        final content = block.blockContent.trim();
        if (content.isEmpty) {
          incomplete = true;
          continue;
        }
        try {
          final tables = TableParseResult.fromHtml(content);
          var text = '';
          if (tables.isEmpty) {
            final markdown = TableParseResult.fromMarkdown(content);
            if (markdown != null) tables.add(markdown);
            if (markdown == null) {
              text = TableParseResult.plainText(
                html.parseFragment(content),
              ).trim();
            }
          } else {
            final fragment = html.parseFragment(content);
            final captions = fragment
                .querySelectorAll('caption')
                .map(TableParseResult.plainText)
                .toList();
            for (final table in fragment.querySelectorAll('table')) {
              table.remove();
            }
            text = [
              ...captions,
              TableParseResult.plainText(fragment),
            ].map((s) => s.trim()).where((s) => s.isNotEmpty).join('\n');
          }
          if (tables.isEmpty &&
              (text.isEmpty ||
                  RegExp(r'^!\[[^\]]*\]\([^)]*\)$').hasMatch(text))) {
            incomplete = true;
            continue;
          }
          parts.add(
            FigureDataPart(
              pageIndex: page.pageIndex,
              blockId: block.blockId,
              tables: tables,
              text: text,
            ),
          );
        } on FormatException {
          incomplete = true;
        }
      }
    }
    return FigureParsedData(
      parts: List.unmodifiable(parts),
      notes: figure.notes,
      incomplete: incomplete,
    );
  }
}
