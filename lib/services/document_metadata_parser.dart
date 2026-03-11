import 'package:path/path.dart' as p;

class DocumentMetadata {
  final String? title;
  final List<String> authors;
  final String? journal;
  final String? year;
  final String? doi;

  const DocumentMetadata({
    this.title,
    this.authors = const [],
    this.journal,
    this.year,
    this.doi,
  });

  bool get hasAny {
    return (title != null && title!.isNotEmpty) ||
        authors.isNotEmpty ||
        (journal != null && journal!.isNotEmpty) ||
        (year != null && year!.isNotEmpty) ||
        (doi != null && doi!.isNotEmpty);
  }

  DocumentMetadata merge(DocumentMetadata other) {
    return DocumentMetadata(
      title: _pickString(other.title, title),
      authors: other.authors.isNotEmpty ? other.authors : authors,
      journal: _pickString(other.journal, journal),
      year: _pickString(other.year, year),
      doi: _pickString(other.doi, doi),
    );
  }

  static String? _pickString(String? primary, String? fallback) {
    final normalizedPrimary = _normalizeOptional(primary);
    if (normalizedPrimary != null) return normalizedPrimary;
    return _normalizeOptional(fallback);
  }

  static String? _normalizeOptional(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class DocumentMetadataParser {
  static final RegExp _doiPattern = RegExp(
    r'10\.\d{4,}/[^\s<>"{}|\\^`\[\]]+',
    caseSensitive: false,
  );

  static final RegExp _yearPattern = RegExp(r'(?:19|20)\d{2}');
  static final RegExp _pdfSuffixPattern = RegExp(
    r'\.pdf$',
    caseSensitive: false,
  );
  static final RegExp _trailingPunctuationPattern = RegExp(r'[.,;)\]]+$');

  static DocumentMetadata parseFilePath(String filePath) {
    return parseText(p.basename(filePath));
  }

  static DocumentMetadata parseText(String text) {
    final normalized = _normalizeText(text);
    if (normalized.isEmpty) return const DocumentMetadata();

    final structured = _parseStructuredText(normalized);
    if (structured.hasAny) return structured;

    return DocumentMetadata(
      doi: extractDoi(normalized),
      year: extractYear(normalized),
    );
  }

  static String? extractDoi(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final normalizedInput = text
        .replaceAll(
          RegExp(r'https?://(?:dx\.)?doi\.org/', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'^doi:\s*', caseSensitive: false), '')
        .trim();
    final match = _doiPattern.firstMatch(normalizedInput);
    if (match == null) return null;
    return match.group(0)?.replaceAll(_trailingPunctuationPattern, '');
  }

  static String? extractYear(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    return _yearPattern.firstMatch(text)?.group(0);
  }

  static String normalizeWhitespace(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _normalizeText(String text) {
    return normalizeWhitespace(text.replaceAll(_pdfSuffixPattern, ''));
  }

  static DocumentMetadata _parseStructuredText(String text) {
    final direct = _parseYearLeadingText(text);
    if (direct.hasAny) return direct;

    for (final match in _yearPattern.allMatches(text)) {
      final parsed = _parseYearLeadingText(text.substring(match.start));
      if (parsed.hasAny) return parsed;
    }

    return const DocumentMetadata();
  }

  static DocumentMetadata _parseYearLeadingText(String text) {
    final normalized = _normalizeText(text);
    final parts = normalized
        .split('-')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length < 3 || !RegExp(r'^\d{4}$').hasMatch(parts.first)) {
      return const DocumentMetadata();
    }

    final title = parts.sublist(2).join('-').trim();
    if (title.isEmpty) return const DocumentMetadata();

    return DocumentMetadata(
      title: title,
      authors: [parts[1]],
      year: parts.first,
      doi: extractDoi(normalized),
    );
  }
}
