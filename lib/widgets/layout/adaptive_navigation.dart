import 'package:flutter/material.dart';

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
  const AdaptiveNavigationRail({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    this.extended = false,
    this.leading,
    this.bottomDestinationCount = 1,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<AdaptiveDestination> destinations;
  final bool extended;
  final Widget? leading;

  /// 固定在底部的导航项数量（从末尾算起）
  final int bottomDestinationCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final splitIndex = destinations.length - bottomDestinationCount;
    final topDestinations = destinations.sublist(0, splitIndex);
    final bottomDestinations = destinations.sublist(splitIndex);

    return SafeArea(
      child: SizedBox(
        width: extended ? 180 : 72,
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
                onTap: () => onDestinationSelected(index),
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
                onTap: () => onDestinationSelected(index),
              );
            }),
            const SizedBox(height: 16),
          ],
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
    final backgroundColor =
        selected ? colorScheme.secondaryContainer : Colors.transparent;
    final iconColor = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
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
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.normal,
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
        ),
      ),
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
      onDestinationSelected: onDestinationSelected,
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
