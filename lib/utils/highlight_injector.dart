import '../data/models/book/highlight.dart';

/// 在 Markdown 源码中注入不可见定界符标记高亮区域。
///
/// 将高亮文本包裹为 `\uFFF9\uFFF9text\uFFF9\uFFF9`，
/// 由 [NRHighlightDelimiterSyntax] 在 markdown 解析阶段识别。
///
/// 核心难点：用户选中的是**渲染后的纯文本**（无 `$...$`、`**` 等语法标记），
/// 需要匹配到 Markdown **源码**中对应的位置。
/// 方案：对源码做 position-mapped stripping，在剥离后的文本上匹配，
/// 再用位置映射回原始源码注入定界符。
class HighlightInjector {
  static const _marker = '\uFFF9\uFFF9';

  /// 保护区域：围栏代码块、LaTeX 显示块、行内代码
  static final _protectedPattern = RegExp(
    r'```[\s\S]*?```'
    r'|'
    r'\$\$[\s\S]*?\$\$'
    r'|'
    r'`[^`\n]+`',
  );

  /// 在 [markdown] 源码中为 [highlights] 注入定界符。
  static String inject(String markdown, List<Highlight> highlights) {
    if (highlights.isEmpty) return markdown;

    var source = markdown.replaceAll('\uFFF9', '');
    final protectedRanges = _buildProtectedRanges(source);

    // 按文本长度降序，优先匹配长片段
    final sorted = List<Highlight>.from(highlights)
      ..sort((a, b) => b.text.length.compareTo(a.text.length));

    final injectedRanges = <_Range>[];

    for (final hl in sorted) {
      source = _injectOne(source, hl, protectedRanges, injectedRanges);
    }
    return source;
  }

