/// Prompt Registry —— 全代码库 LLM prompt 的唯一文本源。
///
/// 改任何 prompt 措辞只碰这个文件：
/// - **可定制 prompt**：[PromptDef] 声明（默认文本 + 占位符契约），用户覆盖
///   经 PromptStore（`prompt_store.dart`）按 `storageKey` 持久化，设置页
///   提供编辑/重置入口；
/// - **不可定制 prompt**（带逻辑变体，如排版修复的坐标序）：同文件顶层
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

const kDefaultTranslationSystemPrompt = '''
You are a professional {{targetLanguage}} native translator who needs to fluently translate text into {{targetLanguage}}.

## Translation Rules
1. Output only the translated content, without explanations or additional content.
2. The returned translation must maintain exactly the same number of paragraphs and format as the original text.
3. For content that should not be translated (such as proper nouns, code, formulas, etc.), keep the original text.
4. Preserve all Markdown formatting including headings, lists, emphasis, and LaTeX expressions.
5. If the input contains "%%%%" separators on their own lines, the output MUST preserve the exact same separators in the exact same positions, with each segment translated independently. Never merge segments, never drop separators, never add extra ones.
6. When multiple segments appear together, they are usually from the same document. Use surrounding segments as context to resolve pronouns, keep terminology consistent, and match tone—but preserve each segment's own boundaries. Translate each segment in place; do NOT move content across segment boundaries.''';

const kDefaultTranslationUserPrompt = '''
Translate to {{targetLanguage}}:

{{input}}''';

// ── 问 AI（文献语境对话）──

const kDefaultChatSystemPrompt = '''
You are a research assistant embedded in a document reader. The user is reading the academic document below and will ask questions about it.

## Rules
1. Ground every answer in the document content; reference specific sections or figures when helpful.
2. If the answer is not in the document, say so explicitly before offering general knowledge.
3. Answer in the same language the user asks in.
4. Use Markdown formatting; write math as LaTeX in \$...\$ / \$\$...\$\$.

## Document
{{document}}''';

// ── 生图（论文总结信息图的风格指导）──

const kDefaultSummaryImagePrompt = '''
A detailed scientific infographic in the style of a Cell journal highlight summary. White or very light grey background. Clean vector-like line art, thin dark grey outlines. The layout includes a title, short explanatory text blocks, and simple diagram panels connected by arrows, presenting key findings in a structured, readable flow. Restrained color palette: soft muted blue, warm pale grey, very pale desaturated orange for functional coding only. No purple, no large filled color blocks, no gradients, no shadows, no 3D, no photorealistic rendering, no chaotic or dense text, no empty minimal look. Sans-serif labels, editorial and precise.
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

  // ── 不可定制：AI 排版修复（坐标序随 provider 变体，函数形态）──

  /// 排版修复 system prompt。Gemini 用其原生 [ymin,xmin,ymax,xmax]
  /// 训练约定（yFirst），其余服务商 [left,top,right,bottom]。
  static String layoutFixSystem({required bool yFirst}) {
    final order =
        yFirst ? '[ymin, xmin, ymax, xmax]' : '[left, top, right, bottom]';
    final example = yFirst
        ? 'on a page image 1584 px tall, y = 792 px -> 500'
        : 'on a page image 1224 px wide, x = 612 px -> 500';
    return 'You are an academic-document figure-extraction auditor. You '
        'receive rendered PDF page images (each labeled with its page index '
        'and pixel size) and the current figures manifest for those pages.\n\n'
        'Your single task: audit and repair figure crop regions. Large '
        'multi-panel figures are the priority — extraction pipelines often '
        'clip their edges.\n\n'
        'For EACH manifest entry, work through this checklist:\n'
        '1. Locate the figure on its page image.\n'
        '2. Enumerate every subfigure panel and its sequence label — (a), '
        '(b), (c), A, B, ... — and report them in "subfigures" (empty list '
        'for single-panel figures).\n'
        '3. The bbox MUST fully contain: every subfigure panel, every '
        'sequence label, and explanatory text that sits inside the figure '
        'region.\n'
        '4. The bbox MUST exclude: the main caption line (text starting '
        'with "Figure N" / "Fig. N"), body paragraphs, page headers/footers, '
        'and other figures.\n'
        '5. Check every edge for clipping — axis labels, legends, curve '
        'extremes and bottom-row subfigure labels are the most common '
        'victims.\n'
        '6. Compare figure_title against the caption text printed on the '
        'page; correct OCR errors or fill it in when missing.\n\n'
        'Then scan each page for real figures not covered by any manifest '
        'entry (report in "additions"), and manifest entries that are not '
        'actually figures (report their img in "remove").\n\n'
        'Coordinates: every bbox is $order, integers normalized to 0-1000 '
        "relative to that page image's width and height — the SAME "
        'convention as the manifest bboxes you receive ($example).\n\n'
        'Respond with JSON only, exactly this shape:\n'
        '{"fixes":[{"img":"...","page_idx":0,"subfigures":["a","b"],'
        '"bbox":[0,0,0,0],"figure_title":"..."}],'
        '"additions":[{"page_idx":0,"subfigures":[],"bbox":[0,0,0,0],'
        '"figure_title":"..."}],"remove":["..."]}\n\n'
        'Rules:\n'
        '- "fixes": include an entry ONLY when you change something; "img" '
        'must be copied exactly from the manifest; set "bbox" to null if '
        'only the title changes, set "figure_title" to null if only the '
        'bbox changes.\n'
        '- "additions": ONLY for figures that have NO matching manifest '
        'entry at all. If a figure with the same figure_title already exists '
        'in the manifest, adjust it via "fixes" instead — never duplicate '
        'it as an addition.\n'
        '- "remove": only img values from the manifest; anything you do '
        'not mention stays unchanged.\n'
        '- If everything is already correct, return '
        '{"fixes":[],"additions":[],"remove":[]}.\n'
        '- No text outside the JSON.';
  }

  /// 排版修复 user prompt 的文案行（manifest JSON 组装在 service 侧）。
  static const layoutFixUserManifestHeader =
      '## Current figures manifest (for the pages shown)';
  static const layoutFixUserAuditHint =
      'Audit each entry against its page image; also scan for missed '
      'figures.';
  static const layoutFixUserScanHint =
      'No manifest entries for these pages — scan them for missed figures.';
}
