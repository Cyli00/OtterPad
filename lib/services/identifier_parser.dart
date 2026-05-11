/// 标识符类型
enum IdentifierType { doi, pmid, arxiv, isbn, unknown }

/// 解析后的标识符
class ParsedIdentifier {
  final IdentifierType type;
  final String value;

  const ParsedIdentifier(this.type, this.value);
}

/// 纯 Dart 标识符解析器，识别 DOI / PMID / arXiv ID / ISBN
class IdentifierParser {
  IdentifierParser._();

  static final _doiRegExp = RegExp(r'^10\.\d{4,}/\S+$');
  static final _arxivNewRegExp = RegExp(r'^\d{4}\.\d{4,5}(v\d+)?$');
  static final _arxivOldRegExp = RegExp(
    r'^[a-z][a-z0-9-]*(?:\.[a-z0-9-]+)?/\d{7}(v\d+)?$',
    caseSensitive: false,
  );
  static final _pmidRegExp = RegExp(r'^\d{1,8}$');
  static final _isbn10RegExp = RegExp(r'^\d{9}[\dXx]$');
  static final _isbn13RegExp = RegExp(r'^\d{13}$');
  static final _doiTrailingPunctuationRegExp = RegExp(r'[.,;)\]]+$');
  static final _doiTrailingXmlTagRegExp = RegExp(
    r'</[A-Za-z][^<>\s]*>$',
    caseSensitive: false,
  );
  static final _doiTrailingPdfSuffixRegExp = RegExp(
    r'\.pdf$',
    caseSensitive: false,
  );

  static String? normalizeDoi(String? raw) {
    if (raw == null) return null;
    var input = raw.trim();
    if (input.isEmpty) return null;

    final doiPrefixes = [
      'https://doi.org/',
      'http://doi.org/',
      'https://dx.doi.org/',
      'http://dx.doi.org/',
      'doi:',
    ];
    for (final prefix in doiPrefixes) {
      if (input.toLowerCase().startsWith(prefix.toLowerCase())) {
        input = input.substring(prefix.length).trim();
        break;
      }
    }

    input = input
        .replaceAll(_doiTrailingXmlTagRegExp, '')
        .replaceAll(_doiTrailingPdfSuffixRegExp, '')
        .replaceAll(_doiTrailingPunctuationRegExp, '');
    if (!_doiRegExp.hasMatch(input)) return null;
    return input;
  }

  static ParsedIdentifier parse(String raw) {
    final doi = normalizeDoi(raw);
    if (doi != null) {
      return ParsedIdentifier(IdentifierType.doi, doi);
    }

    // arXiv：去除常见前缀
    var arxivInput = raw.trim();
    final arxivPrefixes = [
      'https://arxiv.org/abs/',
      'http://arxiv.org/abs/',
      'https://arxiv.org/pdf/',
      'http://arxiv.org/pdf/',
      'arXiv:',
      'arxiv:',
    ];
    for (final prefix in arxivPrefixes) {
      if (arxivInput.toLowerCase().startsWith(prefix.toLowerCase())) {
        arxivInput = arxivInput.substring(prefix.length).trim();
        break;
      }
    }
    arxivInput = arxivInput
        .replaceFirst(RegExp(r'[?#].*$'), '')
        .replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '');
    if (_arxivNewRegExp.hasMatch(arxivInput) ||
        _arxivOldRegExp.hasMatch(arxivInput)) {
      return ParsedIdentifier(IdentifierType.arxiv, arxivInput);
    }

    // PMID：去除前缀
    var pmidInput = raw.trim();
    final pmidPrefixes = ['PMID:', 'pmid:', 'Pmid:'];
    for (final prefix in pmidPrefixes) {
      if (pmidInput.startsWith(prefix)) {
        pmidInput = pmidInput.substring(prefix.length).trim();
        break;
      }
    }
    if (_pmidRegExp.hasMatch(pmidInput)) {
      // 避免与 arXiv 旧格式冲突：纯数字且 ≤8 位
      return ParsedIdentifier(IdentifierType.pmid, pmidInput);
    }

    // ISBN：去除连字符和前缀
    var isbnInput = raw.trim();
    final isbnPrefixes = ['isbn-10:', 'isbn-13:', 'isbn:'];
    for (final prefix in isbnPrefixes) {
      if (isbnInput.toLowerCase().startsWith(prefix)) {
        isbnInput = isbnInput.substring(prefix.length).trim();
        break;
      }
    }
    isbnInput = isbnInput.replaceAll(RegExp(r'[-\s]'), '');
    if (_isbn10RegExp.hasMatch(isbnInput) ||
        _isbn13RegExp.hasMatch(isbnInput)) {
      return ParsedIdentifier(IdentifierType.isbn, isbnInput);
    }

    return ParsedIdentifier(IdentifierType.unknown, raw.trim());
  }
}
