import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../services/update_service.dart';

/// 检查更新结果弹窗：版本对比 + changelog 摘要，串联更新/忽略/稍后/查看发布页四个动作。
/// 纯展示组件，不做网络/下载/持久化——那些交给 `update_flow.dart` 的回调完成。
class UpdateDialog extends StatelessWidget {
  final UpdateInfo info;
  final VoidCallback onUpdateNow;
  final VoidCallback onIgnore;
  final VoidCallback onLater;
  final VoidCallback onOpenReleasePage;

  const UpdateDialog({
    super.key,
    required this.info,
    required this.onUpdateNow,
    required this.onIgnore,
    required this.onLater,
    required this.onOpenReleasePage,
  });

  bool get _canInstallInApp =>
      !kIsWeb && Platform.isAndroid && info.arm64Asset != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;

    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(28),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.updateNewVersionFound,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${info.currentVersion} → ${info.remoteVersion}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (info.changelogLines.isNotEmpty) ...[
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final line in info.changelogLines)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '· $line',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onOpenReleasePage,
                  child: Text(l10n.updateViewFullChangelog),
                ),
              ),
              const SizedBox(height: 8),
              // Wrap 而非 Row：窄屏（360dp）下三个按钮 + zh_Hant 较长文案会溢出，
              // 换行降级而非撑破布局（见 CLAUDE.md 窄屏适配约定）
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                runSpacing: 4,
                children: [
                  TextButton(
                    onPressed: onIgnore,
                    child: Text(l10n.updateIgnoreVersion),
                  ),
                  TextButton(onPressed: onLater, child: Text(l10n.updateLater)),
                  TextButton(
                    onPressed: onUpdateNow,
                    child: Text(
                      _canInstallInApp
                          ? l10n.updateNow
                          : l10n.updateOpenReleasePage,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
