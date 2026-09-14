/// Prompt Registry —— 全代码库 LLM prompt 的唯一文本源。
///
/// 改任何 prompt 措辞只碰这个文件：
/// - **可定制 prompt**：[PromptDef] 声明（默认文本 + 占位符契约），用户覆盖
///   经 PromptStore（`prompt_store.dart`）按 `storageKey` 持久化，设置页
///   提供编辑/重置入口；
/// - **不可定制 prompt**：同文件顶层
///   函数/常量，调用方直接引用。
///
/// 边界约定：成段的措辞进这里；带变量的数据标签（"Aspect ratio: ..."、
/// manifest JSON 组装等）跟着各 service 的组装代码走，不进 registry。
library;

/// 一条可定制 prompt 的声明：身份、默认文本、占位符契约。
///
/// 新 prompt 想开放用户定制 = 在 [Prompts] 加一条声明，五件套
/// （默认值/存储/保存/重置/是否默认）由 PromptStore 统一兑现。
class PromptDef {
  /// 语义 id（`<域>.<角色>`），用于日志与未来的设置 UI 寻址。
  final String id;

  /// GStorage.setting 的持久化 key。历史 prompt 沿用引入前的旧 key，
  /// 保证零数据迁移；新 prompt 建议用 `prompt_<id>` 风格。
  final String storageKey;

  final String defaultText;

  /// 必需占位符（`{{name}}`）。文本缺失任何一个时 PromptStore.set
  /// 拒绝保存——防止用户删掉 `{{input}}` 后翻译静默丢失原文。
  final List<String> requiredPlaceholders;

  /// 可选占位符——纯文档性质，供设置 UI 渲染"可用占位符"提示。
  final List<String> optionalPlaceholders;

  const PromptDef({
    required this.id,
    required this.storageKey,
    required this.defaultText,
    this.requiredPlaceholders = const [],
    this.optionalPlaceholders = const [],
  });

  /// [text] 中缺失的必需占位符；空列表 = 校验通过。
  List<String> missingPlaceholders(String text) =>
      requiredPlaceholders.where((p) => !text.contains('{{$p}}')).toList();

  /// 全部占位符的展示文本（`{{a}}, {{b}}`）。设置页的"可用占位符"提示由它渲染，
  /// 占位符清单只在此维护一份，ARB 文案不再手写占位符名。
  String get placeholdersLabel => [
    ...requiredPlaceholders,
    ...optionalPlaceholders,
  ].map((p) => '{{$p}}').join(', ');
}

/// `{{name}}` 占位符插值。未提供值的占位符原样保留。
String renderPrompt(String template, Map<String, String> values) {
  var out = template;
  values.forEach((k, v) => out = out.replaceAll('{{$k}}', v));
  return out;
}

// ═══════════════════ 默认文本（可定制 prompt）═══════════════════
// 顶层 const 字符串：PromptDef 的 const 构造需要 const 默认文本，
// 同时让设置页可以直接引用（重置按钮回填编辑框）。

// ── 翻译（参考 Read-Frog prompt.ts，适配 Markdown 场景）──
// 多段（`%%%%` 分隔）规则不在默认文本里——只有划词划出子选区时才成立，
// 见下方 [Prompts.translationSegmentGuard]。

const kDefaultTranslationSystemPrompt = '''
You are a professional {{targetLanguage}} native translator who needs to fluently translate text into {{targetLanguage}}.

## Translation Rules
1. Output only the translated content, without explanations or additional content.
2. Preserve the original structure exactly: the same number of paragraphs, and the same Markdown formatting (headings, lists, emphasis, LaTeX).
3. Keep content that should not be translated as-is: code, formulas, URLs, technical identifiers.
4. Translate names and terminology into their established {{targetLanguage}} rendering when one exists; otherwise keep the original.''';

const kDefaultTranslationUserPrompt = '''
Translate to {{targetLanguage}}:

{{input}}''';

// ── 问 AI（文献语境对话）──

const kDefaultChatSystemPrompt = '''
You are a research assistant embedded in a document reader. The user is reading the academic document below and will ask questions about it.

## Rules
1. Prefer document content and cite the section or figure you used. For questions about this document's own findings, methods, or numbers, if the document does not provide an answer, say so explicitly — never present general knowledge as the document's conclusion.
2. Definitions, background, and general concepts may be answered from general knowledge — mark those parts as general knowledge rather than document content.
3. Answer in the same language the user asks in.
4. Use Markdown formatting; write math as LaTeX in \$...\$ / \$\$...\$\$.

## Document
{{document}}''';

// ── 生图（论文总结信息图的风格指导）──

const kDefaultSummaryImagePrompt = '''
A detailed scientific infographic summarizing a paper, in the style of a Cell journal highlight summary.
- Layout: a title, short explanatory text blocks, and simple diagram panels connected by arrows, presenting key findings in a structured, readable flow.
- Style: clean vector-like line art, thin dark grey outlines, sans-serif labels, editorial and precise.
- Color: white or very light grey background; soft muted blue and warm pale grey as the base; very pale desaturated orange for functional coding only.
- Text density: medium — a title plus 3-6 short text blocks.

Do not use: purple, large filled color blocks, gradients, shadows, 3D, or photorealistic rendering.
''';

// ═══════════════════ Registry ═══════════════════

abstract final class Prompts {
  // ── 可定制：翻译 ──

  static const translationSystem = PromptDef(
    id: 'translation.system',
    storageKey: 'translation_config_system_prompt',
    defaultText: kDefaultTranslationSystemPrompt,
    optionalPlaceholders: ['targetLanguage'],
  );

