import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newui_ai_demo/main.dart';
import 'package:newui_ai_demo/paper_favorite_card.dart';
import 'package:newui_ai_demo/paper_surfaces.dart';
import 'package:newui_ai_demo/paper_widgets.dart';

void main() {
  Future<void> host(
    WidgetTester tester,
    String page, {
    bool mobile = false,
  }) async {
    await tester.binding.setSurfaceSize(Size(mobile ? 390 : 1100, 960));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(NewUiDemo(page: page, mobile: mobile));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  for (final page in ['backup', 'widgets']) {
    for (final mobile in [false, true]) {
      testWidgets('$page / mobile=$mobile 深浅色双语与两倍文字无溢出', (tester) async {
        await host(tester, page, mobile: mobile);
        expect(tester.takeException(), isNull);
        await tap(tester, find.byTooltip('切换深浅主题'));
        await tap(tester, find.byTooltip('切换中英文'));
        await tap(tester, find.byTooltip('Adjust text size'));
        await tap(tester, find.byTooltip('Adjust text size'));
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byType(PaperSection).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final action = page == 'backup'
            ? find.byWidgetPredicate(
                (w) => w is PaperActionRow && w.action != null,
              )
            : find.byType(PaperActionRow).at(1);
        tester.widget<PaperActionRow>(action).onTap!();
        await tester.pumpAndSettle();
        expect(find.byType(PaperDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      });
    }
  }
  testWidgets('数据管理保留分组、平台入口和自动备份范围', (tester) async {
    await host(tester, 'backup');
    expect(find.byType(PaperSection), findsNWidgets(4));
    final local = find.byWidgetPredicate(
      (w) => w is PaperActionRow && w.icon == Symbols.computer,
    );
    expect(local, findsOneWidget);
    final choices = tester.widget<PaperOptions>(
      find.byType(PaperOptions).at(1),
    );
    expect(choices.value, 'off');
    choices.onChanged!('daily');
    await tester.pumpAndSettle();
    expect(find.byType(PaperOptions), findsNWidgets(3));
    await tester.pumpWidget(const SizedBox());
    await host(tester, 'backup', mobile: true);
    expect(find.byType(PaperSection), findsNWidgets(4));
    expect(
      find.byWidgetPredicate(
        (w) => w is PaperActionRow && w.title == '本机 Zotero',
      ),
      findsNothing,
    );
    expect(local, findsNothing);
  });
  testWidgets('远程配置校验、取消与保存，S3 和 WebDAV 草稿相互独立', (tester) async {
    await host(tester, 'backup');
    await tap(tester, find.widgetWithText(OutlinedButton, '配置'));
    await tap(tester, find.widgetWithText(FilledButton, '保存'));
    expect(find.text('请完善配置'), findsOneWidget);
    await tap(tester, find.widgetWithText(OutlinedButton, '填入演示配置'));
    await tap(tester, find.widgetWithText(FilledButton, '保存'));
    expect(find.byType(PaperDialog), findsNothing);
    expect(find.textContaining('https://backup.example.com'), findsOneWidget);
    final remote = tester.widget<PaperOptions>(find.byType(PaperOptions).first);
    remote.onChanged!('WebDAV');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, '配置'), findsOneWidget);
    await tap(tester, find.widgetWithText(OutlinedButton, '配置'));
    await tap(tester, find.widgetWithText(OutlinedButton, '填入演示配置'));
    await tap(tester, find.widgetWithText(TextButton, '取消'));
    expect(find.widgetWithText(OutlinedButton, '配置'), findsOneWidget);
    tester.widget<PaperOptions>(find.byType(PaperOptions).first).onChanged!(
      'S3',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('https://backup.example.com'), findsOneWidget);
  });
  testWidgets('收藏夹取消不写回，空名称禁用，保存只更新目标卡片', (tester) async {
    await host(tester, 'widgets', mobile: true);
    final main = find.byKey(const ValueKey('favorite-0'));
    final second = find.byKey(const ValueKey('favorite-1'));
    tester.widget<PaperFavoriteCard>(second).onEdit();
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('favorite-name')), '');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(const ValueKey('favorite-name')), '研究草稿');
    await tap(tester, find.widgetWithText(TextButton, '取消'));
    expect(tester.widget<PaperFavoriteCard>(second).title, '研究方法');
    tester.widget<PaperFavoriteCard>(second).onEdit();
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('favorite-name')), '研究草稿');
    await tap(tester, find.widgetWithText(FilledButton, '保存'));
    expect(tester.widget<PaperFavoriteCard>(second).title, '研究草稿');
    expect(tester.widget<PaperFavoriteCard>(main).title, '我的收藏');
    expect(tester.takeException(), isNull);
  });
  testWidgets('收藏夹六种封面布局保持身份，移除不影响邻居且可撤销', (tester) async {
    await host(tester, 'widgets');
    final main = find.byKey(const ValueKey('favorite-0'));
    for (final count in [0, 1, 2, 3, 4, 8]) {
      tester
          .widget<PaperOptions>(
            find.byWidgetPredicate(
              (w) => w is PaperOptions && w.options.containsKey('8'),
            ),
          )
          .onChanged!('$count');
      await tester.pumpAndSettle();
      expect(tester.widget<PaperFavoriteCard>(main).count, count);
      expect(tester.takeException(), isNull);
    }
    tester.widget<PaperFavoriteCard>(main).onDelete();
    await tester.pumpAndSettle();
    await tap(tester, find.widgetWithText(TextButton, '删除'));
    expect(main, findsNothing);
    expect(find.byType(PaperFavoriteCard), findsNWidgets(2));
    await tap(tester, find.widgetWithText(OutlinedButton, '撤销'));
    expect(main, findsOneWidget);
    expect(tester.widget<PaperFavoriteCard>(main).count, 8);
  });
  testWidgets('文献信息对话框与底部面板可打开和关闭', (tester) async {
    await host(tester, 'widgets', mobile: true);
    await tap(tester, find.byTooltip('文献信息'));
    expect(find.byType(PaperDialog), findsOneWidget);
    expect(find.text('10.0000/otterpad.demo'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PaperDialog), findsNothing);
    await tap(tester, find.byTooltip('文献操作面板'));
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });
  testWidgets('进度 Snackbar 可以取消并回到结果状态', (tester) async {
    await host(tester, 'widgets');
    final start = find.widgetWithText(OutlinedButton, '多任务进度');
    await tester.ensureVisible(start);
    await tester.pumpAndSettle();
    await tester.tap(start);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('2 个演示任务进行中'), findsOneWidget);
    final cancel = find.descendant(
      of: find.byType(SnackBar),
      matching: find.text('取消'),
    );
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(find.text('演示任务已取消'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.textContaining('任务进行中'), findsNothing);
  });
}
