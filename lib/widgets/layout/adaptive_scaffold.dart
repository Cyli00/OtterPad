import 'package:flutter/material.dart';
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
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<AdaptiveDestination> destinations;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? railLeading;
  final bool extendedRail;

  @override
  Widget build(BuildContext context) {
    final showRail = Responsive.showNavigationRail(context);

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
            ),
            const VerticalDivider(thickness: 1, width: 1),
          ],
          Expanded(
            key: const ValueKey('adaptive-body'),
            child: body,
          ),
        ],
      ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: showRail
          ? null
          : AdaptiveBottomNavigation(
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              destinations: destinations,
            ),
    );
  }
}
