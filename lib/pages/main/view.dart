import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/layout/adaptive_scaffold.dart';
import '../../widgets/layout/adaptive_navigation.dart';

/// 主导航外壳，由 StatefulShellRoute 驱动 Tab 切换
class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  void _onDestinationSelected(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: _onDestinationSelected,
      destinations: const [
        AdaptiveDestination(
          icon: Icon(Icons.auto_awesome_mosaic),
          selectedIcon: Icon(Icons.auto_awesome_mosaic),
          label: '首页',
        ),
        AdaptiveDestination(
          icon: Icon(Icons.folder_copy),
          selectedIcon: Icon(Icons.folder_copy),
          label: '库',
        ),
        AdaptiveDestination(
          icon: Icon(Icons.construction),
          selectedIcon: Icon(Icons.construction),
          label: '设置',
        ),
      ],
      body: navigationShell,
    );
  }
}
