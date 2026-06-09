import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/l10n.dart';
import '../../services/agent_model_capability.dart';
import '../../services/haptics.dart';
import '../../widgets/spring_dismissible.dart';
import 'agent_role_widgets.dart';

/// 模型列表中单条记录的渲染——左滑可移除，点按编辑能力。
///
/// 组件只负责视觉呈现；所有状态（检测结果、能力）和动作都通过入参传入。
class AgentModelListTile extends StatelessWidget {
  final String modelId;
  final bool isTesting;
  final bool hasTested;

  /// 若 [hasTested] 为 true，`null` 表示连通成功，非空字符串为错误信息。
  final String? errorMsg;

  /// 模型能力（分类 + 模态 + 工具/推理），用于渲染 badge。
  final AgentModelCapability capability;

  final VoidCallback onRemove;
  final VoidCallback onTest;
  final VoidCallback onShowError;

  /// 点按整行 → 编辑能力。
  final VoidCallback onEdit;

  const AgentModelListTile({
    super.key,
    required this.modelId,
    required this.isTesting,
    required this.hasTested,
    required this.errorMsg,
    required this.capability,
    required this.onRemove,
    required this.onTest,
    required this.onShowError,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isOk = hasTested && errorMsg == null;
    final isErr = hasTested && !isOk;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SpringDismissible(
        onDismissed: onRemove,
        background: Container(
          decoration: BoxDecoration(
            color: cs.errorContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Symbols.delete_rounded, size: 22, color: cs.onErrorContainer),
              const SizedBox(height: 3),
              Text(
                context.l10n.remove,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onErrorContainer,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        child: _buildCard(context, theme, cs, isOk, isErr),
      ),
    );
  }

  Widget _buildCard(BuildContext context, ThemeData theme, ColorScheme cs, bool isOk, bool isErr) {
    final badges = _badges(context, cs);
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Haptics.soft();
          onEdit();
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isOk
                  ? cs.primary.withAlpha(100)
                  : isErr
                  ? cs.error.withAlpha(100)
                  : cs.outlineVariant.withAlpha(60),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOk
                      ? cs.primary
                      : isErr
                      ? cs.error
                      : cs.outlineVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      modelId,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (badges.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 4, runSpacing: 4, children: badges),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 32,
                height: 32,
                child: isTesting
                    ? const Padding(
                        padding: EdgeInsets.all(6),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        icon: Icon(
                          Symbols.vital_signs_rounded,
                          size: 20,
                          color: isOk
                              ? cs.primary
                              : isErr
                              ? cs.error
                              : cs.onSurfaceVariant,
                        ),
                        padding: EdgeInsets.zero,
                        tooltip: isErr ? errorMsg : context.l10n.detectModel,
                        onPressed: () {
                          Haptics.soft();
                          (isErr ? onShowError : onTest)();
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 由能力派生 badge 列表。嵌入模型只显示「嵌入」，其余按模态/能力展开。
  List<Widget> _badges(BuildContext context, ColorScheme cs) {
    final c = capability;
    final l10n = context.l10n;
    if (c.embedding) {
      return [
        RoleBadge(
          label: l10n.roleBadgeEmbedding,
          bg: cs.tertiaryContainer,
          fg: cs.onTertiaryContainer,
        ),
      ];
    }
    return [
      if (c.imageInput)
        RoleBadge(
          label: l10n.roleBadgeVision,
          bg: cs.primaryContainer,
          fg: cs.onPrimaryContainer,
        ),
      if (c.imageOutput)
        RoleBadge(
          label: l10n.roleBadgeImageGen,
          bg: cs.secondaryContainer,
          fg: cs.onSecondaryContainer,
        ),
      if (c.tool)
        RoleBadge(
          label: l10n.roleBadgeTools,
          bg: cs.surfaceContainerHighest,
          fg: cs.onSurfaceVariant,
        ),
      if (c.reasoning)
        RoleBadge(
          label: l10n.roleBadgeReasoning,
          bg: cs.surfaceContainerHighest,
          fg: cs.onSurfaceVariant,
        ),
    ];
  }
}
