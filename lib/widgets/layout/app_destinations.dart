import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/l10n.dart';
import 'adaptive_navigation.dart';

/// 应用一级导航目的地（首页 / 文献库 / 设置）。主外壳与阅读页的导航栏共用，
/// 保证图标与文案一致；底部导航只取前两项。
///
/// 图标不写 fill：选中态的实心 / 描边由导航组件过渡。
List<AdaptiveDestination> appDestinations(AppLocalizations l10n) => [
  AdaptiveDestination(
    icon: const Icon(Symbols.auto_awesome_mosaic_rounded, weight: 600),
    selectedIcon: const Icon(Symbols.auto_awesome_mosaic_rounded, weight: 600),
    label: l10n.home,
  ),
  AdaptiveDestination(
    icon: const Icon(Symbols.folder_copy_rounded, weight: 600),
    selectedIcon: const Icon(Symbols.folder_copy_rounded, weight: 600),
    label: l10n.library,
  ),
  AdaptiveDestination(
    icon: const Icon(Symbols.settings_rounded, weight: 600),
    selectedIcon: const Icon(Symbols.settings_rounded, weight: 600),
    label: l10n.settings,
  ),
];

/// 导航栏底部槽位：切换是否展示目的地文字。
AdaptiveDestination railLabelToggle(
  AppLocalizations l10n, {
  required bool extended,
}) => AdaptiveDestination(
  icon: const Icon(Symbols.menu_rounded, weight: 600, fill: 1),
  selectedIcon: const Icon(Symbols.menu_rounded, weight: 600, fill: 1),
  label: extended ? l10n.navHideLabels : l10n.navShowLabels,
);
