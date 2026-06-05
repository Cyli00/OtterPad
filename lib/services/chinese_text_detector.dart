/// 检测文本是否包含中文（CJK 统一汉字）
class ChineseTextDetector {
  ChineseTextDetector._();

  /// 文本中至少包含 [threshold] 个 CJK 汉字时返回 true。
  ///
  /// 覆盖 CJK Unified Ideographs（U+4E00–U+9FFF）
  /// 及 Extension A（U+3400–U+4DBF）。
  static bool isChinese(String text, {int threshold = 3}) {
    int count = 0;
    for (final rune in text.runes) {
      if (_isCjk(rune)) {
        if (++count >= threshold) return true;
      }
    }
    return false;
  }

  static bool _isCjk(int rune) =>
      (rune >= 0x4e00 && rune <= 0x9fff) ||
      (rune >= 0x3400 && rune <= 0x4dbf);
}
