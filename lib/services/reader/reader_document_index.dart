import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html;
import 'package:markdown/markdown.dart' as md;

import '../../data/models/book/reader_anchor.dart';
import '../../utils/doc_paths.dart';
import '../../utils/markdown_preprocessor.dart';
import '../document_structure.dart';
import '../figure_extract_service.dart';
import '../markdown_paragraph_extractor.dart';
import '../translation_skip_sections.dart';
import 'reader_figure_captions.dart';

String readerPlainText(String value) =>
    html
        .parseFragment(
          md.markdownToHtml(
            value,
            extensionSet: md.ExtensionSet.gitHubWeb,
            inlineSyntaxes: [_ReaderMathSyntax()],
          ),
        )
        .text
        ?.replaceAll(RegExp(r'\s+'), ' ')
        .trim() ??
    '';

String readerCopyText(String value) => value
    .split(RegExp(r'\r?\n\s*\r?\n'))
    .map(
      (paragraph) => paragraph
          .replaceAllMapped(
            RegExp(r'([A-Za-z])[-\u00ad]\r?\n\s*([a-z])'),
            (m) => '${m[1]}${m[2]}',
          )
          .replaceAll(RegExp(r'(?<=[㐀-鿿])[ \t]*\r?\n[ \t]*(?=[㐀-鿿])'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim(),
    )
    .where((paragraph) => paragraph.isNotEmpty)
    .join('\n\n');

String readerTextRevision(String value) =>
    sha256.convert(utf8.encode(value)).toString();

String readerTranslatedText(String value) =>
    readerPlainText(MarkdownPreprocessor.processTranslation(value));

class _ReaderMathSyntax extends md.InlineSyntax {
  _ReaderMathSyntax() : super(r'\$[^$\n]+\$|\\\([\s\S]*?\\\)');
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Text(match[0]!));
    return true;
  }
}

class ReaderParagraph {
  final String id;
  final int pageIndex;
  final LayoutBlock block;
  final List<double>? pageSize;
  final String text;
  final String? translationText;
  final int? markdownStart;
  final int? markdownEnd;
  final List<List<double>> visualBboxes;
  final List<List<double>> protectedBboxes;

  ReaderParagraph({
    required this.id,
    required this.pageIndex,
    required this.block,
    required this.pageSize,
    required this.text,
    this.translationText,
    this.markdownStart,
    this.markdownEnd,
    this.visualBboxes = const [],
    this.protectedBboxes = const [],
  });

  List<LayoutTextRegion> get regions => block.textRegions.isNotEmpty
      ? block.textRegions
      : [LayoutTextRegion(pageIndex, block.blockBbox, plainText.length)];

  late final String hash = MarkdownParagraphExtractor.computeHash(
    translationText ?? text,
  );
  late final String plainText = readerPlainText(text).trim();
  late final String revision = readerTextRevision(plainText);
  bool get isHeading => const {
    'doc_title',
    'paragraph_title',
    'title',
    'section_title',
  }.contains(block.blockLabel);
  bool get isCaption => readerCaptionLabels.contains(block.blockLabel);

  TranslatableParagraph get translatable => TranslatableParagraph(
    offset: markdownStart ?? -1,
    length: markdownStart == null ? 0 : markdownEnd! - markdownStart!,
    text: text,
    hash: hash,
    kind: isHeading ? ParagraphKind.heading : ParagraphKind.text,
  );

  ReaderAnchor anchor({
    String language = 'source',
    String? displayText,
    int start = 0,
    int? end,
  }) {
    final value = displayText ?? plainText;
    final stop = end ?? value.length;
    return ReaderAnchor([
      ReaderAnchorRange(
        paragraphId: id,
        language: language,
        revision: readerTextRevision(value),
        start: start,
        end: stop,
        quote: value.substring(start, stop),
        prefix: value.substring((start - 32).clamp(0, start), start),
        suffix: value.substring(stop, (stop + 32).clamp(stop, value.length)),
      ),
    ]);
  }
}

class ReaderDocumentIndex {
  final List<ReaderParagraph> paragraphs;
  final bool hasStructure;
  final List<StructurePage> pages;
  final List<FigureManifestEntry> figures;
  const ReaderDocumentIndex(
    this.paragraphs, {
    this.hasStructure = true,
    this.pages = const [],
    this.figures = const [],
  });
  static const empty = ReaderDocumentIndex([], hasStructure: false);

