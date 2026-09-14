import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newui_ai_demo/main.dart';
import 'package:newui_ai_demo/paper_widgets.dart';

void main() {
  Future<void> host(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const NewUiDemo());
    await tester.pumpAndSettle();
  }

  for (final width in [390.0, 700.0, 1440.0, 1720.0]) {
    testWidgets('$width 宽度下中英文、深色和两倍文字均不溢出', (tester) async {
      await host(tester, Size(width, 1100));
      expect(find.byType(PaperSection), findsNWidgets(3));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('切换深浅主题'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('切换中英文'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('Adjust text size'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.ensureVisible(find.byType(PaperSlider).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('译文样式单选，忽略内容多选，重置不改变其他字段', (tester) async {
    await host(tester, const Size(1440, 1100));
    Future<void> choose(String label) async {
      final f = find.byWidgetPredicate(
        (w) => w is PaperChoice && w.label == label,
      );
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    bool selected(String label) => tester
        .widget<PaperChoice>(
          find.byWidgetPredicate((w) => w is PaperChoice && w.label == label),
        )
        .selected;
    await choose('加粗');
    expect(selected('加粗'), isTrue);
    expect(selected('主题色'), isFalse);
    await choose('致谢');
    expect(selected('致谢'), isTrue);
    expect(selected('参考文献'), isTrue);
    final slider = find.byType(Slider).first;
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    tester.widget<Slider>(slider).onChanged!(0.75);
    await tester.pumpAndSettle();
    expect(find.text('0.75'), findsOneWidget);
    await tester.tap(find.byTooltip('重置温度'));
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(slider).value, 0);
    expect(selected('加粗'), isTrue);
    expect(selected('致谢'), isTrue);
  });

  testWidgets('用户模板就地校验，切换主题和语言仍保留草稿', (tester) async {
    await host(tester, const Size(1440, 1100));
    final input = find.byKey(const ValueKey('user-prompt'));
    await tester.ensureVisible(input);
    await tester.pumpAndSettle();
    await tester.enterText(input, '保留草稿');
    await tester.pumpAndSettle();
    expect(find.textContaining('当前内容未生效'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('切换中英文'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('切换中英文'));
    await tester.pumpAndSettle();
    final next = tester.widget<TextField>(
      find.byKey(const ValueKey('user-prompt')),
    );
    expect(next.controller!.text, '保留草稿');
    expect(next.decoration!.errorText, contains('not active'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('密钥显隐和输入焦点可用，值不因重建清空', (tester) async {
    await host(tester, const Size(1440, 1100));
    final keyField = find.byKey(const ValueKey('api-key'));
    await tester.enterText(keyField, 'local-demo-only');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(keyField).obscureText, isTrue);
    await tester.tap(find.byTooltip('显示 API Key').first);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(keyField).obscureText, isFalse);
    expect(
      tester.widget<TextField>(keyField).controller!.text,
      'local-demo-only',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('窄屏选择器可以切换提供商，并保留独立草稿', (tester) async {
    await host(tester, const Size(390, 900));
    final input = find.byKey(const ValueKey('api-key'));
    await tester.ensureVisible(input);
    await tester.pumpAndSettle();
    await tester.enterText(input, 'local-demo-only');
    await tester.pumpAndSettle();
    Future<void> change(String from, String to) async {
      final button = find.widgetWithText(OutlinedButton, from).first;
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(to).last);
      await tester.pumpAndSettle();
    }

    await change('OpenAI Compatible', 'Anthropic');
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    await change('Anthropic', 'OpenAI Compatible');
    expect(tester.widget<TextField>(input).controller!.text, 'local-demo-only');
    expect(tester.widget<TextField>(input).obscureText, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('译文样式向读屏提供单选语义，忽略项提供多选语义', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await host(tester, const Size(1440, 1100));
      for (final label in ['加粗', '致谢']) {
        final f = find.byWidgetPredicate(
          (w) => w is PaperChoice && w.label == label,
        );
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        final data = tester.getSemantics(f).getSemanticsData();
        expect(data.flagsCollection.isInMutuallyExclusiveGroup, label == '加粗');
      }
    } finally {
      semantics.dispose();
    }
  });
  testWidgets('说明仅在标题问号打开，键盘 Escape 关闭且不重排字段', (tester) async {
    await host(tester, const Size(390, 1100));
    final field = find.byKey(const ValueKey('api-key'));
    final help = find.byWidgetPredicate(
      (w) => w is PaperHelp && w.message.startsWith('演示无需真实密钥'),
    );
    await tester.ensureVisible(help);
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(field);
    expect(find.text('演示无需真实密钥。输入仅保留在当前页面。'), findsNothing);
    final button = find.descendant(of: help, matching: find.byType(IconButton));
    final focus = tester.widget<IconButton>(button).focusNode!;
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('演示无需真实密钥。输入仅保留在当前页面。'), findsOneWidget);
    expect(tester.getTopLeft(field), before);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('演示无需真实密钥。输入仅保留在当前页面。'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('获取模型原位加载、禁用重复请求、更新目录并保留选择', (tester) async {
    await host(tester, const Size(1440, 1100));
    final button = find.byKey(const ValueKey('fetch-models'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    final before = tester.getSize(button);
    await tester.tap(button);
    await tester.pump();
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    expect(find.text('正在加载演示模型…'), findsOneWidget);
    expect(tester.getSize(button), before);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.text('已获取 4 个演示模型'), findsOneWidget);
    final select = tester.widget<PaperSelect>(
      find.byWidgetPredicate((w) => w is PaperSelect && w.label == '模型'),
    );
    expect(select.options, contains('demo/research-model'));
    expect(select.value, 'deepseek/deepseek-v4.1-flash');
    expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
  });

  testWidgets('无效地址给出重试，切换提供商会丢弃旧获取结果', (tester) async {
    await host(tester, const Size(1440, 1100));
    final endpoint = find.byKey(const ValueKey('endpoint'));
    final button = find.byKey(const ValueKey('fetch-models'));
    await tester.enterText(endpoint, 'invalid');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.textContaining('未能获取模型'), findsOneWidget);
    expect(find.text('重试获取'), findsOneWidget);
    await tester.enterText(endpoint, 'https://api.example.com/v1');
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();
    final provider = tester.widget<PaperSelect>(
      find.byWidgetPredicate(
        (w) => w is PaperSelect && w.value == 'OpenAI Compatible',
      ),
    );
    provider.onChanged('Anthropic');
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.textContaining('已获取'), findsNothing);
    expect(find.text('本地演示目录 · 不发送网络请求'), findsOneWidget);
    await tester.tap(button);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.text('已获取 4 个演示模型'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('三种模型角色有独立图标、名称和帮助，当前模型值始终可见', (tester) async {
    await host(tester, const Size(1440, 1100));
    for (final role in PaperModelRole.values) {
      final icon = find.byWidgetPredicate(
        (w) => w is PaperRoleIcon && w.role == role,
      );
      expect(icon, findsOneWidget);
      final row = tester.widget<PaperFieldRow>(
        find.ancestor(of: icon, matching: find.byType(PaperFieldRow)),
      );
      expect(row.label, isNotEmpty);
      expect(row.hint, isNotEmpty);
      expect((row.child as PaperSelect).value, isNotEmpty);
    }
  });
}
