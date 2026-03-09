import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/documents_provider.dart';
import 'document_card.dart';

class BookshelfGrid extends ConsumerWidget {
  const BookshelfGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(validDocsProvider);

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
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16.0,
          crossAxisSpacing: 16.0,
          childAspectRatio: 0.52,
        ),
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
              isBookmarked: false,
              onTap: () {},
              onBookmarkToggle: () {},
              onMoreTap: () {},
              onDelete: () {
                ref.read(documentsProvider.notifier).delete(doc.id);
              },
            );
          },
          childCount: docs.length,
        ),
      ),
    );
  }
}
