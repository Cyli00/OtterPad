import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

import '../../core/animation_constants.dart';
import '../../services/haptics.dart';
import '../tactile_press.dart';
import '../../core/design_tokens.dart';
import '../../core/folio_look.dart';
import '../glass/liquid_glass.dart';

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

/// 导航图标的选中态：Material Symbols 的 FILL 轴在 0（描边）与 1（实心）
/// 之间过渡。图标自身不能写死 `fill`，否则盖过这里的设置。
class _SelectedIconFill extends StatelessWidget {
  const _SelectedIconFill({required this.selected, required this.child});

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleMotionBuilder(
      motion: kMotionEffects,
      value: selected ? 1 : 0,
      active: !MediaQuery.disableAnimationsOf(context),
      builder: (context, fill, child) => IconTheme.merge(
        data: IconThemeData(fill: fill.clamp(0.0, 1.0)),
        child: child!,
      ),
      child: child,
    );
  }
}

/// 侧栏选中态：图标背后一枚强调色胶囊从中心横向弹开，图标由描边过渡为
/// 实心、由中性灰过渡为强调色上的前景色。
class _RailIndicator extends StatelessWidget {
  const _RailIndicator({
    required this.selected,
    required this.height,
    required this.colorScheme,
    required this.icon,
  });

  final bool selected;
  final double height;
  final ColorScheme colorScheme;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return SingleMotionBuilder(
      motion: kMotionEffects,
      value: selected ? 1 : 0,
      active: !MediaQuery.disableAnimationsOf(context),
      builder: (context, t, child) {
        final k = t.clamp(0.0, 1.0);
        return SizedBox(
          width: 56,
          height: height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 胶囊指示器：从中心横向弹开
              Transform.scale(
                scaleX: t.clamp(0.0, 1.15),
                child: Container(
                  width: 52,
                  height: height >= 48 ? 40 : 32,
                  decoration: ShapeDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: k),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
              IconTheme(
                data: IconThemeData(
                  color: Color.lerp(
                    colorScheme.onSurfaceVariant.withAlpha(190),
                    colorScheme.onPrimaryContainer,
                    k,
                  ),
                  size: 22,
                ),
                child: child!,
              ),
            ],
          ),
        );
      },
      child: _SelectedIconFill(selected: selected, child: icon),
    );
  }
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
      color: backgroundColor ?? colorScheme.surface,
      child: SafeArea(
        child: SizedBox(
          width: 72,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
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
                          extended: false,
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
    );
  }
}

class _NavigationRailItem extends StatelessWidget {
  // 显示文字时每项的上下留白；相邻两项的间距为此值的两倍。
  static const double _labeledItemVerticalPadding = 6;

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
    Widget buildIconOnly() {
      return _RailIndicator(
        selected: selected,
        height: 56,
        colorScheme: colorScheme,
        icon: icon,
      );
    }

    Widget buildWithLabel() {
      return SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            _RailIndicator(
              selected: selected,
              height: 36,
              colorScheme: colorScheme,
              icon: icon,
            ),
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: AnimatedDefaultTextStyle(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : kAnimFast,
                curve: kAnimCurve,
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                  letterSpacing: 0.4,
                  color: selected
                      ? colorScheme.onSurface
                      : colorScheme.onSurfaceVariant.withAlpha(190),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget item = TactilePress(
      baseColor: Colors.transparent,
      highlightSize: extended ? const Size(48, 36) : null,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: onTap,
      haptics: false,
      child: AnimatedSwitcher(
        duration: kAnimFast,
        child: extended
            ? KeyedSubtree(key: const ValueKey(true), child: buildWithLabel())
            : KeyedSubtree(key: const ValueKey(false), child: buildIconOnly()),
      ),
    );
    if (!extended) item = Tooltip(message: label, child: item);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: extended ? 4 : 8,
        vertical: extended ? _labeledItemVerticalPadding : 4,
      ),
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
    final labelBehavior =
        NavigationBarTheme.of(context).labelBehavior ??
        NavigationDestinationLabelBehavior.alwaysShow;
    final cs = Theme.of(context).colorScheme;
    if (FolioLook.of(context).floatingBars) {
      return FloatingGlassNav(
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        destinations: destinations,
      );
    }
    // 平铺底栏：顶边一道细线与内容分开，选中项落在胶囊指示器里
    // （颜色、形状与字号见 app_theme 的 navigationBarTheme）。
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: AppStroke.side(cs))),
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          Haptics.soft();
          onDestinationSelected(index);
        },
        destinations: destinations.asMap().entries.map((entry) {
          final d = entry.value;
          final labelVisible =
              labelBehavior == NavigationDestinationLabelBehavior.alwaysShow ||
              (labelBehavior ==
                      NavigationDestinationLabelBehavior.onlyShowSelected &&
                  entry.key == selectedIndex);
          return NavigationDestination(
            icon: _SelectedIconFill(selected: false, child: d.icon),
            selectedIcon: _SelectedIconFill(
              selected: true,
              child: d.selectedIcon,
            ),
            label: d.label,
            tooltip: labelVisible ? '' : d.label,
          );
        }).toList(),
      ),
    );
  }
}

