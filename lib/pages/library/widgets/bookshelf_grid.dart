import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n.dart';
import '../../../providers/documents_provider.dart';
import '../../../providers/history_provider.dart';
import '../../../providers/selection_provider.dart';
import '../../../utils/doc_paths.dart';
import 'doc_card_actions.dart';
import 'document_card.dart';

class BookshelfGrid extends ConsumerWidget {
  const BookshelfGrid({super.key});

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
    final selection = ref.watch(selectionProvider);
    // 监听 historyProvider 让每张卡片在进度更新后实时 rebuild——若 grid 顶层
    // 不 watch，HistoryNotifier setProgress() 触发的 state 变更不会下沉到 card.
    final history = ref.watch(historyProvider);
    final progressByDoc = {
      for (final e in history) e.docId: e.progress,
    };
    final isSelectionMode =
        selection.isActive && selection.sourceContext == 'library';

    if (docs.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(child: Text(context.l10n.noDocumentsInLibrary)),
        ),
      );
    }

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = _columnsFor(constraints.crossAxisExtent);
        // tile 高度 = 封面高 + 固定文字块高，让卡片底部紧贴年份行而非留空。
        // 封面锁 A4 比例 (W/H 0.707)，高度随列宽成比例放大；文字块（标题 2 行
        // + 期刊 + 年份行 + 上下 8px padding）是固定像素，所以用 mainAxisExtent
        // 而非 childAspectRatio——后者会让宽列产生越来越大的底部空隙。
        final cardWidth =
            (constraints.crossAxisExtent - 32.0 - 16.0 * (crossAxisCount - 1)) /
                crossAxisCount;
        final coverHeight = cardWidth / 0.707;
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 16.0,
              crossAxisSpacing: 16.0,
              mainAxisExtent: coverHeight + _kTextBlockHeight,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final doc = docs[index];
              return DocumentCard(
                docId: doc.id,
                coverAsset:
                    doc.contentHash == null ? '' : DocPaths.pdf(doc.id),
                name: doc.title,
                authors: doc.authors.join(', '),
                journalName: doc.journal ?? '',
                year: doc.year ?? '',
                progress: progressByDoc[doc.id] ?? 0.0,
                isSelectionMode: isSelectionMode,
                isSelected: selection.selectedIds.contains(doc.id),
                onTap: () => DocCardActions.openReader(context, ref, doc),
                onLongPress: () => ref
                    .read(selectionProvider.notifier)
                    .enter(doc.id, 'library'),
                onSelectionTap: () =>
                    ref.read(selectionProvider.notifier).toggle(doc.id),
              );
            }, childCount: docs.length),
          ),
        );
      },
    );
  }
}
