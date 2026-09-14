import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'appearance_palette.dart';
import 'appearance_reader.dart';
import 'default_widgets_demo.dart';
import 'l10n.dart';
import 'paper_surfaces.dart';
import 'paper_display_settings.dart';
import 'paper_theme.dart';
import 'paper_widgets.dart';

class AppearanceDemo extends StatefulWidget {
  const AppearanceDemo({
    super.key,
    this.mobile = false,
    this.initialMode = ThemeMode.system,
    this.platform,
  });
  final bool mobile;
  final ThemeMode initialMode;
  final TargetPlatform? platform;
  @override
  State<AppearanceDemo> createState() => _AppearanceDemoState();
}

class _AppearanceDemoState extends State<AppearanceDemo> {
  late ThemeMode _mode = widget.initialMode;
  PaperFont _font = PaperFont.sans;
  TargetPlatform get _platform =>
      widget.platform ??
      (widget.mobile ? TargetPlatform.android : TargetPlatform.windows);
  DemoPaper _paper = DemoPaper.follow;
  Locale _locale = const Locale('zh');
  bool _reduceMotion = false, _pdf = false, _error = false;
  double _scale = 1;
  String? _favorite;
  String _favoriteEmoji = '\u{1F4DA}';
  final _draft = TextEditingController();
  final _readerScroll = ScrollController();

