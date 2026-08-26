import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../services/haptics.dart';
import 'app_dialog.dart';

/// 欢迎对话框 — 返回 true 表示开始引导，false 表示跳过。
Future<bool> showOnboardingWelcomeDialog(BuildContext context) async {
  final result = await showAppDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final cs = Theme.of(context).colorScheme;
      final theme = Theme.of(context);
      final l10n = context.l10n;
      return AlertDialog(
        backgroundColor: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(
          l10n.onboardingWelcomeTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          l10n.onboardingWelcomeBody,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Haptics.soft();
              Navigator.pop(context, false);
            },
            child: Text(l10n.onboardingSkip),
          ),
          FilledButton(
            onPressed: () {
              Haptics.soft();
              Navigator.pop(context, true);
            },
            child: Text(l10n.onboardingStart),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// OCR 设置对话框 — 带 ocr_token_setting.png 图片，返回 true 前往设置。
Future<bool> showOnboardingOcrDialog(BuildContext context) async {
  final result = await showAppDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final cs = Theme.of(context).colorScheme;
      final theme = Theme.of(context);
      final l10n = context.l10n;
      return AlertDialog(
        backgroundColor: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(
          l10n.onboardingOcrTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        // 矮窗口兜底可滚动，不允许假设窗口高度足够
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.onboardingOcrBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Builder(builder: (context) {
                final lang = Localizations.localeOf(context).languageCode;
                final asset = lang == 'zh'
                    ? 'assets/icons/ocr_token_setting.png'
                    : 'assets/icons/ocr_token_setting_en.png';
                // 图片原生高度大，压到半屏内，否则矮窗口 BOTTOM OVERFLOWED
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                  ),
                  child: Image.asset(asset, fit: BoxFit.contain),
                );
              }),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Haptics.soft();
              Navigator.pop(context, false);
            },
            child: Text(l10n.onboardingSkip),
          ),
          FilledButton(
            onPressed: () {
              Haptics.soft();
              Navigator.pop(context, true);
            },
            child: Text(l10n.onboardingOcrGuide),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// AI 模型设置对话框 — 返回 true 前往配置。
Future<bool> showOnboardingAiDialog(BuildContext context) async {
  final result = await showAppDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final cs = Theme.of(context).colorScheme;
      final theme = Theme.of(context);
      final l10n = context.l10n;
      return AlertDialog(
        backgroundColor: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(
          l10n.onboardingAiTitle,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          l10n.onboardingAiBody,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Haptics.soft();
              Navigator.pop(context, false);
            },
            child: Text(l10n.onboardingSkip),
          ),
          FilledButton(
            onPressed: () {
              Haptics.soft();
              Navigator.pop(context, true);
            },
            child: Text(l10n.onboardingAiGuide),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
