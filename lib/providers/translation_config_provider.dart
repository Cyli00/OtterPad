import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/storage.dart';

// ── 默认提示词模板（参考 Read-Frog prompt.ts，适配 Markdown 场景）────────

const kDefaultTranslationSystemPrompt = '''
You are a professional {{targetLanguage}} native translator who needs to fluently translate text into {{targetLanguage}}.

## Translation Rules
1. Output only the translated content, without explanations or additional content.
2. The returned translation must maintain exactly the same number of paragraphs and format as the original text.
3. For content that should not be translated (such as proper nouns, code, formulas, etc.), keep the original text.
4. Preserve all Markdown formatting including headings, lists, emphasis, and LaTeX expressions.''';

const kDefaultTranslationUserPrompt = '''
Translate to {{targetLanguage}}:

{{input}}''';

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

// ── Hive 存储 key ──────────────────────────────────────────────────────

const _kSystemPrompt = 'translation_config_system_prompt';
const _kUserPrompt = 'translation_config_user_prompt';
const _kTargetLang = 'translation_config_target_language';
const _kTemperature = 'translation_config_temperature';

// ── 数据模型 ───────────────────────────────────────────────────────────

class TranslationConfig {
  final String systemPrompt;
  final String userPrompt;
  final String targetLanguage;
  final double? temperature;

  const TranslationConfig({
    this.systemPrompt = kDefaultTranslationSystemPrompt,
    this.userPrompt = kDefaultTranslationUserPrompt,
    this.targetLanguage = kDefaultTargetLanguage,
    this.temperature,
  });

  bool get isSystemPromptDefault => systemPrompt == kDefaultTranslationSystemPrompt;
  bool get isUserPromptDefault => userPrompt == kDefaultTranslationUserPrompt;

  TranslationConfig copyWith({
    String? systemPrompt,
    String? userPrompt,
    String? targetLanguage,
  }) =>
      TranslationConfig(
        systemPrompt: systemPrompt ?? this.systemPrompt,
        userPrompt: userPrompt ?? this.userPrompt,
        targetLanguage: targetLanguage ?? this.targetLanguage,
        temperature: temperature,
      );
}

// ── StateNotifier ──────────────────────────────────────────────────────

class TranslationConfigNotifier extends StateNotifier<TranslationConfig> {
  TranslationConfigNotifier() : super(_load());

  static TranslationConfig _load() {
    final box = GStorage.setting;
    return TranslationConfig(
      systemPrompt: box.get(_kSystemPrompt, defaultValue: kDefaultTranslationSystemPrompt) as String,
      userPrompt: box.get(_kUserPrompt, defaultValue: kDefaultTranslationUserPrompt) as String,
      targetLanguage: box.get(_kTargetLang, defaultValue: kDefaultTargetLanguage) as String,
      temperature: box.get(_kTemperature) as double?,
    );
  }

  Future<void> setSystemPrompt(String value) async {
    state = state.copyWith(systemPrompt: value);
    await GStorage.setting.put(_kSystemPrompt, value);
  }

  Future<void> setUserPrompt(String value) async {
    state = state.copyWith(userPrompt: value);
    await GStorage.setting.put(_kUserPrompt, value);
  }

  Future<void> setTargetLanguage(String value) async {
    state = state.copyWith(targetLanguage: value);
    await GStorage.setting.put(_kTargetLang, value);
  }

  Future<void> resetSystemPrompt() async {
    state = state.copyWith(systemPrompt: kDefaultTranslationSystemPrompt);
    await GStorage.setting.delete(_kSystemPrompt);
  }

  Future<void> resetUserPrompt() async {
    state = state.copyWith(userPrompt: kDefaultTranslationUserPrompt);
    await GStorage.setting.delete(_kUserPrompt);
  }

  Future<void> setTemperature(double? value) async {
    state = TranslationConfig(
      systemPrompt: state.systemPrompt,
      userPrompt: state.userPrompt,
      targetLanguage: state.targetLanguage,
      temperature: value,
    );
    if (value != null) {
      await GStorage.setting.put(_kTemperature, value);
    } else {
      await GStorage.setting.delete(_kTemperature);
    }
  }

  Future<void> resetAll() async {
    state = const TranslationConfig();
    final box = GStorage.setting;
    await box.delete(_kSystemPrompt);
    await box.delete(_kUserPrompt);
    await box.delete(_kTargetLang);
    await box.delete(_kTemperature);
  }
}

// ── Provider ───────────────────────────────────────────────────────────

final translationConfigProvider =
    StateNotifierProvider<TranslationConfigNotifier, TranslationConfig>(
  (ref) => TranslationConfigNotifier(),
);
