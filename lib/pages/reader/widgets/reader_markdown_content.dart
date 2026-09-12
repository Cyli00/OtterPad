import '../../../services/reader/reader_document_index.dart';
import '../../../services/markdown_paragraph_extractor.dart';
import '../../../utils/markdown_translation_weaver.dart';
import 'webview_reader_html.dart';

typedef ReaderMarkdownContent = ({
  String markdown,
  List<Map<String, dynamic>> entries,
});

typedef _Source = ({
  String id,
  TranslatableParagraph paragraph,
  String source,
  String revision,
  bool caption,
});

class ReaderMarkdownPresentation {
  Object? _sourceKey;
  Object? _key;
  String _markdown = '';
  List<_Source> _sources = [];
  final _translated =
      <String, ({String raw, String text, String revision, String html})>{};
  final _entries = <String, Map<String, dynamic>>{};
  ReaderMarkdownContent? _content;

  ReaderMarkdownContent resolve({
    required String markdown,
    required ReaderDocumentIndex index,
    required Map<String, String> translations,
    required DocTranslationMode mode,
    required String language,
  }) {
    final sourceKey = (markdown, index);
    if (_sourceKey != sourceKey) {
      _sourceKey = sourceKey;
      _translated.clear();
      _entries.clear();
      _sources = index.paragraphs
          .map(
            (p) => (
              id: p.id,
              paragraph: p.translatable,
              source: p.plainText,
              revision: p.revision,
              caption: p.isCaption,
            ),
          )
          .toList();
      if (_sources.isEmpty) {
        _sources = MarkdownParagraphExtractor.extract(markdown).map((p) {
          final source = readerPlainText(p.text);
          return (
            id: 'md:${p.offset}:${p.hash}',
            paragraph: p,
            source: source,
            revision: readerTextRevision(source),
            caption: false,
          );
        }).toList();
      }
      final blocks = _sources.where((s) => s.paragraph.offset >= 0).toList()
        ..sort((a, b) => a.paragraph.offset.compareTo(b.paragraph.offset));
      _markdown = markReaderParagraphs(
        markdown: markdown,
        paragraphs: blocks.map((s) => s.paragraph).toList(),
        paragraphIds: {for (final s in blocks) s.paragraph.offset: s.id},
      );
    }
    final key = (sourceKey, translations, mode, language);
    if (_key == key) return _content!;
    _key = key;
    final entries = <Map<String, dynamic>>[];
    for (final source in _sources) {
      final raw = translations[source.paragraph.hash] ?? '';
      var translated = _translated[source.paragraph.hash];
      if (translated == null || translated.raw != raw) {
        final text = readerTranslatedText(raw);
        translated = (
          raw: raw,
          text: text,
          revision: readerTextRevision(text),
          html: raw.isEmpty ? '' : buildReaderTranslationHtml(raw),
        );
        _translated[source.paragraph.hash] = translated;
      }
      final showSource = mode != DocTranslationMode.translated || raw.isEmpty;
      final showTranslation = mode != DocTranslationMode.off;
      var entry = _entries[source.id];
      if (entry == null ||
          entry['html'] != translated.html ||
          entry['language'] != language ||
          entry['showSource'] != showSource ||
          entry['showTranslation'] != showTranslation ||
          entry['bilingual'] != (mode == DocTranslationMode.bilingual)) {
        entry = {
          'id': source.id,
          'source': source.source,
          'sourceRevision': source.revision,
          'translated': translated.text,
          'translatedRevision': translated.revision,
          'html': translated.html,
          'language': language,
          'caption': source.caption,
          'showSource': showSource,
          'showTranslation': showTranslation,
          'bilingual': mode == DocTranslationMode.bilingual,
        };
        _entries[source.id] = entry;
      }
      entries.add(entry);
    }
    return _content = (markdown: _markdown, entries: entries);
  }
}
