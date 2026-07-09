import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/l10n.dart';
import '../../../services/haptics.dart';

/// 定位原文后悬浮于阅读器上的「返回问 AI / 取消」操作条。
///
/// 视觉对齐 [AddDocumentsToFavoritePage] 右下角确认条；位置由 caller 按底栏
/// 显隐动态计算 bottom inset。
class ReaderChatReturnPrompt extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onReturn;

  const ReaderChatReturnPrompt({
    super.key,
    required this.onCancel,
    required this.onReturn,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      elevation: 6,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () {
                Haptics.soft();
                onCancel();
              },
              child: Text(context.l10n.cancel),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: () {
                Haptics.soft();
                onReturn();
              },
              icon: const Icon(Symbols.auto_awesome_rounded, size: 18),
              label: Text(context.l10n.chatReturnToAi),
            ),
          ],
        ),
      ),
    );
  }
}