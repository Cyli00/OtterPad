import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/l10n.dart';
import '../../services/haptics.dart';
import '../../utils/responsive.dart';
import '../../widgets/layout/adaptive_scaffold.dart';
import '../../widgets/layout/adaptive_navigation.dart';
import 'package:material_symbols_icons/symbols.dart';

/// 主导航外壳，由 StatefulShellRoute 驱动 Tab 切换
class MainShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainShell({super.key, required this.navigationShell});

  void _onDestinationSelected(int index) {
    Haptics.soft();
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final showRail = Responsive.showNavigationRail(context);
    final onSettingsBranch = navigationShell.currentIndex == 2;

    final dest2 = [
      AdaptiveDestination(
        icon: const Icon(
          Symbols.auto_awesome_mosaic_rounded,
          weight: 600,
          fill: 1,
        ),
        selectedIcon: const Icon(
          Symbols.auto_awesome_mosaic_rounded,
          weight: 600,
          fill: 1,
        ),
        label: l10n.home,
      ),
      AdaptiveDestination(
        icon: const Icon(Symbols.folder_copy_rounded, weight: 600, fill: 1),
        selectedIcon: const Icon(
          Symbols.folder_copy_rounded,
          weight: 600,
          fill: 1,
        ),
        label: l10n.library,
      ),
    ];
    final dest3 = [
      ...dest2,
      AdaptiveDestination(
        icon: const Icon(Symbols.settings_rounded, weight: 600, fill: 1),
        selectedIcon: const Icon(
          Symbols.settings_rounded,
          weight: 600,
          fill: 1,
        ),
        label: l10n.settings,
      ),
    ];

    return AdaptiveScaffold(
      destinations: showRail ? dest3 : dest2,
      selectedIndex: showRail
          ? navigationShell.currentIndex
          : navigationShell.currentIndex.clamp(0, 1).toInt(),
      hideBottomNavigation: !showRail && onSettingsBranch,
      railBottomDestinationCount: 1,
      extendedRail: Responsive.showExtendedRail(context),
      onDestinationSelected: _onDestinationSelected,
      body: navigationShell,
    );
  }
}
