import 'package:flutter/material.dart';
import '../../utils/desktop.dart';
import '../../utils/responsive.dart';
import 'adaptive_navigation.dart';

/// 自适应 Scaffold
///
/// 根据屏幕宽度自动切换布局：
/// - 手机: 底部导航
/// - 平板/桌面: 侧边导航栏
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.body,
    this.floatingActionButton,
    this.railLeading,
    this.extendedRail = false,
    this.railBottomDestinationCount = 1,
    this.hideBottomNavigation = false,
    this.railBottomAction,
    this.onRailBottomAction,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<AdaptiveDestination> destinations;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? railLeading;
  final bool extendedRail;
  final int railBottomDestinationCount;
  final bool hideBottomNavigation;

  /// 侧栏底部操作项（非导航目的地，如标签显示模式切换）
  final AdaptiveDestination? railBottomAction;
  final VoidCallback? onRailBottomAction;

  @override
  Widget build(BuildContext context) {
    final showRail = Responsive.showNavigationRail(context);

    // 桌面端侧栏半透明（叠在窗口背景上的轻微着色）；Row 分栏避让，
    // 禁止改回 Stack 叠层——侧栏会遮挡/拦截主内容左侧（设置分组列表等）。
    return Scaffold(
      body: Row(
        children: [
          if (showRail) ...[
            AdaptiveNavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              destinations: destinations,
              extended: extendedRail,
              leading: railLeading,
              bottomDestinationCount: railBottomDestinationCount,
              backgroundColor: isDesktopOs
                  ? Theme.of(
                      context,
                    ).colorScheme.surfaceContainer.withAlpha(180)
                  : null,
              bottomAction: railBottomAction,
              onBottomAction: onRailBottomAction,
            ),
            VerticalDivider(
              thickness: 1,
              width: 1,
              color: Theme.of(context).colorScheme.outlineVariant.withAlpha(80),
            ),
          ],
          Expanded(key: const ValueKey('adaptive-body'), child: body),
        ],
      ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: (showRail || hideBottomNavigation)
          ? null
          : AdaptiveBottomNavigation(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              destinations: destinations,
            ),
    );
  }
}
