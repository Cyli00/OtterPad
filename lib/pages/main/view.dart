import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/layout/adaptive_scaffold.dart';
import '../../widgets/layout/adaptive_navigation.dart';
import 'package:material_symbols_icons/symbols.dart';

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
          icon: Icon(Symbols.auto_awesome_mosaic),
          selectedIcon: Icon(Symbols.auto_awesome_mosaic),
          label: '首页',
        ),
        AdaptiveDestination(
          icon: Icon(Symbols.folder_copy),
          selectedIcon: Icon(Symbols.folder_copy),
          label: '库',
        ),
        AdaptiveDestination(
          icon: Icon(Symbols.construction),
          selectedIcon: Icon(Symbols.construction),
          label: '设置',
        ),
      ],
      body: navigationShell,
    );
  }
}
