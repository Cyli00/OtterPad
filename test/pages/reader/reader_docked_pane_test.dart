import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/core/storage/app_database.dart';
import 'package:otter_pad/core/storage/storage.dart';
import 'package:otter_pad/pages/reader/widgets/reader_docked_pane.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await GStorage.initForTest(database);
  });
  tearDown(() => database.close());

  Widget host({
    required bool open,
    bool animate = true,
    bool disableAnimations = false,
    ReaderDockPane pane = ReaderDockPane.outline,
    Widget outline = const SizedBox(key: ValueKey('outline')),
    Widget notes = const SizedBox(),
    Widget chat = const SizedBox(),
    VoidCallback? onAnimationEnd,
  }) => ProviderScope(
    child: MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(
          body: Row(
            children: [
              const Expanded(child: SizedBox()),
              ReaderDockedPane(
                sidebarWidth: 360,
                open: open,
                animate: animate,
                pane: pane,
                outline: outline,
                notes: notes,
                chat: chat,
                onAnimationEnd: onAnimationEnd,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  double width(WidgetTester tester) =>
      tester.getSize(find.byType(ReaderDockedPane)).width;

  testWidgets('首次挂载打开的侧栏从零宽度连续展开', (tester) async {
    await tester.pumpWidget(host(open: true));
    expect(width(tester), 0);
    await tester.pump(const Duration(milliseconds: 80));
    expect(width(tester), inExclusiveRange(0, 360));
    await tester.pumpAndSettle();
    expect(width(tester), 360);
  });

  testWidgets('桌面侧栏切换时宽度不能在首帧直接跳到终点', (tester) async {
    await tester.pumpWidget(host(open: false));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(open: true));
    expect(width(tester), 0);
    await tester.pump(const Duration(milliseconds: 80));
    expect(width(tester), inExclusiveRange(0, 360));
  });

  testWidgets('减少动态效果时开合立即完成', (tester) async {
    await tester.pumpWidget(host(open: false, disableAnimations: true));
    await tester.pumpWidget(host(open: true, disableAnimations: true));
    expect(width(tester), 360);
    await tester.pumpWidget(host(open: false, disableAnimations: true));
    expect(width(tester), 0);
  });

  testWidgets('窗口向外展开时侧栏立即占位，回退向内展开后恢复动画', (tester) async {
    await tester.pumpWidget(host(open: false, animate: false));
    await tester.pumpWidget(host(open: true, animate: false));
    expect(width(tester), 360);
    await tester.pumpWidget(host(open: false, animate: false));
    expect(width(tester), 0);
    await tester.pumpWidget(host(open: true));
    expect(width(tester), 0);
    await tester.pump(const Duration(milliseconds: 80));
    expect(width(tester), inExclusiveRange(0, 360));
    await tester.pumpAndSettle();
    expect(width(tester), 360);
  });

  testWidgets('开合宽度逐帧单调，侧栏正文只按固定宽度布局', (tester) async {
    final widths = <double>[];
    final content = LayoutBuilder(
      builder: (context, constraints) {
        widths.add(constraints.maxWidth);
        return const SizedBox();
      },
    );
    await tester.pumpWidget(host(open: true, outline: content));
    var previous = width(tester);
    for (var i = 0; i < 70; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final current = width(tester);
      expect(current, inInclusiveRange(previous, 360));
      previous = current;
    }
    expect(previous, 360);
    expect(widths, [359]);

    await tester.pumpWidget(host(open: false, outline: content));
    for (var i = 0; i < 70; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final current = width(tester);
      expect(current, inInclusiveRange(0, previous));
      previous = current;
    }
    expect(previous, 0);
    expect(widths, [359]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('连续反向切换从当前宽度继续且最终状态正确', (tester) async {
    var completed = 0;
    Widget build(bool open) =>
        host(open: open, onAnimationEnd: () => completed++);
    await tester.pumpWidget(build(true));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 48));
      final before = width(tester);
      await tester.pumpWidget(build(i.isOdd));
      expect(width(tester), closeTo(before, 0.5));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(width(tester), 360);
    expect(completed, 1);
    await tester.pumpWidget(build(false));
    await tester.pumpAndSettle();
    expect(width(tester), 0);
    expect(completed, 2);
  });

  testWidgets('只挂载访问过的面板，切换和收起保留输入状态', (tester) async {
    const input = TextField(key: ValueKey('draft'));
    Widget build(bool open, ReaderDockPane pane) => host(
      open: open,
      pane: pane,
      outline: const Text('目录'),
      notes: const Text('笔记'),
      chat: input,
    );
    await tester.pumpWidget(build(true, ReaderDockPane.outline));
    await tester.pumpAndSettle();
    expect(find.byType(TextField, skipOffstage: false), findsNothing);
    expect(find.text('笔记', skipOffstage: false), findsNothing);
    await tester.pumpWidget(build(true, ReaderDockPane.askAi));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '保留这条草稿');
    final state = tester.state(find.byKey(const ValueKey('draft')));
    await tester.pumpWidget(build(false, ReaderDockPane.askAi));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.pumpWidget(build(true, ReaderDockPane.notes));
    await tester.pumpAndSettle();
    await tester.pumpWidget(build(true, ReaderDockPane.askAi));
    await tester.pumpAndSettle();
    expect(tester.state(find.byKey(const ValueKey('draft'))), same(state));
    expect(find.text('保留这条草稿'), findsOneWidget);
  });

  testWidgets('动画中启用减少动态效果会立即结束', (tester) async {
    await tester.pumpWidget(host(open: true));
    await tester.pump(const Duration(milliseconds: 80));
    expect(width(tester), inExclusiveRange(0, 360));
    await tester.pumpWidget(host(open: true, disableAnimations: true));
    expect(width(tester), 360);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
