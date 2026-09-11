import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/core/l10n.dart';
import 'package:otter_pad/core/storage/app_database.dart';
import 'package:otter_pad/core/storage/storage.dart';
import 'package:otter_pad/pages/setting/ocr_settings_page.dart';
import 'package:otter_pad/providers/api_provider.dart';

void main() {
  late AppDatabase database;
  late Directory temp;
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    temp = await Directory.systemTemp.createTemp('otter_mineru_options_');
    await GStorage.initForTest(
      database,
      dbDirPath: temp.path,
      libraryDirPath: temp.path,
      logsDirPath: temp.path,
    );
  });
  tearDown(() async {
    await database.close();
    await temp.delete(recursive: true);
  });

  test('新增解析参数可重载并随重置恢复默认值', () async {
    final notifier = DocExtractApiNotifier();
    addTearDown(notifier.dispose);
    await notifier.setProvider(DocExtractProvider.mineru);
    await notifier.setString('mineruModelVersion', 'pipeline');
    await notifier.setString('mineruPageRanges', '2--2');
    await notifier.setString('mineruLanguage', 'japan');
    await notifier.setMineruExtraFormats(['docx', 'html']);
    notifier.reload();
    expect(notifier.state.mineruModelVersion, 'pipeline');
    expect(notifier.state.mineruPageRanges, '2--2');
    expect(notifier.state.mineruLanguage, 'japan');
    expect(notifier.state.mineruExtraFormats, ['docx', 'html']);
    await notifier.resetExceptApiKey();
    notifier.reload();
    expect(notifier.state.provider, DocExtractProvider.mineru);
    expect(notifier.state.mineruModelVersion, 'vlm');
    expect(notifier.state.mineruPageRanges, isEmpty);
    expect(notifier.state.mineruExtraFormats, isEmpty);
  });

  for (final locale in ['zh', 'en']) {
    testWidgets('MinerU 分类在 360dp 下可输入、校验和选择格式 $locale', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final notifier = DocExtractApiNotifier();
      await tester.runAsync(
        () => notifier.setProvider(DocExtractProvider.mineru),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [docExtractApiProvider.overrideWith((ref) => notifier)],
          child: MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const OcrSettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byType(TextFormField);
      await tester.ensureVisible(field);
      await tester.enterText(field, '2,4-6');
      await tester.pumpAndSettle();
      expect(notifier.state.mineruPageRanges, '2,4-6');
      await tester.enterText(field, '0');
      await tester.pumpAndSettle();
      final context = tester.element(field);
      expect(find.text(context.l10n.mineruPageRangesInvalid), findsOneWidget);
      expect(notifier.state.mineruPageRanges, '2,4-6');
      final chip = find.widgetWithText(FilterChip, 'DOCX');
      await tester.scrollUntilVisible(
        chip,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(chip);
      await tester.pumpAndSettle();
      expect(notifier.state.mineruExtraFormats, ['docx']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
