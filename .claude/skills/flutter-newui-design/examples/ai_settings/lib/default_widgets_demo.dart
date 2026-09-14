import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'l10n.dart';
import 'paper_favorite_card.dart';
import 'paper_surfaces.dart';
import 'paper_widgets.dart';
import 'paper_theme.dart';

/// 收藏夹身份图标：沿用生产 `Favorite.emoji` 的 emoji 字符串与顺序，
/// 不新增 Symbols 引用，也不再加分类层级——直接在一格里挑。
const List<String> _emojis = [
  '\u{1F4DA}',
  '\u{1F4D6}',
  '\u{1F4D8}',
  '\u{1F4D5}',
  '\u{1F4D7}',
  '\u{1F4D9}',
  '\u{1F4D3}',
  '\u{1F4DD}',
  '\u{270F}\u{FE0F}',
  '\u{1F58A}\u{FE0F}',
  '\u{1F393}',
  '\u{1F3EB}',
  '\u{1F52C}',
  '\u{1F52D}',
  '\u{1F9EA}',
  '\u{1F4BB}',
  '\u{2699}\u{FE0F}',
  '\u{1F4CE}',
  '\u{1F4C1}',
  '\u{1F4C2}',
  '\u{1F5C2}\u{FE0F}',
  '\u{1F4CB}',
  '\u{1F4CA}',
  '\u{1F4C8}',
  '\u{2B50}',
  '\u{1F31F}',
  '\u{1F525}',
  '\u{1F4A1}',
  '\u{2764}\u{FE0F}',
  '\u{1F308}',
  '\u{1F33F}',
  '\u{1F33B}',
  '\u{1F340}',
  '\u{1F30D}',
  '\u{2600}\u{FE0F}',
  '\u{1F319}',
  '\u{1F3AF}',
  '\u{1F680}',
  '\u{1F48E}',
  '\u{1F3C6}',
  '\u{1F381}',
  '\u{1F9E9}',
  '\u{2705}',
  '\u{1F4CC}',
  '\u{1F516}',
  '\u{1F3F7}\u{FE0F}',
  '\u{1F4AC}',
  '\u{1F4AD}',
];
const String _bookEmoji = '\u{1F4DA}';
const String _folderEmoji = '\u{1F4C1}';

class DefaultWidgetsDemo extends StatefulWidget {
  const DefaultWidgetsDemo({super.key});
  @override
  State<DefaultWidgetsDemo> createState() => _DefaultWidgetsDemoState();
}

class _DefaultWidgetsDemoState extends State<DefaultWidgetsDemo> {
  int _count = 0, _resultVersion = 0;
  final _names = <int, String>{};
  final _emojis = <int, String>{};
  final _deleted = <int>{};
  bool _alert = true, _enabled = true;
  String _name(int id) =>
      _names[id] ??
      [
        context.l10n.demoFavoriteTitle,
        context.l10n.demoMethodsCollection,
        context.l10n.demoVisualCollection,
      ][id];

  /// 演示数据里每个收藏夹的文献数；卡片与编辑器预览共用同一来源。
  int _papers(int id) => switch (id) {
    0 => _count,
    1 => 3,
    _ => 8,
  };
  String _emoji(int id) => _emojis[id] ?? (id == 0 ? _bookEmoji : _folderEmoji);
  String _picker = 'recent', _remote = 'S3', _logLevel = 'error';
  final _checked = <String>{'pdf'};
  double _usage = .68;
  Timer? _timer;
  final _progress = ValueNotifier<double>(0);
  int _tasks = 1;
  @override
  void dispose() {
    _timer?.cancel();
    _progress.dispose();
    super.dispose();
  }

  Future<void> _editFavorite([int id = 0]) async {
    final result = await showPaperDialog<(String, String)>(
      context,
      (_) => FavoriteEditorDemo(
        initialName: _name(id),
        initialEmoji: _emoji(id),
        paperCount: _papers(id),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _names[id] = result.$1;
      _emojis[id] = result.$2;
      _deleted.remove(id);
    });
    _result(context.l10n.demoFavoriteSaved);
  }

