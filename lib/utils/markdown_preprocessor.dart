class MarkdownPreprocessor {
  static String process(String markdown) {
    var result = markdown;
    result = _sanitizeLatex(result);
    result = _fixLatexSpacing(result);
    result = _simplifyInlineLatex(result);
    result = _normalizeInlineSpacing(result);
    result = _healBrokenParagraphs(result);
    result = _cleanSpecificFooters(result);
    result = result.replaceAll(RegExp(r'<table[^>]*>\s*</table>'), '');
    return result;
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

  static String _healBrokenParagraphs(String text) {
    final lines = text.split('\n');
    final buffer = StringBuffer();
    var inMathBlock = false;

    for (int i = 0; i < lines.length; i++) {
      final current = lines[i];

      if (current.trim() == r'$$') {
        inMathBlock = !inMathBlock;
        buffer.writeln(current);
        continue;
      }
      if (inMathBlock) {
        buffer.writeln(current);
        continue;
      }

      if (i == lines.length - 1) {
        buffer.writeln(current);
        break;
      }

      final next = lines[i + 1];
      final currentTrimmed = current.trimRight();
      final nextTrimmed = next.trimLeft();

      if (currentTrimmed.isEmpty || nextTrimmed.isEmpty) {
        buffer.writeln(current);
        continue;
      }

      if (nextTrimmed == r'$$') {
        buffer.writeln(current);
        continue;
      }

      final lastChar = currentTrimmed[currentTrimmed.length - 1];
      final firstCharNext = nextTrimmed[0];
      final isSentenceEnd = const {
        '.',
        ':',
        '?',
        '!',
        ';',
        '"',
        '\u201D',
        "'",
        '\u2019',
        '\u3002',
        '\uFF1A',
        '\uFF1F',
        '\uFF01',
        '\uFF1B',
      }.contains(lastChar);
      final isNextLowercase = RegExp(r'[a-z]').hasMatch(firstCharNext);
      final isCurrentHeadingOrList = RegExp(
        r'^(\s*#|\s*[-*]|\s*\d+\.\s+)',
      ).hasMatch(current);
      final isHtmlTag =
          currentTrimmed.endsWith('>') || nextTrimmed.startsWith('<');
      final isNextContinuationPunctuation = RegExp(
        r"""^[\.,:;!?\)\]\}"'\uFF0C\u3002\uFF1B\uFF1A\uFF01\uFF1F\u3001\u300B\u300D\u300F\u3011]""",
      ).hasMatch(nextTrimmed);

      if (isNextContinuationPunctuation &&
          !isCurrentHeadingOrList &&
          !isHtmlTag) {
        buffer.write(currentTrimmed);
        continue;
      }

      if (!isSentenceEnd &&
          isNextLowercase &&
          !isCurrentHeadingOrList &&
          !isHtmlTag) {
        buffer.write('$currentTrimmed ');
      } else {
        buffer.writeln(current);
      }
    }

    return buffer.toString();
  }

  static String _cleanSpecificFooters(String text) {
    var res = text.replaceAll(
      RegExp(
        r'bioRxiv preprint doi:.*?(?:International license\.|license\.)',
        multiLine: true,
        caseSensitive: false,
        dotAll: true,
      ),
      '',
    );

    res = res.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return res;
  }
}
