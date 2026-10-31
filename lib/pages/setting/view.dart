import 'dart:math' as math;

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:motor/motor.dart';

import '../../core/animation_constants.dart';
import '../../core/l10n.dart';
import '../../router/app_routes.dart';
import '../../utils/desktop.dart';
import '../../utils/responsive.dart';
import '../../widgets/app_divider.dart';
import '../../widgets/tactile_press.dart';
import 'about_page.dart';
import 'api_settings_page.dart';
import 'appearance_settings_page.dart';
import 'backup_settings_page.dart';
import 'general_settings_page.dart';
import 'network_settings_page.dart';
import 'ocr_settings_page.dart';
import 'storage_space_page.dart';

enum SettingNavMode { shell, overlay }

enum SettingsSection {
  general,
  network,
  api,
  extract,
  appearance,
  backup,
  storage,
  about,
}

class SettingPage extends StatefulWidget {
  const SettingPage({
    super.key,
    this.mode = SettingNavMode.overlay,
    this.initialSection,
  });

  final SettingNavMode mode;

  /// 进入时预选的设置分组（overlay 深链：宽屏直接定位到右侧详情）
  final SettingsSection? initialSection;

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  SettingsSection? _selectedSection;

  bool get _isShell => widget.mode == SettingNavMode.shell;

  bool get _isWide => MediaQuery.sizeOf(context).width >= 600;

  @override
  void initState() {
    super.initState();
    _selectedSection = widget.initialSection;
  }

  void _openSection(SettingsSection section) {
    // shell 或宽屏 overlay 都走原地切换（宽屏左右分栏，禁止整窗 push 子页）
    if (_isShell || _isWide) {
      setState(() => _selectedSection = section);
      return;
    }
    context.push(_overlayPath(section));
  }

  String _overlayPath(SettingsSection section) {
    return switch (section) {
      SettingsSection.general => AppRoutes.settingsOverlayGeneral,
      SettingsSection.network => AppRoutes.settingsOverlayNetwork,
      SettingsSection.api => AppRoutes.settingsOverlayApi,
      SettingsSection.extract => AppRoutes.settingsOverlayExtract,
      SettingsSection.appearance => AppRoutes.settingsOverlayAppearance,
      SettingsSection.backup => AppRoutes.settingsOverlayBackup,
      SettingsSection.storage => AppRoutes.settingsOverlayStorage,
      SettingsSection.about => AppRoutes.settingsOverlayAbout,
    };
  }

  String _sectionTitle(SettingsSection section) {
    final l10n = context.l10n;
    return switch (section) {
      SettingsSection.general => l10n.generalSettings,
      SettingsSection.network => l10n.networkSettings,
      SettingsSection.api => l10n.aiSettings,
      SettingsSection.extract => l10n.ocrSettings,
      SettingsSection.appearance => l10n.appearanceSettings,
      SettingsSection.backup => l10n.dataManagement,
      SettingsSection.storage => l10n.storageSpace,
      SettingsSection.about => l10n.about,
    };
  }

  Widget _sectionPage(SettingsSection section) {
    return switch (section) {
      SettingsSection.general => const GeneralSettingsPage(embedded: true),
      SettingsSection.network => const NetworkSettingsPage(embedded: true),
      SettingsSection.api => const ApiSettingsPage(embedded: true),
      SettingsSection.extract => const OcrSettingsPage(embedded: true),
      SettingsSection.appearance => const AppearanceSettingsPage(
        embedded: true,
      ),
      SettingsSection.backup => BackupSettingsPage(
        embedded: true,
        onOpenStorage: () =>
            setState(() => _selectedSection = SettingsSection.storage),
      ),
      SettingsSection.storage => const StorageSpacePage(embedded: true),
      SettingsSection.about => const AboutPage(embedded: true),
    };
  }

  void _onShellPop({required bool showMasterDetail}) {
    if (!showMasterDetail && _selectedSection != null) {
      setState(() => _selectedSection = null);
      return;
    }
    if (!Responsive.showNavigationRail(context)) {
      StatefulNavigationShell.maybeOf(context)?.goBranch(0);
    }
  }

  SettingsSection? _listHighlight(SettingsSection? section) {
    if (section == SettingsSection.storage) return SettingsSection.backup;
    return section;
  }

