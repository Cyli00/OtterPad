/// 译文视觉样式策略（策略模式）。
///
/// 每种样式负责把"原段落 + 译文"织成一段新的 markdown 片段。
/// 新增样式只需继承 [TranslationStyleStrategy] 并添加到 [kTranslationStyles]。
///
/// 设计约束：
/// 1. 所有产物必须是有效 markdown，能被现有渲染管线直接消费；
/// 2. 双语模式保留原段落不动，译文接在下一段；
/// 3. 单译文模式用 styled 译文替换原段。
library;

/// 译文样式策略基类。
abstract class TranslationStyleStrategy {
  const TranslationStyleStrategy();

  /// 唯一标识，持久化时使用。
  String get id;

  /// 设置 UI 里展示的中文名。
  String get label;

  /// 双语模式下把原段落与译文拼成 markdown。
  String weaveBilingual(String original, String translation);

  /// 仅译文模式下把译文包装成 markdown。
  String weaveTranslated(String translation);
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
    return '$original\n\n${_wrap(translation)}';
  }

  @override
  String weaveTranslated(String translation) => _wrap(translation);

  /// 译文自身可能含 `*`，用反斜杠转义避免破坏斜体边界。
  String _wrap(String t) {
    final escaped = t.replaceAll('*', r'\*');
    return '*$escaped*';
  }
}

// ── 主题色（需要自定义 markdown 节点）──────────────────────────────────

class ThemedTranslationStyle extends TranslationStyleStrategy {
  const ThemedTranslationStyle();

  /// 渲染层（nr_translated_node）识别这两个标记把整段上 primary 色。
  static const markerOpen = '[[tr]]';
  static const markerClose = '[[/tr]]';

  @override
  String get id => 'themed';

  @override
  String get label => '主题色';

  @override
  String weaveBilingual(String original, String translation) {
    return '$original\n\n${_wrap(translation)}';
  }

  @override
  String weaveTranslated(String translation) => _wrap(translation);

  String _wrap(String t) => '$markerOpen$t$markerClose';
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
    return '$original\n\n${_wrap(translation)}';
  }

  @override
  String weaveTranslated(String translation) => _wrap(translation);

  /// 译文每行前加 `> `，空行写作 `>` 以维持 blockquote 连续性。
  String _wrap(String t) {
    return t
        .split('\n')
        .map((line) => line.isEmpty ? '>' : '> $line')
        .join('\n');
  }
}

// ── 注册表 ─────────────────────────────────────────────────────────────

const kTranslationStyles = <TranslationStyleStrategy>[
  ItalicTranslationStyle(),
  ThemedTranslationStyle(),
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
