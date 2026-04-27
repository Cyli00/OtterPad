import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../providers/history_provider.dart';
import '../../services/snackbar_service.dart';
import '../../widgets/spring_dismissible.dart';
import '../library/widgets/doc_card_actions.dart';
import '../library/widgets/doc_list_card.dart';

/// 阅读历史页面：按日期桶分组展示所有已阅读文献
///
/// 设计要点：
/// - 复用 [DocListCard]，与收藏夹/星标保持卡片视觉一致
/// - 日期桶来自 [historySectionsProvider]，页面只负责渲染
/// - 每个桶一个 section header（圆点 + 标签 + 细分隔线 + 计数），
///   多个 sliver 自然实现"从上到下按日期分类"的视觉层次
class ReadingHistoryPage extends ConsumerWidget {
  const ReadingHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sections = ref.watch(historySectionsProvider);
    final totalCount = ref.watch(historyCountProvider);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        title: Text(
          '阅读历史',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          onPressed: () => context.pop(),
          icon: const Icon(Symbols.arrow_back_rounded),
        ),
        actions: [
          if (totalCount > 0)
            IconButton(
              tooltip: '清空历史',
              icon: const Icon(Symbols.delete_sweep_rounded),
              onPressed: () => _confirmClear(context, ref),
            ),
        ],
      ),
      body: sections.isEmpty
          ? _buildEmpty(theme)
          : CustomScrollView(
              slivers: [
                for (int i = 0; i < sections.length; i++)
                  ..._buildSectionSlivers(
                    context: context,
                    ref: ref,
                    section: sections[i],
                    isFirst: i == 0,
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
    );
  }

  // ─── 空状态 ─────────────────────────────────────────────

  Widget _buildEmpty(ThemeData theme) {
    final cs = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Symbols.history_rounded,
            size: 64,
            color: cs.onSurfaceVariant.withAlpha(80),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无阅读记录',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '打开任意文献后，这里会按日期显示浏览顺序',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant.withAlpha(160),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 单个日期桶：header sliver + list sliver ────────────

  List<Widget> _buildSectionSlivers({
    required BuildContext context,
    required WidgetRef ref,
    required HistorySection section,
    required bool isFirst,
  }) {
    return [
      SliverToBoxAdapter(
        child: _SectionHeader(
          label: section.label,
          count: section.docs.length,
          topPadding: isFirst ? 8 : 24,
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverList.separated(
          itemCount: section.docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final doc = section.docs[index];
            final theme = Theme.of(context);
            final cs = theme.colorScheme;
            return SpringDismissible(
              key: ValueKey(doc.id),
              onDismissed: () {
                ref.read(historyProvider.notifier).removeDoc(doc.id);
                ref
                    .read(snackBarServiceProvider)
                    .showResult(message: '已从历史移除');
              },
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
                    Icon(Symbols.delete_rounded,
                        size: 22, color: cs.onErrorContainer),
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
              child: DocListCard(
                doc: doc,
                compact: true,
                isSelectionMode: false,
                isSelected: false,
                onTap: () => DocCardActions.openReader(context, ref, doc),
              ),
            );
          },
        ),
      ),
    ];
  }

  // ─── 清空全部历史 ───────────────────────────────────────

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空阅读历史'),
        content: const Text('将清除所有阅读记录，文献本身不会被删除。此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: cs.error,
            ),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    ref.read(historyProvider.notifier).clear();
    ref.read(snackBarServiceProvider).showResult(message: '已清空阅读历史');
  }
}

/// 日期段标签：圆点 + 标签文字 + 细分隔线 + 计数
class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final double topPadding;

  const _SectionHeader({
    required this.label,
    required this.count,
    required this.topPadding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPadding, 20, 12),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: cs.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              color: cs.outlineVariant.withAlpha(120),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$count',
            style: theme.textTheme.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
