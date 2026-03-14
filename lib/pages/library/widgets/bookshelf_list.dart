import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/documents_provider.dart';
import 'doc_card_actions.dart';
import 'doc_list_card.dart';

/// 文献库列表视图
///
/// 窄屏（<900dp）：单栏 [SliverList]，卡片自然高度。
/// 宽屏（≥900dp）：双栏 [SliverGrid]，内容区居中且不超过 [_kMaxContentWidth]。
class BookshelfList extends ConsumerWidget {
  const BookshelfList({super.key});

  // ┌─ 桌面端布局参数（可调） ──────────────────────────────┐
  static const _kTwoColumnBreakpoint = 900.0; // ← 双栏触发宽度
  static const _kMaxContentWidth = 1200.0; // ← 内容区最大宽度
  static const _kCardHeight = 160.0; // ← 双栏模式卡片高度
  // └──────────────────────────────────────────────────────────┘

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

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final useTwoColumns = width >= _kTwoColumnBreakpoint;

        if (useTwoColumns) {
          final contentWidth = width.clamp(0.0, _kMaxContentWidth);
          final hPadding = (width - contentWidth) / 2 + 16;

          return SliverPadding(
            padding:
                EdgeInsets.symmetric(horizontal: hPadding, vertical: 8.0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisExtent: _kCardHeight,
                crossAxisSpacing: 16,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final doc = docs[index];
                  return DocListCard(
                    doc: doc,
                    onTap: () => DocCardActions.openReader(context, doc),
                    onDelete: () => DocCardActions.delete(ref, doc.id),
                  );
                },
                childCount: docs.length,
              ),
            ),
          );
        }

        // 窄屏：单栏列表
        return SliverPadding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          sliver: SliverList.separated(
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = docs[index];
              return DocListCard(
                doc: doc,
                onTap: () => DocCardActions.openReader(context, doc),
                onDelete: () => DocCardActions.delete(ref, doc.id),
              );
            },
          ),
        );
      },
    );
  }
}
