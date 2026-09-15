// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/secure_credential_vault.dart';
import '../core/storage/settings_keys.dart';
import '../core/storage/storage.dart';

import '../data/models/ocr/doc_extract_config.dart';
export '../data/models/ocr/doc_extract_config.dart';

class DocExtractApiNotifier extends StateNotifier<DocExtractApiState> {
  /// PaddleOCR key 槽（历史键名，勿改——旧用户数据在此）
  static const _paddleApiKeyKey = 'doc_extract_api_key';
  static const _mineruApiKeyKey = 'doc_extract_api_key_mineru';
  static const _prefix = SettingsKeys.docExtractPrefix;

  DocExtractApiNotifier() : super(_load());

  static DocExtractApiState _load() {
    final box = GStorage.setting;

    final provider = DocExtractProviderExt.fromName(
      box.get('$_prefix${SettingsKeys.docExtractProviderField}') as String?,
    );
    final paddleApiKey = SecureCredentialVault.read(_paddleApiKeyKey);
    final mineruApiKey = SecureCredentialVault.read(_mineruApiKeyKey);
    final useChartRecognition =
        box.get('${_prefix}useChartRecognition', defaultValue: false) as bool;
    final useDocOrientationClassify =
        box.get('${_prefix}useDocOrientationClassify', defaultValue: false)
            as bool;
    final useDocUnwarping =
        box.get('${_prefix}useDocUnwarping', defaultValue: false) as bool;
    final useSealRecognition =
        box.get('${_prefix}useSealRecognition', defaultValue: false) as bool;
    final useOcrForImageBlock =
        box.get('${_prefix}useOcrForImageBlock', defaultValue: false) as bool;
    final restructurePages =
        box.get('${_prefix}restructurePages', defaultValue: true) as bool;
    final layoutNms =
        box.get('${_prefix}layoutNms', defaultValue: true) as bool;
    final mergeTables =
        box.get('${_prefix}mergeTables', defaultValue: true) as bool;
    final layoutShapeMode =
        box.get('${_prefix}layoutShapeMode', defaultValue: 'auto') as String;
    final repetitionPenalty =
        box.get('${_prefix}repetitionPenalty', defaultValue: 1.0) as double;
    final temperature =
        box.get('${_prefix}temperature', defaultValue: 0.0) as double;

    final rawLabels = box.get('${_prefix}markdownIgnoreLabels') as List?;
    final markdownIgnoreLabels = rawLabels != null
        ? rawLabels.cast<String>().toList()
        : List<String>.from(kDefaultIgnoreLabels);

    final mineruIsOcr =
        box.get('${_prefix}mineruIsOcr', defaultValue: false) as bool;
    final mineruEnableFormula =
        box.get('${_prefix}mineruEnableFormula', defaultValue: true) as bool;
    final mineruEnableTable =
        box.get('${_prefix}mineruEnableTable', defaultValue: true) as bool;
    final mineruLanguage =
        box.get('${_prefix}mineruLanguage', defaultValue: 'ch') as String;

    return DocExtractApiState(
      provider: provider,
      paddleApiKey: paddleApiKey,
      mineruApiKey: mineruApiKey,
      useChartRecognition: useChartRecognition,
      useDocOrientationClassify: useDocOrientationClassify,
      useDocUnwarping: useDocUnwarping,
      useSealRecognition: useSealRecognition,
      useOcrForImageBlock: useOcrForImageBlock,
      restructurePages: restructurePages,
      layoutNms: layoutNms,
      mergeTables: mergeTables,
      layoutShapeMode: layoutShapeMode,
      repetitionPenalty: repetitionPenalty,
      temperature: temperature,
      markdownIgnoreLabels: markdownIgnoreLabels,
      mineruIsOcr: mineruIsOcr,
      mineruEnableFormula: mineruEnableFormula,
      mineruEnableTable: mineruEnableTable,
      mineruLanguage: mineruLanguage,
      mineruExtraFormats:
          (box.get('${_prefix}mineruExtraFormats') as List?)?.cast<String>() ??
          const [],
    );
  }

