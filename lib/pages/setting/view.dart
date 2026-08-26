import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

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
              Expanded(child: _sectionPage(detailSection)),
            ],
          );
        } else if (inSection) {
          body = _sectionPage(_selectedSection!);
        } else {
          body = _buildList(showChevron: true);
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
            title: Text(
              showMasterDetail
                  ? _sectionTitle(detailSection)
                  : (inSection
                        ? _sectionTitle(_selectedSection!)
                        : l10n.settings),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
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

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (children.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1) const AppDivider.tile(),
          ],
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return TactilePress(
      onTap: onTap,
      baseColor: selected ? colorScheme.primaryContainer : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
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
    );
  }
}
