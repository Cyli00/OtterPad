import '../services/markdown_paragraph_extractor.dart';
import '../services/translation_style.dart';
import 'markdown_preprocessor.dart';

/// 文档翻译显示模式。
enum DocTranslationMode {
  /// 关闭——显示原文（未翻译或用户主动切回）
  off,

  /// 双语对照：原段落后接译文段
  bilingual,

  /// 仅译文：段落替换为译文
  translated,
}

/// 按当前 [mode] 与 [style]，把 [translations] 织回 [markdown]，生成新 markdown。
///
/// - 未翻译 / 翻译为空的段落保留原文（翻译失败或进行中都走这条分支）。
/// - 段落顺序由 [paragraphs] 提供的 offset 决定；调用方必须保证它是 extract 的原输出，
///   不可乱序或手动修改（否则字符偏移会与源 md 失配）。
String applyTranslationToMarkdown({
  required String markdown,
  required List<TranslatableParagraph> paragraphs,
  required Map<String, String> translations,
  required DocTranslationMode mode,
  required TranslationStyleStrategy style,
}) {
  if (mode == DocTranslationMode.off || translations.isEmpty) {
    return markdown;
  }

  final buf = StringBuffer();
  int cursor = 0;

  for (final para in paragraphs) {
    if (para.offset < cursor) continue; // 防御：段落异常重叠

    final translation = translations[para.hash];
    if (translation == null || translation.isEmpty) {
      continue; // 尚未翻译或失败——保持原文
    }

    // 译文走同原文一致的 LaTeX 预处理（Unicode 简化 + 间距修正），
    // 确保简单公式被转为 Unicode 可在 [[tr]] 内正常显示，
    // 复杂公式保留 $...$ 由 ThemedTranslationStyle 在标记边界分割。
    final processed = MarkdownPreprocessor.processTranslation(translation);

    // 写入 [cursor, para.offset) 这段不变内容
    buf.write(markdown.substring(cursor, para.offset));

    final original = markdown.substring(para.offset, para.offset + para.length);
    final replaced = switch (mode) {
      DocTranslationMode.bilingual =>
          style.weaveBilingual(original, processed),
      DocTranslationMode.translated => style.weaveTranslated(processed),
      DocTranslationMode.off => original, // unreachable（上面早退了）
    };
    buf.write(replaced);

    cursor = para.offset + para.length;
  }

  if (cursor < markdown.length) {
    buf.write(markdown.substring(cursor));
  }

  return buf.toString();
}
