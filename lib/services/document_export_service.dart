import 'dart:convert';

import '../core/storage/app_database.dart' show AppDatabase;
import '../core/storage/db_convert.dart';
import '../data/models/book/document.dart';
import '../data/models/book/highlight.dart';

class DocumentExportEntry {
  const DocumentExportEntry(this.document, this.highlights);

  final Document document;
  final List<Highlight> highlights;
}

class DocumentExportService {
  static Future<List<DocumentExportEntry>> load(
    AppDatabase database,
    Iterable<String> documentIds,
  ) => database.transaction(() async {
    final entries = <DocumentExportEntry>[];
    for (final id in documentIds.toSet()) {
      final row = await (database.select(
        database.documents,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) continue;
      final highlights = await (database.select(
        database.highlights,
      )..where((t) => t.docId.equals(id))).map(highlightFromRow).get();
      highlights.sort((a, b) {
        final time = a.createdAt.compareTo(b.createdAt);
        return time == 0 ? a.id.compareTo(b.id) : time;
      });
      entries.add(DocumentExportEntry(documentFromRow(row), highlights));
    }
    return entries;
  });

  static String markdown(
    List<DocumentExportEntry> entries, {
    required String highlightsHeading,
    required String noteHeading,
    required String emptyMessage,
  }) {
    final out = StringBuffer();
    for (final entry in entries) {
      if (out.isNotEmpty) out.writeln('\n---\n');
      final doc = entry.document;
      out.writeln('# ${_markdownText(doc.title)}\n');
      for (final value in [
        doc.authors.join(' · '),
        doc.journal ?? '',
        doc.year ?? '',
        if (doc.doi?.isNotEmpty == true) 'DOI: ${doc.doi}',
      ]) {
        if (value.trim().isNotEmpty) out.writeln('${_markdownText(value)}\n');
      }
      out.writeln('ID: ${_markdownText(doc.id)}\n');
      out.writeln('## $highlightsHeading\n');
      if (entry.highlights.isEmpty) out.writeln('$emptyMessage\n');
      final groups = <String, List<Highlight>>{};
      for (final h in entry.highlights) {
        final key = h.groupId == null ? 'item:${h.id}' : 'group:${h.groupId}';
        groups.putIfAbsent(key, () => []).add(h);
      }
      var number = 0;
      for (final group in groups.values) {
        out.writeln('### ${++number}\n');
        for (final h in group) {
          out.writeln(
            _markdownText(h.text).split('\n').map((s) => '> $s').join('\n'),
          );
          out.writeln();
        }
        final notes = group
            .map((h) => h.note?.trim() ?? '')
            .where((s) => s.isNotEmpty)
            .toSet();
        if (notes.isNotEmpty) {
          out.writeln('**$noteHeading**\n');
          for (final note in notes) {
            out.writeln('${_markdownText(note)}\n');
          }
        }
        out.writeln('${group.first.createdAt.toUtc().toIso8601String()}\n');
      }
    }
    return out.toString();
  }

  static String bibtex(List<DocumentExportEntry> entries) {
    return entries
        .map((entry) {
          final doc = entry.document;
          final key = base64Url.encode(utf8.encode(doc.id)).replaceAll('=', '');
          // 现有题录没有出版类型，journal 也可能装书名或出版社，不能据此猜成期刊论文。
          final fields = <String, String>{
            'title': '{${_bibText(doc.title)}}',
            if (doc.authors.isNotEmpty)
              'author': doc.authors
                  .map((a) => '{${_bibText(a)}}')
                  .join(' and '),
            if (doc.journal?.isNotEmpty == true)
              'howpublished': _bibText(doc.journal!),
            if (doc.year?.isNotEmpty == true) 'year': _bibText(doc.year!),
            if (doc.doi?.isNotEmpty == true) 'doi': _bibText(doc.doi!),
            if (doc.keywords.isNotEmpty)
              'keywords': _bibText(doc.keywords.join(', ')),
          };
          return '@misc{otter_$key,\n${fields.entries.map((f) => '  ${f.key} = {${f.value}}').join(',\n')}\n}\n';
        })
        .join('\n');
  }

  static String _markdownText(String value) => value
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAllMapped(RegExp(r'[\\`*_{}\[\]()#+.!|~-]'), (m) => '\\${m[0]}');

  static String _bibText(String value) => value.replaceAllMapped(
    RegExp(r'[\\{}%&#_$~^]|[\r\n]+'),
    (m) => switch (m[0]) {
      r'\' => r'\textbackslash{}',
      '~' => r'\textasciitilde{}',
      '^' => r'\textasciicircum{}',
      final s when s!.contains('\n') || s.contains('\r') => ' ',
      final s => '\\$s',
    },
  );
}
