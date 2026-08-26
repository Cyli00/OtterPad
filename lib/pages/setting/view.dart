import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/l10n.dart';
import '../../router/app_routes.dart';
import '../../utils/desktop.dart';
import '../../utils/responsive.dart';
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

enum _SettingsSection {
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
  const SettingPage({super.key, this.mode = SettingNavMode.overlay});

  final SettingNavMode mode;

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  _SettingsSection? _selectedSection;

  bool get _isShell => widget.mode == SettingNavMode.shell;

  void _openSection(_SettingsSection section) {
    if (_isShell) {
      setState(() => _selectedSection = section);
      return;
    }
    context.push(_overlayPath(section));
  }

  String _overlayPath(_SettingsSection section) {
    return switch (section) {
      _SettingsSection.general => AppRoutes.settingsOverlayGeneral,
      _SettingsSection.network => AppRoutes.settingsOverlayNetwork,
      _SettingsSection.api => AppRoutes.settingsOverlayApi,
      _SettingsSection.extract => AppRoutes.settingsOverlayExtract,
      _SettingsSection.appearance => AppRoutes.settingsOverlayAppearance,
      _SettingsSection.backup => AppRoutes.settingsOverlayBackup,
      _SettingsSection.storage => AppRoutes.settingsOverlayStorage,
      _SettingsSection.about => AppRoutes.settingsOverlayAbout,
    };
  }

  String _sectionTitle(_SettingsSection section) {
    final l10n = context.l10n;
    return switch (section) {
      _SettingsSection.general => l10n.generalSettings,
      _SettingsSection.network => l10n.networkSettings,
      _SettingsSection.api => l10n.aiSettings,
      _SettingsSection.extract => l10n.ocrSettings,
      _SettingsSection.appearance => l10n.appearanceSettings,
      _SettingsSection.backup => l10n.dataManagement,
      _SettingsSection.storage => l10n.storageSpace,
      _SettingsSection.about => l10n.about,
    };
  }

  Widget _sectionPage(_SettingsSection section) {
    return switch (section) {
      _SettingsSection.general => const GeneralSettingsPage(embedded: true),
      _SettingsSection.network => const NetworkSettingsPage(embedded: true),
      _SettingsSection.api => const ApiSettingsPage(embedded: true),
      _SettingsSection.extract => const OcrSettingsPage(embedded: true),
      _SettingsSection.appearance => const AppearanceSettingsPage(
        embedded: true,
      ),
      _SettingsSection.backup => BackupSettingsPage(
        embedded: true,
        onOpenStorage: () =>
            setState(() => _selectedSection = _SettingsSection.storage),
      ),
      _SettingsSection.storage => const StorageSpacePage(embedded: true),
      _SettingsSection.about => const AboutPage(embedded: true),
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

  _SettingsSection? _listHighlight(_SettingsSection? section) {
    if (section == _SettingsSection.storage) return _SettingsSection.backup;
    return section;
  }

  Widget _buildList({_SettingsSection? selected, required bool showChevron}) {
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
              selected: selected == _SettingsSection.general,
              showChevron: showChevron,
              onTap: () => _openSection(_SettingsSection.general),
            ),
            if (isDesktopOs)
              _SettingsTile(
                icon: Symbols.dns_rounded,
                title: l10n.networkSettings,
                subtitle: l10n.networkSettingsSubtitle,
                selected: selected == _SettingsSection.network,
                showChevron: showChevron,
                onTap: () => _openSection(_SettingsSection.network),
              ),
            _SettingsTile(
              icon: Symbols.memory_rounded,
              title: l10n.aiSettings,
              subtitle: l10n.aiSettingsSubtitle,
              selected: selected == _SettingsSection.api,
              showChevron: showChevron,
              onTap: () => _openSection(_SettingsSection.api),
            ),
            _SettingsTile(
              icon: Symbols.document_scanner_rounded,
              title: l10n.ocrSettings,
              subtitle: l10n.ocrSettingsSubtitle,
              selected: selected == _SettingsSection.extract,
              showChevron: showChevron,
              onTap: () => _openSection(_SettingsSection.extract),
            ),
            _SettingsTile(
              icon: Symbols.palette_rounded,
              title: l10n.appearanceSettings,
              subtitle: l10n.appearanceSettingsSubtitle,
              selected: selected == _SettingsSection.appearance,
              showChevron: showChevron,
              onTap: () => _openSection(_SettingsSection.appearance),
            ),
            _SettingsTile(
              icon: Symbols.backup_table_rounded,
              title: l10n.dataManagement,
              subtitle: l10n.dataManagementSubtitle,
              selected: selected == _SettingsSection.backup,
              showChevron: showChevron,
              onTap: () => _openSection(_SettingsSection.backup),
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
              selected: selected == _SettingsSection.about,
              showChevron: showChevron,
              onTap: () => _openSection(_SettingsSection.about),
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
        final showMasterDetail = _isShell && constraints.maxWidth >= 600;
        final inSection =
            _isShell && !showMasterDetail && _selectedSection != null;
        final detailSection = _selectedSection ?? _SettingsSection.general;

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
                    onPressed: () => setState(() => _selectedSection = null),
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
            if (i < children.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                indent: 80,
                endIndent: 20,
                color: cs.outlineVariant.withAlpha(80),
              ),
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
