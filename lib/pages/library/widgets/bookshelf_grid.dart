import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/local_docs_provider.dart';
import 'document_card.dart';

class BookshelfGrid extends ConsumerWidget {
  const BookshelfGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(localDocsProvider);

    return docsAsync.when(
      data: (pdfAssets) {
        if (pdfAssets.isEmpty) {
          return const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Center(child: Text('暂无文献，请添加 PDF 文件到 assets/docs/')),
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
              childAspectRatio: 0.58,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final assetPath = pdfAssets[index];
                // 从文件名中提取简短标题
                final fileName = assetPath.split('/').last;
                final title = fileName.replaceAll('.pdf', '');

                return DocumentCard(
                  title: title,
                  author: '',
                  coverAsset: assetPath,
                  isBookmarked: false,
                  onTap: () {},
                  onBookmarkToggle: () {},
                  onMoreTap: () {},
                );
              },
              childCount: pdfAssets.length,
            ),
          ),
        );
      },
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, stack) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Center(child: Text('加载文献失败: $error')),
        ),
      ),
    );
  }
}
