import 'package:flutter/material.dart';
import 'document_card.dart';

class BookshelfGrid extends StatelessWidget {
  const BookshelfGrid({super.key});

  // 真实的 assets/docs/ 下的 PDF 文件列表
  static const List<String> _pdfAssets = [
    'assets/docs/2024-Deng 等-Long-working-distance high-collection-efficiency t.pdf',
  ];

  @override
  Widget build(BuildContext context) {
    if (_pdfAssets.isEmpty) {
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
            final assetPath = _pdfAssets[index];
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
          childCount: _pdfAssets.length,
        ),
      ),
    );
  }
}
