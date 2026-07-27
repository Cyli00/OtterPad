import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../core/animation_constants.dart';
import '../../core/l10n.dart';
import '../../core/storage/settings_keys.dart';
import '../../core/storage/storage.dart';
import '../../services/agent_http.dart';
import '../../services/haptics.dart';
import '../../services/snackbar_service.dart';
import '../../services/system_specs.dart';
import '../../widgets/tactile_press.dart';

// ── GStorage keys ──

const _kLogEnabled = SettingsKeys.logEnabled;
const _kLogLevel = SettingsKeys.logLevel;
const _kHapticsEnabled = SettingsKeys.hapticsEnabled;
const _kCacheAutoCleanup = SettingsKeys.cacheAutoCleanup;
const _kAutoCheckUpdate = SettingsKeys.autoCheckUpdate;
const _kHttp2Enabled = SettingsKeys.http2Enabled;

class GeneralSettingsPage extends ConsumerStatefulWidget {
  const GeneralSettingsPage({super.key});

  @override
  ConsumerState<GeneralSettingsPage> createState() =>
      _GeneralSettingsPageState();
}

class _GeneralSettingsPageState extends ConsumerState<GeneralSettingsPage> {
  late bool _logEnabled =
      GStorage.setting.get(_kLogEnabled) as bool? ?? true;
  late String _logLevel =
      GStorage.setting.get(_kLogLevel) as String? ?? 'error';
  late bool _hapticsEnabled =
      GStorage.setting.get(_kHapticsEnabled) as bool? ?? true;
  late bool _cacheAutoCleanup =
      GStorage.setting.get(_kCacheAutoCleanup) as bool? ?? false;
  late bool _autoCheckUpdate =
      GStorage.setting.get(_kAutoCheckUpdate) as bool? ?? true;
  late bool _http2Enabled =
      GStorage.setting.get(_kHttp2Enabled) as bool? ?? false;

  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          l10n.generalSettings,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        backgroundColor: cs.surface,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ).copyWith(bottom: 40),
        children: [
          // ── 日志记录 ──
          _buildGroup(
            context,
            title: l10n.generalLogRecording,
            child: Column(
              children: [
                _SwitchTile(
                  title: l10n.generalLogRecording,
                  subtitle: l10n.generalLogRecordingDesc,
                  value: _logEnabled,
                  onChanged: (v) {
                    Haptics.soft();
                    setState(() => _logEnabled = v);
                    GStorage.setting.put(_kLogEnabled, v);
                  },
                ),
                AnimatedSize(
                  duration: kAnimFast,
                  curve: kAnimCurve,
                  alignment: Alignment.topCenter,
                  child: _logEnabled
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.generalLogLevel,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: SegmentedButton<String>(
                                  segments: [
                                    ButtonSegment(
                                      value: 'info',
                                      label: Text(l10n.generalLogLevelInfo),
                                    ),
                                    ButtonSegment(
                                      value: 'warning',
                                      label: Text(l10n.generalLogLevelWarning),
                                    ),
                                    ButtonSegment(
                                      value: 'error',
                                      label: Text(l10n.generalLogLevelError),
                                    ),
                                  ],
                                  selected: {_logLevel},
                                  onSelectionChanged: (set) {
                                    Haptics.soft();
                                    setState(() => _logLevel = set.first);
                                    GStorage.setting.put(_kLogLevel, _logLevel);
                                  },
                                  style: SegmentedButton.styleFrom(
                                    backgroundColor: cs.surface,
                                    selectedBackgroundColor: cs.primaryContainer,
                                    side: BorderSide(
                                      color: cs.outlineVariant.withAlpha(100),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                _divider(cs, indent: 80),
                _ActionTile(
                  icon: Symbols.upload_file_rounded,
                  title: l10n.generalExportTodayLog,
                  subtitle: l10n.generalExportTodayLogDesc,
                  onTap: _exportTodayLog,
                ),
                _divider(cs, indent: 80),
                _ActionTile(
                  icon: Symbols.bug_report_rounded,
                  title: l10n.generalReportIssue,
                  subtitle: l10n.generalReportIssueDesc,
                  onTap: _reportIssue,
                ),
              ],
            ),
          ),

          // ── 系统 ──
          _buildGroup(
            context,
            title: l10n.generalSystem,
            child: Column(
              children: [
                _SwitchTile(
                  title: l10n.generalHapticFeedback,
                  subtitle: l10n.generalHapticFeedbackDesc,
                  value: _hapticsEnabled,
                  onChanged: (v) {
                    Haptics.soft();
                    setState(() => _hapticsEnabled = v);
                    GStorage.setting.put(_kHapticsEnabled, v);
                    Haptics.setEnabled(v);
                  },
                ),
                _divider(cs),
                _SwitchTile(
                  title: l10n.generalCacheAutoCleanup,
                  subtitle: l10n.generalCacheAutoCleanupDesc,
                  value: _cacheAutoCleanup,
                  onChanged: (v) {
                    Haptics.soft();
                    setState(() => _cacheAutoCleanup = v);
                    GStorage.setting.put(_kCacheAutoCleanup, v);
                  },
                ),
                _divider(cs),
                _SwitchTile(
                  title: l10n.generalAutoCheckUpdate,
                  subtitle: l10n.generalAutoCheckUpdateDesc,
                  value: _autoCheckUpdate,
                  onChanged: (v) {
                    Haptics.soft();
                    setState(() => _autoCheckUpdate = v);
                    GStorage.setting.put(_kAutoCheckUpdate, v);
                  },
                ),
                _divider(cs),
                _SwitchTile(
                  title: l10n.generalEnableHttp2,
                  subtitle: l10n.generalEnableHttp2Desc,
                  value: _http2Enabled,
                  onChanged: (v) {
                    Haptics.soft();
                    setState(() => _http2Enabled = v);
                    GStorage.setting.put(_kHttp2Enabled, v);
                    AgentHttp.instance.resetInstances();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportTodayLog() async {
    final l10n = context.l10n;
    final snackBar = ref.read(snackBarServiceProvider);
    Haptics.soft();

    try {
      final file = await prepareTodayLogForExport();
      if (file == null) {
        snackBar.showResult(message: l10n.generalExportLogEmpty);
        return;
      }

      if (_isDesktop) {
        final targetPath = await FilePicker.platform.saveFile(
          dialogTitle: l10n.generalExportTodayLog,
          fileName: p.basename(file.path),
          type: FileType.custom,
          allowedExtensions: const ['log'],
          lockParentWindow: true,
        );
        if (targetPath == null) return;
        final target = File(targetPath);
        if (await target.exists()) await target.delete();
        await file.copy(target.path);
        if (!mounted) return;
        snackBar.showResult(
          message: l10n.generalExportLogSaved(target.path),
        );
      } else {
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: p.basename(file.path),
        );
      }
    } catch (_) {
      if (!mounted) return;
      snackBar.showResult(message: l10n.generalExportLogFailed);
    }
  }

  Future<void> _reportIssue() async {
    final l10n = context.l10n;
    await openBugReportForm(
      snackBar: ref.read(snackBarServiceProvider),
      copiedMessage: l10n.aboutSpecsCopied,
      openFailedMessage: l10n.aboutOpenIssueFailed,
    );
  }

  Widget _buildGroup(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 12, top: 24),
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ],
    );
  }

  Widget _divider(ColorScheme cs, {double indent = 20}) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: indent,
      endIndent: 20,
      color: cs.outlineVariant.withAlpha(70),
    );
  }
}

// ── Switch Tile ──

class _SwitchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

// ── Action Tile（与数据管理页卡片按钮一致）──

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: cs.primary, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Symbols.chevron_right_rounded,
            color: cs.onSurfaceVariant.withAlpha(120),
          ),
        ],
      ),
    );
  }
}