  static String _injectOne(
    String source,
    Highlight hl,
    List<_Range> protectedRanges,
    List<_Range> injectedRanges,
  ) {
    final text = hl.text.trim();
    if (text.isEmpty) return source;

    // 多段落高亮：按换行拆分逐行注入
    if (text.contains('\n')) {
      final lines = text.split(RegExp(r'[\n\r]+'));
      var result = source;
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.length < 2) continue;
        result = _injectText(result, trimmed, protectedRanges, injectedRanges);
      }
      return result;
    }

    return _injectText(source, text, protectedRanges, injectedRanges);
  }

  static String _injectText(
    String source,
    String text,
    List<_Range> protectedRanges,
    List<_Range> injectedRanges,
  ) {
    final cleanText = text.replaceAll('\uFFFC', '').trim();
    if (cleanText.length < 2) return source;

    // 策略 1：直接匹配（纯文本段落）
    final directIdx =
        _findUnprotected(source, cleanText, protectedRanges, injectedRanges);
    if (directIdx >= 0) {
      injectedRanges.add(_Range(directIdx, directIdx + cleanText.length));
      return _insertMarkers(source, directIdx, cleanText.length);
    }

    // 策略 2：position-mapped stripping 匹配
    // 剥离 markdown 语法标记（$、**、*、_、~~），保留位置映射
    final stripped = _stripWithPositions(source);
    final matchIdx = stripped.text.indexOf(cleanText);
    if (matchIdx >= 0) {
      final matchEnd = matchIdx + cleanText.length;
      if (matchEnd <= stripped.positions.length) {
        var srcStart = stripped.positions[matchIdx];
        var srcEnd = stripped.positions[matchEnd - 1] + 1;
        // 扩展范围包含紧邻的语法标记（如 ** 和 ~~）
        srcStart = _extendBackward(source, srcStart);
        srcEnd = _extendForward(source, srcEnd);
        if (!_overlapsAny(srcStart, srcEnd, protectedRanges) &&
            !_overlapsAny(srcStart, srcEnd, injectedRanges)) {
          injectedRanges.add(_Range(srcStart, srcEnd));
          return _insertMarkers(source, srcStart, srcEnd - srcStart);
        }
      }
    }

    // 策略 3：含 \uFFFC 的文本，按 \uFFFC 拆分片段做 stripped 匹配
    if (text.contains('\uFFFC')) {
      final segments = text
          .split('\uFFFC')
          .map((s) => s.trim())
          .where((s) => s.length >= 2)
          .toList();
      if (segments.length >= 2) {
        final result = _injectSegments(
            source, stripped, segments, protectedRanges, injectedRanges);
        if (result != null) return result;
      }
    }

    return source;
  }

  /// 多片段匹配：在 stripped 文本中按顺序查找所有片段，
  /// 用第一个片段的起始和最后一个片段的结尾确定源码范围。
  static String? _injectSegments(
    String source,
    _StrippedText stripped,
    List<String> segments,
    List<_Range> protectedRanges,
    List<_Range> injectedRanges,
  ) {
    final strippedText = stripped.text;

    // 在 stripped 文本中按顺序查找每个片段
    var searchFrom = 0;
    int? firstMatchStart;
    int? lastMatchEnd;

    for (final seg in segments) {
      final idx = strippedText.indexOf(seg, searchFrom);
      if (idx < 0) return null;
      firstMatchStart ??= idx;
      lastMatchEnd = idx + seg.length;
      searchFrom = lastMatchEnd;
    }

    if (firstMatchStart == null ||
        lastMatchEnd == null ||
        lastMatchEnd > stripped.positions.length) {
      return null;
    }

    var srcStart = stripped.positions[firstMatchStart];
    var srcEnd = stripped.positions[lastMatchEnd - 1] + 1;
    srcStart = _extendBackward(source, srcStart);
    srcEnd = _extendForward(source, srcEnd);

    if (_overlapsAny(srcStart, srcEnd, protectedRanges) ||
        _overlapsAny(srcStart, srcEnd, injectedRanges)) {
      return null;
    }

    injectedRanges.add(_Range(srcStart, srcEnd));
    return _insertMarkers(source, srcStart, srcEnd - srcStart);
  }

  /// 在 [source] 的 [start] 位置插入定界符。
  static String _insertMarkers(String source, int start, int length) {
    return '${source.substring(0, start)}'
        '$_marker'
        '${source.substring(start, start + length)}'
        '$_marker'
        '${source.substring(start + length)}';
  }

  /// 在 [source] 中查找 [text]，跳过保护区域和已注入区域。
  static int _findUnprotected(
    String source,
    String text,
    List<_Range> protectedRanges,
    List<_Range> injectedRanges,
  ) {
    var searchFrom = 0;
    while (true) {
      final idx = source.indexOf(text, searchFrom);
      if (idx < 0) return -1;
      final end = idx + text.length;
      if (!_overlapsAny(idx, end, protectedRanges) &&
          !_overlapsAny(idx, end, injectedRanges)) {
        return idx;
      }
      searchFrom = idx + 1;
    }
  }

  /// 向前扩展位置，跳过紧邻的语法标记字符（`*`、`_`、`~`）。
  static int _extendForward(String source, int pos) {
    var i = pos;
    while (i < source.length && _isMarkdownSyntaxChar(source[i])) {
      i++;
    }
    return i;
  }

  /// 向后扩展位置，跳过紧邻的语法标记字符。
  static int _extendBackward(String source, int pos) {
    var i = pos;
    while (i > 0 && _isMarkdownSyntaxChar(source[i - 1])) {
      i--;
    }
    return i;
  }

  static bool _isMarkdownSyntaxChar(String c) =>
      c == '*' || c == '_' || c == '~';

  /// 剥离 markdown 内联语法标记，保留原始位置映射。
  ///
  /// 只跳过标记字符本身（`$`、`**`、`*`、`_`、`~~`），
  /// **保留 `$...$` 内部内容**（因为简单 LaTeX 如 `$F$`
  /// 渲染为纯文本 "F"，需要参与匹配）。
  static _StrippedText _stripWithPositions(String source) {
    final buf = StringBuffer();
    final positions = <int>[];
    var i = 0;

    while (i < source.length) {
      final c = source[i];

      // 跳过 $ 定界符本身（保留内部内容）
      if (c == '\$') {
        i++;
        continue;
      }

      // 跳过 ** 或 ~~（两字符标记）
      if (i + 1 < source.length) {
        final pair = source.substring(i, i + 2);
        if (pair == '**' || pair == '~~') {
          i += 2;
          continue;
        }
      }

      // 跳过单字符 * 或 _（仅当用作强调标记时）
      if ((c == '*' || c == '_') && _isEmphasisMarker(source, i)) {
        i++;
        continue;
      }

      buf.write(c);
      positions.add(i);
      i++;
    }

    return _StrippedText(text: buf.toString(), positions: positions);
  }

  /// 判断 source[i] 处的 * 或 _ 是否是强调标记（而非普通字符）
  static bool _isEmphasisMarker(String source, int i) {
    final before = i > 0 ? source[i - 1] : ' ';
    final after = i + 1 < source.length ? source[i + 1] : ' ';
    return before != ' ' || after != ' ';
  }

  static List<_Range> _buildProtectedRanges(String source) {
    return _protectedPattern
        .allMatches(source)
        .map((m) => _Range(m.start, m.end))
        .toList();
  }

  static bool _overlapsAny(int start, int end, List<_Range> ranges) {
    for (final r in ranges) {
      if (start < r.end && end > r.start) return true;
    }
    return false;
  }
}

class _StrippedText {
  final String text;
  final List<int> positions;
  const _StrippedText({required this.text, required this.positions});
}

class _Range {
  final int start;
  final int end;
  const _Range(this.start, this.end);
}