  Widget _buildList({SettingsSection? selected, required bool showChevron}) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _SettingsCard(
          children: [
            _SettingsTile(
              icon: Symbols.tune_rounded,
              title: l10n.generalSettings,
              subtitle: l10n.generalSettingsSubtitle,
              selected: selected == SettingsSection.general,
              showChevron: showChevron,
              onTap: () => _openSection(SettingsSection.general),
            ),
            if (isDesktopOs)
              _SettingsTile(
                icon: Symbols.dns_rounded,
                title: l10n.networkSettings,
                subtitle: l10n.networkSettingsSubtitle,
                selected: selected == SettingsSection.network,
                showChevron: showChevron,
                onTap: () => _openSection(SettingsSection.network),
              ),
            _SettingsTile(
              icon: Symbols.memory_rounded,
              title: l10n.aiSettings,
              subtitle: l10n.aiSettingsSubtitle,
              selected: selected == SettingsSection.api,
              showChevron: showChevron,
              onTap: () => _openSection(SettingsSection.api),
            ),
            _SettingsTile(
              icon: Symbols.document_scanner_rounded,
              title: l10n.ocrSettings,
              subtitle: l10n.ocrSettingsSubtitle,
              selected: selected == SettingsSection.extract,
              showChevron: showChevron,
              onTap: () => _openSection(SettingsSection.extract),
            ),
            _SettingsTile(
              icon: Symbols.palette_rounded,
              title: l10n.appearanceSettings,
              subtitle: l10n.appearanceSettingsSubtitle,
              selected: selected == SettingsSection.appearance,
              showChevron: showChevron,
              onTap: () => _openSection(SettingsSection.appearance),
            ),
            _SettingsTile(
              icon: Symbols.backup_table_rounded,
              title: l10n.dataManagement,
              subtitle: l10n.dataManagementSubtitle,
              selected: selected == SettingsSection.backup,
              showChevron: showChevron,
              onTap: () => _openSection(SettingsSection.backup),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsCard(
          children: [
            _SettingsTile(
              icon: Symbols.info_rounded,
              title: l10n.about,
              subtitle: l10n.aboutSubtitle,
              selected: selected == SettingsSection.about,
              showChevron: showChevron,
              onTap: () => _openSection(SettingsSection.about),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final l10n = context.l10n;
        final showRail = Responsive.showNavigationRail(context);
        // shell 与 overlay 在宽屏都走左右分栏；overlay 深链（initialSection）
        // 在窄屏直接呈现目标分组，一次 pop 回到调用页
        final showMasterDetail = constraints.maxWidth >= 600;
        final inSection = !showMasterDetail && _selectedSection != null;
        final detailSection = _selectedSection ?? SettingsSection.general;
        final reduceMotion = MediaQuery.disableAnimationsOf(context);

        Widget body;
        if (showMasterDetail) {
          final lo = 200.0;
          final computed = math.min(280.0, constraints.maxWidth * 0.35);
          final hi = math.max(lo, computed);
          final leftW = computed.clamp(lo, hi);
          body = Row(
            children: [
              SizedBox(
                width: leftW,
                child: _buildList(
                  selected: _listHighlight(detailSection),
                  showChevron: false,
                ),
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: colorScheme.outlineVariant.withAlpha(80),
              ),
              // 平级分组切换：fade through
              Expanded(
                child: PageTransitionSwitcher(
                  duration: reduceMotion ? Duration.zero : kAnimSlow,
                  transitionBuilder: (child, animation, secondaryAnimation) =>
                      FadeThroughTransition(
                        animation: animation,
                        secondaryAnimation: secondaryAnimation,
                        fillColor: colorScheme.surface,
                        child: child,
                      ),
                  child: KeyedSubtree(
                    key: ValueKey(detailSection),
                    child: _sectionPage(detailSection),
                  ),
                ),
              ),
            ],
          );
        } else {
          // 窄屏列表 ↔ 分组：横向 shared axis，返回时反向
          body = PageTransitionSwitcher(
            duration: reduceMotion ? Duration.zero : kAnimSlow,
            reverse: !inSection,
            transitionBuilder: (child, animation, secondaryAnimation) =>
                SharedAxisTransition(
                  animation: animation,
                  secondaryAnimation: secondaryAnimation,
                  transitionType: SharedAxisTransitionType.horizontal,
                  fillColor: colorScheme.surface,
                  child: child,
                ),
            child: inSection
                ? KeyedSubtree(
                    key: ValueKey(_selectedSection),
                    child: _sectionPage(_selectedSection!),
                  )
                : KeyedSubtree(
                    key: const ValueKey('list'),
                    child: _buildList(showChevron: true),
                  ),
          );
        }

        Widget page = Scaffold(
          backgroundColor: colorScheme.surface,
          appBar: AppBar(
            leading: inSection
                ? IconButton(
                    icon: const Icon(Symbols.arrow_back_rounded),
                    tooltip: l10n.back,
                    onPressed: () => _isShell
                        ? setState(() => _selectedSection = null)
                        : context.pop(),
                  )
                : (_isShell && !showRail
                      ? IconButton(
                          icon: const Icon(Symbols.arrow_back_rounded),
                          tooltip: l10n.back,
                          onPressed: () => StatefulNavigationShell.maybeOf(
                            context,
                          )?.goBranch(0),
                        )
                      : null),
            automaticallyImplyLeading: !_isShell,
            title: AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : kAnimFast,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previous, ?current],
              ),
              child: Text(
                showMasterDetail
                    ? _sectionTitle(detailSection)
                    : (inSection
                          ? _sectionTitle(_selectedSection!)
                          : l10n.settings),
                key: ValueKey(
                  showMasterDetail ? detailSection : _selectedSection,
                ),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            centerTitle: false,
            backgroundColor: colorScheme.surface,
            scrolledUnderElevation: 0,
          ),
          body: body,
        );

        if (_isShell) {
          page = PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) {
                _onShellPop(showMasterDetail: showMasterDetail);
              }
            },
            child: page,
          );
        }

        return page;
      },
    );
  }
}