  static const translationUser = PromptDef(
    id: 'translation.user',
    storageKey: 'translation_config_user_prompt',
    defaultText: kDefaultTranslationUserPrompt,
    requiredPlaceholders: ['targetLanguage', 'input'],
  );

  // ── 可定制：问 AI ──

  static const chatSystem = PromptDef(
    id: 'chat.system',
    storageKey: 'prompt_chat_system',
    defaultText: kDefaultChatSystemPrompt,
    requiredPlaceholders: ['document'],
  );

  // ── 可定制：生图 ──

  static const summaryImage = PromptDef(
    id: 'image.summary',
    storageKey: 'image_generation_prompt',
    defaultText: kDefaultSummaryImagePrompt,
  );

  // ── 不可定制：问 AI 会话标题生成（快速模型、强制关思考）──

  static const chatTitleSystem =
      'Summarize the user message into a very short conversation title in '
      'the same language as the message: at most 12 characters for CJK or '
      '6 words for English. Output the title only — no quotes, no trailing '
      'punctuation, no explanation.';

  // ── 不可定制：翻译受保护 span 占位符守卫 ──

  /// masked 输入含 `[[mN]]` 占位符（行内公式/代码，见
  /// ProtectedSpans）时追加到 system prompt。
  static const translationPlaceholderGuard =
      'The input contains placeholders like [[m0]], [[m1]] that stand for '
      'protected content (formulas or code). Keep every placeholder exactly '
      'as-is at its corresponding position in the translation. Never '
      'translate, alter, merge, or drop a placeholder.';

  // ── 不可定制：翻译多段分隔符守卫 ──

  /// 输入被 `%%%%` 行切成多段（划词划出子选区，见
  /// TranslationHighlightParser.buildSegmentedInput）时追加到 system prompt。
  /// 文档翻译逐段独立请求、输入不含分隔符，故不做常驻——避免每次请求白带
  /// 与当下无关的规则。
  static const translationSegmentGuard =
      'The input is divided into independent segments by lines containing only '
      '"%%%%". Translate every segment in place and reproduce the separator '
      'lines in the same order and count. Never merge or split segments, never '
      'add or remove separators. Use neighbouring segments only for '
      'terminology and tone consistency.';

  // ── 不可定制：AI 修缮 figure 提取（caption-first 归属审计）──

  /// figure 修缮 system prompt。纯文本 inventory（无图片），LLM 只输出 block_id
  /// 引用 + 归属关系，绝不输出 bbox 坐标（与已删的多模态 0–1000 bbox 方案切割）。
  static const figureFixSystem = '''
You are an academic-document figure-extraction auditor. You receive a text-only inventory of an extracted PDF (per-page captions, visual blocks, column layouts) and the current figures manifest produced by a heuristic extractor.

Your task: repair the CAPTION-to-VISUAL ownership. The heuristic often pairs a large figure (especially multi-panel or cross-column) with the WRONG title, or splits one figure across two manifest entries. Every figure/table must end up with exactly the right title.

Rules:
1. For every caption that has visual content, emit one entry in "figures" listing exactly the visual_ids that belong to it — its own panels, subfigure labels, tables, and footnotes sitting inside the figure area. Candidates may sit on the same page or an adjacent one (±1).
2. A figure may span both columns of a two-column page, or spill onto an adjacent page: assign ALL of its blocks to the single caption that titles it.
3. A caption with no visual content at all goes to "orphan_captions". A caption-side explanatory footnote is neither a figure's visual nor an orphan caption: never assign it to a figure merely because it starts with a letter marker.
4. A real visual with no owning caption goes to "uncaptioned_visuals" — UNLESS it sits on a page that has no captions at all (e.g. a book cover, copyright page, or front-matter page carrying only decorative imagery/logos). Such pages are not figure-bearing academic pages; ignore their visuals entirely.
5. Every visual_id you emit MUST appear in the inventory. Never synthesize ids, never guess ownership, never reorder content. If everything is already correct, return {"figures":[],"orphan_captions":[],"uncaptioned_visuals":[]}.

Respond with JSON only, exactly this shape and no other fields (no coordinates, no geometry, no caption text):
{"figures":[{"caption_id":"p<page>:c<idx>","visual_ids":["p<page>:b<block_id>"],"kind":"figure|table|chart"}],"orphan_captions":["p<page>:c<idx>"],"uncaptioned_visuals":["p<page>:b<block_id>"]}
kind is one of figure, table, chart (chart covers Scheme/Plate/Map/Box/Diagram/Exhibit). caption_id is null for an uncaptioned visual figure.''';

  /// user prompt 段头（JSON 体由 figure_fix_service 组装，遵循"数据标签跟组装代码走"边界）。
  static const figureFixUserManifestHeader =
      '## Current figures manifest (heuristic output — audit only, do not reference its block_ids)';

  /// inventory 段头 + 字段图例：block id 形态、label 取值、子图序号怎么判断——
  /// 属数据结构说明，跟数据同行（system prompt 只留判断规则）。
  static const figureFixUserInventoryHeader =
      '## Page inventory\n'
      'caption_id "p<page>:c<idx>" identifies a caption; visual_id '
      '"p<page>:b<block_id>" identifies a visual block. A subfigure label may be '
      'labelled `text`, `vision_footnote`, or `vision_footer` — judge it by its '
      'content, `role`, bbox, and position relative to the caption.';
  static const figureFixUserHintsHeader = '## Candidate hints (informational)';
  static const figureFixUserFooter =
      'Audit every caption-to-visual ownership above and output the corrected '
      'ownership JSON per the system instructions.';
}
