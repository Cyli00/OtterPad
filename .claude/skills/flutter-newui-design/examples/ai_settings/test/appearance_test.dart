import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newui_ai_demo/appearance_palette.dart';
import 'package:newui_ai_demo/main.dart';
import 'package:newui_ai_demo/paper_surfaces.dart';
import 'package:newui_ai_demo/paper_theme.dart';

void main() {
  Future<void> host(WidgetTester tester, {double width = 1100}) async {
    await tester.binding.setSurfaceSize(Size(width, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(NewUiDemo(page: 'appearance', mobile: width < 700));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  void choosePaper(WidgetTester tester, DemoPaper paper) {
    tester
        .widget<DropdownButtonFormField<DemoPaper>>(
          find.byKey(const ValueKey('appearance-paper')),
        )
        .onChanged!(paper);
  }

  test('石墨与所有纸面的正文、次要文字、链接满足最低对比度', () {
    for (final brightness in Brightness.values) {
      for (final paper in DemoPaper.values) {
        final palette = AppearancePaper.resolve(paper, brightness);
        expect(
          appearanceContrast(palette.ink, palette.background),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          appearanceContrast(palette.muted, palette.background),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          appearanceContrast(
            paperTheme(palette.brightness).colorScheme.primary,
            palette.background,
          ),
          greaterThanOrEqualTo(4.5),
        );
        final theme = paperTheme(brightness);
        expect(
          appearanceContrast(
            theme.colorScheme.primary,
            theme.colorScheme.onPrimary,
          ),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });

  testWidgets('换色保留备注和阅读位置；固定纸面与应用明暗独立', (tester) async {
    await host(tester);
    final draft = find.byKey(const ValueKey('appearance-draft'));
    await tester.enterText(draft, '保留这段备注');
    final scroll = tester
        .widget<SingleChildScrollView>(
          find.byKey(const PageStorageKey('appearance-reader-scroll')),
        )
        .controller!;
    scroll.jumpTo(180);
    choosePaper(tester, DemoPaper.white);
    await tester.pumpAndSettle();
    Color paperColor() =>
        (tester
                    .widget<Container>(
                      find.byKey(const ValueKey('appearance-reader')),
                    )
                    .decoration!
                as BoxDecoration)
            .color!;
    final before = paperColor();
    await tap(tester, find.byTooltip('切换深浅主题'));
    expect(find.text('阅读纸面'), findsOneWidget);
    expect(paperColor(), before);
    expect(scroll.offset, 180);
    expect(tester.widget<TextField>(draft).controller!.text, '保留这段备注');
    final fieldTheme = Theme.of(tester.element(draft));
    expect(fieldTheme.brightness, Brightness.dark);
    final border =
        fieldTheme.inputDecorationTheme.focusedBorder! as OutlineInputBorder;
    expect(
      border.borderSide.color,
      paperTheme(Brightness.dark).colorScheme.primary,
    );
    choosePaper(tester, DemoPaper.follow);
    await tester.pumpAndSettle();
    expect(paperColor(), isNot(before));
    expect(tester.takeException(), isNull);
  });

  testWidgets('PDF 原稿与插图保持原色；应用浮层使用深色', (tester) async {
    await host(tester);
    final options = tester
        .widgetList<PaperOptions>(find.byType(PaperOptions))
        .last;
    options.onChanged!('pdf');
    await tester.pumpAndSettle();
    BoxDecoration original() =>
        tester
                .widget<DecoratedBox>(
                  find.byKey(const ValueKey('appearance-original-page')),
                )
                .decoration
            as BoxDecoration;
    expect(original().color, Colors.white);
    final figure = tester
        .widget<Container>(
          find.byKey(const ValueKey('appearance-original-figure')),
        )
        .decoration;
    choosePaper(tester, DemoPaper.night);
    await tap(tester, find.byTooltip('切换深浅主题'));
    expect(original().color, Colors.white);
    expect(
      tester
          .widget<Container>(
            find.byKey(const ValueKey('appearance-original-figure')),
          )
          .decoration,
      figure,
    );
    await tap(tester, find.widgetWithText(OutlinedButton, '文献信息'));
    expect(
      Theme.of(tester.element(find.byType(PaperDialog))).brightness,
      Brightness.dark,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PaperDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('显示设置默认 sans，保存 serif 后保留备注；取消不写回', (tester) async {
    await host(tester);
    final draft = find.byKey(const ValueKey('appearance-draft'));
    await tester.enterText(draft, '字体切换保留草稿');
    expect(
      Theme.of(tester.element(draft)).textTheme.bodyLarge!.fontFamily,
      'sans-serif',
    );
    await tap(tester, find.byTooltip('显示设置'));
    await tap(tester, find.widgetWithText(TextButton, '衬线'));
    await tap(tester, find.widgetWithText(TextButton, '取消'));
    expect(
      Theme.of(tester.element(draft)).textTheme.bodyLarge!.fontFamily,
      'sans-serif',
    );
    await tap(tester, find.byTooltip('显示设置'));
    await tap(tester, find.widgetWithText(TextButton, '衬线'));
    await tap(tester, find.widgetWithText(FilledButton, '保存'));
    expect(
      Theme.of(tester.element(draft)).textTheme.bodyLarge!.fontFamily,
      'serif',
    );
    expect(tester.widget<TextField>(draft).controller!.text, '字体切换保留草稿');
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 400.0, 402.0, 1100.0]) {
    testWidgets('外观验证 $width 宽度、深色英文与两倍字号', (tester) async {
      await host(tester, width: width);
      expect(tester.takeException(), isNull);
      await tap(tester, find.byTooltip('切换深浅主题'));
      await tap(tester, find.byTooltip('切换中英文'));
      await tap(tester, find.byTooltip('Adjust text size'));
      await tap(tester, find.byTooltip('Adjust text size'));
      expect(tester.takeException(), isNull);
      await tap(tester, find.widgetWithText(OutlinedButton, 'Edit Favorite'));
      expect(find.byType(PaperDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tap(tester, find.widgetWithText(FilledButton, 'Show snackbar'));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final device in [
    ('xiaomi15', const Size(400, 890), TargetPlatform.android, 48.0),
    ('iphone17pro', const Size(402, 874), TargetPlatform.iOS, 44.0),
  ]) {
    testWidgets('${device.$1} 使用对应平台与触控尺寸', (tester) async {
      await tester.binding.setSurfaceSize(device.$2);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        NewUiDemo(page: 'appearance', mobile: true, device: device.$1),
      );
      await tester.pumpAndSettle();
      final segment = find.widgetWithText(TextButton, '自动');
      expect(Theme.of(tester.element(segment)).platform, device.$3);
      expect(tester.getSize(segment).height, greaterThanOrEqualTo(device.$4));
      expect(
        tester.getSize(find.byTooltip('显示设置')).width,
        greaterThanOrEqualTo(device.$4),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
