import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n.dart';
import '../../services/snackbar_service.dart';
import '../../services/system_specs.dart';
import '../../services/update_flow.dart';
import '../../services/update_service.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/tactile_press.dart';

class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  PackageInfo? _packageInfo;
  bool _checkingUpdate = false;
  String _systemLabel = '...';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _packageInfo = info);
    });
    resolveOsShortLabel().then((label) {
      if (mounted) setState(() => _systemLabel = label);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: widget.embedded ? null : AppBar(
        title: Text(
          l10n.about,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        backgroundColor: cs.surface,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
            .copyWith(bottom: 40),
        children: [
          // ── App Icon + Name + Subtitle ──
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                image: const DecorationImage(
                  image: AssetImage('assets/icons/app_icon.png'),
                  fit: BoxFit.cover,
                ),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withAlpha(30),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              l10n.appTitle,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 32),

          // ── Info & Action Card ──
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(24),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _AboutTile(
                  icon: Symbols.tag_rounded,
                  title: l10n.aboutVersion,
                  trailing: _packageInfo?.version ?? '...',
                ),
                _divider(cs),
                _AboutTile(
                  icon: Symbols.update_rounded,
                  title: l10n.aboutCheckUpdate,
                  onTap: _checkForUpdate,
                ),
                _divider(cs),
                _AboutTile(
                  icon: Symbols.computer_rounded,
                  title: l10n.aboutSystem,
                  trailing: _systemLabel,
                  onTap: _copySpecs,
                ),
                _divider(cs),
                _AboutTile(
                  icon: Symbols.bug_report_rounded,
                  title: l10n.aboutReportIssue,
                  onTap: _reportIssue,
                ),
                _divider(cs),
                _AboutTile(
                  icon: Symbols.code_rounded,
                  title: l10n.aboutProject,
                  trailing: kGitHubRepo,
                  onTap: () => _openUrl(kGitHubUrl),
                ),
                _divider(cs),
                _AboutTile(
                  icon: Symbols.description_rounded,
                  title: l10n.aboutLicense,
                  onTap: () => _showLicenseDialog(context),
                ),
                _divider(cs),
                _AboutTile(
                  icon: Symbols.gavel_rounded,
                  title: l10n.aboutDisclaimer,
                  onTap: () => _showDisclaimerDialog(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(ColorScheme cs) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 80,
      endIndent: 20,
      color: cs.outlineVariant.withAlpha(80),
    );
  }

  Future<void> _copySpecs() async {
    final l10n = context.l10n;
    await copySystemSpecs(
      snackBar: ref.read(snackBarServiceProvider),
      copiedMessage: l10n.aboutSpecsCopied,
    );
  }

  Future<void> _reportIssue() async {
    final l10n = context.l10n;
    await openBugReportForm(
      snackBar: ref.read(snackBarServiceProvider),
      copiedMessage: l10n.aboutSpecsCopied,
      openFailedMessage: l10n.aboutOpenIssueFailed,
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _checkForUpdate() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      final info = await UpdateService.instance.checkForUpdate();
      if (!mounted) return;
      if (info.hasUpdate) {
        await presentUpdateDialog(context: context, info: info);
      } else {
        ref
            .read(snackBarServiceProvider)
            .showResult(message: context.l10n.updateUpToDate);
      }
    } catch (_) {
      if (mounted) {
        ref
            .read(snackBarServiceProvider)
            .showResult(message: context.l10n.updateCheckFailed);
      }
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  void _showLicenseDialog(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;

    showAppDialog(
      context: context,
      builder: (context) {
        return Material(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(28),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 540,
              maxHeight: MediaQuery.sizeOf(context).height * 0.7,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.aboutLicense,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(
                        l10n.aboutLicenseContent,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _openUrl('$kGitHubUrl/blob/main/LICENSE');
                        },
                        child: Text(l10n.aboutViewFullLicense),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(l10n.close),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showDisclaimerDialog(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;

    showAppDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Material(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(28),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 540,
              maxHeight: MediaQuery.sizeOf(context).height * 0.7,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.aboutDisclaimer,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(
                        l10n.aboutDisclaimerContent,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: cs.error,
                        ),
                        onPressed: () => exit(0),
                        child: Text(l10n.aboutDisagree),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(l10n.aboutAgree),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── About Tile ──

class _AboutTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailing;
  final VoidCallback? onTap;

  const _AboutTile({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final content = Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: cs.primary, size: 22),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ),
        if (trailing != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              trailing!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        if (onTap != null)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(
              Symbols.chevron_right_rounded,
              color: cs.onSurfaceVariant.withAlpha(120),
            ),
          ),
      ],
    );

    if (onTap != null) {
      return TactilePress(
        onTap: onTap,
        baseColor: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: content,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: content,
    );
  }
}
