import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/services/translation_highlight_parser.dart';

void main() {
  group('findInFullText', () {
    test('直接匹配', () {
      final r = TranslationHighlightParser.findInFullText(
        'abc def ghi',
        'def',
      );
      expect(r, (4, 7));
    });

    test('跨段落空白差异仍能匹配', () {
      final r = TranslationHighlightParser.findInFullText(
        'hello\n\nworld',
        'helloworld',
      );
      expect(r, isNotNull);
      expect(r!.$1, 0);
      expect(r.$2, 12);
    });

    test('不存在返回 null', () {
      final r = TranslationHighlightParser.findInFullText('abc', 'xyz');
      expect(r, isNull);
    });
  });

  group('buildSegmentedInput', () {
    test('选区在中间 → 3 段', () {
      final r = TranslationHighlightParser.buildSegmentedInput(
        'before selected after',
        'selected',
      );
      expect(r.hlSegmentIndex, 1);
      expect(r.text, contains('%%%%'));
      expect(r.text.split('\n%%%%\n').length, 3);
    });

    test('选区在开头 → 2 段（无 before）', () {
      final r = TranslationHighlightParser.buildSegmentedInput(
        'selected after',
        'selected',
      );
      expect(r.hlSegmentIndex, 0);
      expect(r.text.split('\n%%%%\n').length, 2);
    });

    test('选区在末尾 → 2 段（无 after）', () {
      final r = TranslationHighlightParser.buildSegmentedInput(
        'before selected',
        'selected',
      );
      expect(r.hlSegmentIndex, 1);
      expect(r.text.split('\n%%%%\n').length, 2);
    });

    test('选区 = 全文 → 1 段', () {
      final r = TranslationHighlightParser.buildSegmentedInput(
        'entire text',
        'entire text',
      );
      // fullText == sourceText → 走 _hasHighlight=false 分支，不该到这里
      // 但如果调用了，range 会匹配整个文本，before/after 都空
      expect(r.hlSegmentIndex, 0);
    });

    test('找不到选区 → 原文返回', () {
      final r = TranslationHighlightParser.buildSegmentedInput(
        'some text',
        'missing',
      );
      expect(r.hlSegmentIndex, -1);
      expect(r.text, 'some text');
    });
  });

  group('parse 流式输出', () {
    test('无分隔模式（hlSegmentIndex=-1）→ 原文无高亮', () {
      final r = TranslationHighlightParser.parse('翻译文本', -1);
      expect(r.text, '翻译文本');
      expect(r.hlStart, isNull);
      expect(r.hlEnd, isNull);
    });

    test('流完成：3 段正确分割和高亮', () {
      final r = TranslationHighlightParser.parse(
        '前段\n%%%%\n高亮段\n%%%%\n后段',
        1,
      );
      expect(r.text, '前段高亮段后段');
      expect(r.hlStart, 2);
      expect(r.hlEnd, 5);
    });

    // ── 流式中间态 ──

    test('流式：分隔符尚未到达 → 无高亮', () {
      final r = TranslationHighlightParser.parse('前段翻译中', 1);
      expect(r.text, '前段翻译中');
      expect(r.hlStart, isNull);
    });

    test('流式：半截 %% 不应暴露给用户', () {
      final r = TranslationHighlightParser.parse('前段翻译%%', 1);
      // BUG: 当前实现会返回 "前段翻译%%" —— %% 可见
      expect(r.text, isNot(contains('%%')),
          reason: '半截分隔符不应出现在显示文本中');
    });

    test('流式：第一个 %%%% 到达，第二个未到 → 高亮从分隔后开始', () {
      final r = TranslationHighlightParser.parse(
        '前段\n%%%%\n高亮中间',
        1,
      );
      expect(r.text, '前段高亮中间');
      expect(r.hlStart, 2);
      expect(r.hlEnd, 6);
    });

    test('选区在开头（hlSegmentIndex=0）→ 第一个 token 就有高亮', () {
      final r = TranslationHighlightParser.parse('高亮开始', 0);
      expect(r.text, '高亮开始');
      expect(r.hlStart, 0);
      expect(r.hlEnd, 4);
    });

    test('选区在开头，第一个 %%%% 到达 → 高亮正确截断', () {
      final r = TranslationHighlightParser.parse(
        '高亮段\n%%%%\n后段',
        0,
      );
      expect(r.text, '高亮段后段');
      expect(r.hlStart, 0);
      expect(r.hlEnd, 3);
    });

    test('流式：单个 % 不应暴露', () {
      final r = TranslationHighlightParser.parse('前段翻译%', 1);
      expect(r.text, isNot(contains('%')));
    });

    test('流式：3 个 %%% 不应暴露', () {
      final r = TranslationHighlightParser.parse('前段翻译%%%', 1);
      expect(r.text, isNot(contains('%')));
    });

    test('LLM 不输出分隔符 → 全文无高亮', () {
      final r = TranslationHighlightParser.parse(
        '前段翻译高亮翻译后段翻译',
        1,
      );
      expect(r.text, '前段翻译高亮翻译后段翻译');
      expect(r.hlStart, isNull);
    });

    test('%%%% 无换行包围也能正确分割', () {
      final r = TranslationHighlightParser.parse(
        '前段%%%%高亮段%%%%后段',
        1,
      );
      expect(r.text, '前段高亮段后段');
      expect(r.hlStart, 2);
      expect(r.hlEnd, 5);
    });

    test('文本内容含百分号不会被误剥离', () {
      // 完整 3 段模式下，文本中的 % 不应被剥离
      final r = TranslationHighlightParser.parse(
        '增长了50%\n%%%%\n选中段\n%%%%\n后段',
        1,
      );
      expect(r.text, contains('50%'));
      expect(r.hlStart, isNotNull);
    });
  });
}
