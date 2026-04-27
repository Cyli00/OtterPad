import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../widgets/spring_dismissible.dart';

/// 模型列表中单条记录的渲染——左滑可移除。
///
/// 组件只负责视觉呈现；所有状态（检测结果、角色）和动作都通过入参传入，
/// 父组件持有 _modelTestResults/_modelTesting 等状态。
class AgentModelListTile extends StatelessWidget {
  final String modelId;
  final bool isTesting;
  final bool hasTested;

  /// 若 [hasTested] 为 true，`null` 表示连通成功，非空字符串为错误信息。
  final String? errorMsg;

  /// 该模型是否已设置过自定义参数（非全部默认）。
  final bool hasCustomParams;

  final VoidCallback onRemove;
  final VoidCallback onTest;
  final VoidCallback onShowError;
  final VoidCallback onTune;

  const AgentModelListTile({
    super.key,
    required this.modelId,
    required this.isTesting,
    required this.hasTested,
    required this.errorMsg,
    required this.hasCustomParams,
    required this.onRemove,
    required this.onTest,
    required this.onShowError,
    required this.onTune,
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
                '移除',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.onErrorContainer,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        child: _buildCard(theme, cs, isOk, isErr),
      ),
    );
  }

  Widget _buildCard(ThemeData theme, ColorScheme cs, bool isOk, bool isErr) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
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
            const SizedBox(width: 8),
            SizedBox(
              width: 32,
              height: 32,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: Icon(
                      Symbols.tune_rounded,
                      size: 20,
                      color: hasCustomParams ? cs.primary : cs.onSurfaceVariant,
                    ),
                    padding: EdgeInsets.zero,
                    tooltip: '调节参数',
                    onPressed: onTune,
                  ),
                  if (hasCustomParams)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cs.primary,
                          border: Border.all(color: cs.surface, width: 1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
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

