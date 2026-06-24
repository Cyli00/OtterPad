/// 翻译弹窗的 %%%% 分隔符高亮解析——从 UI 层提取的纯函数，可独立测试。
class TranslationHighlightParser {
  TranslationHighlightParser._();

  static final separatorRe = RegExp(r'\n?%%%%\n?');

  /// 在 [haystack] 中定位 [needle]，返回 (start, end)。
  /// 先尝试直接匹配，失败后剥离空白再匹配——处理跨段落选择
  /// 丢失 `\n\n` 分隔符的情况。
  static (int, int)? findInFullText(String haystack, String needle) {
    final direct = haystack.indexOf(needle);
    if (direct >= 0) return (direct, direct + needle.length);

    final origPos = <int>[];
    final normBuf = StringBuffer();
    for (int i = 0; i < haystack.length; i++) {
      final c = haystack.codeUnitAt(i);
      if (c != 0x20 && c != 0x0A && c != 0x0D && c != 0x09) {
        normBuf.writeCharCode(c);
        origPos.add(i);
      }
    }

    final normH = normBuf.toString();
    final normN = needle.replaceAll(RegExp(r'\s+'), '');
    final idx = normH.indexOf(normN);
    if (idx < 0 || idx + normN.length > origPos.length) return null;

    final start = origPos[idx];
    final end = origPos[idx + normN.length - 1] + 1;
    return (start, end);
  }

  /// 构建带 %%%% 分隔符的输入文本，返回拼接结果和高亮段索引。
  static ({String text, int hlSegmentIndex}) buildSegmentedInput(
    String fullText,
    String sourceText,
  ) {
    final range = findInFullText(fullText, sourceText);
    if (range == null) return (text: fullText, hlSegmentIndex: -1);

    final (s, e) = range;
    final before = fullText.substring(0, s);
    final selected = fullText.substring(s, e);
    final after = fullText.substring(e);

    final segments = <String>[];
    if (before.trim().isNotEmpty) segments.add(before);
    final hlSegmentIndex = segments.length;
    segments.add(selected);
    if (after.trim().isNotEmpty) segments.add(after);

    return (text: segments.join('\n%%%%\n'), hlSegmentIndex: hlSegmentIndex);
  }

  /// 解析流式翻译输出中的 %%%% 分隔符，提取高亮范围。
  ///
  /// [raw] 是当前累积的翻译文本（每次 emit 的完整快照）。
  /// [hlSegmentIndex] 是高亮段在原始分段中的索引（-1 = 无分隔）。
  static ({String text, int? hlStart, int? hlEnd}) parse(
    String raw,
    int hlSegmentIndex,
  ) {
    if (hlSegmentIndex < 0) return (text: raw, hlStart: null, hlEnd: null);

    final parts = raw.split(separatorRe);

    if (parts.length <= hlSegmentIndex) {
      // 剥离完整 %%%% 和流式传输中可能出现的末尾半截 %+
      var clean = raw.replaceAll(separatorRe, '');
      clean = clean.replaceAll(RegExp(r'%+$'), '');
      return (text: clean, hlStart: null, hlEnd: null);
    }

    final trimmed = parts.map((p) => p.trim()).toList();
    final beforeText = trimmed.sublist(0, hlSegmentIndex).join('');
    final hlText = trimmed[hlSegmentIndex];
    final afterText = trimmed.length > hlSegmentIndex + 1
        ? trimmed.sublist(hlSegmentIndex + 1).join('')
        : '';

    return (
      text: beforeText + hlText + afterText,
      hlStart: beforeText.length,
      hlEnd: beforeText.length + hlText.length,
    );
  }
}
