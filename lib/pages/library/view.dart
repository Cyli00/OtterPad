import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/documents_provider.dart';
import 'widgets/home_header.dart';
import 'widgets/home_tab_bar.dart';
import 'widgets/bookshelf_grid.dart';
import 'widgets/bookshelf_list.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGrid = ref.watch(viewModeProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
            return <Widget>[
              // 顶部的搜索栏与操作按钮
              const HomeHeader(),
              // 吸顶的 TabBar
              SliverPersistentHeader(
                pinned: true,
                delegate: HomeTabBarDelegate(
                  backgroundColor: theme.colorScheme.surface,
                  tabBar: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.center,
                    indicatorSize: TabBarIndicatorSize.label,
                    indicatorWeight: 3.0,
                    indicatorColor: theme.colorScheme.primary,
                    labelColor: theme.colorScheme.primary,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                    unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                    dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(text: '文献库'),
                      Tab(text: '推荐'),
                      Tab(text: '会议日程'),
                    ],
                  ),
                ),
              ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              // Tab1: 书架视图（根据 viewMode 切换 Grid/List）
              CustomScrollView(
                slivers: [
                  if (isGrid) const BookshelfGrid() else const BookshelfList(),
                ],
              ),
              // Tab2: 推荐视图暂未实现
              const Center(child: Text('推荐内容')),
              // Tab3: 会议日程暂未实现
              const Center(child: Text('会议日程')),
            ],
          ),
        ),
      ),
    );
  }
}
