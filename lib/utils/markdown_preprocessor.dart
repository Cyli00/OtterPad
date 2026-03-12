class MarkdownPreprocessor {
  /// 执行完整的 Markdown 预处理流程
  static String process(String markdown) {
    var result = markdown;
    result = _fixLatexSpacing(result);
    // 这里也可以集成之前 DocExtractService 的 resolveMarkdownImagePaths 逻辑
    // 但作为第一步，我们先处理纯文本的排版问题
    result = _healBrokenParagraphs(result);
    result = _cleanSpecificFooters(result);
    
    // 简单清理异常的空表格标签（Paddle有时的错误输出）
    result = result.replaceAll(RegExp(r'<table[^>]*>\s*</table>'), '');
    
    return result;
  }

  /// 修复 LaTeX 数学公式前后的多余空格
  static String _fixLatexSpacing(String text) {
    // 1. 处理行内公式（单$）: `$ ^{1,2} $` -> `$^{1,2}$`
    // 匹配 `$` 分隔的块，如果内部有内容，去除首尾空格
    // 使用非贪婪模式匹配 `$` 和 `$` 之间的内容，且内部不包含换行符（通常行内公式不跨行）
    var res = text.replaceAllMapped(RegExp(r'\$([^\$\n]+)\$'), (match) {
      final inner = match.group(1)!;
      // 去掉首尾多余空格
      final trimmed = inner.trim();
      // 如果修剪后变成空，意味着原始内容只是 "$ $"，可能不是有效公式，但也压缩掉空格
      return '\$$trimmed\$';
    });
    
    // 2. 处理块级公式（双$$）: 例如 ` $$ \mathbf{\Lambda} $$ `
    // 将 `$$` 单独分行，并使其不带多余的缩进，以防止被 Markdown 解析为代码块
    res = res.replaceAllMapped(RegExp(r'^[ \t]*\$\$[ \t]*$(.*?)^[ \t]*\$\$[ \t]*$', multiLine: true, dotAll: true), (match) {
      final inner = match.group(1)?.trim() ?? '';
      return '\n\$\$\n$inner\n\$\$\n';
    });

    // 还有一种情况是行内的双$$：` $$ math $$ `
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

    for (int i = 0; i < lines.length; i++) {
      final current = lines[i];
      if (i == lines.length - 1) {
        buffer.writeln(current);
        break;
      }
      
      final next = lines[i + 1];
      final currentTrimmed = current.trimRight();
      final nextTrimmed = next.trimLeft();
      
      // 如果当前行空 或者 下一行空，不合并
      if (currentTrimmed.isEmpty || nextTrimmed.isEmpty) {
        buffer.writeln(current);
        continue;
      }
      
      // 检查当前行结尾字符，以及下一行开头字符
      final lastChar = currentTrimmed.substring(currentTrimmed.length - 1);
      final firstCharNext = nextTrimmed.substring(0, 1);
      
      // 常见的句子结尾标点符号
      final isSentenceEnd = ['.', ':', '?', '!', ';', '。', '：', '？', '！', '；', '"', '”', "'", '’'].contains(lastChar);
      
      // 判断下一行是否以小写字母开头，这强烈暗示它是上一句的延续
      final isNextLowercase = RegExp(r'[a-z]').hasMatch(firstCharNext);
      
      // 避免合并标题、列表等带有专门前缀的行
      final isCurrentHeadingOrList = RegExp(r'^(\s*#|\s*[-*]|\s*\d+\.\s+)').hasMatch(current);
      // 避免合并块级公式内部或 HTML 标签
      final isHtmlTag = currentTrimmed.endsWith('>') || nextTrimmed.startsWith('<');
      
      if (!isSentenceEnd && isNextLowercase && !isCurrentHeadingOrList && !isHtmlTag) {
        // 进行合并：当前行去除尾部空格后，加上一个空格补充，不加换行符
        buffer.write(currentTrimmed + ' ');
      } else {
        buffer.writeln(current);
      }
    }
    
    return buffer.toString();
  }

  /// 清理经常出现的无意义干扰文本
  static String _cleanSpecificFooters(String text) {
    // 匹配类似 "bioRxiv preprint doi: ... license." 的跨行无意义段落
    var res = text.replaceAll(RegExp(r'bioRxiv preprint doi:.*?(?:International license\.|license\.)', multiLine: true, caseSensitive: false, dotAll: true), '');
    
    // 清除连续的多个空行（压缩为最多两个换行符）
    res = res.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return res;
  }
}