  static Future<ReaderDocumentIndex> load(
    String documentId,
    String markdown,
  ) async {
    final figures = FigureExtractService.loadManifest(documentId);
    final structure = await DocumentStructure.load(DocPaths.json(documentId));
    return build(structure, markdown, figures: await figures ?? const []);
  }

  List<TranslatableParagraph> get figureParagraphs => [
    for (final figure in figures.where((f) => f.isDisplayFigure))
      TranslatableParagraph(
        offset: -1,
        length: 0,
        text: figure.captionText.trim(),
        hash: MarkdownParagraphExtractor.computeHash(figure.captionText),
        kind: ParagraphKind.text,
      ),
  ];

  static bool canTranslate(LayoutBlock block, StructurePage page) {
    const captions = readerCaptionLabels;
    const allowed = {
      'text',
      'paragraph',
      'abstract',
      'doc_title',
      'paragraph_title',
      'title',
      'section_title',
      'list',
    };
    if (!captions.contains(block.blockLabel) &&
        !allowed.contains(block.blockLabel)) {
      return false;
    }
    if (RegExp(
      r'<table\b|^\s*\|[- :|]+\|\s*$',
      caseSensitive: false,
      multiLine: true,
    ).hasMatch(block.blockContent)) {
      return false;
    }
    final visuals = page.blocks.where(
      (b) => const {
        'image',
        'chart',
        'table',
        'image_body',
        'chart_body',
        'table_body',
      }.contains(b.blockLabel),
    );
    for (final visual in visuals) {
      if (!captions.contains(block.blockLabel) &&
          block.parentId != null &&
          (block.parentId == visual.parentId ||
              block.parentId == visual.blockId)) {
        return false;
      }
      final b = visual.blockBbox;
      if (b.length != 4) continue;
      final boxes = block.textRegions.isEmpty
          ? [block.blockBbox]
          : block.textRegions
                .where((r) => r.pageIndex == page.pageIndex)
                .map((r) => r.bbox);
      // 合并段落的总外框可能跨过图表，只检查当前页实际占用的文字区域。
      for (final a in boxes) {
        if (a.length != 4) continue;
        final w = a[2].clamp(b[0], b[2]) - a[0].clamp(b[0], b[2]);
        final h = a[3].clamp(b[1], b[3]) - a[1].clamp(b[1], b[3]);
        if (w * h > 0) return false;
      }
    }
    return block.blockContent.trim().isNotEmpty;
  }

  static ReaderDocumentIndex build(
    DocumentStructure structure,
    String markdown, {
    List<FigureManifestEntry> figures = const [],
  }) {
    if (structure.isEmpty) {
      return ReaderDocumentIndex(
        const [],
        hasStructure: false,
        figures: figures,
      );
    }
    structure = readerFigureCaptionStructure(structure, figures);
    final raw = _ComparableText(markdown);
    final markdownParagraphs = MarkdownParagraphExtractor.extract(markdown);
    final eligible =
        <
          ({StructurePage page, LayoutBlock block, String key, String identity})
        >[];
    final sourceCounts = <String, int>{};
    for (final page in structure.pages) {
      for (final block in page.blocks) {
        if (!canTranslate(block, page)) continue;
        final identity = _ComparableText(block.blockContent).text;
        final simplified = _ComparableText(
          MarkdownPreprocessor.process(block.blockContent),
        ).text;
        final key =
            raw.text.contains(identity) || !raw.text.contains(simplified)
            ? identity
            : simplified;
        if (key.isEmpty) continue;
        eligible.add((page: page, block: block, key: key, identity: identity));
        sourceCounts.update(key, (n) => n + 1, ifAbsent: () => 1);
      }
    }
    final occurrences = <String, int>{};
    final identities = <String, int>{};
    final result = <ReaderParagraph>[];
    for (final entry in eligible) {
      final hits = <int>[];
      var cursor = 0;
      while (cursor < raw.text.length) {
        final at = raw.text.indexOf(entry.key, cursor);
        if (at < 0) break;
        hits.add(at);
        cursor = at + entry.key.length;
      }
      final occurrence = occurrences.update(
        entry.key,
        (n) => n + 1,
        ifAbsent: () => 0,
      );
      final identity =
          'p${entry.page.pageIndex}_${readerTextRevision(entry.identity).substring(0, 16)}';
      final duplicate = identities.update(
        identity,
        (n) => n + 1,
        ifAbsent: () => 0,
      );
      // 重复文本只有数量一致才按阅读顺序配对，避免把缺失的图注绑到正文引用。
      final at = hits.length == sourceCounts[entry.key]
          ? hits[occurrence]
          : null;
      int? start = at == null ? null : raw.offsets[at];
      int? end = at == null ? null : raw.offsets[at + entry.key.length - 1] + 1;
      if (start != null && end != null) {
        for (final candidate in markdownParagraphs) {
          if (candidate.offset <= start! &&
              candidate.offset + candidate.length >= end! &&
              _ComparableText(candidate.text).text == entry.key) {
            start = candidate.offset;
            end = candidate.offset + candidate.length;
            break;
          }
        }
      }
      result.add(
        ReaderParagraph(
          id: '${identity}_${sourceCounts[entry.key]}_$duplicate',
          pageIndex: entry.page.pageIndex,
          visualBboxes: entry.page.blocks
              .where(
                (b) => const {'image', 'chart', 'table'}.contains(b.blockLabel),
              )
              .map((b) => b.blockBbox)
              .where((b) => b.length == 4)
              .toList(),
          protectedBboxes: entry.page.blocks
              .where((b) => !canTranslate(b, entry.page))
              .map((b) => b.blockBbox)
              .where((b) => b.length == 4)
              .toList(),
          block: entry.block,
          pageSize: entry.page.pageSize,
          translationText: readerCaptionLabels.contains(entry.block.blockLabel)
              ? entry.block.blockContent.trim()
              : null,
          text: start == null
              ? entry.block.blockContent.trim()
              : markdown.substring(start, end!),
          markdownStart: start,
          markdownEnd: end,
        ),
      );
    }
    return ReaderDocumentIndex(
      result,
      pages: structure.pages,
      figures: figures,
    );
  }

