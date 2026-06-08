import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../../providers/locale_provider.dart';
import '../../router/app_routes.dart';
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
    final locale = ref.watch(localeProvider);

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
              if (_isDesktop)
                _SettingsTile(
                  icon: Symbols.dns,
                  title: l10n.networkSettings,
                  subtitle: l10n.networkSettingsSubtitle,
                  onTap: () => context.push(AppRoutes.settingsNetwork),
                ),
              _SettingsTile(
                icon: Symbols.memory,
                title: l10n.aiSettings,
                subtitle: l10n.aiSettingsSubtitle,
                onTap: () => context.push(AppRoutes.settingsApi),
              ),
              _SettingsTile(
                icon: Symbols.document_scanner,
                title: l10n.ocrSettings,
                subtitle: l10n.ocrSettingsSubtitle,
                onTap: () => context.push(AppRoutes.settingsExtract),
              ),
              _SettingsTile(
                icon: Symbols.palette,
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
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Text(
              l10n.systemSettings,
              style: theme.textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Symbols.language_rounded,
                title: l10n.language,
                subtitle: _localeName(l10n, locale),
                onTap: () => _showLanguageSheet(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _localeName(AppLocalizations l10n, Locale? locale) {
    if (locale == null) return l10n.languageSystem;
    return switch (locale.languageCode) {
      'zh' => l10n.languageChinese,
      'en' => l10n.languageEnglish,
      _ => locale.languageCode,
    };
  }

  void _showLanguageSheet(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final current = ref.read(localeProvider);

    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LanguageOption(
              label: l10n.languageSystem,
              selected: current == null,
              onTap: () {
                ref.read(localeProvider.notifier).setLocale(null);
                Navigator.pop(context);
              },
            ),
            _LanguageOption(
              label: l10n.languageChinese,
              selected: current?.languageCode == 'zh',
              onTap: () {
                ref.read(localeProvider.notifier).setLocale(const Locale('zh'));
                Navigator.pop(context);
              },
            ),
            _LanguageOption(
              label: l10n.languageEnglish,
              selected: current?.languageCode == 'en',
              onTap: () {
                ref.read(localeProvider.notifier).setLocale(const Locale('en'));
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _LanguageOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      title: Text(
        label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? cs.primary : cs.onSurface,
        ),
      ),
      trailing: selected
          ? Icon(Symbols.check_rounded, color: cs.primary)
          : null,
      onTap: onTap,
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
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
        ),
      ),
    );
  }
}
