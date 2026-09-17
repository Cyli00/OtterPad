import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/core/storage/app_database.dart';
import 'package:otter_pad/core/storage/storage.dart';
import 'package:otter_pad/pages/reader/widgets/reader_docked_pane.dart';
import 'package:otter_pad/pages/reader/widgets/reader_webview_viewport.dart';

void main() {
  late AppDatabase database;
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await GStorage.initForTest(database);
  });
  tearDown(() => database.close());

  const surfaceKey = ValueKey('native-surface');
  const inputKey = ValueKey('reader-state');
  Widget host({
    required bool open,
    bool reduceMotion = false,
    bool preserveSurfaceWidth = true,
    required ValueChanged<double> onWidth,
  }) => ProviderScope(
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(800, 600),
          disableAnimations: reduceMotion,
        ),
        child: Scaffold(
          body: Row(
            children: [
              Expanded(
                child: ReaderWebViewViewport(
                  onLayoutWidthChanged: onWidth,
                  preserveSurfaceWidth: preserveSurfaceWidth,
                  child: const SizedBox(
                    key: surfaceKey,
                    child: TextField(key: inputKey),
                  ),
                ),
              ),
              ReaderDockedPane(
                sidebarWidth: 360,
                open: open,
                pane: ReaderDockPane.outline,
                outline: const SizedBox(),
                notes: const SizedBox(),
                chat: const SizedBox(),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  testWidgets('侧栏开合和快速反向只改排版宽度，原生画布逐帧不缩放', (tester) async {
    final widths = <double>[];
    Widget build(bool open) => host(open: open, onWidth: widths.add);
    await tester.pumpWidget(build(false));
    final state = tester.state(find.byKey(inputKey));
    await tester.enterText(find.byKey(inputKey), '保留正文状态');
    final surface = tester.getSize(find.byKey(surfaceKey));
    for (final open in [true, false, true, false, true]) {
      await tester.pumpWidget(build(open));
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getSize(find.byKey(surfaceKey)), surface);
      }
    }
    await tester.pumpAndSettle();
    expect(widths.last, 440);
    expect(tester.getSize(find.byKey(surfaceKey)), surface);
    expect(tester.state(find.byKey(inputKey)), same(state));
    expect(find.text('保留正文状态'), findsOneWidget);
    await tester.pumpWidget(build(false));
    await tester.pumpAndSettle();
    expect(widths.last, 800);
    expect(tester.getSize(find.byKey(surfaceKey)), surface);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首次在已展开侧栏中挂载，收起仍不拉伸原生画布', (tester) async {
    final widths = <double>[];
    await tester.pumpWidget(
      host(open: true, reduceMotion: true, onWidth: widths.add),
    );
    final surface = tester.getSize(find.byKey(surfaceKey));
    expect(widths.last, 440);
    await tester.pumpWidget(
      host(open: false, reduceMotion: true, onWidth: widths.add),
    );
    expect(widths.last, 800);
    expect(tester.getSize(find.byKey(surfaceKey)), surface);
  });

  testWidgets('非桌面原生视图仍使用实际布局宽度', (tester) async {
    await tester.pumpWidget(
      host(
        open: true,
        reduceMotion: true,
        preserveSurfaceWidth: false,
        onWidth: (_) {},
      ),
    );
    expect(tester.getSize(find.byKey(surfaceKey)).width, 440);
  });
}
