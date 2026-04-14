import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'agent_role_widgets.dart';

/// 模型列表中单条记录的渲染——含左滑"移除"动作。
///
/// 组件只负责视觉呈现；所有状态（检测结果、角色）和动作都通过入参传入，
/// 父组件持有 _modelTestResults/_modelTesting 等状态。
class AgentModelListTile extends StatelessWidget {
  final String modelId;
  final bool isDefault;
  final bool isFast;
  final bool isTesting;
  final bool hasTested;

  /// 若 [hasTested] 为 true，`null` 表示连通成功，非空字符串为错误信息。
  final String? errorMsg;

  final VoidCallback onRemove;
  final VoidCallback onTest;
  final VoidCallback onShowError;

  const AgentModelListTile({
    super.key,
    required this.modelId,
    required this.isDefault,
    required this.isFast,
    required this.isTesting,
    required this.hasTested,
    required this.errorMsg,
    required this.onRemove,
    required this.onTest,
    required this.onShowError,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isOk = hasTested && errorMsg == null;
    final isErr = hasTested && !isOk;

    return LayoutBuilder(
      builder: (ctx, constraints) {
        // 目标像素宽度 96 → 反算 extentRatio，让移除按钮在任何窗口下
        // 都稳定在 ~88–110 px；ratio clamp 防极端宽度出现过度拉伸
        final cardWidth = constraints.maxWidth;
        const targetPx = 96.0;
        final ratio = (targetPx / cardWidth).clamp(0.06, 0.30).toDouble();

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Slidable(
            key: ValueKey('agent-model-$modelId'),
            groupTag: 'agent-models',
            endActionPane: ActionPane(
              motion: const StretchMotion(),
              extentRatio: ratio,
              children: [
                CustomSlidableAction(
                  onPressed: (_) => onRemove(),
                  // 透明背景让内层 Container 自己控制圆角和填色
                  backgroundColor: Colors.transparent,
                  foregroundColor: cs.onErrorContainer,
                  padding: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.errorContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Symbols.delete_rounded,
                                size: 22,
                                color: cs.onErrorContainer,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '移除',
                                maxLines: 1,
                                softWrap: false,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onErrorContainer,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            child: _buildCard(theme, cs, isOk, isErr),
          ),
        );
      },
    );
  }

  Widget _buildCard(ThemeData theme, ColorScheme cs, bool isOk, bool isErr) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOk
              ? cs.primary.withAlpha(100)
              : isErr
                  ? cs.error.withAlpha(100)
                  : cs.outlineVariant.withAlpha(60),
        ),
      ),
      child: Padding(
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
              child: Text(
                modelId,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isDefault) ...[
              const SizedBox(width: 6),
              RoleBadge(
                label: '默认',
                bg: cs.primaryContainer,
                fg: cs.onPrimaryContainer,
              ),
            ],
            if (isFast) ...[
              const SizedBox(width: 4),
              RoleBadge(
                label: '快速',
                bg: cs.tertiaryContainer,
                fg: cs.onTertiaryContainer,
              ),
            ],
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
                        Symbols.vital_signs,
                        size: 20,
                        color: isOk
                            ? cs.primary
                            : isErr
                                ? cs.error
                                : cs.onSurfaceVariant,
                      ),
                      padding: EdgeInsets.zero,
                      tooltip: isErr ? errorMsg : '检测模型',
                      onPressed: isErr ? onShowError : onTest,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
