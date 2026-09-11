import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:otter_pad/core/l10n.dart';
import 'package:otter_pad/pages/reader/widgets/reader_bottom_bar.dart';
import 'package:otter_pad/pages/reader/widgets/reader_top_toolbar.dart';
import 'package:otter_pad/providers/document_translation_provider.dart';
import 'package:otter_pad/providers/reader_settings_provider.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Align(alignment: Alignment.bottomCenter, child: child),
    ),
  );

  ReaderBottomBar bottom({
    bool desktop = true,
    DocumentTranslationState translation = const DocumentTranslationState(),
    VoidCallback? onOutline,
  }) => ReaderBottomBar(
    desktop: desktop,
    readerSettings: const ReaderSettingsState(),
    translation: translation,
    onOpenOutline: onOutline ?? () {},
    onTranslate: () {},
    onCycleTranslationMode: () {},
    onAskAi: () {},
    onOpenNotes: () {},
    onOpenTheme: () {},
  );

  for (final width in [240.0, 360.0, 1200.0]) {
    testWidgets('桌面底栏在 $width 宽度无溢出，加载状态尺寸不变', (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var taps = 0;
      await tester.pumpWidget(host(bottom(onOutline: () => taps++)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final before = tester.getSize(find.byType(ReaderBottomBar));
      await tester.tap(find.byIcon(Symbols.menu_rounded));
      expect(taps, 1);
      if (width == 240) {
        final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
        expect(scroll.position.maxScrollExtent, greaterThan(0));
      }
      await tester.pumpWidget(
        host(
          bottom(
            translation: const DocumentTranslationState(
              status: DocTranslationStatus.loading,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(ReaderBottomBar)), before);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  }

  testWidgets('移动端保持 56 高内容区和原有顶边框', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(bottom(desktop: false)));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(ReaderBottomBar)), const Size(360, 56.5));
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄窗顶部导航开关可达，提示随状态变化，工具区可滚动', (tester) async {
    await tester.binding.setSurfaceSize(const Size(240, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var visible = true;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) {
            return ReaderTopToolbar(
              showPreview: true,
              hasResult: true,
              hasMarkdownContent: true,
              fileExists: true,
              inFavorite: false,
              extracting: false,
              canRetranslate: false,
              hasSummaryImage: false,
              showNavigationToggle: true,
              navigationVisible: visible,
              onToggleNavigation: () => setState(() => visible = !visible),
              extractButton: const SizedBox(width: 48),
              onBack: () {},
              onSearch: () {},
              onGenerateSummaryImage: () {},
              onAddFavorite: () {},
              onRemoveFavorite: () {},
              onExtract: () {},
              onShowInfo: () {},
              onReprocess: () {},
              onRetranslate: () {},
              onOpenSummaryImage: () {},
              onAiFixFigures: () {},
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Hide navigation'));
    await tester.pumpAndSettle();
    expect(visible, isFalse);
    expect(find.byTooltip('Show navigation'), findsOneWidget);
    await tester.tap(find.byTooltip('Show navigation'));
    await tester.pumpAndSettle();
    expect(visible, isTrue);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
