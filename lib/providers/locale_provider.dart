import 'dart:ui';

// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/storage.dart';

class LocaleNotifier extends StateNotifier<Locale?> {
  static const _kLocale = 'app_locale';

  LocaleNotifier() : super(_load());

  static Locale? _load() {
    final tag = GStorage.setting.get(_kLocale) as String?;
    return _parseTag(tag);
  }

  /// null = 跟随系统
  void setLocale(Locale? locale) {
    state = locale;
    if (locale == null) {
      GStorage.setting.delete(_kLocale);
    } else {
      GStorage.setting.put(_kLocale, _toTag(locale));
    }
  }

  static String _toTag(Locale locale) {
    if (locale.scriptCode != null) {
      return '${locale.languageCode}_${locale.scriptCode}';
    }
    if (locale.countryCode != null) {
      return '${locale.languageCode}_${locale.countryCode}';
    }
    return locale.languageCode;
  }

  static Locale? _parseTag(String? tag) {
    if (tag == null || tag.isEmpty) return null;
    final parts = tag.split('_');
    if (parts.length >= 2) {
      if (parts[1].length == 4) {
        return Locale.fromSubtags(
            languageCode: parts[0], scriptCode: parts[1]);
      }
      return Locale(parts[0], parts[1]);
    }
    return Locale(parts[0]);
  }
}

/// null 表示跟随系统（MaterialApp.locale = null 时走平台默认）
final localeProvider = StateNotifierProvider<LocaleNotifier, Locale?>(
  (ref) => LocaleNotifier(),
);
