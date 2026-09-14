import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'l10n.dart';
import 'paper_favorite_card.dart';
import 'paper_surfaces.dart';
import 'paper_widgets.dart';

class DefaultWidgetsDemo extends StatefulWidget {
  const DefaultWidgetsDemo({super.key});
  @override
  State<DefaultWidgetsDemo> createState() => _DefaultWidgetsDemoState();
}

class _DefaultWidgetsDemoState extends State<DefaultWidgetsDemo> {
  int _count = 0, _resultVersion = 0;
  final _names = <int, String>{};
  final _identities = <int, int>{};
  final _deleted = <int>{};
  bool _alert = true, _enabled = true;
  String _name(int id) =>
      _names[id] ??
      [
        context.l10n.demoFavoriteTitle,
        context.l10n.demoMethodsCollection,
        context.l10n.demoVisualCollection,
      ][id];
  String _picker = 'recent', _remote = 'S3', _logLevel = 'error';
  final _checked = <String>{'pdf'};
  double _usage = .68;
  Timer? _timer;
  final _progress = ValueNotifier<double>(0);
  int _tasks = 1;
  final _icons = const [
    Symbols.book,
    Symbols.science,
    Symbols.school,
    Symbols.folder,
    Symbols.star,
    Symbols.auto_stories,
  ];
  @override
  void dispose() {
    _timer?.cancel();
    _progress.dispose();
    super.dispose();
  }

  Future<void> _editFavorite([int id = 0]) async {
    final result = await showPaperDialog<(String, int)>(
      context,
      (_) => FavoriteEditorDemo(
        initialName: _name(id),
        initialIcon: _identities[id] ?? (id == 0 ? 0 : 3),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _names[id] = result.$1;
      _identities[id] = result.$2;
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
                      (0, _name(0), _count),
                      (1, _name(1), 3),
                      (2, _name(2), 8),
                    ])
                      if (!_deleted.contains(entry.$1))
                        SizedBox(
                          width: width,
                          child: PaperFavoriteCard(
                            key: ValueKey('favorite-${entry.$1}'),
                            title: entry.$2,
                            count: entry.$3,
                            identity:
                                _icons[_identities[entry.$1] ??
                                    (entry.$1 == 0 ? 0 : 3)],
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
      ], 32),
    );
  }
}

class FavoriteEditorDemo extends StatefulWidget {
  const FavoriteEditorDemo({
    super.key,
    required this.initialName,
    required this.initialIcon,
  });
  final String initialName;
  final int initialIcon;
  @override
  State<FavoriteEditorDemo> createState() => _FavoriteEditorDemoState();
}

class _FavoriteEditorDemoState extends State<FavoriteEditorDemo> {
  late final _name = TextEditingController(text: widget.initialName);
  late int _icon = widget.initialIcon;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final icons = [
      Symbols.book,
      Symbols.science,
      Symbols.school,
      Symbols.folder,
      Symbols.star,
      Symbols.auto_stories,
    ];
    final names = [
      l.demoIconBook,
      l.demoIconScience,
      l.demoIconSchool,
      l.demoIconFolder,
      l.demoIconStar,
      l.demoIconReading,
    ];
    return PaperDialog(
      title: l.editFavorite,
      children: [
        PaperLabel(title: l.selectIcon),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < icons.length; i++)
              IconButton(
                isSelected: _icon == i,
                tooltip: names[i],
                style: IconButton.styleFrom(
                  backgroundColor: _icon == i
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => setState(() => _icon = i),
                icon: Icon(icons[i], weight: 350, fill: 0),
              ),
          ],
        ),
        PaperLabel(title: l.favoriteName),
        TextField(
          key: const ValueKey('favorite-name'),
          controller: _name,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) {
            if (_name.text.trim().isNotEmpty)
              Navigator.pop(context, (_name.text.trim(), _icon));
          },
          decoration: InputDecoration(
            hintText: l.enterFavoriteName,
            errorText: _name.text.trim().isEmpty ? l.demoNameRequired : null,
          ),
        ),
        PaperNotice(
          title: l.demoLivePreview,
          message: _name.text.trim().isEmpty ? l.unnamed : _name.text.trim(),
        ),
      ],
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, (_name.text.trim(), _icon)),
          child: Text(l.save),
        ),
      ],
    );
  }
}
