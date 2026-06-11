import '../core/storage/storage.dart';
import 'prompts.dart';

/// PromptStore —— 可定制 prompt"五件套"（默认值/保存/重置/是否默认/校验）
/// 的唯一实现，按 [PromptDef.storageKey] 读写 GStorage。
///
/// 自身不持有状态、不做 provider：现有的 TranslationConfigNotifier /
/// ImageGenerationConfigNotifier 是这个 seam 上的状态 adapter，对外
/// 接口（config state 的 prompt 字段）保持不变。
abstract final class PromptStore {
  /// 解析生效文本：用户覆盖优先，未定制或存量为空白时回退默认——
  /// "空白即未定制"，用户清空后直接用当前默认文本。
  static String resolve(PromptDef def) {
    final stored = GStorage.setting.get(def.storageKey) as String?;
    if (stored == null || stored.trim().isEmpty) return def.defaultText;
    return stored;
  }

  /// 保存用户覆盖。返回缺失的必需占位符——非空表示**已拒绝保存**
  /// （存储保留旧值，UI 据此渲染错误提示）。trim 后为空视为重置，
  /// 不落空串。
  static Future<List<String>> set(PromptDef def, String text) async {
    if (text.trim().isEmpty) {
      await reset(def);
      return const [];
    }
    final missing = def.missingPlaceholders(text);
    if (missing.isNotEmpty) return missing;
    await GStorage.setting.put(def.storageKey, text);
    return const [];
  }

  static Future<void> reset(PromptDef def) =>
      GStorage.setting.delete(def.storageKey);

  static bool isDefault(PromptDef def) =>
      resolve(def).trim() == def.defaultText.trim();
}
