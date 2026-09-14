import 'package:markdown/markdown.dart' as md;

class CjkEmphasisSyntax extends md.InlineSyntax {
  CjkEmphasisSyntax()
    : super(r'(\*\*\*|___|\*\*|__|~~|\*)(?!\s)([^\n]+?)(?<!\s)\1');

  static final _punctuation = RegExp(r'[\u3000-\u303f\uff01-\uff65“”‘’]');

  @override
  bool tryMatch(md.InlineParser parser, [int? startMatchPos]) {
    final match = pattern.matchAsPrefix(
      parser.source,
      startMatchPos ?? parser.pos,
    );
    if (match == null) return false;
    final content = match[2]!;
    // 仅放宽中文标点边界；代码、转义及普通英文强调仍由标准解析器处理。
    if (!_punctuation.hasMatch(content[0]) &&
        !_punctuation.hasMatch(content[content.length - 1])) {
      return false;
    }
    return super.tryMatch(parser, startMatchPos);
  }

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final content = match[2]!;
    final tag = switch (match[1]) {
      '*' => 'em',
      '~~' => 'del',
      _ => 'strong',
    };
    final children = md.InlineParser(content, parser.document).parse();
    parser.addNode(
      md.Element(
        tag,
        match[1]!.length == 3 ? [md.Element('em', children)] : children,
      ),
    );
    return true;
  }
}
