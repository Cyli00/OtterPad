import '../core/rust_backend.dart';
import '../src/rust/prompts.dart';

/// 可定制提示词：默认值、存储键与占位符都由 Rust 定义，启动时载入（[Prompts.load]）。
class PromptDef {
  const PromptDef(this.definition);

  final PromptDefinition definition;

  PromptKind get kind => definition.kind;
  String get defaultText => definition.defaultText;

  /// [text] 中缺失的必需占位符；空列表 = 校验通过。
  List<String> missingPlaceholders(String text) => definition
      .requiredPlaceholders
      .where((p) => !text.contains('{{$p}}'))
      .toList();

  /// 全部占位符的展示文本（`{{a}}, {{b}}`），设置页「可用占位符」提示用。
  String get placeholdersLabel => [
    ...definition.requiredPlaceholders,
    ...definition.optionalPlaceholders,
  ].map((p) => '{{$p}}').join(', ');
}

abstract final class Prompts {
  static final _definitions = <PromptKind, PromptDef>{};

  /// 启动与恢复设置后从 Rust 载入全部提示词定义与当前文本。
  static Future<void> load() async {
    for (final kind in PromptKind.values) {
      _definitions[kind] = PromptDef(
        await RustBackend.instance.prompt(kind: kind),
      );
    }
  }

  static void update(PromptDefinition definition) =>
      _definitions[definition.kind] = PromptDef(definition);

  static PromptDef of(PromptKind kind) => _definitions[kind]!;

  static PromptDef get translationSystem => of(PromptKind.translationSystem);
  static PromptDef get translationUser => of(PromptKind.translationUser);
  static PromptDef get chatSystem => of(PromptKind.chatSystem);
  static PromptDef get summaryImage => of(PromptKind.summaryImage);

  /// 不可定制：问 AI 会话标题。
  static const chatTitleSystem =
      'Summarize the user message into a very short conversation title in '
      'the same language as the message: at most 12 characters for CJK or '
      '6 words for English. Output the title only — no quotes, no trailing '
      'punctuation, no explanation.';
}
