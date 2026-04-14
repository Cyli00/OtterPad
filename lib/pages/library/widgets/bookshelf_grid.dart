import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/documents_provider.dart';
import '../../../providers/selection_provider.dart';
import 'doc_card_actions.dart';
import 'document_card.dart';

class BookshelfGrid extends ConsumerWidget {
  const BookshelfGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(validDocsProvider);
    final selection = ref.watch(selectionProvider);
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

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      sliver: SliverGrid(
        // ┌─ 网格卡片最大宽度（可调） ──────────────────────────────┐
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 300, // ← 调大 = 更宽卡片、更少列数
          mainAxisSpacing: 16.0,
          crossAxisSpacing: 16.0,
          childAspectRatio: 0.618  // ← 宽高比，调小 = 更高的卡片
        ),
        // └──────────────────────────────────────────────────────────┘
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final doc = docs[index];

            return DocumentCard(
              docId: doc.id,
              coverAsset: doc.filePath,
              name: doc.title,
              authors: doc.authors.join(', '),
              journalName: doc.journal ?? '',
              year: doc.year ?? '',
              isSelectionMode: isSelectionMode,
              isSelected: selection.selectedIds.contains(doc.id),
              onTap: () => DocCardActions.openReader(context, ref, doc),
              onLongPress: () => ref
                  .read(selectionProvider.notifier)
                  .enter(doc.id, 'library'),
              onSelectionTap: () =>
                  ref.read(selectionProvider.notifier).toggle(doc.id),
            );
          },
          childCount: docs.length,
        ),
      ),
    );
  }
}
