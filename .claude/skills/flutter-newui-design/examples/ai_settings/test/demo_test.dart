import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:newui_ai_demo/default_widgets_demo.dart';
import 'package:newui_ai_demo/main.dart';
import 'package:newui_ai_demo/paper_favorite_card.dart';
import 'package:newui_ai_demo/paper_widgets.dart';

void main() {
  Future<void> host(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const NewUiDemo());
    await tester.pumpAndSettle();
  }

  Future<void> hostWidgets(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const NewUiDemo(page: 'widgets'));
    await tester.pumpAndSettle();
  }

  Future<void> openEditor(WidgetTester tester) async {
    final entry = find.byTooltip('编辑收藏夹');
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(FavoriteEditorDemo), findsOneWidget);
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
    expect(tester.widget<IconButton>(button).onPressed, isNull);
    expect(find.text('正在加载演示模型…'), findsOneWidget);
    expect(tester.getSize(button), before);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.text('已获取 4 个演示模型'), findsOneWidget);
    final card = tester.widget<PaperModelCard>(
      find.byWidgetPredicate(
        (w) => w is PaperModelCard && w.model == 'deepseek/deepseek-v4.1-flash',
      ),
    );
    expect(
      find.byKey(const ValueKey('model-card-demo/research-model')),
      findsOneWidget,
    );
    expect(card.selected, isTrue);
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);
  });

  testWidgets('模型卡片可切换当前模型，获取 API Key 在标题栏提供反馈', (tester) async {
    await host(tester, const Size(1440, 1100));
    final next = find.byKey(const ValueKey('model-card-claude-sonnet-4'));
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PaperModelCard>(
            find.byWidgetPredicate(
              (w) => w is PaperModelCard && w.model == 'claude-sonnet-4',
            ),
          )
          .selected,
      isTrue,
    );
    final apiKeyButton = find.byKey(const ValueKey('get-api-key'));
    await tester.ensureVisible(apiKeyButton);
    expect(tester.widget<IconButton>(apiKeyButton).tooltip, '获取 API Key');
    await tester.tap(apiKeyButton);
    await tester.pumpAndSettle();
    expect(find.text('演示不连接外部服务商，请在服务商控制台获取 API Key。'), findsOneWidget);
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
    expect(find.byTooltip('重试获取'), findsOneWidget);
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
      final card = tester.widget<PaperRoleCard>(
        find.byWidgetPredicate((w) => w is PaperRoleCard && w.role == role),
      );
      expect(card.title, isNotEmpty);
      expect(card.help, isNotEmpty);
      expect(card.value, isNotEmpty);
    }
  });

  testWidgets('收藏夹编辑器：直接选 emoji，空名禁用保存并给出占位预览', (tester) async {
    await hostWidgets(tester, const Size(1440, 1100));
    await openEditor(tester);
    expect(find.text('选择图标'), findsOneWidget);
    expect(find.text('收藏夹名称'), findsOneWidget);
    expect(find.text('效果预览'), findsOneWidget);
    // 目录一次全部展开，没有分类层级：📚 出现在图标格、预览与页面卡片
    expect(find.text('\u{1F4DA}'), findsNWidgets(3));
    expect(find.text('\u{1F52C}'), findsOneWidget);
    await tester.tap(find.text('\u{1F52C}'));
    await tester.pumpAndSettle();
    expect(find.text('\u{1F52C}'), findsNWidgets(2));
    expect(find.text('\u{1F4DA}'), findsNWidgets(2));
    // 空名：保存禁用、预览给出占位名，主动清空不显示错误
    final save = find.widgetWithText(FilledButton, '保存');
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.tap(find.byTooltip('清空'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(find.text('0 / 20'), findsOneWidget);
    expect(find.text('未命名'), findsOneWidget);
    expect(find.text('请输入收藏夹名称'), findsNothing);
    // 输入后再删空：就地校验，不关闭弹窗
    final field = find.byKey(const ValueKey('favorite-name'));
    await tester.enterText(field, '读书');
    await tester.pumpAndSettle();
    expect(find.text('2 / 20'), findsOneWidget);
    await tester.enterText(field, '');
    await tester.pumpAndSettle();
    expect(find.text('请输入收藏夹名称'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('收藏夹编辑器：保存后名称与 emoji 写入对应卡片', (tester) async {
    await hostWidgets(tester, const Size(1440, 1100));
    await openEditor(tester);
    await tester.tap(find.text('\u{1F52C}'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('favorite-name')),
      '演示新收藏夹',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.byType(FavoriteEditorDemo), findsNothing);
    final card = tester.widget<PaperFavoriteCard>(
      find.byKey(const ValueKey('favorite-0')),
    );
    expect(card.title, '演示新收藏夹');
    expect(card.emoji, '\u{1F52C}');
    expect(find.text('收藏夹已在本页更新'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
