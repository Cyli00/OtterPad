import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/l10n.dart';
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
    final l10n = context.l10n;
    return AdaptiveScaffold(
      selectedIndex: navigationShell.currentIndex,
      onDestinationSelected: _onDestinationSelected,
      destinations: [
        AdaptiveDestination(
          icon: const Icon(Symbols.auto_awesome_mosaic, weight: 600, fill: 1),
          selectedIcon: const Icon(Symbols.auto_awesome_mosaic, weight: 600, fill: 1),
          label: l10n.home,
        ),
        AdaptiveDestination(
          icon: const Icon(Symbols.folder_copy, weight: 600, fill: 1),
          selectedIcon: const Icon(Symbols.folder_copy, weight: 600, fill: 1),
          label: l10n.library,
        ),
        AdaptiveDestination(
          icon: const Icon(Symbols.construction, weight: 600, fill: 1),
          selectedIcon: const Icon(Symbols.construction, weight: 600, fill: 1),
          label: l10n.settings,
        ),
      ],
      body: navigationShell,
    );
  }
}
