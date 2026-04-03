class MarkdownPreprocessor {
  static String process(String markdown) {
    var result = markdown;
    result = _sanitizeLatex(result);
    result = _fixLatexSpacing(result);
    result = _promoteInlineEquations(result);
    result = _simplifyInlineLatex(result);
    result = _normalizeInlineSpacing(result);
    result = result.replaceAll(RegExp(r'<table[^>]*>\s*</table>'), '');
    return result;
  }

  /// 通过元数据标题匹配，过滤 Markdown 中标题行之前的冗余内容（如期刊名）。
  ///
  /// 例如提取结果为：
  /// ```
  /// # Cell Metabolism
  /// # Microglial lipid droplet accumulation in tauopathy brain...
  /// ```
  /// 传入 title="Microglial lipid droplet accumulation..."，
  /// 则会删除 "# Cell Metabolism" 及其之前的所有内容。
  static String filterBeforeTitle(String markdown, String? title) {
    if (title == null || title.trim().isEmpty) return markdown;

    final lines = markdown.split('\n');
    int titleLineIndex = -1;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('#')) continue;

      final headingText = line.replaceFirst(RegExp(r'^#+\s*'), '').trim();
      if (_isMatchingTitle(headingText, title.trim())) {
        titleLineIndex = i;
        break;
      }
    }

    if (titleLineIndex <= 0) return markdown;

    return lines.sublist(titleLineIndex).join('\n');
  }

  static bool _isMatchingTitle(String heading, String title) {
    final h = heading.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final t = title.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

    if (h == t) return true;
    if (h.contains(t) || t.contains(h)) return true;

    // 词汇重叠度 >= 80%（忽略短词）
    final titleWords = t.split(' ').where((w) => w.length > 2).toSet();
    if (titleWords.isEmpty) return false;
    final headingWords = h.split(' ').toSet();
    final overlap = titleWords.intersection(headingWords).length;
    return overlap / titleWords.length >= 0.8;
  }

  /// 将独占一行的长内联公式（$...$）提升为块级公式（$$...$$）。
  /// API 提取经常将独立的 display 方程误标为 inline。
  static String _promoteInlineEquations(String text) {
    return text.replaceAllMapped(
      RegExp(r'^[ \t]*\$([^\$\n]+)\$[ \t]*$', multiLine: true),
      (match) {
        final inner = match.group(1)!.trim();
        if (inner.contains('=') || inner.length > 60) {
          return '\n\$\$\n$inner\n\$\$\n';
        }
        return match.group(0)!;
      },
    );
  }

  static String _sanitizeLatex(String text) {
    var res = text
        .replaceAllMapped(RegExp(r'\\pmb(?=\s*\{)'), (_) => r'\boldsymbol')
        .replaceAllMapped(RegExp(r'\\mbox(?=\s*\{)'), (_) => r'\text');

    for (var i = 0; i < 3; i++) {
      final prev = res;
      res = res.replaceAllMapped(
        RegExp(r'\\boldsymbol\{\\boldsymbol\{([^}]*)\}\}'),
        (m) =>
            r'\boldsymbol{'
            '${m.group(1)}'
            '}',
      );
      if (res == prev) {
        break;
      }
    }

    res = res.replaceAllMapped(
      RegExp(r'\\begin\{array\}\{([rclp|]+(?:\s+[rclp|]+)+)\}'),
      (m) =>
          r'\begin{array}{'
          '${m.group(1)!.replaceAll(' ', '')}'
          '}',
    );

    return res;
  }

  static String _fixLatexSpacing(String text) {
    var res = text.replaceAllMapped(RegExp(r'\$([^\$\n]+)\$'), (match) {
      final trimmed = match.group(1)!.trim();
      return '\$$trimmed\$';
    });

    res = res.replaceAllMapped(
      RegExp(
        r'^[ \t]*\$\$[ \t]*$(.*?)^[ \t]*\$\$[ \t]*$',
        multiLine: true,
        dotAll: true,
      ),
      (match) {
        final inner = match.group(1)?.trim() ?? '';
        return '\n\$\$\n$inner\n\$\$\n';
      },
    );

    res = res.replaceAllMapped(RegExp(r'\$\$(.*?)\$\$'), (match) {
      final inner = match.group(1)?.trim() ?? '';
      return '\n\$\$\n$inner\n\$\$\n';
    });

    return res;
  }

  static String _simplifyInlineLatex(String text) {
    return text.replaceAllMapped(RegExp(r'\$([^\$\n]+)\$'), (match) {
      final inner = match.group(1)!.trim();

      const symbolMap = {
        r'\approx': '≈',
        r'\sim': '∼',
        r'\times': '×',
        r'\pm': '±',
        r'\leq': '≤',
        r'\geq': '≥',
        r'\neq': '≠',
      };
      if (symbolMap.containsKey(inner)) {
        return symbolMap[inner]!;
      }

      final superscriptMatch = RegExp(
        r'^\{\}\s*\^\{([^{}]+)\}$',
      ).firstMatch(inner);
      if (superscriptMatch != null) {
        return _toSuperscriptText(superscriptMatch.group(1)!);
      }

      final plainTextMatch = RegExp(
        r'^\\(?:underline|text|textrm|texttt|textsf|textbf)\{((?:[^{}]|\{[^{}]*\})+)\}$',
      ).firstMatch(inner);
      if (plainTextMatch != null) {
        return plainTextMatch
            .group(1)!
            .replaceAllMapped(
              RegExp(r'\\text\{([^{}]+)\}'),
              (nested) => nested.group(1)!,
            );
      }

      return '\$$inner\$';
    });
  }

  static String _toSuperscriptText(String text) {
    const map = {
      '0': '\u2070',
      '1': '\u00B9',
      '2': '\u00B2',
      '3': '\u00B3',
      '4': '\u2074',
      '5': '\u2075',
      '6': '\u2076',
      '7': '\u2077',
      '8': '\u2078',
      '9': '\u2079',
      '+': '\u207A',
      '-': '\u207B',
      '=': '\u207C',
      '(': '\u207D',
      ')': '\u207E',
      'n': '\u207F',
      'i': '\u2071',
    };

    final buffer = StringBuffer();
    for (final char in text.split('')) {
      buffer.write(map[char] ?? char);
    }
    return buffer.toString();
  }

  static String _normalizeInlineSpacing(String text) {
    const superscriptChars =
        r'\u2070\u00B9\u00B2\u00B3\u2074-\u2079\u207A-\u207E\u207F\u2071';

    var result = text.replaceAllMapped(
      RegExp('(?<=\\S)\\s+([$superscriptChars]+)'),
      (match) => match.group(1)!,
    );

    result = result.replaceAllMapped(
      RegExp('([$superscriptChars]+)\\s+([.,;:!?])'),
      (match) => '${match.group(1)}${match.group(2)}',
    );

    return result;
  }

}
