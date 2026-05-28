import 'package:path/path.dart' as p;

import 'identifier_parser.dart';

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
    r'10\.\d{4,}/[^\s"{}|\\^`\[\]]+',
    caseSensitive: false,
  );

  static final RegExp _yearPattern = RegExp(r'(?:19|20)\d{2}');
  static final RegExp _pdfSuffixPattern = RegExp(
    r'\.pdf$',
    caseSensitive: false,
  );

  // pdfTeX / Word 经常往 PDF /Title 里漏脏数据。这些 case 不应该被当成有效 title。
  static final RegExp _windowsDrivePrefix = RegExp(r'^[A-Za-z]:[\\/]');
  static const _intermediateFileExts = [
    '.eps', '.ps', '.dvi', '.tif', '.tiff',
    '.fig', '.bbl', '.aux', '.log', '.tex',
    '.cls', '.sty', '.synctex',
  ];
  static final RegExp _wordPlaceholderPattern = RegExp(
    r'^(microsoft\s*word\s*-\s*)?document\d*$',
    caseSensitive: false,
  );
  static final RegExp _untitledNumberedPattern = RegExp(
    r'^untitled-?\d+$',
    caseSensitive: false,
  );

  /// 判断 title 字符串是否"看起来像样"——拒绝明显是文件路径、LaTeX 中间产物
  /// 或 Word 占位符的 title。
  ///
  /// pdfTeX 常见坑：作者没显式调 `\pdfinfo{/Title (...)}`，PDF 的 `/Title`
  /// 字段会被打成最后处理的 EPS / DVI 临时文件路径，例如
  /// `/tmp/tpXXXX.eps`。这类 title 显示到 UI 上完全没意义。
  static bool isPlausibleTitle(String? value) {
    if (value == null) return false;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;

    // 文件路径：POSIX `/...`、UNC `\\server\...`、Windows 盘符 `C:\...`
    if (trimmed.startsWith('/') ||
        trimmed.startsWith(r'\\') ||
        _windowsDrivePrefix.hasMatch(trimmed)) {
      return false;
    }

    final lower = trimmed.toLowerCase();
    for (final ext in _intermediateFileExts) {
      if (lower.endsWith(ext)) return false;
    }

    if (lower == 'untitled') return false;
    if (_wordPlaceholderPattern.hasMatch(lower)) return false;
    if (_untitledNumberedPattern.hasMatch(lower)) return false;

    return true;
  }

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
    return IdentifierParser.normalizeDoi(match.group(0));
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
