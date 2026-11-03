import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/pages/reader/widgets/reader_background.dart';
import 'package:otter_pad/pages/reader/widgets/reader_pdf_typesetting.dart';
import 'package:otter_pad/pages/reader/widgets/webview_reader_html.dart';
import 'package:otter_pad/providers/reader_settings_provider.dart';
import 'package:otter_pad/providers/translation_config_provider.dart';
import 'package:otter_pad/services/prompts.dart';
import 'package:otter_pad/services/translation_bidi.dart';

// Issue #3: Persian output must stay right-aligned without disturbing
// formulas or tables.
void main() {
  const palette = ReaderPalette(
    background: Color(0xFFFFFFFF),
    text: Color(0xFF111111),
    secondaryText: Color(0xFF666666),
    link: Color(0xFF3366CC),
    divider: Color(0xFFDDDDDD),
    codeBlock: Color(0xFFF4F4F4),
  );

  test('Persian joins the target languages and is right to left', () {
    expect(kTargetLanguages, contains('فارسی'));
    expect(kRtlTargetLanguages, containsAll(['فارسی', 'العربية']));
    for (final language in kRtlTargetLanguages) {
      expect(kTargetLanguages, contains(language));
      expect(isRtlTargetLanguage(language), isTrue);
    }
    expect(isRtlTargetLanguage('English'), isFalse);
    expect(isRtlTargetLanguage('中文(简体)'), isFalse);
    expect(Prompts.translationRtlGuard, contains('formulas'));
    expect(Prompts.translationRtlGuard, contains('Markdown tables'));
  });

  test('formulas and tables stay left to right inside Persian prose', () {
    const formula = r'$E = mc^2$';
    final text = isolateLtrFragments(
      'مقدار $formula در جدول\n'
      '| a | b |\n'
      '| --- | --- |\n'
      '| 1 | 2 |\n',
    );
    expect(text, contains('\u2066$formula\u2069'));
    expect(text, isNot(contains('\u2066مقدار')));
    final tableAt = text.indexOf('\u2066| a | b |');
    expect(tableAt, greaterThan(0));
    final table = text.substring(tableAt);
    expect(table, contains('| 1 | 2 |'));
    expect(table.indexOf('\u2069'), greaterThan(table.indexOf('| 1 | 2 |')));
    expect(
      isolateLtrFragments(r'قبل $$x + y$$ بعد'),
      'قبل \u2066\$\$x + y\$\$\u2069 بعد',
    );
  });

  test('Persian reader cell is RTL while formulas and tables stay LTR', () {
    const id = 'p1';
    final key = base64Url.encode(utf8.encode(id));
    // `$\frac$` 不会被预处理器降级成纯文本，才能留在公式节点里。
    const translation = r'''متن $\frac{a}{b}$ است

| colPersian | b |
| --- | --- |
| $\frac{a}{b}$ | 1 |''';
    final html = buildReaderHtml(
      markdownContent:
          '<!-- reader-pair:$key -->\n\nHello\n\n<!-- reader-end -->\n',
      palette: palette,
      settings: const ReaderSettingsState(),
      baseHref: '/',
      serverRoot: '/tmp',
      readerEntries: [
        {
          'id': id,
          'translated': translation,
          'html': buildReaderTranslationHtml(translation),
          'language': 'فارسی',
          'rtl': true,
          'showSource': true,
          'showTranslation': true,
          'bilingual': true,
        },
      ],
    );

    expect(
      RegExp(
        'data-language="فارسی"[^>]*dir="rtl"|dir="rtl"[^>]*data-language="فارسی"',
      ).hasMatch(html),
      isTrue,
    );
    expect(RegExp('dir="rtl"').allMatches(html), hasLength(1));
    expect(html, contains('class="math-inline"'));
    expect(html, contains('dir="ltr"'));
    expect(html, contains(r'$\frac{a}{b}$'));
    expect(html, contains('colPersian'));
    final table = RegExp('<table\\b[^>]*>').firstMatch(html);
    expect(table, isNotNull);
    expect(table!.group(0), isNot(contains('rtl')));
    expect(RegExp('data-language="source"[^>]*dir=').hasMatch(html), isFalse);

    final css = File('assets/reader/reader.css').readAsStringSync();
    expect(css, contains('.reader-language[dir="rtl"]'));
    expect(css, contains('unicode-bidi: isolate'));
    expect(css, contains('table, pre, code, .math-inline'));

    const english = r'Hello $\frac{a}{b}$';
    final englishHtml = buildReaderHtml(
      markdownContent:
          '<!-- reader-pair:$key -->\n\nHello\n\n<!-- reader-end -->\n',
      palette: palette,
      settings: const ReaderSettingsState(),
      baseHref: '/',
      serverRoot: '/tmp',
      readerEntries: [
        {
          'id': id,
          'translated': english,
          'html': buildReaderTranslationHtml(english),
          'language': 'English',
          'rtl': false,
          'showSource': true,
          'showTranslation': true,
          'bilingual': true,
        },
      ],
    );
    expect(englishHtml, isNot(contains('dir="rtl"')));
    expect(englishHtml, contains('dir="ltr"'));
  });

  test('display math is an LTR block', () {
    final html = buildReaderTranslationHtml('\$\$\nE = mc^2\n\$\$');
    expect(html, contains('math-display'));
    expect(html, contains('dir="ltr"'));
    expect(html, isNot(contains('dir="rtl"')));
  });

  testWidgets(
    'Persian PDF text sits on the right and the formula stays between the words',
    (tester) async {
      const mixed = r'سلام $x+y$ دنیا';
      final typeset = await tester.runAsync(
        () => ReaderTypesetText.fit(
          text: mixed,
          source: 'Hello world today',
          rect: const Rect.fromLTWH(0, 0, 420, 140),
          heading: false,
          style: const TextStyle(fontSize: 18, color: Color(0xFF000000)),
          textDirection: TextDirection.rtl,
          minFontScale: 0,
        ),
      );
      expect(typeset, isNotNull);
      addTearDown(typeset!.dispose);
      final first = typeset.charRects.first;
      final last = typeset.charRects[mixed.length - 1];
      final formula = typeset.charRects[mixed.indexOf('x')];
      expect(first.isEmpty, isFalse, reason: 'first glyph has no box');
      expect(last.isEmpty, isFalse, reason: 'last glyph has no box');
      expect(formula.isEmpty, isFalse, reason: 'formula has no box');
      expect(first.center.dx, greaterThan(formula.center.dx));
      expect(formula.center.dx, greaterThan(last.center.dx));
      for (final rect in typeset.charRects) {
        if (rect.isEmpty) continue;
        expect(rect.left, greaterThanOrEqualTo(-1));
        expect(rect.right, lessThanOrEqualTo(421));
      }

      const english = 'Hello world';
      final ltr = await tester.runAsync(
        () => ReaderTypesetText.fit(
          text: english,
          source: english,
          rect: const Rect.fromLTWH(0, 0, 420, 80),
          heading: false,
          style: const TextStyle(fontSize: 18, color: Color(0xFF000000)),
          minFontScale: 0,
        ),
      );
      expect(ltr, isNotNull);
      addTearDown(ltr!.dispose);
      expect(
        ltr.charRects.first.center.dx,
        lessThan(ltr.charRects[english.length - 1].center.dx),
      );
    },
  );
}
