class MarkdownPreprocessor {
  /// 执行完整的 Markdown 预处理流程
  static String process(String markdown) {
    var result = markdown;
    result = _sanitizeLatex(result);
    result = _fixLatexSpacing(result);
    result = _healBrokenParagraphs(result);
    result = _cleanSpecificFooters(result);

    // 清理 Paddle 有时输出的空表格标签
    result = result.replaceAll(RegExp(r'<table[^>]*>\s*</table>'), '');

    return result;
  }

  /// 清理 PaddleOCR 输出中冗余 / 不标准的 LaTeX 命令
  static String _sanitizeLatex(String text) {
    var res = text;

    // 去除嵌套重复的 \boldsymbol{\boldsymbol{x}} → \boldsymbol{x}
    // PaddleOCR 经常对同一符号重复加粗
    for (var i = 0; i < 3; i++) {
      final prev = res;
      res = res.replaceAllMapped(
        RegExp(r'\\boldsymbol\{\\boldsymbol\{([^}]*)\}\}'),
        (m) => '\\boldsymbol{${m.group(1)}}',
      );
      if (res == prev) break;
    }

    // \begin{array}{r l} → \begin{array}{rl}
    // 部分渲染器对列说明符中的空格兼容性不佳
    res = res.replaceAllMapped(
      RegExp(r'\\begin\{array\}\{([rclp|]+(?:\s+[rclp|]+)+)\}'),
      (m) => '\\begin{array}{${m.group(1)!.replaceAll(' ', '')}}',
    );

    return res;
  }

  /// 修复 LaTeX 数学公式前后的多余空格
  static String _fixLatexSpacing(String text) {
    // 1. 行内公式（单$）: `$ ^{1,2} $` → `$^{1,2}$`
    var res = text.replaceAllMapped(RegExp(r'\$([^\$\n]+)\$'), (match) {
      final trimmed = match.group(1)!.trim();
      return '\$$trimmed\$';
    });

    // 2. 块级公式（独占行的双$$）: 规范化为 \n$$\n...\n$$\n
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

    // 3. 行内的双$$ `$$ math $$` 转为块级
    res = res.replaceAllMapped(RegExp(r'\$\$(.*?)\$\$'), (match) {
      final inner = match.group(1)?.trim() ?? '';
      return '\n\$\$\n$inner\n\$\$\n';
    });

    return res;
  }

  /// 启发式合并断裂段落
  static String _healBrokenParagraphs(String text) {
    final lines = text.split('\n');
    final buffer = StringBuffer();
    var inMathBlock = false;

    for (int i = 0; i < lines.length; i++) {
      final current = lines[i];

      // 跟踪 $$ 块级公式范围，内部不做任何合并
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

      // 当前行或下一行为空，不合并
      if (currentTrimmed.isEmpty || nextTrimmed.isEmpty) {
        buffer.writeln(current);
        continue;
      }

      // 下一行是 $$ 块起始，不合并
      if (nextTrimmed == r'$$') {
        buffer.writeln(current);
        continue;
      }

      final lastChar = currentTrimmed[currentTrimmed.length - 1];
      final firstCharNext = nextTrimmed[0];

      // 当前行以行内 LaTeX $ 结尾，不合并（保留公式与后文的分行）
      if (lastChar == r'$') {
        buffer.writeln(current);
        continue;
      }

      final isSentenceEnd = const {
        '.', ':', '?', '!', ';',
        '。', '：', '？', '！', '；',
        '"', '\u201D', "'", '\u2019',
      }.contains(lastChar);

      final isNextLowercase = RegExp(r'[a-z]').hasMatch(firstCharNext);
      final isCurrentHeadingOrList =
          RegExp(r'^(\s*#|\s*[-*]|\s*\d+\.\s+)').hasMatch(current);
      final isHtmlTag =
          currentTrimmed.endsWith('>') || nextTrimmed.startsWith('<');

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

  /// 清理无意义的重复性干扰文本
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

    // 压缩连续空行
    res = res.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return res;
  }
}
