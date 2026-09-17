import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/pages/reader/widgets/reader_pdf_document.dart';
import 'package:otter_pad/services/reader/reader_document_index.dart';
import 'package:otter_pad/services/document_structure.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  testWidgets('双语切换按源页复用文字与布局，不按旧槽位借用另一页缓存', (tester) async {
    await tester.runAsync(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => Directory.systemTemp.path,
          );
      await pdfrxFlutterInitialize();
      final directory = await Directory.systemTemp.createTemp(
        'otter-reader-cache-',
      );
      final file = File('${directory.path}/two-pages.pdf');
      await file.writeAsBytes(_twoPages());
      final ref = ReaderPdfDocumentRef(file.path);
      const style = TextStyle(fontSize: 14, color: Colors.black);
      void configure(ReaderPdfLayerMode mode) =>
          ref.configure(ReaderDocumentIndex.empty, const {}, 'zh', style, mode);
      configure(ReaderPdfLayerMode.source);
      final document = await ref.loadDocument((_, [_]) {});
      try {
        final first = await (document.pages[0] as ReaderPdfPage).layout;
        final second = await (document.pages[1] as ReaderPdfPage).layout;
        expect(first.text.fullText, contains('First'));
        expect(second.text.fullText, contains('Second'));
        configure(ReaderPdfLayerMode.bilingual);
        expect(document.pages, hasLength(4));
        for (var i = 0; i < 4; i++) {
          final page = document.pages[i] as ReaderPdfPage;
          expect(
            (await page.layout).text.fullText,
            contains(i < 2 ? 'First' : 'Second'),
          );
          expect(page.sourcePageNumber, i ~/ 2 + 1);
        }
        expect(await (document.pages[0] as ReaderPdfPage).layout, same(first));
        expect(await (document.pages[2] as ReaderPdfPage).layout, same(second));
        final translated = await (document.pages[3] as ReaderPdfPage).layout;
        configure(ReaderPdfLayerMode.translated);
        expect(
          await (document.pages[1] as ReaderPdfPage).layout,
          same(translated),
        );
        configure(ReaderPdfLayerMode.source);
        expect(await (document.pages[1] as ReaderPdfPage).layout, same(second));

        final index = ReaderDocumentIndex.build(
          DocumentStructure([
            StructurePage(
              pageIndex: 0,
              pageSize: const [200, 300],
              markdown: 'First page.',
              blocks: [
                LayoutBlock(
                  blockId: 'first',
                  blockLabel: 'text',
                  blockBbox: const [18, 25, 100, 45],
                  blockContent: 'First page.',
                ),
              ],
            ),
          ]),
          'First page.',
        );
        final translations = {index.paragraphs.single.hash: '初始译文。'};
        void update() => ref.configure(
          index,
          translations,
          'zh',
          style,
          ReaderPdfLayerMode.bilingual,
        );
        update();
        final before = List<PdfPage>.of(document.pages);
        update();
        expect(document.pages, orderedEquals(before));
        translations[index.paragraphs.single.hash] = '更新译文。';
        update();
        expect(document.pages[0], same(before[0]));
        expect(document.pages[1], isNot(same(before[1])));
        expect(document.pages[2], same(before[2]));
        expect(document.pages[3], same(before[3]));
        final changed = await (document.pages[1] as ReaderPdfPage).layout;
        expect(changed.blocks.single.text, '更新译文。');
      } finally {
        ref.disposeLayout();
        await document.dispose();
        await directory.delete(recursive: true);
      }
    });
    await tester.pump();
  });
}

Uint8List _twoPages() {
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
    for (var i = 0; i < 2; i++)
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] /Resources << /Font << /F1 5 0 R >> >> /Contents ${6 + i} 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    for (final label in ['First', 'Second'])
      _stream('BT /F1 12 Tf 20 260 Td ($label page.) Tj ET'),
  ];
  var text = '%PDF-1.4\n';
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(text.length);
    text += '${i + 1} 0 obj\n${objects[i]}\nendobj\n';
  }
  final xref = text.length;
  text += 'xref\n0 ${objects.length + 1}\n0000000000 65535 f \n';
  for (final offset in offsets) {
    text += '${offset.toString().padLeft(10, '0')} 00000 n \n';
  }
  text +=
      'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF';
  return Uint8List.fromList(ascii.encode(text));
}

String _stream(String text) =>
    '<< /Length ${text.length} >>\nstream\n$text\nendstream';
