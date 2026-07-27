import 'package:flutter_riverpod/legacy.dart';

import '../core/storage/settings_keys.dart';
import '../core/storage/storage.dart';

enum OnboardingStep {
  welcome,
  ocrIntro,
  ocrGetToken,
  ocrApiKey,
  ocrGoBack,
  toolsHighlight,
  aiIntro,
  aiExpert,
  aiFast,
  aiImageGen,
  completed,
}

class OnboardingNotifier extends StateNotifier<OnboardingStep> {
  OnboardingNotifier() : super(_initialStep());

  static const _key = SettingsKeys.hasSeenOnboarding;

  static OnboardingStep _initialStep() {
    final seen = GStorage.setting.get(_key) as bool? ?? false;
    return seen ? OnboardingStep.completed : OnboardingStep.welcome;
  }

  bool get isActive => state != OnboardingStep.completed;

  void advance() {
    if (state == OnboardingStep.completed) return;
    final nextIndex = state.index + 1;
    if (nextIndex >= OnboardingStep.values.length) return;
    state = OnboardingStep.values[nextIndex];
    if (state == OnboardingStep.completed) {
      GStorage.setting.put(_key, true);
    }
  }

  void jumpTo(OnboardingStep step) {
    state = step;
  }

  void complete() {
    state = OnboardingStep.completed;
    GStorage.setting.put(_key, true);
  }
}

final onboardingProvider =
    StateNotifierProvider<OnboardingNotifier, OnboardingStep>(
  (ref) => OnboardingNotifier(),
);
