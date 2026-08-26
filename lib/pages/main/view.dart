import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/l10n.dart';
import '../../providers/nav_rail_provider.dart';
import '../../services/haptics.dart';
import '../../utils/responsive.dart';
import '../../widgets/layout/adaptive_scaffold.dart';
import '../../widgets/layout/adaptive_navigation.dart';
import 'package:material_symbols_icons/symbols.dart';

/// 主导航外壳，由 StatefulShellRoute 驱动 Tab 切换
class MainShell extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final showRail = Responsive.showNavigationRail(context);
    final onSettingsBranch = navigationShell.currentIndex == 2;
    // 手动切换优先；未设过则跟随宽度自动（≥1200 展开文字）
    final railExtended =
        ref.watch(navRailExtendedProvider) ??
        Responsive.showExtendedRail(context);

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
      // 设置上移为文献库同级；底部槽位改为标签展示模式切换
      railBottomDestinationCount: 0,
      extendedRail: railExtended,
      railBottomAction: AdaptiveDestination(
        icon: Icon(
          railExtended
              ? Symbols.left_panel_close_rounded
              : Symbols.left_panel_open_rounded,
          weight: 600,
          fill: 1,
        ),
        selectedIcon: Icon(
          railExtended
              ? Symbols.left_panel_close_rounded
              : Symbols.left_panel_open_rounded,
          weight: 600,
          fill: 1,
        ),
        label: railExtended ? l10n.navHideLabels : l10n.navShowLabels,
      ),
      onRailBottomAction: () =>
          ref.read(navRailExtendedProvider.notifier).setExtended(!railExtended),
      onDestinationSelected: _onDestinationSelected,
      body: navigationShell,
    );
  }
}
