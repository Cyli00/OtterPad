import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class Haptics {
  Haptics._();

  static bool _enabled = true;
  static bool get enabled => _enabled;
  static void setEnabled(bool v) => _enabled = v;

  static void light() {
    if (!_enabled) return;
    _safe(() => HapticFeedback.lightImpact());
  }

  static void medium() {
    if (!_enabled) return;
    _safe(() => HapticFeedback.mediumImpact());
  }

  static void soft() {
    if (!_enabled) return;
    _safe(() => HapticFeedback.selectionClick());
  }

  static void _safe(Future<void> Function() action) {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      action();
    } catch (_) {
      // 吞没平台异常
    }
  }
}
