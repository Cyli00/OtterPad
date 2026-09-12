import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/settings_keys.dart';
import '../core/storage/storage.dart';
import '../services/prompt_store.dart';
import '../services/prompts.dart';
import '../services/translation_skip_sections.dart';
import '../services/translation_style.dart';

// 默认提示词文本在 Prompt Registry（services/prompts.dart）——
// 本文件只管理翻译域的非 prompt 配置，prompt 的存取委托 PromptStore。

const kDefaultTargetLanguage = '中文(简体)';

/// 预置的目标语言列表
const kTargetLanguages = <String>[
  '中文(简体)',
  '中文(繁体)',
  'English',
  '日本語',
  '한국어',
  'Français',
  'Deutsch',
  'Español',
  'Português',
  'Русский',
  'Italiano',
  'Nederlands',
  'Polski',
  'Türkçe',
  'العربية',
  'ภาษาไทย',
  'Tiếng Việt',
  'Bahasa Indonesia',
  'हिन्दी',
  'Svenska',
  'Čeština',
  'Українська',
  'Magyar',
  'Ελληνικά',
  'Română',
];

// ── Hive 存储 key（prompt 的 key 在 PromptDef.storageKey）──────────────

const _kTargetLang = SettingsKeys.translationTargetLang;
const _kTemperature = SettingsKeys.translationTemperature;
const _kDisplayStyle = SettingsKeys.translationDisplayStyle;
const _kIgnoreSections = SettingsKeys.translationIgnoreSections;

// ── 数据模型 ───────────────────────────────────────────────────────────

class TranslationConfig {
  final String systemPrompt;
  final String userPrompt;
  final String targetLanguage;
  final double? temperature;

  /// 译文视觉样式 id（对应 [kTranslationStyles] 中一个策略）。
  final String displayStyleId;

  /// 翻译时忽略的区域 ID 列表。列表内的区域整段跳过；
  /// 未列入的已知区域合并为单个段落送入 LLM。
  final List<String> ignoreSections;

  const TranslationConfig({
    this.systemPrompt = kDefaultTranslationSystemPrompt,
    this.userPrompt = kDefaultTranslationUserPrompt,
    this.targetLanguage = kDefaultTargetLanguage,
    this.temperature,
    this.displayStyleId = kDefaultTranslationStyleId,
    this.ignoreSections = kDefaultTranslationIgnoreSections,
  });

  bool get isSystemPromptDefault =>
      systemPrompt.trim() == kDefaultTranslationSystemPrompt.trim();
  bool get isUserPromptDefault =>
      userPrompt.trim() == kDefaultTranslationUserPrompt.trim();

  /// 解析后的样式策略对象（便于 UI / weaver 直接用）。
  TranslationStyle get displayStyle => resolveTranslationStyle(displayStyleId);

  TranslationConfig copyWith({
    String? systemPrompt,
    String? userPrompt,
    String? targetLanguage,
    String? displayStyleId,
    List<String>? ignoreSections,
  }) => TranslationConfig(
    systemPrompt: systemPrompt ?? this.systemPrompt,
    userPrompt: userPrompt ?? this.userPrompt,
    targetLanguage: targetLanguage ?? this.targetLanguage,
    temperature: temperature,
    displayStyleId: displayStyleId ?? this.displayStyleId,
    ignoreSections: ignoreSections ?? this.ignoreSections,
  );
}

// ── StateNotifier ──────────────────────────────────────────────────────

class TranslationConfigNotifier extends StateNotifier<TranslationConfig> {
  TranslationConfigNotifier() : super(_load());

  static TranslationConfig _load() {
    final box = GStorage.setting;
    final rawSections = box.get(_kIgnoreSections) as List?;
    return TranslationConfig(
      systemPrompt: PromptStore.resolve(Prompts.translationSystem),
      userPrompt: PromptStore.resolve(Prompts.translationUser),
      targetLanguage:
          box.get(_kTargetLang, defaultValue: kDefaultTargetLanguage) as String,
      temperature: box.get(_kTemperature) as double?,
      displayStyleId:
          box.get(_kDisplayStyle, defaultValue: kDefaultTranslationStyleId)
              as String,
      ignoreSections: rawSections != null
          ? rawSections.cast<String>().toList()
          : List<String>.from(kDefaultTranslationIgnoreSections),
    );
  }

  /// 返回缺失的必需占位符——非空表示已拒绝保存（state 与存储均保留旧值），
  /// UI 据此渲染 errorText。空白输入 = 重置为默认（PromptStore 语义）。
  Future<List<String>> setSystemPrompt(String value) async {
    final missing = await PromptStore.set(Prompts.translationSystem, value);
    if (missing.isEmpty) {
      state = state.copyWith(
        systemPrompt: PromptStore.resolve(Prompts.translationSystem),
      );
    }
    return missing;
  }

  Future<List<String>> setUserPrompt(String value) async {
    final missing = await PromptStore.set(Prompts.translationUser, value);
    if (missing.isEmpty) {
      state = state.copyWith(
        userPrompt: PromptStore.resolve(Prompts.translationUser),
      );
    }
    return missing;
  }

  Future<void> setTargetLanguage(String value) async {
    state = state.copyWith(targetLanguage: value);
    await GStorage.setting.put(_kTargetLang, value);
  }

  Future<void> resetSystemPrompt() async {
    await PromptStore.reset(Prompts.translationSystem);
    state = state.copyWith(systemPrompt: kDefaultTranslationSystemPrompt);
  }

  Future<void> resetUserPrompt() async {
    await PromptStore.reset(Prompts.translationUser);
    state = state.copyWith(userPrompt: kDefaultTranslationUserPrompt);
  }

  Future<void> setTemperature(double? value) async {
    state = TranslationConfig(
      systemPrompt: state.systemPrompt,
      userPrompt: state.userPrompt,
      targetLanguage: state.targetLanguage,
      temperature: value,
      displayStyleId: state.displayStyleId,
      ignoreSections: state.ignoreSections,
    );
    if (value != null) {
      await GStorage.setting.put(_kTemperature, value);
    } else {
      await GStorage.setting.delete(_kTemperature);
    }
  }

  Future<void> setDisplayStyleId(String value) async {
    state = state.copyWith(displayStyleId: value);
    await GStorage.setting.put(_kDisplayStyle, value);
  }

  Future<void> setIgnoreSections(List<String> value) async {
    state = state.copyWith(ignoreSections: value);
    await GStorage.setting.put(_kIgnoreSections, value);
  }

  Future<void> resetAll() async {
    state = const TranslationConfig();
    await PromptStore.reset(Prompts.translationSystem);
    await PromptStore.reset(Prompts.translationUser);
    final box = GStorage.setting;
    await box.delete(_kTargetLang);
    await box.delete(_kTemperature);
    await box.delete(_kDisplayStyle);
    await box.delete(_kIgnoreSections);
  }
}

// ── Provider ───────────────────────────────────────────────────────────

final translationConfigProvider =
    StateNotifierProvider<TranslationConfigNotifier, TranslationConfig>(
      (ref) => TranslationConfigNotifier(),
    );
