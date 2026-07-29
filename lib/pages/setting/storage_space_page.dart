import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/animation_constants.dart';
import '../../core/l10n.dart';
import '../../services/haptics.dart';
import '../../services/snackbar_service.dart';
import '../../services/storage_usage_service.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/tactile_press.dart';

class StorageSpacePage extends ConsumerStatefulWidget {
  const StorageSpacePage({super.key});

  @override
  ConsumerState<StorageSpacePage> createState() => _StorageSpacePageState();
}

class _StorageSpacePageState extends ConsumerState<StorageSpacePage> {
  StorageReport? _report;
  bool _loading = false;
  bool _clearing = false;
  final Set<StorageGroupKey> _selected = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final report = await StorageUsageService.computeReport();
      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle(StorageGroupKey key) {
    Haptics.soft();
    setState(() {
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else {
        _selected.add(key);
      }
    });
  }

  int get _selectedBytes {
    if (_report == null) return 0;
    return _report!.groups
        .where((g) => _selected.contains(g.key))
        .fold(0, (sum, g) => sum + g.bytes);
  }

  Future<void> _confirmClear() async {
    if (_selected.isEmpty) return;
    Haptics.soft();
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final names =
        _selected.map((k) => _groupTitle(k)).join(l10n.listSeparator);

    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        title: Text(l10n.clearData),
        content: Text(l10n.clearDataConfirm(names)),
        actions: [
          TextButton(
            onPressed: () {
              Haptics.soft();
              Navigator.pop(ctx, false);
            },
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Haptics.soft();
              Navigator.pop(ctx, true);
            },
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: Text(l10n.clearData),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearing = true);
    try {
      await StorageUsageService.clearGroups(_selected);
      if (!mounted) return;
      ref
          .read(snackBarServiceProvider)
          .showResult(message: l10n.storageSpaceCleared);
      setState(() => _selected.clear());
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ref.read(snackBarServiceProvider).showResult(
            message: e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''),
          );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  // ── data helpers ──

  IconData _groupIcon(StorageGroupKey key) {
    switch (key) {
      case StorageGroupKey.papers:
        return Symbols.article_rounded;
      case StorageGroupKey.chat:
        return Symbols.chat_rounded;
      case StorageGroupKey.cache:
        return Symbols.cached_rounded;
      case StorageGroupKey.logs:
        return Symbols.receipt_long_rounded;
      case StorageGroupKey.database:
        return Symbols.database_rounded;
    }
  }

  String _groupTitle(StorageGroupKey key) {
    final l10n = context.l10n;
    switch (key) {
      case StorageGroupKey.papers:
        return l10n.storageGroupPapers;
      case StorageGroupKey.chat:
        return l10n.storageCategoryChat;
      case StorageGroupKey.cache:
        return l10n.storageCategoryCache;
      case StorageGroupKey.logs:
        return l10n.storageCategoryLogs;
      case StorageGroupKey.database:
        return l10n.storageCategoryDatabase;
    }
  }

  Color _groupColor(StorageGroupKey key, ColorScheme cs) {
    switch (key) {
      case StorageGroupKey.papers:
        return cs.primary;
      case StorageGroupKey.chat:
        return cs.secondary;
      case StorageGroupKey.cache:
        return cs.error;
      case StorageGroupKey.logs:
        return cs.outline;
      case StorageGroupKey.database:
        return cs.tertiary;
    }
  }

  String _subTitle(String id) {
    final l10n = context.l10n;
    switch (id) {
      case 'files':
        return l10n.storageCategoryFiles;
      case 'images':
        return l10n.storageCategoryImages;
      default:
        return id;
    }
  }

  Color _subColor(String id, ColorScheme cs) {
    switch (id) {
      case 'files':
        return cs.primary;
      case 'images':
        return cs.tertiary;
      default:
        return cs.outline;
    }
  }

  /// 无选中 → 组级段；单选有子分类 → 子分类段；其余 → 所选组段。
  List<_Segment> _computeSegments(StorageReport report, ColorScheme cs) {
    if (_selected.isEmpty) {
      return [
        for (final g in report.groups)
          _Segment(
            label: _groupTitle(g.key),
            bytes: g.bytes,
            color: _groupColor(g.key, cs),
          ),
      ];
    }

    final sel =
        report.groups.where((g) => _selected.contains(g.key)).toList();

    if (sel.length == 1 && sel.first.subcategories.isNotEmpty) {
      return [
        for (final s in sel.first.subcategories)
          _Segment(
            label: _subTitle(s.id),
            bytes: s.bytes,
            color: _subColor(s.id, cs),
          ),
      ];
    }

    return [
      for (final g in sel)
        _Segment(
          label: _groupTitle(g.key),
          bytes: g.bytes,
          color: _groupColor(g.key, cs),
        ),
    ];
  }

  // ── build ──

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          l10n.storageSpace,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
        backgroundColor: cs.surface,
        scrolledUnderElevation: 0,
      ),
      body: _loading && _report == null
          ? const Center(child: CircularProgressIndicator())
          : _report == null
              ? Center(
                  child: Text(
                    l10n.storageSpaceLoadFailed,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                )
              : _buildBody(theme, cs, l10n, _report!),
    );
  }

  Widget _buildBody(
    ThemeData theme,
    ColorScheme cs,
    AppLocalizations l10n,
    StorageReport report,
  ) {
    final hasSelection = _selected.isNotEmpty;
    final displayTotal = hasSelection ? _selectedBytes : report.totalBytes;
    final segments = _computeSegments(report, cs);
    final nonEmpty = segments.where((s) => s.bytes > 0).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
          .copyWith(bottom: 40),
      children: [
        // ── 总览卡 ──
        _buildSection(
          theme,
          cs,
          title: hasSelection ? l10n.storageSpaceSelected : l10n.storageSpace,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSwitcher(
                  duration: kAnimFast,
                  child: Text(
                    hasSelection
                        ? l10n.storageSpaceSelected
                        : l10n.storageSpaceTotal,
                    key: ValueKey(hasSelection),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                AnimatedSwitcher(
                  duration: kAnimFast,
                  child: Text(
                    StorageUsageService.formatSize(displayTotal),
                    key: ValueKey(displayTotal),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _UsageBar(segments: nonEmpty, totalBytes: displayTotal),
                const SizedBox(height: 12),
                _UsageLegend(segments: nonEmpty),
              ],
            ),
          ),
        ),

        // ── 分类列表 ──
        _buildSection(
          theme,
          cs,
          title: l10n.storageSpaceDetails,
          child: Column(
            children: [
              for (int i = 0; i < report.groups.length; i++) ...[
                _GroupRow(
                  icon: _groupIcon(report.groups[i].key),
                  color: _groupColor(report.groups[i].key, cs),
                  title: _groupTitle(report.groups[i].key),
                  sizeText:
                      StorageUsageService.formatSize(report.groups[i].bytes),
                  countText: l10n.storageSpaceFilesCount(
                    report.groups[i].fileCount,
                  ),
                  checked: _selected.contains(report.groups[i].key),
                  onToggle: () => _toggle(report.groups[i].key),
                ),
                if (i != report.groups.length - 1) _divider(cs),
              ],
            ],
          ),
        ),

        // ── 清除按钮 ──
        const SizedBox(height: 24),
        Center(
          child: TextButton.icon(
            onPressed:
                _clearing || _selected.isEmpty ? null : _confirmClear,
            icon: _clearing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Symbols.delete_forever_rounded, size: 20),
            label: Text(l10n.clearData),
            style: TextButton.styleFrom(foregroundColor: cs.error),
          ),
        ),
      ],
    );
  }

  // ── shared builders ──

  Widget _buildSection(
    ThemeData theme,
    ColorScheme cs, {
    required String title,
    required Widget child,
  }) {
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

  Widget _divider(ColorScheme cs) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 80,
      endIndent: 20,
      color: cs.outlineVariant.withAlpha(70),
    );
  }
}