  @override
  void dispose() {
    _draft.dispose();
    _readerScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'OtterPad · Appearance',
    locale: _locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: paperTheme(Brightness.light, font: _font, platform: _platform),
    darkTheme: paperTheme(Brightness.dark, font: _font, platform: _platform),
    themeMode: _mode,
    themeAnimationDuration: Duration.zero,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(_scale),
        disableAnimations:
            _reduceMotion || MediaQuery.disableAnimationsOf(context),
      ),
      child: child!,
    ),
    home: Builder(builder: _page),
  );

  Widget _page(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final paper = AppearancePaper.resolve(_paper, theme.brightness);
    final document = _pdf ? AppearancePaper.original : paper;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          key: const PageStorageKey('appearance-scroll'),
          padding: EdgeInsets.all(widget.mobile ? 16 : 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 24,
                runSpacing: 8,
                children: [
                  PaperLabel(
                    title: l.appearanceTitle,
                    help: l.appearanceHelp,
                    style: widget.mobile
                        ? _scale > 1.3
                              ? theme.textTheme.titleMedium
                              : theme.textTheme.headlineSmall
                        : theme.textTheme.headlineLarge,
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: l.darkMode,
                        onPressed: () => setState(
                          () => _mode = theme.brightness == Brightness.dark
                              ? ThemeMode.light
                              : ThemeMode.dark,
                        ),
                        icon: Icon(
                          theme.brightness == Brightness.dark
                              ? Symbols.light_mode
                              : Symbols.dark_mode,
                        ),
                      ),
                      IconButton(
                        tooltip: l.language,
                        onPressed: () => setState(
                          () => _locale = Locale(
                            _locale.languageCode == 'zh' ? 'en' : 'zh',
                          ),
                        ),
                        icon: const Icon(Symbols.translate),
                      ),
                      IconButton(
                        tooltip: l.fontScale,
                        onPressed: () => setState(
                          () => _scale = _scale == 1
                              ? 1.3
                              : _scale == 1.3
                              ? 2
                              : 1,
                        ),
                        icon: const Icon(Symbols.text_fields),
                      ),
                      IconButton(
                        tooltip: l.displaySettings,
                        onPressed: () async {
                          final next = await showPaperDisplaySettings(
                            context,
                            _font,
                          );
                          if (next != null && mounted)
                            setState(() => _font = next);
                        },
                        icon: const Icon(Symbols.tune),
                      ),
                      Tooltip(
                        message: l.reduceMotion,
                        child: Semantics(
                          label: l.reduceMotion,
                          child: Switch(
                            value: _reduceMotion,
                            onChanged: (value) =>
                                setState(() => _reduceMotion = value),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(l.appearanceScope, style: theme.textTheme.bodySmall),
              const SizedBox(height: 24),
              PaperOptions(
                label: l.appearanceMode,
                help: l.appearanceModeHelp,
                value: _mode.name,
                options: {
                  'system': l.appearanceSystem,
                  'light': l.appearanceLight,
                  'dark': l.appearanceDark,
                },
                onChanged: (value) =>
                    setState(() => _mode = ThemeMode.values.byName(value)),
              ),
              const SizedBox(height: 16),

              Divider(color: cs.outlineVariant),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final reader = _reader(context, paper);
                  final controls = _controls(context);
                  if (constraints.maxWidth < 800 || _scale > 1.3) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        controls,
                        const SizedBox(height: 24),
                        reader,
                        const SizedBox(height: 24),
                        _feedback(context),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 280,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            controls,
                            const SizedBox(height: 20),
                            _feedback(context),
                          ],
                        ),
                      ),
                      const SizedBox(width: 28),
                      Expanded(child: reader),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              PaperLabel(
                title: l.appearanceContrast,
                help: l.appearanceContrastHelp,
              ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _contrast(
                    context,
                    l.appearanceUiText,
                    cs.onSurface,
                    cs.surface,
                  ),
                  _contrast(
                    context,
                    l.appearanceReadingText,
                    document.ink,
                    document.background,
                  ),
                  _contrast(
                    context,
                    l.appearanceLink,
                    paperTheme(document.brightness).colorScheme.primary,
                    document.background,
                  ),
                ],
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final paperLabels = [
      l.appearanceFollow,
      l.appearanceWhite,
      l.appearanceSepia,
      l.appearancePaleGreen,
      l.appearanceNight,
      l.appearanceBlack,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaperLabel(title: l.appearancePaper, help: l.appearancePaperHelp),
        Semantics(
          label: l.appearancePaper,
          child: DropdownButtonFormField<DemoPaper>(
            key: const ValueKey('appearance-paper'),
            initialValue: _paper,
            isExpanded: true,
            style: theme.textTheme.bodyLarge,
            decoration: const InputDecoration(),
            items: [
              for (final value in DemoPaper.values)
                DropdownMenuItem(
                  value: value,
                  child: Text(paperLabels[value.index]),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _paper = value);
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _paper == DemoPaper.follow
              ? l.appearanceFollowing
              : l.appearancePinned,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _feedback(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaperLabel(
          title: l.appearanceComponents,
          help: l.appearanceComponentsHelp,
        ),
        TextField(
          key: const ValueKey('appearance-draft'),
          controller: _draft,
          decoration: InputDecoration(
            labelText: l.appearanceDraft,
            hintText: l.appearanceDraftHint,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: () => _documentInfo(context),
              icon: const Icon(Symbols.description),
              label: Text(l.demoDocumentInfo),
            ),
            OutlinedButton.icon(
              onPressed: () => _edit(context),
              icon: const Icon(Symbols.folder_open),
              label: Text(l.editFavorite),
            ),
            FilledButton(
              onPressed: () => paperSnack(
                context,
                l.appearanceSnack,
                actionLabel: l.close,
                onAction: () {},
              ),
              child: Text(l.appearanceShowSnack),
            ),
            OutlinedButton(
              onPressed: () => setState(() => _error = !_error),
              child: Text(l.appearanceShowError),
            ),
            OutlinedButton(onPressed: null, child: Text(l.appearanceDisabled)),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          _favorite ?? l.demoFavoriteTitle,
          key: const ValueKey('appearance-favorite'),
          style: theme.textTheme.titleSmall,
        ),
        if (_error) ...[
          const SizedBox(height: 12),
          PaperNotice(
            title: l.appearanceErrorTitle,
            message: l.appearanceErrorMessage,
            error: true,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                setState(() => _error = false);
                paperSnack(context, l.appearanceRetryDone);
              },
              child: Text(l.demoRetry),
            ),
          ),
        ],
      ],
    );
  }

  Widget _reader(BuildContext context, AppearancePaper paper) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaperOptions(
          label: l.appearanceReader,
          help: l.appearanceReaderHelp,
          value: _pdf ? 'pdf' : 'markdown',
          options: const {'markdown': 'Markdown', 'pdf': 'PDF'},
          onChanged: (value) => setState(() => _pdf = value == 'pdf'),
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            key: const ValueKey('appearance-reader'),
            decoration: BoxDecoration(
              color: paper.background,
              border: Border.all(color: paper.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _pdf ? l.appearanceOriginal : l.appearanceReadingPreview,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: paper.muted),
                  ),
                ),
                Divider(height: 1, color: paper.line),
                SizedBox(
                  height: widget.mobile ? 480 : 560,
                  child: Scrollbar(
                    controller: _readerScroll,
                    child: SingleChildScrollView(
                      key: const PageStorageKey('appearance-reader-scroll'),
                      controller: _readerScroll,
                      padding: EdgeInsets.all(widget.mobile ? 16 : 28),
                      child: Theme(
                        data: paperTheme(
                          paper.brightness,
                          font: _font,
                          platform: _platform,
                        ),
                        child: AppearanceReader(paper: paper, pdf: _pdf),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _pdf ? l.appearancePdfNote : l.appearanceMarkdownNote,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _contrast(
    BuildContext context,
    String label,
    Color foreground,
    Color background,
  ) {
    final value = appearanceContrast(foreground, background);
    final pass = value >= 4.5;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: pass ? cs.outlineVariant : cs.error),
      ),
      child: Text(
        '$label  ${value.toStringAsFixed(2)}:1 · ${pass ? context.l10n.appearancePass : context.l10n.appearanceFail}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  void _documentInfo(BuildContext context) {
    final l = context.l10n;
    showPaperDialog<void>(
      context,
      (dialogContext) => PaperDialog(
        title: l.demoDocumentInfo,
        children: [
          Text(
            l.appearanceArticleTitle,
            style: Theme.of(dialogContext).textTheme.titleMedium,
          ),
          Text(l.appearanceArticleByline),
          PaperNotice(
            title: l.appearanceSample,
            message: l.appearanceSampleHelp,
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

  Future<void> _edit(BuildContext context) async {
    final result = await showPaperDialog<(String, String)>(
      context,
      (_) => FavoriteEditorDemo(
        initialName: _favorite ?? context.l10n.demoFavoriteTitle,
        initialEmoji: _favoriteEmoji,
      ),
    );
    if (!mounted || !context.mounted || result == null) return;
    setState(() {
      _favorite = result.$1;
      _favoriteEmoji = result.$2;
    });
    paperSnack(context, context.l10n.demoFavoriteSaved);
  }
}
