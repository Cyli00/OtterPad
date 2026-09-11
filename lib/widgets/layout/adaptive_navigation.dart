import 'package:flutter/material.dart';

import '../../core/animation_constants.dart';
import '../../services/haptics.dart';
import '../tactile_press.dart';

/// 导航目标项配置
class AdaptiveDestination {
  const AdaptiveDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final Widget icon;
  final Widget selectedIcon;
  final String label;
}

/// 侧边导航栏组件 (平板/桌面)
class AdaptiveNavigationRail extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<AdaptiveDestination> destinations;
  final bool extended;
  final Widget? leading;

  /// 固定在底部的导航项数量（从末尾算起）
  final int bottomDestinationCount;

  /// 覆盖默认背景色（桌面端半透明侧栏时传半透明色）
  final Color? backgroundColor;

  /// 底部操作项（非导航目的地，无选中态，如标签显示模式切换）
  final AdaptiveDestination? bottomAction;
  final VoidCallback? onBottomAction;

  const AdaptiveNavigationRail({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.extended = false,
    this.leading,
    this.bottomDestinationCount = 1,
    this.backgroundColor,
    this.bottomAction,
    this.onBottomAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final splitIndex = destinations.length - bottomDestinationCount;
    final topDestinations = destinations.sublist(0, splitIndex);
    final bottomDestinations = destinations.sublist(splitIndex);

    return ColoredBox(
      color: backgroundColor ?? colorScheme.surfaceContainer,
      child: SafeArea(
        child: AnimatedContainer(
          duration: kAnim,
          curve: kAnimCurve,
          width: extended ? 180 : 72,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: extended ? 180 : null,
              maxWidth: extended ? 180 : null,
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        children: [
                          if (leading != null) ...[
                            leading!,
                            const SizedBox(height: 8),
                          ],
                          const SizedBox(height: 16),
                          ...topDestinations.asMap().entries.map((entry) {
                            final index = entry.key;
                            final dest = entry.value;
                            final selected = index == selectedIndex;

                            return _NavigationRailItem(
                              icon: selected ? dest.selectedIcon : dest.icon,
                              label: dest.label,
                              selected: selected,
                              extended: extended,
                              colorScheme: colorScheme,
                              onTap: () {
                                Haptics.soft();
                                onDestinationSelected(index);
                              },
                            );
                          }),
                          const Spacer(),
                          ...bottomDestinations.asMap().entries.map((entry) {
                            final index = entry.key + splitIndex;
                            final dest = entry.value;
                            final selected = index == selectedIndex;

                            return _NavigationRailItem(
                              icon: selected ? dest.selectedIcon : dest.icon,
                              label: dest.label,
                              selected: selected,
                              extended: extended,
                              colorScheme: colorScheme,
                              onTap: () {
                                Haptics.soft();
                                onDestinationSelected(index);
                              },
                            );
                          }),
                          if (bottomAction != null)
                            _NavigationRailItem(
                              icon: bottomAction!.icon,
                              label: bottomAction!.label,
                              selected: false,
                              extended: extended,
                              colorScheme: colorScheme,
                              onTap: () {
                                Haptics.soft();
                                onBottomAction?.call();
                              },
                            ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationRailItem extends StatelessWidget {
  const _NavigationRailItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.extended,
    required this.colorScheme,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final bool selected;
  final bool extended;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = selected
        ? colorScheme.secondaryContainer
        : Colors.transparent;
    final iconColor = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;

    Widget item = TactilePress(
      baseColor: backgroundColor,
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      haptics: false,
      child: SizedBox(
        height: 56,
        child: extended
            ? Row(
                children: [
                  const SizedBox(width: 16),
                  IconTheme(
                    data: IconThemeData(color: iconColor, size: 24),
                    child: icon,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: iconColor,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              )
            : Center(
                child: IconTheme(
                  data: IconThemeData(color: iconColor, size: 24),
                  child: icon,
                ),
              ),
      ),
    );
    if (!extended) {
      item = Tooltip(message: label, child: item);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: item,
    );
  }
}

/// 底部导航栏组件 (手机)
class AdaptiveBottomNavigation extends StatelessWidget {
  const AdaptiveBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<AdaptiveDestination> destinations;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: (index) {
        Haptics.soft();
        onDestinationSelected(index);
      },
      destinations: destinations.map((d) {
        return NavigationDestination(
          icon: d.icon,
          selectedIcon: d.selectedIcon,
          label: d.label,
        );
      }).toList(),
    );
  }
}
