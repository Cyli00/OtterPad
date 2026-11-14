import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../services/haptics.dart';

const _minLength = 8;

/// 设置备份密钥的加密口令。返回新口令；返回 '' 表示关闭；取消返回 null。
Future<String?> showBackupCredentialsDialog(
  BuildContext context, {
  required bool enabled,
}) => showDialog<String>(
  context: context,
  builder: (_) => _BackupCredentialsDialog(enabled: enabled),
);

class _BackupCredentialsDialog extends StatefulWidget {
  const _BackupCredentialsDialog({required this.enabled});

  final bool enabled;

  @override
  State<_BackupCredentialsDialog> createState() =>
      _BackupCredentialsDialogState();
}

class _BackupCredentialsDialogState extends State<_BackupCredentialsDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _save() {
    final l10n = context.l10n;
    final password = _password.text;
    final error = password.length < _minLength
        ? l10n.passwordTooShort(_minLength)
        : password != _confirm.text
        ? l10n.passwordMismatch
        : null;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Haptics.soft();
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ts = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(l10n.backupCredentials),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.backupCredentialsMessage,
              style: ts.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.password),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.confirmPassword,
                errorText: _error,
              ),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.enabled)
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: Text(l10n.turnOff),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _save, child: Text(l10n.save)),
      ],
    );
  }
}

/// 恢复含加密密钥的备份时输入口令。返回口令；跳过返回 null。
Future<String?> showRestoreCredentialsDialog(
  BuildContext context, {
  required bool wrongPassword,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _RestoreCredentialsDialog(wrongPassword: wrongPassword),
);

class _RestoreCredentialsDialog extends StatefulWidget {
  const _RestoreCredentialsDialog({required this.wrongPassword});

  final bool wrongPassword;

  @override
  State<_RestoreCredentialsDialog> createState() =>
      _RestoreCredentialsDialogState();
}

class _RestoreCredentialsDialogState extends State<_RestoreCredentialsDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_password.text.isEmpty) return;
    Navigator.of(context).pop(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ts = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(l10n.restoreCredentialsTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.restoreCredentialsMessage,
              style: ts.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.password,
                errorText: widget.wrongPassword ? l10n.wrongPassword : null,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.skip),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.confirm)),
      ],
    );
  }
}
