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
  static final _arxivOldRegExp = RegExp(r'^[a-z-]+/\d{7}$');
  static final _pmidRegExp = RegExp(r'^\d{1,8}$');
  static final _isbn10RegExp = RegExp(r'^\d{9}[\dXx]$');
  static final _isbn13RegExp = RegExp(r'^\d{13}$');

  static ParsedIdentifier parse(String raw) {
    var input = raw.trim();

    // DOI：去除常见前缀
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
    if (_doiRegExp.hasMatch(input)) {
      return ParsedIdentifier(IdentifierType.doi, input);
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
        // 去除可能的 .pdf 后缀
        if (arxivInput.endsWith('.pdf')) {
          arxivInput = arxivInput.substring(0, arxivInput.length - 4);
        }
        break;
      }
    }
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
    final isbnPrefixes = ['ISBN:', 'isbn:', 'ISBN-10:', 'ISBN-13:'];
    for (final prefix in isbnPrefixes) {
      if (isbnInput.startsWith(prefix)) {
        isbnInput = isbnInput.substring(prefix.length).trim();
        break;
      }
    }
    isbnInput = isbnInput.replaceAll('-', '');
    if (_isbn10RegExp.hasMatch(isbnInput) ||
        _isbn13RegExp.hasMatch(isbnInput)) {
      return ParsedIdentifier(IdentifierType.isbn, isbnInput);
    }

    return ParsedIdentifier(IdentifierType.unknown, raw.trim());
  }
}
