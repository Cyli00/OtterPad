import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/documents_provider.dart';
import '../../../providers/history_provider.dart';
import '../../../providers/selection_provider.dart';
import 'doc_card_actions.dart';
import 'doc_list_card.dart';

/// 文献库列表视图
///
/// 窄屏（<900dp）：单栏 [SliverList]，卡片自然高度。
/// 中屏（≥900dp）：双栏 [SliverGrid]。
/// 宽屏（≥1800dp）：三栏 [SliverGrid]，内容区居中且不超过 [_kMaxContentWidth]。
class BookshelfList extends ConsumerWidget {
  const BookshelfList({super.key});

  // ┌─ 桌面端布局参数（可调） ──────────────────────────────────┐
  static const _kTwoColumnBreakpoint = 900; // ← 双栏触发宽度
  static const _kThreeColumnBreakpoint = 1800; // ← 三栏触发宽度
  static const _kMaxContentWidth = 2700; // ← 内容区最大宽度
  static const _kCardHeight = 208.0; // ← 预留选中态边框后的多栏模式卡片高度
  // └──────────────────────────────────────────────────────────┘

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(validDocsProvider);
    final selection = ref.watch(selectionProvider);
    // 顶层一次 watch，派生进度 Map 下推给每张卡——避免 500 张卡各自订阅。
    final history = ref.watch(historyProvider);
    final progressByDoc = {for (final e in history) e.docId: e.progress};
    final isSelectionMode =
        selection.isActive && selection.sourceContext == 'library';

    if (docs.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Center(child: Text('暂无文献')),
        ),
      );
    }

    Widget buildCard(int index) {
      final doc = docs[index];
      return DocListCard(
        doc: doc,
        progress: progressByDoc[doc.id] ?? 0.0,
        isSelectionMode: isSelectionMode,
        isSelected: selection.selectedIds.contains(doc.id),
        onTap: () => DocCardActions.openReader(context, ref, doc),
        onLongPress: () =>
            ref.read(selectionProvider.notifier).enter(doc.id, 'library'),
        onSelectionTap: () =>
            ref.read(selectionProvider.notifier).toggle(doc.id),
      );
    }

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final columnCount = width >= _kThreeColumnBreakpoint
            ? 3
            : width >= _kTwoColumnBreakpoint
            ? 2
            : 1;

        if (columnCount >= 2) {
          final contentWidth = width.clamp(0.0, _kMaxContentWidth);
          final hPadding = (width - contentWidth) / 2 + 16;

          return SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: 8.0),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columnCount,
                mainAxisExtent: _kCardHeight,
                crossAxisSpacing: 16,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => buildCard(index),
                childCount: docs.length,
              ),
            ),
          );
        }

        // 窄屏：单栏列表
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          sliver: SliverList.separated(
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) => buildCard(index),
          ),
        );
      },
    );
  }
}
