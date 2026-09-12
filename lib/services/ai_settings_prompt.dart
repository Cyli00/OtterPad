import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/l10n.dart';
import '../data/models/ai/agent_config.dart';
import '../data/models/ocr/doc_extract_config.dart';
import '../router/app_router.dart';
import '../router/app_routes.dart';
import '../widgets/app_dialog.dart';

class AiSettingsPrompt {
  AiSettingsPrompt._();

  static Future<bool> ensureTextModelConfigured({
    BuildContext? context,
    required AgentApiState agentState,
  }) async {
    final hasModel =
        (agentState.fastModelId?.isNotEmpty ?? false) ||
        (agentState.defaultModelId?.isNotEmpty ?? false);
    if (!hasModel) {
      final ctx = _resolveContext(context);
      if (ctx == null) return false;
      await _showDialog(
        context: ctx,
        message: ctx.l10n.aiSettingsSelectTextModel,
        route: AppRoutes.settingsOverlayApi,
      );
      return false;
    }
    if (agentState.apiKey.trim().isEmpty) {
      final ctx = _resolveContext(context);
      if (ctx == null) return false;
      await _showDialog(
        context: ctx,
        message: ctx.l10n.aiSettingsFillApiKey,
        route: AppRoutes.settingsOverlayApi,
      );
      return false;
    }
    return true;
  }

  static Future<bool> ensureImageModelSelected({
    BuildContext? context,
    required ({String? id, String? modelId}) imageRole,
  }) async {
    if (imageRole.id != null && imageRole.modelId != null) return true;
    final ctx = _resolveContext(context);
    if (ctx == null) return false;
    await _showDialog(
      context: ctx,
      message: ctx.l10n.selectImageModelFirst,
      route: AppRoutes.settingsOverlayApi,
    );
    return false;
  }

  static Future<bool> ensureImageModelConfigured({
    BuildContext? context,
    required AgentApiState agentState,
  }) async {
    final hasModel = agentState.imageModelId?.isNotEmpty ?? false;
    if (!hasModel) {
      final ctx = _resolveContext(context);
      if (ctx == null) return false;
      await _showDialog(
        context: ctx,
        message: ctx.l10n.selectImageModelFirst,
        route: AppRoutes.settingsOverlayApi,
      );
      return false;
    }
    if (agentState.apiKey.trim().isEmpty) {
      final ctx = _resolveContext(context);
      if (ctx == null) return false;
      await _showDialog(
        context: ctx,
        message: ctx.l10n.aiSettingsFillImageApiKey,
        route: AppRoutes.settingsOverlayApi,
      );
      return false;
    }
    return true;
  }

  static Future<bool> ensureExtractConfigured({
    BuildContext? context,
    required DocExtractApiState apiState,
  }) async {
    if (apiState.isConfigured) return true;
    final ctx = _resolveContext(context);
    if (ctx == null) return false;
    await _showDialog(
      context: ctx,
      message: ctx.l10n.configureExtractToken,
      route: AppRoutes.settingsOverlayExtract,
    );
    return false;
  }

  static Future<bool> showForConfigError({
    required BuildContext context,
    required Object error,
  }) async {
    final message = _normalizeError(error);
    if (!message.contains('AI 设置')) return false;
    if (!context.mounted) return false;
    await _showDialog(
      context: context,
      message: message,
      route: AppRoutes.settingsOverlayApi,
    );
    return true;
  }

  static BuildContext? _resolveContext(BuildContext? context) {
    final ctx = context ?? rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return null;
    return ctx;
  }

  static Future<void> _showDialog({
    required BuildContext context,
    required String message,
    required String route,
  }) async {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // 视觉对齐 §3.1 Dialog 规范（titleLarge bold 标题 + bodyMedium 正文 +
    // fromLTRB(24,24,24,20) + 宽度 clamp），与 _showNewChatDialog 等保持一致；
    // 不再用 Material AlertDialog（其默认 headlineSmall 标题与 padding 不符）。
    final goToSettings = await showAppDialog<bool>(
      context: context,
      builder: (ctx) {
        final width = (MediaQuery.of(ctx).size.width * 0.85).clamp(
          320.0,
          480.0,
        );
        return Material(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: width,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.configurationRequired,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(l10n.cancel),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(l10n.goToSettings),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (goToSettings == true && context.mounted) {
      context.push(route);
    }
  }

  static String _normalizeError(Object error) {
    return '$error'
        .replaceFirst('Exception: ', '')
        .replaceAll('"AI 设置"', '「AI 设置」')
        .replaceAll('在 AI 设置中', '在「AI 设置」中')
        .trim();
  }
}
