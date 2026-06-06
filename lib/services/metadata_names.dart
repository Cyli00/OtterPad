/// 文献元数据里"人名 / 作者行"的统一格式化原语。
///
/// 此前 CrossRef / PubMed / eLife 各自手写 "given + family → 显示名" 与作者行
/// 拆分，改一处格式要同步改多处（shotgun surgery）。收敛到这里作为单一真值点。
class MetadataNames {
  MetadataNames._();

  /// `"given family"`——任一为空则只保留另一个；两者皆空返回 `''`。
  ///
  /// 覆盖原 CrossRef（`'$given $family'.trim()`）与 PubMed
  /// （`given.isNotEmpty ? '$given $lastName' : lastName`）两套等价逻辑。
  static String formatPersonName(String? given, String? family) {
    return [given, family]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .join(' ');
  }

  /// 把 `"A, B, C"` / `"A, B ... C"` 这类作者行拆成列表（eLife authorLine 兜底）。
  /// `...`（省略号）先归一为逗号，再按逗号切分、去空白与空项。
  static List<String> splitAuthorLine(String line) {
    return line
        .replaceAll('...', ',')
        .split(',')
        .map((author) => author.trim())
        .where((author) => author.isNotEmpty)
        .toList();
  }
}
