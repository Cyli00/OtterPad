import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/documents_provider.dart';
import '../../../providers/selection_provider.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/staggered_entrance.dart';
import 'doc_card_actions.dart';
import 'doc_list_card.dart';
import 'library_empty_state.dart';

/// 文献库列表视图
///
/// 窄屏（<900dp）：单栏 [SliverList]，卡片自然高度。
/// 中屏（≥900dp）：双栏 [SliverGrid]。
/// 宽屏（≥1800dp）：三栏 [SliverGrid]，内容区居中且不超过 [_kMaxContentWidth]。
class BookshelfList extends ConsumerWidget {
  final VoidCallback? onStartSetup;

  const BookshelfList({super.key, this.onStartSetup});

  // ┌─ 桌面端布局参数（可调） ──────────────────────────────────┐
  static const _kTwoColumnBreakpoint = 900; // ← 双栏触发宽度
  static const _kThreeColumnBreakpoint = 1800; // ← 三栏触发宽度
  static const _kMaxContentWidth = 2700; // ← 内容区最大宽度
  static const _kCardHeight = 174.0; // ← padding(16×2) + thumbHeightFull(142)
  // └──────────────────────────────────────────────────────────┘

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(validDocsProvider);
    final isSelectionMode = ref.watch(
      selectionProvider.select(
        (s) => s.isActive && s.sourceContext == 'library',
      ),
    );

    if (docs.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: LibraryEmptyState(onStartSetup: onStartSetup),
      );
    }

    final orderedIds = [for (final d in docs) d.id];

    Widget buildCard(BuildContext context, int index) {
      final doc = docs[index];
      // 进度由 DocListCard 内部按 docId 细粒度订阅，无需在此下发
      return StaggeredEntrance(
        index: index,
        child: Consumer(
          builder: (context, ref, _) => DocListCard(
            doc: doc,
            isSelectionMode: isSelectionMode,
            isSelected: ref.watch(
              selectionProvider.select((s) => s.selectedIds.contains(doc.id)),
            ),
            onTap: () => DocCardActions.openReader(context, ref, doc),
            onLongPress: () =>
                ref.read(selectionProvider.notifier).enter(doc.id, 'library'),
            onSelectionTap: () =>
                ref.read(selectionProvider.notifier).toggle(doc.id),
            onModifierToggle: () =>
                DocCardActions.modifierToggle(ref, doc.id, 'library'),
            onSelectRange: () => DocCardActions.selectRange(
              ref,
              docId: doc.id,
              sourceContext: 'library',
              orderedIds: orderedIds,
            ),
            onFavorite: () =>
                DocCardActions.addToFavorite(context, ref, {doc.id}),
            onContextMenu: (pos) => DocCardActions.showMenu(
              context: context,
              ref: ref,
              globalPosition: pos,
              doc: doc,
              sourceContext: 'library',
              orderedIds: orderedIds,
            ),
          ),
        ),
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
          // 桌面宽屏紧凑密度：行距 -4px（Responsive.compactDensity）
          final rowSpacing = Responsive.compactDensity(context) ? 8.0 : 12.0;

          return SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: 8.0),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columnCount,
                mainAxisExtent: _kCardHeight,
                crossAxisSpacing: 16,
                mainAxisSpacing: rowSpacing,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => buildCard(context, index),
                childCount: docs.length,
              ),
            ),
          );
        }

        // 窄屏：单栏列表
        final rowSpacing = Responsive.compactDensity(context) ? 8.0 : 12.0;
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          sliver: SliverList.separated(
            itemCount: docs.length,
            separatorBuilder: (_, _) => SizedBox(height: rowSpacing),
            itemBuilder: (context, index) => buildCard(context, index),
          ),
        );
      },
    );
  }
}
