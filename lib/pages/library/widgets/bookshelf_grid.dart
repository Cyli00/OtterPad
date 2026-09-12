import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/documents_provider.dart';
import '../../../providers/history_provider.dart';
import '../../../providers/selection_provider.dart';
import '../../../utils/doc_paths.dart';
import '../../../utils/responsive.dart';
import '../../../widgets/staggered_entrance.dart';
import 'doc_card_actions.dart';
import 'document_card.dart';
import 'library_empty_state.dart';

class BookshelfGrid extends ConsumerWidget {
  final VoidCallback? onStartSetup;

  const BookshelfGrid({super.key, this.onStartSetup});

  /// 文字块固定高度：标题 2 行 + 期刊 1 行 + 年份行 + 上下 8px padding +
  /// 行间 4px 间距，约 92px，留少量余量防字体渲染舍入触发 overflow。
  static const double _kTextBlockHeight = 96.0;

  /// 屏幕宽度 → 列数。移动端窄屏 2 列，宽屏桌面 3–4 列。
  ///
  /// 之前用 `SliverGridDelegateWithMaxCrossAxisExtent(300)` 在大桌面屏上
  /// 会蹦到 5+ 列，卡片缩成名片大小；改成显式断点更稳。
  static int _columnsFor(double width) {
    if (width < 600) return 2;
    if (width < 900) return 3;
    return 4;
  }

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

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = _columnsFor(constraints.crossAxisExtent);
        // tile 高度 = 封面高 + 固定文字块高，让卡片底部紧贴年份行而非留空。
        // 封面锁 A4 比例 (W/H 0.707)，高度随列宽成比例放大；文字块（标题 2 行
        // + 期刊 + 年份行 + 上下 8px padding）是固定像素，所以用 mainAxisExtent
        // 而非 childAspectRatio——后者会让宽列产生越来越大的底部空隙。
        final spacing = Responsive.showNavigationRail(context) ? 12.0 : 16.0;
        // 桌面宽屏紧凑密度：行距 -4px（token 见 Responsive.compactDensity）
        final rowSpacing = Responsive.compactDensity(context)
            ? spacing - 4
            : spacing;
        final cardWidth =
            (constraints.crossAxisExtent -
                32.0 -
                spacing * (crossAxisCount - 1)) /
            crossAxisCount;
        final coverHeight = cardWidth / 0.707;
        final orderedIds = [for (final d in docs) d.id];
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: rowSpacing,
              crossAxisSpacing: spacing,
              mainAxisExtent: coverHeight + _kTextBlockHeight,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final doc = docs[index];
              // 进度走单卡片粒度订阅（docProgressProvider）——阅读器每
              // 500ms 的 setProgress 只重建对应卡片，不再整 grid rebuild。
              return StaggeredEntrance(
                index: index,
                child: Consumer(
                  builder: (context, ref, _) => DocumentCard(
                    docId: doc.id,
                    coverAsset: doc.contentHash == null
                        ? ''
                        : DocPaths.pdf(doc.id),
                    name: doc.title,
                    authors: doc.authors.join(', '),
                    journalName: doc.journal ?? '',
                    year: doc.year ?? '',
                    progress: ref.watch(docProgressProvider(doc.id)),
                    isSelectionMode: isSelectionMode,
                    isSelected: ref.watch(
                      selectionProvider.select(
                        (s) => s.selectedIds.contains(doc.id),
                      ),
                    ),
                    onTap: () => DocCardActions.openReader(context, ref, doc),
                    onLongPress: () => ref
                        .read(selectionProvider.notifier)
                        .enter(doc.id, 'library'),
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
            }, childCount: docs.length),
          ),
        );
      },
    );
  }
}
