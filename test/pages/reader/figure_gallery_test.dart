import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:otter_pad/core/l10n.dart';
import 'package:otter_pad/pages/reader/widgets/figure_viewer.dart';
import 'package:otter_pad/pages/reader/widgets/outline_panel.dart';
import 'package:otter_pad/providers/summary_image_provider.dart';
import 'package:otter_pad/services/figure_extract_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late FigureManifestEntry figure;
  setUp(() async {
    final output = await Directory('build/figure-review').create(recursive: true);
    dir = await output.createTemp('gallery_');
    final images = await Directory(p.join(dir.path, 'figures')).create();
    final file = File(p.join(images.path, 'same.png'));
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 100, 40), ui.Paint()..color = const ui.Color(0xFF336699));
    final picture = recorder.endRecording();
    final image = await picture.toImage(100, 40);
    await file.writeAsBytes((await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
    image.dispose(); picture.dispose();
    figure = FigureManifestEntry(id: 'stable-result', imagePath: file.path,
      captionText: 'Unnumbered results with a long explanation. ' * 8,
      pageIndex: 0, blockIds: ['body', 'caption']);
    await File(p.join(images.path, 'figures.json')).writeAsString(
      FigureExtractService.encodeManifest([figure], p.join(dir.path, 'source.pdf')));
  });
  tearDown(() async {
    // Flutter's Windows FileImage may retain a mapped buffer until engine exit.
    // These fixtures intentionally live under build/ for visual inspection.
  });

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
  }

  Future<void> flushIo(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds: 40)); });
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Widget host(Widget child) => ProviderScope(child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child)));

  testWidgets('360dp gallery displays the unnumbered caption without overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(FigureViewer(figures: [figure])));
    await flushIo(tester);
    expect(find.byType(FigureViewer), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('outline uses the stable anchor even when the filename occurs earlier', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final summary = ValueNotifier(const SummaryImageState());
    addTearDown(summary.dispose);
    final markdown = 'same.png mentioned in prose\n\n${figure.markdownAnchor}\n\n'
        '![fig:${figure.captionText}](${Uri.file(figure.imagePath)})';
    int? location;
    await tester.pumpWidget(host(OutlinePanel(markdownContent: markdown,
      documentId: p.join(dir.path, 'source.pdf'), summaryImageState: summary,
      onNavigate: (offset) => location = offset)));
    await flushIo(tester);
    await tester.ensureVisible(find.byIcon(Symbols.article_rounded));
    await tester.tap(find.byIcon(Symbols.article_rounded));
    expect(location, markdown.indexOf(figure.markdownAnchor));
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
}
