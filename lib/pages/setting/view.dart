import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../../router/app_routes.dart';
import '../../widgets/tactile_press.dart';
import 'package:material_symbols_icons/symbols.dart';

bool get _isDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

class SettingPage extends ConsumerWidget {
  const SettingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          l10n.settings,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Symbols.tune_rounded,
                title: l10n.generalSettings,
                subtitle: l10n.generalSettingsSubtitle,
                onTap: () => context.push(AppRoutes.settingsGeneral),
              ),
              if (_isDesktop)
                _SettingsTile(
                  icon: Symbols.dns_rounded,
                  title: l10n.networkSettings,
                  subtitle: l10n.networkSettingsSubtitle,
                  onTap: () => context.push(AppRoutes.settingsNetwork),
                ),
              _SettingsTile(
                icon: Symbols.memory_rounded,
                title: l10n.aiSettings,
                subtitle: l10n.aiSettingsSubtitle,
                onTap: () => context.push(AppRoutes.settingsApi),
              ),
              _SettingsTile(
                icon: Symbols.document_scanner_rounded,
                title: l10n.ocrSettings,
                subtitle: l10n.ocrSettingsSubtitle,
                onTap: () => context.push(AppRoutes.settingsExtract),
              ),
              _SettingsTile(
                icon: Symbols.palette_rounded,
                title: l10n.appearanceSettings,
                subtitle: l10n.appearanceSettingsSubtitle,
                onTap: () => context.push(AppRoutes.settingsAppearance),
              ),
              _SettingsTile(
                icon: Symbols.backup_table_rounded,
                title: l10n.dataManagement,
                subtitle: l10n.dataManagementSubtitle,
                onTap: () => context.push(AppRoutes.settingsBackup),
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
                onTap: () => context.push(AppRoutes.settingsAbout),
              ),
            ],
          ),
        ],
      ),
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
          ]
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
