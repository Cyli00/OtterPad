import 'package:flutter/foundation.dart';

abstract final class AppFonts {
  static const sans = 'sans';
  static const serif = 'serif';
  static const systemPrefix = 'system:';

  static String? family(String selection, TargetPlatform platform) {
    if (selection == serif) {
      return platform == TargetPlatform.android ||
              platform == TargetPlatform.linux
          ? 'serif'
          : 'Times New Roman';
    }
    if (isDesktop(platform) && selection.startsWith(systemPrefix)) {
      final name = selection.substring(systemPrefix.length).trim();
      if (name.isNotEmpty) return name;
    }
    return switch (platform) {
      TargetPlatform.windows => 'Microsoft YaHei UI',
      TargetPlatform.macOS || TargetPlatform.iOS => '.AppleSystemUIFont',
      _ => null,
    };
  }

  static bool isDesktop(TargetPlatform platform) => const [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ].contains(platform);

  static List<String> fallbacks(String selection, TargetPlatform platform) => [
    if (selection == serif) ...[
      'Noto Serif CJK SC',
      'Noto Serif CJK TC',
      'Songti SC',
      'Songti TC',
      'SimSun',
      'Noto Serif',
    ],
    if (family(sans, platform) case final String name) name,
  ];
}
