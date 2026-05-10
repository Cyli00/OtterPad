/// 译文视觉样式策略（策略模式）。
///
/// 每种样式负责把"原段落 + 译文"织成一段新的 markdown 片段。
/// 新增样式只需继承 [TranslationStyleStrategy] 并添加到 [kTranslationStyles]。
///
/// 设计约束：
/// 1. 所有产物必须是有效 markdown，能被现有渲染管线直接消费；
/// 2. 双语模式保留原段落不动，译文接在下一段；
/// 3. 仅译文模式不加任何样式——译文即全部内容，字体/颜色与原文保持一致。
library;

/// 所有需要自定义 inline 渲染的样式共用的标记对。
const kTranslationMarkerOpen = '[[tr]]';
const kTranslationMarkerClose = '[[/tr]]';

/// 译文样式策略基类。
abstract class TranslationStyleStrategy {
  const TranslationStyleStrategy();

  /// 唯一标识，持久化时使用。
  String get id;

  /// 设置 UI 里展示的中文名。
  String get label;

  /// 双语模式下把原段落与译文拼成 markdown。
  String weaveBilingual(String original, String translation);

  /// 仅译文模式：直接返回原文，不加样式。
  /// 样式仅在双语对照时用于区分原文与译文，纯译文场景无需区分。
  String weaveTranslated(String translation) => translation;
}

// ── helper ──────────────────────────────────────────────────────────────

/// 把译文用 `[[tr]]...[[/tr]]` 标记包起来。
///
/// **必须按段切分独立 wrap**：[_TranslationInlineSyntax] 是 InlineSyntax，
/// markdown 解析器在 block 阶段见到 `\n\n` 就 close 段落开始新段，inline
/// 解析在每段内独立运行——若整段译文用一对 marker 包裹，跨段后头/尾 marker
/// 都会变成字面残留（用户截图里看到的 `[[tr]]` `[[/tr]]` 字面残留就是这个）。
///
/// **标题段特判**：markdown ATX heading（`#+ `）必须行首，包在 `[[tr]]` 里
/// 会让整段降级为普通段落（heading 文本含字面 `##`）。修法是反过来包：
/// `## [[tr]]内容[[/tr]]`——block parser 先识别 H2，inline parser 再处理
/// 内部 marker，渲染为 `<h2><span class="translated">...</span></h2>`。
String _wrapMarker(String t) {
  final segs = t.split(_paragraphBoundaryRe);
  return segs
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .map(_wrapSegment)
      .join('\n\n');
}

String _wrapSegment(String segment) {
  final headingMatch = _atxHeadingRe.firstMatch(segment);
  if (headingMatch != null) {
    return '${headingMatch[1]}'
        '$kTranslationMarkerOpen${headingMatch[2]!.trim()}$kTranslationMarkerClose';
  }
  return '$kTranslationMarkerOpen$segment$kTranslationMarkerClose';
}

final _paragraphBoundaryRe = RegExp(r'\n{2,}');
final _atxHeadingRe = RegExp(r'^(#{1,6}\s+)(.+)$');

// ── 主题色（需要自定义 markdown 节点）──────────────────────────────────

class ThemedTranslationStyle extends TranslationStyleStrategy {
  const ThemedTranslationStyle();

  @override
  String get id => 'themed';
  @override
  String get label => '主题色';

  @override
  String weaveBilingual(String original, String translation) =>
      '$original\n\n${_wrapMarker(translation)}';
}

// ── 加粗 ───────────────────────────────────────────────────────────────

class BoldTranslationStyle extends TranslationStyleStrategy {
  const BoldTranslationStyle();

  @override
  String get id => 'bold';
  @override
  String get label => '加粗';

  @override
  String weaveBilingual(String original, String translation) {
    final escaped = translation.replaceAll('*', r'\*');
    return '$original\n\n**$escaped**';
  }
}

// ── 斜体 ───────────────────────────────────────────────────────────────

class ItalicTranslationStyle extends TranslationStyleStrategy {
  const ItalicTranslationStyle();

  @override
  String get id => 'italic';
  @override
  String get label => '斜体';

  @override
  String weaveBilingual(String original, String translation) {
    final escaped = translation.replaceAll('*', r'\*');
    return '$original\n\n*$escaped*';
  }
}

// ── 弱化 ───────────────────────────────────────────────────────────────

class WeakenedTranslationStyle extends TranslationStyleStrategy {
  const WeakenedTranslationStyle();

  @override
  String get id => 'weakened';
  @override
  String get label => '弱化';

  @override
  String weaveBilingual(String original, String translation) =>
      '$original\n\n${_wrapMarker(translation)}';
}

// ── 虚线下划线 ─────────────────────────────────────────────────────────

class DashedTranslationStyle extends TranslationStyleStrategy {
  const DashedTranslationStyle();

  @override
  String get id => 'dashed';
  @override
  String get label => '虚线下划线';

  @override
  String weaveBilingual(String original, String translation) =>
      '$original\n\n${_wrapMarker(translation)}';
}

// ── 背景色 ─────────────────────────────────────────────────────────────

class HighlightTranslationStyle extends TranslationStyleStrategy {
  const HighlightTranslationStyle();

  @override
  String get id => 'highlight';
  @override
  String get label => '背景色';

  @override
  String weaveBilingual(String original, String translation) =>
      '$original\n\n${_wrapMarker(translation)}';
}

// ── 模糊 ───────────────────────────────────────────────────────────────

class BlurTranslationStyle extends TranslationStyleStrategy {
  const BlurTranslationStyle();

  @override
  String get id => 'blur';
  @override
  String get label => '模糊';

  @override
  String weaveBilingual(String original, String translation) =>
      '$original\n\n${_wrapMarker(translation)}';
}

// ── 引用 ───────────────────────────────────────────────────────────────

class QuoteTranslationStyle extends TranslationStyleStrategy {
  const QuoteTranslationStyle();

  @override
  String get id => 'quote';
  @override
  String get label => '引用';

  @override
  String weaveBilingual(String original, String translation) {
    final wrapped = translation
        .split('\n')
        .map((line) => line.isEmpty ? '>' : '> $line')
        .join('\n');
    return '$original\n\n$wrapped';
  }
}

// ── 注册表 ─────────────────────────────────────────────────────────────

const kTranslationStyles = <TranslationStyleStrategy>[
  ThemedTranslationStyle(),
  BoldTranslationStyle(),
  ItalicTranslationStyle(),
  WeakenedTranslationStyle(),
  DashedTranslationStyle(),
  HighlightTranslationStyle(),
  BlurTranslationStyle(),
  QuoteTranslationStyle(),
];

const kDefaultTranslationStyleId = 'themed';

TranslationStyleStrategy resolveTranslationStyle(String? id) {
  for (final s in kTranslationStyles) {
    if (s.id == id) return s;
  }
  return kTranslationStyles.firstWhere(
    (s) => s.id == kDefaultTranslationStyleId,
    orElse: () => kTranslationStyles.first,
  );
}
