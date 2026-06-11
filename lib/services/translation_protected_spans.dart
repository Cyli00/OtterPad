/// 翻译「受保护 span」占位符往返。
///
/// 段落级跳过（`$$…$$` 块、围栏代码）由 MarkdownParagraphExtractor 负责；
/// 本模块补齐**行内**粒度：行内公式（`$…$`、`\(…\)`、`\[…\]`）与行内代码
/// （反引号）在送翻译前抠出替换为 `[[m0]]` 占位符，译后逐字节原样还原——
/// LLM 全程看不到 LaTeX/代码，无从改坏（pdf2zh `{v0}` 占位思路的 markdown 版）。
///
/// 往返恒等：`mask(text).restore(masked) == text`（无 span 时直接零开销透传）。
class ProtectedSpans {
  /// 替换占位符后的文本（送给翻译的版本）。
  final String masked;

  /// 按序号索引的原始片段；空列表 = 无受保护内容。
  final List<String> spans;

  const ProtectedSpans._(this.masked, this.spans);

  bool get isEmpty => spans.isEmpty;

  // 行内代码优先（代码里的 $ 不是公式）；行内公式要求 $ 内侧无空格且闭合
  // $ 后不跟数字——排除 "costs $5 and $10" 这类货币误伤（pandoc 同款规则）。
  //
  // ⟪⟫ 是划词翻译弹窗的高亮标记（translation_popup），在 mask 之前就已插入
  // 原文——所有片段模式把它当硬边界（选区边界落在公式内部时，标记决不能
  // 被吞进占位符，否则模型看不到标记、译文高亮失效）。
  static final _spanRe = RegExp(
    r'`[^`\n⟪⟫]+`'
    r'|\\\((?:[^\\⟪⟫]|\\[^)⟪⟫])+?\\\)'
    r'|\\\[(?:[^\\⟪⟫]|\\[^\]⟪⟫])+?\\\]'
    r'|\$(?!\s)(?:[^$\n⟪⟫]*?[^$\s⟪⟫])?\$(?!\d)',
  );

  /// 占位符还原匹配：容忍 LLM 在括号内加空格（`[[ m0 ]]`）。
  static final _placeholderRe = RegExp(r'\[\[\s*m(\d+)\s*\]\]');

  /// 抠出受保护片段。无命中时 [masked] 即原文、[spans] 为空。
  static ProtectedSpans mask(String text) {
    final spans = <String>[];
    final masked = text.replaceAllMapped(_spanRe, (m) {
      spans.add(m.group(0)!);
      return '[[m${spans.length - 1}]]';
    });
    return ProtectedSpans._(masked, spans);
  }

  /// 把译文中的占位符还原为原始片段。
  ///
  /// 容错：序号越界的占位符原样保留；模型弄丢的占位符对应片段无法恢复
  /// （译文里该公式缺失），但不会破坏其余内容——宁缺毋坏。
  String restore(String translated) {
    if (spans.isEmpty) return translated;
    return translated.replaceAllMapped(_placeholderRe, (m) {
      final idx = int.tryParse(m.group(1)!);
      if (idx == null || idx < 0 || idx >= spans.length) return m.group(0)!;
      return spans[idx];
    });
  }
}
