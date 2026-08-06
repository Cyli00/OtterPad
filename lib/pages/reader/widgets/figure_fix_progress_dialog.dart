import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;

import '../../../core/l10n.dart';
import '../../../services/haptics.dart';
import '../../../widgets/app_dialog.dart';

/// AI 修缮 figure 进度对话框。监听 [stageNotifier] 实时显示阶段文案，
/// 取消按钮触发 [onCancel]（调用方持有 CancelToken 执行实际中断）。
///
/// 通过 [showFigureFixProgressDialog] 弹出。barrierDismissible=false——只能
/// 点「取消」或等任务完成由调用方 Navigator.pop 关闭。
class FigureFixProgressDialog extends StatelessWidget {
  final ValueListenable<String> stageNotifier;
  final VoidCallback onCancel;

  const FigureFixProgressDialog({
    super.key,
    required this.stageNotifier,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 280,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3, color: cs.primary),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<String>(
              valueListenable: stageNotifier,
              builder: (context, stage, _) => Text(
                stage,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface, fontSize: 14),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                Haptics.light();
                onCancel();
              },
              child: Text(context.l10n.cancel),
            ),
          ],
        ),
      ),
    );
  }
}

/// 弹出 [FigureFixProgressDialog]。返回可在任务完成后用 Navigator.pop(true) 关闭。
Future<void> showFigureFixProgressDialog({
  required BuildContext context,
  required ValueListenable<String> stageNotifier,
  required VoidCallback onCancel,
}) {
  return showAppDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => FigureFixProgressDialog(
      stageNotifier: stageNotifier,
      onCancel: onCancel,
    ),
  );
}