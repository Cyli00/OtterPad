import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 主章节标题匹配器：判断一个标题文本是否是文献的**顶级章节**
/// （Abstract / Introduction / Methods / Part A / 摘要 / 结论 …）。
///
/// 模式来源 `assets/config/major_sections.json`，与 [BackMatterDetector]
/// 是同一接缝上的两个 adapter（后置区检测 / 主章节检测），编译形态对齐：
/// 容忍编号前缀（`1.` / `2.1)` / `III.` / `A.`）与冒号尾注，忽略大小写。
///
/// 当前消费方：阅读器搜索快照的结果分组（命中才当组标签）。
/// 大纲层级、推荐算法等未来可复用同一判定。
class MajorSectionMatcher {
  MajorSectionMatcher._();

  static final instance = MajorSectionMatcher._();

  String? _patternSource;

  /// 完整正则源串（含锚点/前缀容忍）。供需要在 isolate 内自行编译的
  /// 调用方传递——RegExp 不保证可跨 isolate 发送，源串可以。
  /// 资产缺失/损坏时返回 null（调用方应回退到无分级行为）。
  Future<String?> patternSource() async {
    if (_patternSource != null) return _patternSource;
    try {
      final raw = await rootBundle.loadString(
        'assets/config/major_sections.json',
      );
      final patterns =
          ((jsonDecode(raw) as Map<String, dynamic>)['patterns'] as List)
              .whereType<String>()
              .toList();
      if (patterns.isEmpty) return null;
      return _patternSource = buildPattern(patterns);
    } catch (_) {
      return null;
    }
  }

  /// 把模式体列表组装为完整正则：
  /// `^[编号/Part 前缀]? (p1|p2|…) [：- 尾注]?$`
  static String buildPattern(List<String> bodies) {
    final body = bodies.join('|');
    return r'^\s*(?:\d+(?:\.\d+)*\s*[.)、]?\s*|[ivxlcdm]+\s*[.)、]\s*|'
        r'[一二三四五六七八九十]+\s*[、.．]\s*)?(?:'
        '$body'
        r')\s*(?:[:：].*)?$';
  }
}
