import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/l10n.dart';
import '../../services/haptics.dart';
import 'agent_role_widgets.dart';

/// 用户在"添加模型"对话框中做出的角色选择。
class AddModelChoice {
  final bool setAsDefault;
  final bool setAsFast;

  const AddModelChoice({
    required this.setAsDefault,
    required this.setAsFast,
  });
}

/// 弹出"添加模型"对话框，询问用户是否将该模型设为默认 / 快速。
///
/// 返回 `null` 表示用户取消；否则返回 [AddModelChoice]。
///
/// 唯一性由调用方 notifier 保证——此对话框只负责视觉提示。
Future<AddModelChoice?> showAgentAddModelDialog({
  required BuildContext context,
  required String modelId,
  required String? currentDefault,
  required String? currentFast,
  bool isMultimodal = true,
}) {
  bool setAsDefault = false;
  bool setAsFast = false;

  return showDialog<AddModelChoice>(
    context: context,
    barrierColor: Colors.black.withAlpha(90),
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final cs = theme.colorScheme;
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final defaultReplaces = setAsDefault &&
              currentDefault != null &&
              currentDefault != modelId;
          final fastReplaces =
              setAsFast && currentFast != null && currentFast != modelId;

          return Dialog(
            backgroundColor: cs.surfaceContainerHigh,
            elevation: 0,
            insetPadding: const EdgeInsets.symmetric(horizontal: 40),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      ctx.l10n.addModelTitle,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      ctx.l10n.assignRoleHint,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (isMultimodal) ...[
                      RoleToggleTile(
                        icon: Symbols.psychology_rounded,
                        label: ctx.l10n.expertModel,
                        containerColor: cs.primaryContainer,
                        onContainerColor: cs.onPrimaryContainer,
                        value: setAsDefault,
                        onChanged: (v) {
                          Haptics.soft();
                          setLocal(() => setAsDefault = v);
                        },
                        replacingText: defaultReplaces
                            ? ctx.l10n.willReplace(currentDefault)
                            : null,
                      ),
                      const SizedBox(height: 10),
                    ],
                    RoleToggleTile(
                      icon: Symbols.bolt_rounded,
                      label: ctx.l10n.fastModel,
                      containerColor: cs.tertiaryContainer,
                      onContainerColor: cs.onTertiaryContainer,
                      value: setAsFast,
                      onChanged: (v) {
                        Haptics.soft();
                        setLocal(() => setAsFast = v);
                      },
                      replacingText:
                          fastReplaces ? ctx.l10n.willReplace(currentFast) : null,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            Haptics.soft();
                            Navigator.pop(ctx);
                          },
                          child: Text(ctx.l10n.cancel),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            Haptics.soft();
                            Navigator.pop(
                              ctx,
                              AddModelChoice(
                                setAsDefault: setAsDefault,
                                setAsFast: setAsFast,
                              ),
                            );
                          },
                          child: Text(ctx.l10n.add),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
