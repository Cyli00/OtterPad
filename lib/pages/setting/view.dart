import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../../router/app_routes.dart';
import '../../utils/desktop.dart';
import '../../utils/responsive.dart';
import '../../widgets/tactile_press.dart';
import 'package:material_symbols_icons/symbols.dart';
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

  void _onShellPop() {
    if (_selectedSection != null) {
      setState(() => _selectedSection = null);
      return;
    }
    if (!Responsive.showNavigationRail(context)) {
      StatefulNavigationShell.maybeOf(context)?.goBranch(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = context.l10n;
    final showRail = Responsive.showNavigationRail(context);
    final inSection = _isShell && _selectedSection != null;

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
                      onPressed: () =>
                          StatefulNavigationShell.maybeOf(context)?.goBranch(0),
                    )
                  : null),
        automaticallyImplyLeading: !_isShell,
        title: Text(
          inSection ? _sectionTitle(_selectedSection!) : l10n.settings,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
      ),
      body: inSection
          ? _sectionPage(_selectedSection!)
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                _SettingsCard(
                  children: [
                    _SettingsTile(
                      icon: Symbols.tune_rounded,
                      title: l10n.generalSettings,
                      subtitle: l10n.generalSettingsSubtitle,
                      onTap: () => _openSection(_SettingsSection.general),
                    ),
                    if (isDesktopOs)
                      _SettingsTile(
                        icon: Symbols.dns_rounded,
                        title: l10n.networkSettings,
                        subtitle: l10n.networkSettingsSubtitle,
                        onTap: () => _openSection(_SettingsSection.network),
                      ),
                    _SettingsTile(
                      icon: Symbols.memory_rounded,
                      title: l10n.aiSettings,
                      subtitle: l10n.aiSettingsSubtitle,
                      onTap: () => _openSection(_SettingsSection.api),
                    ),
                    _SettingsTile(
                      icon: Symbols.document_scanner_rounded,
                      title: l10n.ocrSettings,
                      subtitle: l10n.ocrSettingsSubtitle,
                      onTap: () => _openSection(_SettingsSection.extract),
                    ),
                    _SettingsTile(
                      icon: Symbols.palette_rounded,
                      title: l10n.appearanceSettings,
                      subtitle: l10n.appearanceSettingsSubtitle,
                      onTap: () => _openSection(_SettingsSection.appearance),
                    ),
                    _SettingsTile(
                      icon: Symbols.backup_table_rounded,
                      title: l10n.dataManagement,
                      subtitle: l10n.dataManagementSubtitle,
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
                      onTap: () => _openSection(_SettingsSection.about),
                    ),
                  ],
                ),
              ],
            ),
    );

    if (_isShell) {
      page = PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _onShellPop();
        },
        child: page,
      );
    }

    return page;
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

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return TactilePress(
      onTap: onTap,
      baseColor: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
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
          Icon(
            Symbols.chevron_right_rounded,
            color: colorScheme.onSurfaceVariant.withAlpha(120),
          ),
        ],
      ),
    );
  }
}