/// 悬浮玻璃底栏：一枚胶囊浮在内容上方，选中项下面是一片会「流动」的
/// 液态透镜——前沿用快弹簧、后沿用慢弹簧，切换时透镜先被拉长再收拢。
class FloatingGlassNav extends StatefulWidget {
  const FloatingGlassNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<AdaptiveDestination> destinations;

  /// 胶囊本体高度；页面据此给列表留出底部空间。
  static const double barHeight = 64;

  @override
  State<FloatingGlassNav> createState() => _FloatingGlassNavState();
}

class _FloatingGlassNavState extends State<FloatingGlassNav> {
  static const double _itemWidth = 112;
  static const double _inset = 6;
  bool _movingRight = true;

  @override
  void didUpdateWidget(FloatingGlassNav old) {
    super.didUpdateWidget(old);
    if (old.selectedIndex != widget.selectedIndex) {
      _movingRight = widget.selectedIndex > old.selectedIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final n = widget.destinations.length;
    final i = widget.selectedIndex.clamp(0, n - 1);
    final lead = kMotionSpatialFast;
    const trail = kMotionSpatialSteady;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Center(
        heightFactor: 1,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: LiquidGlass(
            padding: const EdgeInsets.all(_inset),
            child: SizedBox(
              width: _itemWidth * n,
              height: FloatingGlassNav.barHeight - _inset * 2,
              child: Stack(
                children: [
                  SingleMotionBuilder(
                    motion: _movingRight ? trail : lead,
                    value: i * _itemWidth,
                    active: !reduce,
                    builder: (context, left, _) => SingleMotionBuilder(
                      motion: _movingRight ? lead : trail,
                      value: (i + 1) * _itemWidth,
                      active: !reduce,
                      builder: (context, right, _) {
                        final w = (right - left).clamp(24.0, _itemWidth * n);
                        // 被拉长时略微压扁，像一滴液体
                        final stretch = (w / _itemWidth - 1).clamp(0.0, 1.0);
                        return Positioned(
                          left: left,
                          width: w,
                          top: 4 * stretch,
                          bottom: 4 * stretch,
                          child: DecoratedBox(
                            decoration: ShapeDecoration(
                              shape: const StadiumBorder(),
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color.alphaBlend(
                                    Colors.white.withValues(alpha: .22),
                                    cs.primaryContainer,
                                  ),
                                  cs.primaryContainer,
                                ],
                              ),
                              shadows: [
                                BoxShadow(
                                  color: cs.primary.withValues(alpha: .18),
                                  blurRadius: 12,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Row(
                    children: [
                      for (var k = 0; k < n; k++)
                        _GlassNavItem(
                          width: _itemWidth,
                          destination: widget.destinations[k],
                          selected: k == i,
                          onTap: () {
                            Haptics.soft();
                            widget.onDestinationSelected(k);
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassNavItem extends StatelessWidget {
  const _GlassNavItem({
    required this.width,
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final double width;
  final AdaptiveDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = selected ? cs.onPrimaryContainer : cs.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconTheme(
                data: IconThemeData(color: color, size: 22),
                child: _SelectedIconFill(
                  selected: selected,
                  child: selected ? destination.selectedIcon : destination.icon,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: AnimatedDefaultTextStyle(
                  duration: kAnimFast,
                  curve: kAnimCurve,
                  style: theme.textTheme.labelLarge!.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  child: Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