  Future<void> _delete([int id = 0]) async {
    final l = context.l10n;
    final yes = await showPaperDialog<bool>(
      context,
      (context) => PaperDialog(
        title: l.demoDeleteFavorite,
        children: [
          PaperNotice(title: _name(id), message: l.demoDeleteHint, error: true),
        ],
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _deleted.add(id));
    _result(
      l.demoFavoriteRemoved,
      action: l.demoUndo,
      onAction: () => setState(() => _deleted.remove(id)),
    );
  }

  void _result(
    String message, {
    String? action,
    VoidCallback? onAction,
    bool error = false,
  }) {
    final version = ++_resultVersion;
    final controller = paperSnack(
      context,
      message,
      actionLabel: action,
      onAction: onAction,
      error: error,
    );
    controller.closed.then((_) {
      if (mounted && version == _resultVersion && _timer?.isActive == true)
        _showProgress();
    });
  }

  void _showProgress() {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: MediaQuery.sizeOf(context).width >= 600 ? 420 : null,
        duration: const Duration(days: 1),
        content: ValueListenableBuilder<double>(
          valueListenable: _progress,
          builder: (context, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${l.demoTasks(_tasks)} · ${(value * 100).round()}%',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onInverseSurface,
                ),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: value, minHeight: 3),
            ],
          ),
        ),
        action: SnackBarAction(
          label: l.cancel,
          onPressed: () {
            _timer?.cancel();
            _result(l.demoTaskCanceled);
          },
        ),
      ),
    );
  }

  void _startProgress(int tasks) {
    _resultVersion++;
    _timer?.cancel();
    _tasks = tasks;
    _progress.value = 0;
    _showProgress();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      _progress.value = (_progress.value + .04).clamp(0, 1);
      if (_progress.value >= 1) {
        timer.cancel();
        if (mounted) _result(context.l10n.demoOperationDone);
      }
    });
  }

  void _documentInfo() {
    final l = context.l10n;
    showPaperDialog<void>(
      context,
      (dialogContext) => PaperDialog(
        title: l.demoDocumentInfo,
        children: [
          SelectableText(
            l.demoPaperTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final row in {
            l.author: 'Lin Chen, Maya Li',
            l.journal: 'Journal of Digital Reading',
            l.year: '2026',
            'DOI': '10.0000/otterpad.demo',
            l.demoKeywords: l.demoKeywordValues,
          }.entries)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.key, style: Theme.of(context).textTheme.bodySmall),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: SelectableText(row.value)),
                    IconButton(
                      tooltip: l.demoCopyField(row.key),
                      onPressed: () async {
                        try {
                          await Clipboard.setData(
                            ClipboardData(text: row.value),
                          );
                          if (mounted) _result(l.demoCopied);
                        } catch (_) {
                          if (mounted) _result(l.demoCopyFailed, error: true);
                        }
                      },
                      icon: const Icon(Symbols.content_copy, size: 19),
                    ),
                  ],
                ),
              ],
            ),
        ],
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l.close),
          ),
        ],
      ),
    );
  }

  void _sheet() {
    final l = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.demoDocumentActions,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              PaperActionRow(
                title: l.demoDocumentInfo,
                icon: Symbols.description,
                onTap: () {
                  Navigator.pop(context);
                  _documentInfo();
                },
              ),
              PaperActionRow(
                title: l.demoAddFavorite,
                icon: Symbols.bookmark_add,
                onTap: () {
                  Navigator.pop(context);
                  _editFavorite();
                },
              ),
              PaperActionRow(
                title: l.demoExportCitation,
                icon: Symbols.format_quote,
                onTap: () {
                  Navigator.pop(context);
                  _result(l.demoOperationDone);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: spaced([
        PaperSection(
          title: l.demoSelection,
          help: l.demoSelectionHelp,
          action: IconButton(
            tooltip: l.demoResetExample,
            onPressed: () => setState(() {
              _remote = 'S3';
              _logLevel = 'error';
            }),
            icon: const Icon(Symbols.restart_alt),
          ),
          children: [
            PaperOptions(
              label: l.backupMethod,
              value: _remote,
              options: const {'S3': 'S3', 'WebDAV': 'WebDAV'},
              icons: const {
                'S3': Symbols.cloud_circle,
                'WebDAV': Symbols.cloud_sync,
              },
              onChanged: (v) => setState(() => _remote = v),
            ),
            const Divider(),
            PaperOptions(
              label: l.generalLogLevel,
              value: _logLevel,
              options: {
                'info': l.demoLogInfo,
                'warning': l.demoLogWarning,
                'error': l.demoLogError,
              },
              onChanged: (v) => setState(() => _logLevel = v),
            ),
          ],
        ),
        PaperSection(
          title: l.demoDialogs,
          help: l.demoDialogsHelp,
          children: [
            PaperActionRow(
              title: l.demoDocumentInfo,
              icon: Symbols.article,
              help: l.demoDocumentInfoHelp,
              onTap: _documentInfo,
            ),
            PaperActionRow(
              title: l.editFavorite,
              icon: Symbols.edit,
              help: l.demoEditFavoriteHelp,
              onTap: _editFavorite,
            ),
            PaperActionRow(
              title: l.demoDeleteFavorite,
              icon: Symbols.delete,
              onTap: _delete,
            ),
            PaperActionRow(
              title: l.demoDocumentActions,
              icon: Symbols.expand_less,
              help: l.demoSheetHelp,
              onTap: _sheet,
            ),
          ],
        ),
        PaperSection(
          title: l.demoFavoriteCards,
          help: l.demoFavoriteCardsHelp,
          children: [
            PaperOptions(
              label: l.demoCoverCount,
              value: '$_count',
              options: {
                for (final count in [0, 1, 2, 3, 4, 8]) '$count': '$count',
              },
              onChanged: (v) => setState(() => _count = int.parse(v)),
            ),
            if (_deleted.isNotEmpty)
              PaperNotice(
                title: l.demoFavoriteRemoved,
                message: l.demoUndoHint,
                action: OutlinedButton(
                  onPressed: () => setState(() => _deleted.clear()),
                  child: Text(l.demoUndo),
                ),
              ),
            LayoutBuilder(
              builder: (context, c) {
                final columns = c.maxWidth >= 900
                    ? 3
                    : c.maxWidth >= 620
                    ? 2
                    : 1;
                final width = (c.maxWidth - (columns - 1) * 16) / columns;
                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final entry in [
                      (0, _name(0), _papers(0)),
                      (1, _name(1), _papers(1)),
                      (2, _name(2), _papers(2)),
                    ])
                      if (!_deleted.contains(entry.$1))
                        SizedBox(
                          width: width,
                          child: PaperFavoriteCard(
                            key: ValueKey('favorite-${entry.$1}'),
                            title: entry.$2,
                            count: entry.$3,
                            emoji: _emoji(entry.$1),
                            onOpen: () => showPaperDialog<void>(
                              context,
                              (context) => PaperDialog(
                                title: entry.$2,
                                children: [
                                  if (entry.$3 == 0)
                                    PaperNotice(
                                      title: l.demoEmptyLibrary,
                                      message: l.demoEmptyLibraryHint,
                                    )
                                  else
                                    for (var i = 0; i < entry.$3; i++)
                                      ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: const Icon(
                                          Symbols.description,
                                        ),
                                        title: Text(
                                          '${l.demoPaperTitle} ${i + 1}',
                                        ),
                                        onTap: _documentInfo,
                                      ),
                                ],
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: Text(l.close),
                                  ),
                                ],
                              ),
                            ),
                            onEdit: () => _editFavorite(entry.$1),
                            onDelete: () => _delete(entry.$1),
                          ),
                        ),
                  ],
                );
              },
            ),
          ],
        ),
        PaperSection(
          title: l.demoFeedback,
          help: l.demoFeedbackHelp,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _result(l.demoResultMessage),
                  child: Text(l.demoResultSnack),
                ),
                OutlinedButton(
                  onPressed: () => _result(
                    l.demoNetworkError,
                    action: l.demoRetry,
                    onAction: () => _result(l.demoRetryReady),
                    error: true,
                  ),
                  child: Text(l.demoErrorSnack),
                ),
                OutlinedButton(
                  onPressed: () => _startProgress(1),
                  child: Text(l.demoProgressSnack),
                ),
                OutlinedButton(
                  onPressed: () => _startProgress(2),
                  child: Text(l.demoAggregateSnack),
                ),
              ],
            ),
            if (_alert)
              PaperNotice(
                title: l.demoAlertTitle,
                message: l.demoAlertMessage,
                error: true,
                action: OutlinedButton(
                  onPressed: () => setState(() => _alert = false),
                  child: Text(l.demoRetry),
                ),
              ),
            if (!_alert)
              PaperNotice(
                title: l.demoAlertResolved,
                message: l.demoRetryReady,
                action: TextButton(
                  onPressed: () => setState(() => _alert = true),
                  child: Text(l.demoResetExample),
                ),
              ),
          ],
        ),
        PaperSection(
          title: l.demoBasicControls,
          help: l.demoBasicControlsHelp,
          children: [
            Row(
              children: [
                Expanded(
                  child: PaperLabel(
                    title: l.demoNotifications,
                    help: l.demoNotificationsHelp,
                  ),
                ),
                Switch(
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
              ],
            ),
            PaperFieldRow(
              label: l.demoSort,
              child: PaperSelect(
                label: l.demoSort,
                value: _picker,
                options: {
                  'recent': l.demoRecent,
                  'title': l.demoSortTitle,
                  'year': l.year,
                  'author': l.author,
                },
                onChanged: (v) => setState(() => _picker = v),
              ),
            ),
            PaperLabel(title: l.demoFileTypes, help: l.demoFileTypesHelp),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in {
                  'pdf': 'PDF',
                  'epub': 'EPUB',
                  'markdown': 'Markdown',
                }.entries)
                  PaperChoice(
                    label: e.value,
                    multiple: true,
                    selected: _checked.contains(e.key),
                    onSelected: (_) => setState(() {
                      if (!_checked.add(e.key)) _checked.remove(e.key);
                    }),
                  ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: () => _result(l.demoResultMessage),
                  child: Text(l.demoPrimaryAction),
                ),
                OutlinedButton(
                  onPressed: () => _result(l.demoResultMessage),
                  child: Text(l.demoSecondaryAction),
                ),
                TextButton(
                  onPressed: () => _result(l.demoResultMessage),
                  child: Text(l.demoTextAction),
                ),
                OutlinedButton(
                  onPressed: null,
                  child: Text(l.demoDisabledAction),
                ),
              ],
            ),
          ],
        ),
        PaperSection(
          title: l.demoUsage,
          help: l.demoUsageHelp,
          children: [
            PaperSlider(
              title: l.demoQuota,
              help: l.demoQuotaHelp,
              value: _usage,
              min: 0,
              max: 1.5,
              divisions: 30,
              onChanged: (v) => setState(() => _usage = v),
              resetLabel: l.demoResetExample,
              onReset: () => setState(() => _usage = .68),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.demoEstimatedUsage,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  '${(_usage * 100).round()} / 100',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: _usage > 1 ? cs.error : cs.onSurface,
                  ),
                ),
              ],
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _usage.clamp(0, 1),
                minHeight: 4,
                color: _usage > 1 ? cs.error : cs.primary,
              ),
            ),
            if (_usage > 1)
              PaperNotice(
                title: l.demoOverQuota,
                message: l.demoOverQuotaHint,
                error: true,
              ),
          ],
        ),
      ], PaperMetrics.groupGap),
    );
  }
}

