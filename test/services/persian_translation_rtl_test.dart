import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/pages/reader2/reader_layout.dart';
import 'package:otter_pad/providers/translation_config_provider.dart';
import 'package:otter_pad/services/translation_bidi.dart';
import 'package:otter_pad/src/rust/api/document.dart';
import 'package:otter_pad/src/rust/document.dart';

// Issue #3: Persian output must stay right-aligned without disturbing
// formulas or tables. The prompt guard is covered by the Rust translate tests.
void main() {
  test('Persian joins the target languages and is right to left', () {
    expect(kTargetLanguages, contains('فارسی'));
    expect(kRtlTargetLanguages, containsAll(['فارسی', 'العربية']));
    for (final language in kRtlTargetLanguages) {
      expect(kTargetLanguages, contains(language));
      expect(isRtlTargetLanguage(language), isTrue);
    }
    expect(isRtlTargetLanguage('English'), isFalse);
    expect(isRtlTargetLanguage('中文(简体)'), isFalse);
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
  });

  testWidgets('only translated blocks are laid out right to left', (
    tester,
  ) async {
    Block block(String id, String text) => Block(
      id: id,
      kind: BlockKind.paragraph,
      sourceRegions: const [],
      text: text,
      markdown: text,
      revision: id,
      runs: [
        InlineRun(
          text: text,
          bold: false,
          italic: false,
          code: false,
          strike: false,
        ),
      ],
    );
    final model = ReaderDocument(
      version: 1,
      blocks: [block('b1', 'Energy'), block('b1#t', 'انرژی')],
      translationKeys: const ['', ''],
      figures: const [],
      figureAssets: const [],
      figureImages: const [],
      assetDirectory: '',
    );
    final typesetter = ReaderTypesetter();
    addTearDown(typesetter.dispose);
    final layout = typesetter.layout(
      model,
      const ReaderLayoutSpec(
        width: 400,
        pageHeight: 600,
        body: TextStyle(fontSize: 16),
        mutedColor: Colors.grey,
        linkColor: Colors.blue,
        ruleColor: Colors.grey,
        rtlTranslations: true,
      ),
    );
    expect(layout.items.map((i) => i.direction), [
      TextDirection.ltr,
      TextDirection.rtl,
    ]);
  });
}
