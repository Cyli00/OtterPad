import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'ai_settings_demo.dart';
import 'appearance_demo.dart';
import 'backup_settings_demo.dart';
import 'default_widgets_demo.dart';
import 'l10n.dart';
import 'paper_theme.dart';
import 'paper_widgets.dart';
import 'paper_display_settings.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 为浏览器交互验收暴露 Flutter 原生语义树。
  SemanticsBinding.instance.ensureSemantics();
  runApp(
    NewUiDemo(
      page: Uri.base.queryParameters['page'] ?? 'ai',
      mobile: const [
        'mobile',
        'xiaomi15',
        'iphone17pro',
      ].contains(Uri.base.queryParameters['device']),
      device: Uri.base.queryParameters['device'],
    ),
  );
}

class NewUiDemo extends StatefulWidget {
  const NewUiDemo({
    super.key,
    this.page = 'ai',
    this.mobile = false,
    this.device,
  });
  final String page;
  final bool mobile;
  final String? device;
  @override
  State<NewUiDemo> createState() => _NewUiDemoState();
}

class _NewUiDemoState extends State<NewUiDemo> {
  bool _dark = Uri.base.queryParameters['theme'] == 'dark';
  PaperFont _font = PaperFont.sans;
  TargetPlatform get _platform => widget.device == 'iphone17pro'
      ? TargetPlatform.iOS
      : widget.mobile
      ? TargetPlatform.android
      : TargetPlatform.windows;
  bool _reduceMotion = false;
  Locale _locale = const Locale('zh');
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    if (widget.page == 'appearance') {
      return AppearanceDemo(
        mobile: widget.mobile,
        platform: _platform,
        initialMode: switch (Uri.base.queryParameters['theme']) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
      );
    }
    return _settingsDemo(context);
  }

  Widget _settingsDemo(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'OtterPad · AI settings',
    locale: _locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: paperTheme(Brightness.light, font: _font, platform: _platform),
    darkTheme: paperTheme(Brightness.dark, font: _font, platform: _platform),
    themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
    themeAnimationDuration: _reduceMotion ? Duration.zero : kAnim,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(_scale),
        disableAnimations:
            _reduceMotion || MediaQuery.disableAnimationsOf(context),
      ),
      child: child!,
    ),
    home: Builder(
      builder: (context) {
        final l = context.l10n;
        return Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, c) {
                final narrow = c.maxWidth < 700;
                final text = Theme.of(context).textTheme;
                return SingleChildScrollView(
                  key: const PageStorageKey('ai-settings-scroll'),
                  padding: EdgeInsets.fromLTRB(
                    narrow ? 16 : 32,
                    narrow ? 20 : 28,
                    narrow ? 16 : 32,
                    64,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1160),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 24,
                            runSpacing: 8,
                            children: [
                              PaperLabel(
                                title: widget.page == 'backup'
                                    ? l.dataManagement
                                    : widget.page == 'widgets'
                                    ? l.demoWidgetTitle
                                    : l.aiSettings,
                                help: widget.page == 'backup'
                                    ? l.demoBackupHelp
                                    : widget.page == 'widgets'
                                    ? l.demoWidgetHelp
                                    : l.subtitle,
                                style: narrow
                                    ? text.headlineSmall
                                    : text.headlineLarge,
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: l.darkMode,
                                    onPressed: () =>
                                        setState(() => _dark = !_dark),
                                    icon: Icon(
                                      _dark
                                          ? Symbols.light_mode
                                          : Symbols.dark_mode,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: l.language,
                                    onPressed: () => setState(
                                      () => _locale = Locale(
                                        _locale.languageCode == 'zh'
                                            ? 'en'
                                            : 'zh',
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
                                      final next =
                                          await showPaperDisplaySettings(
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
                                        onChanged: (value) => setState(
                                          () => _reduceMotion = value,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(l.demoNote, style: text.bodySmall),
                          const SizedBox(height: 20),
                          if (widget.page == 'backup')
                            const BackupSettingsDemo()
                          else if (widget.page == 'widgets')
                            const DefaultWidgetsDemo()
                          else
                            const AiSettingsDemo(),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    ),
  );
}
