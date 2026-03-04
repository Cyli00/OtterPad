import 'package:flutter/material.dart';

import 'widgets/home_header.dart';
import 'widgets/home_tab_bar.dart';
import 'widgets/bookshelf_grid.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage>
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

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
            return <Widget>[
              // 1. 顶部的搜索栏与头像
              const HomeHeader(),
              // 2. 吸顶的 TabBar
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
                    dividerColor: Colors.transparent, // 隐藏底部默认的细线
                    tabs: const [
                      Tab(text: '书架'),
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
              // Tab1: 书架视图（Slivers 需要包装在 CustomScrollView 中）
              const CustomScrollView(
                slivers: [BookshelfGrid()],
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