// ─── Bar Segment model ───────────────────────────────

class _Segment {
  final String label;
  final int bytes;
  final Color color;

  const _Segment({
    required this.label,
    required this.bytes,
    required this.color,
  });
}

// ─── Usage Bar ───────────────────────────────────────

class _UsageBar extends StatelessWidget {
  final List<_Segment> segments;
  final int totalBytes;

  const _UsageBar({required this.segments, required this.totalBytes});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (segments.isEmpty || totalBytes <= 0) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Container(height: 12, color: cs.onSurface.withAlpha(20)),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Row(
        children: [
          for (final s in segments)
            Expanded(
              flex: ((s.bytes / totalBytes) * 1000).round().clamp(1, 1000),
              child: Container(height: 12, color: s.color),
            ),
        ],
      ),
    );
  }
}

// ─── Usage Legend ─────────────────────────────────────

class _UsageLegend extends StatelessWidget {
  final List<_Segment> segments;

  const _UsageLegend({required this.segments});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (segments.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        for (final s in segments)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: s.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                s.label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ],
          ),
      ],
    );
  }
}

// ─── Group Row ───────────────────────────────────────

class _GroupRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String sizeText;
  final String countText;
  final bool checked;
  final VoidCallback onToggle;

  const _GroupRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.sizeText,
    required this.countText,
    required this.checked,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return TactilePress(
      onTap: onToggle,
      baseColor: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: checked,
              onChanged: (_) => onToggle(),
              activeColor: cs.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 12),
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
                  '$sizeText · $countText',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