  Future<void> setProvider(DocExtractProvider provider) async {
    state = state.copyWith(provider: provider);
    await GStorage.setting.put(
      '$_prefix${SettingsKeys.docExtractProviderField}',
      provider.name,
    );
  }

  /// 写指定提供商的 token；槽位隔离，切换提供商互不影响。
  Future<void> setApiKey(DocExtractProvider provider, String key) async {
    switch (provider) {
      case DocExtractProvider.paddle:
        state = state.copyWith(paddleApiKey: key);
        await SecureCredentialVault.write(_paddleApiKeyKey, key);
      case DocExtractProvider.mineru:
        state = state.copyWith(mineruApiKey: key);
        await SecureCredentialVault.write(_mineruApiKeyKey, key);
    }
  }

  Future<void> setBool(String field, bool value) async {
    switch (field) {
      case 'useChartRecognition':
        state = state.copyWith(useChartRecognition: value);
      case 'useDocOrientationClassify':
        state = state.copyWith(useDocOrientationClassify: value);
      case 'useDocUnwarping':
        state = state.copyWith(useDocUnwarping: value);
      case 'useSealRecognition':
        state = state.copyWith(useSealRecognition: value);
      case 'useOcrForImageBlock':
        state = state.copyWith(useOcrForImageBlock: value);
      case 'restructurePages':
        state = state.copyWith(restructurePages: value);
      case 'layoutNms':
        state = state.copyWith(layoutNms: value);
      case 'mergeTables':
        state = state.copyWith(mergeTables: value);
      case 'mineruIsOcr':
        state = state.copyWith(mineruIsOcr: value);
      case 'mineruEnableFormula':
        state = state.copyWith(mineruEnableFormula: value);
      case 'mineruEnableTable':
        state = state.copyWith(mineruEnableTable: value);
    }
    await GStorage.setting.put('$_prefix$field', value);
  }

  Future<void> setDouble(String field, double value) async {
    switch (field) {
      case 'repetitionPenalty':
        state = state.copyWith(repetitionPenalty: value);
      case 'temperature':
        state = state.copyWith(temperature: value);
    }
    await GStorage.setting.put('$_prefix$field', value);
  }

  Future<void> setString(String field, String value) async {
    switch (field) {
      case 'layoutShapeMode':
        state = state.copyWith(layoutShapeMode: value);
      case 'mineruLanguage':
        state = state.copyWith(mineruLanguage: value);
    }
    await GStorage.setting.put('$_prefix$field', value);
  }

  Future<void> setMineruExtraFormats(List<String> formats) async {
    state = state.copyWith(mineruExtraFormats: List.unmodifiable(formats));
    await GStorage.setting.put('${_prefix}mineruExtraFormats', formats);
  }

  Future<void> setIgnoreLabels(List<String> labels) async {
    state = state.copyWith(markdownIgnoreLabels: labels);
    await GStorage.setting.put('${_prefix}markdownIgnoreLabels', labels);
  }

  /// 重置除 API Key 与提供商选择外的所有提取配置为默认值。
  Future<void> resetExceptApiKey() async {
    final box = GStorage.setting;
    const fields = SettingsKeys.docExtractFields;
    for (final f in fields) {
      await box.delete('$_prefix$f');
    }
    for (final f in SettingsKeys.docExtractMineruFields) {
      await box.delete('$_prefix$f');
    }
    state = DocExtractApiState(
      provider: state.provider,
      paddleApiKey: state.paddleApiKey,
      mineruApiKey: state.mineruApiKey,
    );
  }

  void reload() {
    state = _load();
  }
}

final docExtractApiProvider =
    StateNotifierProvider<DocExtractApiNotifier, DocExtractApiState>(
      (ref) => DocExtractApiNotifier(),
    );
