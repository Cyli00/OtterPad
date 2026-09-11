import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/core/l10n.dart';
import 'package:otter_pad/providers/api_provider.dart';
import 'package:otter_pad/widgets/extract_provider_dialog.dart';

void main() {
  testWidgets('360dp 重新排版选择已保存来源，取消不选择', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    DocExtractProvider? result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('打开'),
              onPressed: () async {
                result = await showReprocessSourceDialog(
                  context: context,
                  sources: DocExtractProvider.values,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MinerU'));
    await tester.pumpAndSettle();
    expect(result, DocExtractProvider.mineru);
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final locale in ['zh', 'en']) {
    testWidgets('360dp 选择本次 OCR 接口，取消不启动任务 $locale', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      const initial = DocExtractApiState(mineruLanguage: 'japan');
      DocExtractApiState? result;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showExtractProviderDialog(
                    context: context,
                    apiState: initial,
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MinerU'));
      await tester.pumpAndSettle();
      final l10n = tester.element(find.byType(AlertDialog)).l10n;
      await tester.tap(find.text(l10n.confirm));
      await tester.pumpAndSettle();
      expect(result?.provider, DocExtractProvider.mineru);
      expect(result?.mineruLanguage, 'japan');
      expect(initial.provider, DocExtractProvider.paddle);
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
