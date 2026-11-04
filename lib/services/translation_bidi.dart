/// 在从右向左的译文里隔离仍须从左向右阅读的片段。
///
/// 用 Unicode LTR isolate（U+2066 / U+2069）包住公式、代码和 Markdown 表格，
/// 使周围波斯语/阿拉伯语右对齐时不会重排数学符号或对调表格列。
/// 只用于展示，不写回译文缓存。
String isolateLtrFragments(String text) {
  if (text.isEmpty) return text;
  return text.replaceAllMapped(
    _ltrFragment,
    (match) => '\u2066${match[0]!}\u2069',
  );
}

final _ltrFragment = RegExp(
  r'```[\s\S]*?```'
  r'|\$\$[\s\S]*?\$\$'
  r'|\\\[[\s\S]*?\\\]'
  r'|\\\([\s\S]*?\\\)'
  r'|\$[^$\n]+\$'
  r'|`[^`\n]+`'
  r'|(?:^[ \t]*\|.+\|[ \t]*\n?)+',
  multiLine: true,
);