/// 收藏夹编辑器：分组图标选择、名称输入与卡片效果预览。
/// 收藏夹编辑器：分组 emoji 选择、名称输入与卡片效果预览。
class FavoriteEditorDemo extends StatefulWidget {
  const FavoriteEditorDemo({
    super.key,
    required this.initialName,
    required this.initialEmoji,
    this.paperCount = 0,
  });
  final String initialName;
  final String initialEmoji;
  final int paperCount;
  @override
  State<FavoriteEditorDemo> createState() => _FavoriteEditorDemoState();
}

class _FavoriteEditorDemoState extends State<FavoriteEditorDemo> {
  static const _maxLength = 20;
  late final _name = TextEditingController(text: widget.initialName);
  late String _emoji = widget.initialEmoji;
  bool _touched = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty;

  void _submit() {
    if (!_valid) {
      setState(() => _touched = true);
      return;
    }
    Navigator.pop(context, (_name.text.trim(), _emoji));
  }

  void _clear() {
    _name.clear();
    setState(() => _touched = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final invalid = _touched && !_valid;
    return PaperDialog(
      title: l.editFavorite,
      children: [
        // 不再分分类：一格里直接挑，对话框自身滚动承接长列表。
        PaperLabel(title: l.selectIcon),
        _picker(context),
        Row(
          children: [
            Expanded(child: PaperLabel(title: l.favoriteName)),
            Text(
              '${_name.text.characters.length} / $_maxLength',
              style: theme.textTheme.bodySmall?.copyWith(
                color: invalid ? cs.error : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        TextField(
          key: const ValueKey('favorite-name'),
          controller: _name,
          autofocus: true,
          maxLength: _maxLength,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() => _touched = true),
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: l.enterFavoriteName,
            counterText: '',
            errorText: invalid ? l.demoNameRequired : null,
            suffixIcon: _name.text.isEmpty
                ? null
                : IconButton(
                    tooltip: l.clearField,
                    onPressed: _clear,
                    icon: const Icon(Symbols.close, size: 20),
                  ),
          ),
        ),
        PaperLabel(title: l.demoLivePreview),
        _preview(context),
      ],
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: _valid ? _submit : null, child: Text(l.save)),
      ],
    );
  }

  Widget _picker(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [for (final emoji in _emojis) _tile(context, emoji)],
      ),
    );
  }

  Widget _tile(BuildContext context, String emoji) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final colors = theme.extension<PaperColors>()!;
    final selected = _emoji == emoji;
    final side = PaperMetrics.target(theme.platform);
    // MergeSemantics 让 emoji 名称、选中状态与按钮落在同一语义节点。
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        child: InkWell(
          onTap: () => setState(() => _emoji = emoji),
          borderRadius: BorderRadius.circular(12),
          hoverColor: colors.hover,
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : kAnimFast,
            curve: kAnimCurve,
            width: side,
            height: side,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? colors.selected : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? cs.primary : Colors.transparent,
                width: selected ? 2 : 1,
              ),
            ),
            // emoji 是身份图形，按图标处理：不跟随系统字号放大，避免撑破命中区。
            child: Text(
              emoji,
              textScaler: TextScaler.noScaling,
              style: const TextStyle(fontSize: 20, height: 1.0),
              strutStyle: const StrutStyle(forceStrutHeight: true, height: 1.0),
            ),
          ),
        ),
      ),
    );
  }

  /// 效果预览直接复用收藏夹卡片头部（标题行与 emoji＋篇数行），不再另画一份。
  Widget _preview(BuildContext context) {
    final l = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final name = _name.text.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: PaperFavoriteHeader(
        title: name.isEmpty ? l.unnamed : name,
        count: widget.paperCount,
        emoji: _emoji,
        titleColor: name.isEmpty ? cs.onSurfaceVariant : null,
      ),
    );
  }
}
