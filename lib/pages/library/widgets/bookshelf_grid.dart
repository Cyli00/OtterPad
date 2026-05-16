import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/documents_provider.dart';
import '../../../providers/history_provider.dart';
import '../../../providers/selection_provider.dart';
import '../../../utils/doc_paths.dart';
import 'doc_card_actions.dart';
import 'document_card.dart';

class BookshelfGrid extends ConsumerWidget {
  const BookshelfGrid({super.key});

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
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Center(child: Text('暂无文献，请添加 PDF 文件到文库')),
        ),
      );
    }

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = _columnsFor(constraints.crossAxisExtent);
        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          sliver: SliverGrid(
            // childAspectRatio 0.50：A4 缩略图 (W/H 0.707) 占满卡宽时高度
            // ≈ 1.414×宽，整卡需为缩略图 + 文字层（标题 2 行 + 期刊 + 底行
            // ≈ 78px inner）留出空间。0.55 在移动端 156px 时只给 48px 内高，
            // 文字 column 会触发 14px 的 RenderFlex overflow。
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 16.0,
              crossAxisSpacing: 16.0,
              childAspectRatio: 0.50,
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
