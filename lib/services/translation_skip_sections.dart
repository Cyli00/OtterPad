/// 翻译时可跳过的文档区域定义与检测。
///
/// **数据源**：转发到 [BackMatterDetector]——历史上本文件维护硬编码 References
/// 正则，与 `back_matter_sections.json` 数据严重重复。重构后 6 个 section 全部
/// 来自 detector 的 [BackMatterDetector.availableSections]，本文件仅做：
/// 1. 用户翻译配置的"启用 ID 集合"接口（[kAllTranslationSkipSections] 转换）
/// 2. detector 检测结果到 [DetectedSkipSection]（保留旧字段名，避免下游改）
library;

import 'back_matter_detector.dart';

// ── 区域定义（从 detector 派生） ─────────────────────────────────────────

class TranslationSkipSectionDef {
  final String id;
  final String label;
  const TranslationSkipSectionDef({required this.id, required this.label});
}

/// UI 列表用——展示所有可勾选 section。从 [BackMatterDetector] 单一数据源
/// 派生，确保翻译跳过 / 摘要图压缩共用同一个 section 集合。
final List<TranslationSkipSectionDef> kAllTranslationSkipSections = [
  for (final s in BackMatterDetector.availableSections)
    TranslationSkipSectionDef(id: s.id, label: s.label),
];

/// 默认勾选的 section ID 集——`references` + `acknowledgments`（高置信度且阅读
/// 价值低）。**必须 const**：[TranslationConfig] 的 const constructor 用作字段
/// 默认值，Dart 编译期要求 const 表达式。
///
/// 设计契约：每个 ID 必须存在于 [BackMatterDetector.availableSections] 中且
/// 那条 section 的 `defaultIgnore` 应该为 true——两份数据手动保持一致。这样
/// 折衷换来"const + 数据驱动"两边都不丢；如果未来希望强制同步，可以改为
/// runtime assert 或在 settings 重置时从 detector 重新派生。
const kDefaultTranslationIgnoreSections = <String>[
  'references',
  'acknowledgments',
];

// ── 检测结果（保留旧 API 形态，避免 markdown_paragraph_extractor 改动） ──

class DetectedSkipSection {
  final String id;

  /// 内容区起始偏移（标题后第一个非空字符）
  final int contentStart;

  /// 内容区结束偏移（下一个标题前或 EOF，已剥除尾部空白）
  final int contentEnd;

  const DetectedSkipSection({
    required this.id,
    required this.contentStart,
    required this.contentEnd,
  });
}

// ── 检测入口 ─────────────────────────────────────────────────────────────

/// 扫描 markdown 中已知 back-matter 区域。**默认检测所有 section**——
/// caller（[MarkdownParagraphExtractor]）需要完整列表来决定每个区域是
/// "彻底跳过翻译"还是"合并成单段翻译"，不能在这一层做用户配置过滤。
///
/// 可选 [restrictToIds] 仅在确实需要"局部检测"时传入（当前未使用，预留扩展）。
///
/// 调用前 [BackMatterDetector.instance.init] 必须已完成（main.dart 启动时调）；
/// 未初始化时返回空列表（safe-fail，不影响翻译流程，只是不跳过任何区域）。
List<DetectedSkipSection> detectSkipSections(
  String markdown, {
  Set<String>? restrictToIds,
}) {
  final ids = restrictToIds ??
      BackMatterDetector.availableSections.map((s) => s.id).toSet();
  if (ids.isEmpty) return const [];
  final detected = BackMatterDetector.instance.detectByIds(
    markdown: markdown,
    ids: ids,
  );
  return [
    for (final d in detected)
      DetectedSkipSection(
        id: d.id,
        contentStart: d.contentStart,
        contentEnd: d.contentEnd,
      ),
  ];
}
