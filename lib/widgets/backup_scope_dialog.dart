import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../services/backup_restore_service.dart';
import 'app_dialog.dart';

/// 备份范围选择对话框（设置页手动备份与云同步页「立即备份」共用）。
/// 取消返回 null。
Future<BackupScope?> showBackupScopeDialog(BuildContext context) {
  var scope = BackupScope.dataOnly;
  return showAppDialog<BackupScope>(
    context: context,
    builder: (context) {
      final cs = Theme.of(context).colorScheme;
      final ts = Theme.of(context).textTheme;
      final l10n = context.l10n;
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: cs.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            title: Text(l10n.backupScopeTitle),
            content: SizedBox(
              width: 420,
              child: RadioGroup<BackupScope>(
                groupValue: scope,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => scope = value);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final s in BackupScope.values)
                      RadioListTile<BackupScope>(
                        value: s,
                        activeColor: cs.primary,
                        contentPadding: EdgeInsets.zero,
                        title: Text(switch (s) {
                          BackupScope.full => l10n.backupScopeFull,
                          BackupScope.dataOnly => l10n.backupScopeData,
                        }),
                        subtitle: Text(
                          switch (s) {
                            BackupScope.full => l10n.backupScopeFullDesc,
                            BackupScope.dataOnly => l10n.backupScopeDataDesc,
                          },
                          style: ts.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(scope),
                child: Text(l10n.startBackup),
              ),
            ],
          );
        },
      );
    },
  );
}