// ── 设置项卡片 ──

/// 设置分组卡片。选中项的底色是卡片内唯一的滑动指示器：选中项变化时用弹簧
/// 滑到新位置；选中移到别的卡片时淡出，移入时淡入。
class _SettingsCard extends StatefulWidget {
  final List<_SettingsTile> children;

  const _SettingsCard({required this.children});

  @override
  State<_SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends State<_SettingsCard> {
  final _stackKey = GlobalKey();
  final List<GlobalKey> _tileKeys = [];

  /// 最近一次选中项的位置；取消选中后保留，供淡出时停在原处
  Rect? _indicatorRect;

  int get _selectedIndex => widget.children.indexWhere((t) => t.selected);

  /// 指示器跟随布局：选中项、窗口宽度或文字换行变化后都重新量取
  void _measure() {
    if (!mounted || _selectedIndex < 0) return;
    final stack = _stackKey.currentContext?.findRenderObject();
    final tile = _tileKeys[_selectedIndex].currentContext?.findRenderObject();
    if (stack is! RenderBox || tile is! RenderBox || !tile.hasSize) return;
    final rect = _SettingsTile.margin.deflateRect(
      tile.localToGlobal(Offset.zero, ancestor: stack) & tile.size,
    );
    if (rect != _indicatorRect) setState(() => _indicatorRect = rect);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final children = widget.children;
    if (children.isEmpty) return const SizedBox.shrink();

    while (_tileKeys.length < children.length) {
      _tileKeys.add(GlobalKey());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        key: _stackKey,
        children: [
          if (_indicatorRect != null)
            MotionBuilder<Rect>(
              motion: kMotionSpatialFast,
              converter: MotionConverter.rect,
              value: _indicatorRect!,
              active: !reduceMotion,
              builder: (context, rect, child) =>
                  Positioned.fromRect(rect: rect, child: child!),
              child: SingleMotionBuilder(
                motion: kMotionEffects,
                value: _selectedIndex >= 0 ? 1 : 0,
                active: !reduceMotion,
                builder: (context, opacity, child) =>
                    Opacity(opacity: opacity.clamp(0.0, 1.0), child: child),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(_SettingsTile.radius),
                  ),
                ),
              ),
            ),
          Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                KeyedSubtree(key: _tileKeys[i], child: children[i]),
                if (i < children.length - 1) const AppDivider.tile(),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── 单个设置项 ──

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool selected;
  final bool showChevron;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.selected = false,
    this.showChevron = true,
  });

  /// 点按区与卡片边缘的间隙；选中指示器与点按高亮共用这块区域。
  /// 圆角与卡片 24 同心（24 - 6）。
  static const EdgeInsets margin = EdgeInsets.symmetric(
    horizontal: 6,
    vertical: 4,
  );
  static const double radius = 18;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 选中底色由 _SettingsCard 的滑动指示器绘制，这里保持透明
    return Padding(
      padding: margin,
      child: TactilePress(
        onTap: onTap,
        baseColor: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        // 加上 margin 后内容位置不变（20 / 16）
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : kAnimFast,
              curve: kAnimCurve,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.surface
                    : colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: colorScheme.primary, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showChevron)
              Icon(
                Symbols.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant.withAlpha(120),
              ),
          ],
        ),
      ),
    );
  }
}
