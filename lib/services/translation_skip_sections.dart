/// 翻译时可跳过/合并的文档区域定义与检测。
///
/// 模块化设计——新增区域只需：
/// 1. 在 [kAllTranslationSkipSections] 添加定义
/// 2. 在 [detectSkipSections] 添加检测分支
library;

// ── 区域定义 ─────────────────────────────────────────────────────────────

class TranslationSkipSectionDef {
  final String id;
  final String label;
  const TranslationSkipSectionDef({required this.id, required this.label});
}

const kAllTranslationSkipSections = <TranslationSkipSectionDef>[
  TranslationSkipSectionDef(id: 'references', label: '参考文献'),
];

const kDefaultTranslationIgnoreSections = <String>['references'];

// ── 检测结果 ─────────────────────────────────────────────────────────────

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

/// 扫描 markdown 中的已知区域边界。
/// 返回的 [DetectedSkipSection.contentStart/End] 不含标题行本身——
/// 标题作为普通 heading 段落独立翻译。
List<DetectedSkipSection> detectSkipSections(String markdown) {
  final sections = <DetectedSkipSection>[];

  // ── References / 参考文献 / Bibliography ──
  final refMatch = _referencesHeadingRe.firstMatch(markdown);
  if (refMatch != null) {
    final range = _sectionContentRange(markdown, refMatch.end);
    if (range != null) {
      sections.add(DetectedSkipSection(
        id: 'references',
        contentStart: range.$1,
        contentEnd: range.$2,
      ));
    }
  }

  return sections;
}

// ── 内部工具 ─────────────────────────────────────────────────────────────

/// 从 [headingEnd]（标题匹配结束位）向后查找内容区域：
/// 跳过前导空白 → 到下一个同级标题前 / EOF，剥除尾部空白。
(int, int)? _sectionContentRange(String markdown, int headingEnd) {
  int start = headingEnd;
  while (start < markdown.length && _isBlank(markdown.codeUnitAt(start))) {
    start++;
  }
  final after = markdown.substring(headingEnd);
  final next = _nextHeadingRe.firstMatch(after);
  int end = next != null ? headingEnd + next.start : markdown.length;
  while (end > start && _isBlank(markdown.codeUnitAt(end - 1))) {
    end--;
  }
  return start < end ? (start, end) : null;
}

bool _isBlank(int cu) =>
    cu == 0x20 || cu == 0x09 || cu == 0x0A || cu == 0x0D;

final _referencesHeadingRe = RegExp(
  r'^#{1,3}\s+(?:References|参考文献|Bibliography|Works?\s+Cited)',
  multiLine: true,
  caseSensitive: false,
);

final _nextHeadingRe = RegExp(r'^#{1,3}\s+\S', multiLine: true);
