// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/settings_keys.dart';
import '../core/storage/storage.dart';

/// 导航栏标签展示偏好：null = 跟随宽度自动（≥1200 展开文字）。
class NavRailExtendedNotifier extends StateNotifier<bool?> {
  NavRailExtendedNotifier()
    : super(GStorage.setting.get(SettingsKeys.navRailExtended) as bool?);

  void setExtended(bool value) {
    state = value;
    GStorage.setting.put(SettingsKeys.navRailExtended, value);
  }
}

final navRailExtendedProvider =
    StateNotifierProvider<NavRailExtendedNotifier, bool?>(
      (ref) => NavRailExtendedNotifier(),
    );
