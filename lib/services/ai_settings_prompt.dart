import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../providers/api_provider.dart';
import '../router/app_router.dart';
import 'snackbar_service.dart';

class AiSettingsPrompt {
  AiSettingsPrompt._();

  static AppLocalizations? get _l10n {
    final ctx = rootNavigatorKey.currentContext;
    return ctx != null ? AppLocalizations.of(ctx) : null;
  }

  static bool ensureTextModelConfigured({
    required AgentApiState agentState,
    required SnackBarService snackBar,
    required VoidCallback onOpenSettings,
  }) {
    final l10n = _l10n;
    final hasModel =
        (agentState.fastModelId?.isNotEmpty ?? false) ||
        (agentState.defaultModelId?.isNotEmpty ?? false);
    if (!hasModel) {
      _show(
        snackBar,
        message: l10n?.aiSettingsSelectTextModel ?? '请先在「AI 设置」中选择快速模型或专家模型',
        onOpenSettings: onOpenSettings,
      );
      return false;
    }
    if (agentState.apiKey.trim().isEmpty) {
      _show(
        snackBar,
        message: l10n?.aiSettingsFillApiKey ?? '请先在「AI 设置」中填写 API Key',
        onOpenSettings: onOpenSettings,
      );
      return false;
    }
    return true;
  }

  static bool ensureImageModelSelected({
    required ({String? id, String? modelId}) imageRole,
    required SnackBarService snackBar,
    required VoidCallback onOpenSettings,
  }) {
    if (imageRole.id != null && imageRole.modelId != null) return true;
    _show(
      snackBar,
      message: _l10n?.selectImageModelFirst ?? '请先在「AI 设置」中选择生图模型',
      onOpenSettings: onOpenSettings,
    );
    return false;
  }

  static bool ensureImageModelConfigured({
    required AgentApiState agentState,
    required SnackBarService snackBar,
    required VoidCallback onOpenSettings,
  }) {
    final l10n = _l10n;
    final hasModel = agentState.imageModelId?.isNotEmpty ?? false;
    if (!hasModel) {
      _show(
        snackBar,
        message: l10n?.selectImageModelFirst ?? '请先在「AI 设置」中选择生图模型',
        onOpenSettings: onOpenSettings,
      );
      return false;
    }
    if (agentState.apiKey.trim().isEmpty) {
      _show(
        snackBar,
        message: l10n?.aiSettingsFillImageApiKey ?? '请先在「AI 设置」中填写生图模型 API Key',
        onOpenSettings: onOpenSettings,
      );
      return false;
    }
    return true;
  }

  static bool showForConfigError({
    required Object error,
    required SnackBarService snackBar,
    required VoidCallback onOpenSettings,
  }) {
    final message = _normalizeError(error);
    if (!message.contains('AI 设置')) return false;
    _show(snackBar, message: message, onOpenSettings: onOpenSettings);
    return true;
  }

  static void _show(
    SnackBarService snackBar, {
    required String message,
    required VoidCallback onOpenSettings,
  }) {
    snackBar.showResult(
      message: message,
      action: SnackBarAction(
        label: rootNavigatorKey.currentContext != null
            ? AppLocalizations.of(rootNavigatorKey.currentContext!)!
                .goToSettings
            : '前往设置',
        onPressed: onOpenSettings,
      ),
    );
  }

  static String _normalizeError(Object error) {
    return '$error'
        .replaceFirst('Exception: ', '')
        .replaceAll('"AI 设置"', '「AI 设置」')
        .replaceAll('在 AI 设置中', '在「AI 设置」中')
        .trim();
  }
}
