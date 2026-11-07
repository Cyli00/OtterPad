import '../core/rust_backend.dart';
import 'prompts.dart';

/// 提示词的读写：保存、重置与校验都在 Rust，这里同步读取载入后的文本。
abstract final class PromptStore {
  /// 生效文本：用户覆盖优先，未定制或为空白时为默认值。
  static String resolve(PromptDef def) => def.definition.text;

  /// 保存用户覆盖。返回缺失的必需占位符——非空表示已拒绝保存；
  /// 空白文本视为重置。
  static Future<List<String>> set(PromptDef def, String text) async {
    final missing = text.trim().isEmpty
        ? const <String>[]
        : def.missingPlaceholders(text);
    if (missing.isNotEmpty) return missing;
    Prompts.update(
      await RustBackend.instance.setPrompt(kind: def.kind, text: text),
    );
    return const [];
  }

  static Future<void> reset(PromptDef def) => set(def, '');

  static bool isDefault(PromptDef def) =>
      Prompts.of(def.kind).definition.isDefault;
}
