import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/local_docs_provider.dart';
import 'widgets/library_menu_item.dart';
import 'widgets/favorite_card.dart';

class ShelfPage extends ConsumerWidget {
  const ShelfPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final docsAsync = ref.watch(localDocsProvider);
    final docsCount = docsAsync.value?.length ?? 0;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                // 页面大标题
                Text(
                  '我的库',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 32),
                
                // 菜单列表项
                LibraryMenuItem(
                  icon: Icons.cloud_upload_outlined,
                  title: '已同步',
                  onTap: () {},
                ),
                LibraryMenuItem(
                  icon: Icons.history, // 历史图标
                  title: '阅读历史',
                  onTap: () {},
                ),
                LibraryMenuItem(
                  icon: Icons.star_border, // 星标
                  title: '星标项目',
                  onTap: () {},
                ),
                
                // 思维导图先不要考虑
                // LibraryMenuItem(
                //   icon: Icons.account_tree_outlined,
                //   title: '思维导图',
                //   onTap: () {},
                // ),

                const SizedBox(height: 16),
                
                // 分割线
                Divider(
                  height: 32,
                  thickness: 1,
                  color: theme.colorScheme.outlineVariant.withAlpha(128),
                ),
                const SizedBox(height: 8),
                
                // 收藏夹标题与操作栏
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      '收藏夹',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '1',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary, // 绿色的数字
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add),
                      color: theme.colorScheme.onSurfaceVariant,
                      onPressed: () {},
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // 水平滚动的卡片列表
                SizedBox(
                  height: 380, // 增加高度以容纳多本书的预览
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none, // 防止卡片的阴影被裁剪
                    children: [
                      FavoriteCard(
                        title: '默认文库',
                        subtitle: '包含所有文献',
                        subtitleIcon: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.colorScheme.primaryContainer,
                          ),
                          child: Icon(
                            Icons.menu_book_rounded,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        pdfAssets: docsAsync.value ?? [],
                        totalCount: docsCount,
                        onTap: () {},
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32), // 底部留白
              ],
            ),
          ),
        ),
      ),
    );
  }
}
