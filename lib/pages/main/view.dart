import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/l10n.dart';
import '../../providers/nav_rail_provider.dart';
import '../../services/haptics.dart';
import '../../utils/responsive.dart';
import '../../widgets/layout/adaptive_scaffold.dart';
import '../../widgets/layout/app_destinations.dart';

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

    final destinations = appDestinations(l10n);

    return AdaptiveScaffold(
      destinations: showRail ? destinations : destinations.take(2).toList(),
      selectedIndex: showRail
          ? navigationShell.currentIndex
          : navigationShell.currentIndex.clamp(0, 1).toInt(),
      hideBottomNavigation: !showRail && onSettingsBranch,
      // 设置上移为文献库同级；底部槽位改为标签展示模式切换
      railBottomDestinationCount: 0,
      extendedRail: railExtended,
      railBottomAction: railLabelToggle(l10n, extended: railExtended),
      onRailBottomAction: () =>
          ref.read(navRailExtendedProvider.notifier).setExtended(!railExtended),
      onDestinationSelected: _onDestinationSelected,
      body: navigationShell,
    );
  }
}