  List<ReaderParagraph> translationParagraphs(
    String markdown,
    List<String> ignored,
  ) {
    final skips = detectSkipSections(
      markdown,
    ).where((s) => ignored.contains(s.id)).toList();
    var previousOffset = 0;
    final result = <ReaderParagraph>[];
    for (final p in paragraphs) {
      final start = p.markdownStart ?? previousOffset;
      final end = p.markdownEnd ?? start + 1;
      if (p.markdownStart != null) previousOffset = p.markdownStart!;
      if (!skips.any((s) => start < s.contentEnd && end > s.contentStart)) {
        result.add(p);
      }
    }
    return result;
  }

  ReaderParagraph? byId(String id) {
    for (final p in paragraphs) {
      if (p.id == id) return p;
    }
    return null;
  }

  ReaderParagraph? paragraphForQuote(
    String quote, {
    ReaderAnchor? anchor,
    Map<String, String> translations = const {},
  }) {
    for (final range in anchor?.ranges ?? <ReaderAnchorRange>[]) {
      final paragraph = byId(range.paragraphId);
      if (paragraph == null) continue;
      final text = range.language == 'source'
          ? paragraph.plainText
          : readerTranslatedText(translations[paragraph.hash] ?? '');
      if (text.isEmpty && range.language != 'source' ||
          range.resolve(text, readerTextRevision(text)) != null) {
        return paragraph;
      }
    }
    String comparable(String value) =>
        readerPlainText(value).replaceAll(RegExp(r'[\s\u00ad\u200b]+'), '');
    final key = comparable(quote);
    if (key.isEmpty) return null;
    final matches = paragraphs
        .where(
          (paragraph) =>
              comparable(paragraph.plainText).contains(key) ||
              comparable(translations[paragraph.hash] ?? '').contains(key),
        )
        .toList();
    return matches.length == 1 ? matches.single : null;
  }
}

class _ComparableText {
  final String text;
  final List<int> offsets;
  factory _ComparableText(String input) {
    final excluded = <int>{};
    for (final pattern in [
      RegExp(r'!\[[^\]]*\]\([^)]*\)'),
      RegExp(r'<[^>]*>'),
      RegExp(r'\]\([^)]*\)'),
      RegExp(r'<!--.*?-->', dotAll: true),
    ]) {
      for (final m in pattern.allMatches(input)) {
        for (var i = m.start; i < m.end; i++) {
          excluded.add(i);
        }
      }
    }
    final buffer = StringBuffer();
    final offsets = <int>[];
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (excluded.contains(i) ||
          RegExp(r'[\s#$*_`>\[\]!\-]').hasMatch(c) ||
          c == '\u00ad') {
        continue;
      }
      buffer.write(c);
      offsets.add(i);
    }
    return _ComparableText._(buffer.toString(), offsets);
  }
  const _ComparableText._(this.text, this.offsets);
}
