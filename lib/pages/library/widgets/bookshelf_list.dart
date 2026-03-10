import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/documents_provider.dart';
import '../../reader/view.dart';
import 'doc_list_card.dart';

/// 文献库列表视图
class BookshelfList extends ConsumerWidget {
  const BookshelfList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docs = ref.watch(validDocsProvider);

    if (docs.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Center(child: Text('暂无文献')),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      sliver: SliverList.separated(
        itemCount: docs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final doc = docs[index];
          return DocListCard(
            doc: doc,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReaderPage(document: doc),
                ),
              );
            },
            onDelete: () {
              ref.read(documentsProvider.notifier).delete(doc.id);
            },
          );
        },
      ),
    );
  }
}
