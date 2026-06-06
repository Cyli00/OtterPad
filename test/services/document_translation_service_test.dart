import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/services/document_translation_service.dart';
import 'package:otter_pad/services/markdown_paragraph_extractor.dart';

TranslatableParagraph _p(String hash, String text) => TranslatableParagraph(
  offset: 0,
  length: text.length,
  text: text,
  hash: hash,
  kind: ParagraphKind.text,
);

void main() {
  group('partitionParagraphs（缓存分流）', () {
    test('useCache=false → 全部进 pending，cachedHits 为空', () {
      final part = DocumentTranslationService.partitionParagraphs(
        paragraphs: [_p('a', 'A'), _p('b', 'B')],
        cached: {'a': '甲'},
        useCache: false,
      );
      expect(part.pending.map((p) => p.hash).toList(), ['a', 'b']);
      expect(part.cachedHits, isEmpty);
    });

    test('useCache=true → 命中走 cachedHits，未命中走 pending', () {
      final part = DocumentTranslationService.partitionParagraphs(
        paragraphs: [_p('a', 'A'), _p('b', 'B'), _p('c', 'C')],
        cached: {'a': '甲', 'c': '丙'},
        useCache: true,
      );
      expect(part.pending.map((p) => p.hash).toList(), ['b']);
      expect(part.cachedHits, {'a': '甲', 'c': '丙'});
    });

    test('缓存值为空串视为未命中', () {
      final part = DocumentTranslationService.partitionParagraphs(
        paragraphs: [_p('a', 'A')],
        cached: {'a': ''},
        useCache: true,
      );
      expect(part.pending.map((p) => p.hash).toList(), ['a']);
      expect(part.cachedHits, isEmpty);
    });

    test('全部命中 → pending 为空（调用方据此判定"使用了缓存"）', () {
      final part = DocumentTranslationService.partitionParagraphs(
        paragraphs: [_p('a', 'A'), _p('b', 'B')],
        cached: {'a': '甲', 'b': '乙'},
        useCache: true,
      );
      expect(part.pending, isEmpty);
      expect(part.cachedHits, {'a': '甲', 'b': '乙'});
    });
  });

  group('translateWithRetry（重试策略）', () {
    test('首次成功 → 只调用一次', () async {
      var calls = 0;
      final r = await DocumentTranslationService.translateWithRetry(
        text: 'hello',
        translator: (t) async {
          calls++;
          return '你好';
        },
        backoff: (_) async {},
      );
      expect(r, '你好');
      expect(calls, 1);
    });

    test('失败两次后成功 → 调用三次', () async {
      var calls = 0;
      final r = await DocumentTranslationService.translateWithRetry(
        text: 'hello',
        translator: (t) async {
          calls++;
          if (calls < 3) throw Exception('boom');
          return '你好';
        },
        backoff: (_) async {},
      );
      expect(r, '你好');
      expect(calls, 3);
    });

    test('全部失败 → 返回 null，调用 maxRetries+1 次', () async {
      var calls = 0;
      final r = await DocumentTranslationService.translateWithRetry(
        text: 'hello',
        translator: (t) async {
          calls++;
          throw Exception('boom');
        },
        backoff: (_) async {},
      );
      expect(r, isNull);
      expect(calls, 3); // maxRetries 默认 2 → 首次 + 2 次重试
    });

    test('空译文按失败处理并重试', () async {
      var calls = 0;
      final r = await DocumentTranslationService.translateWithRetry(
        text: 'hello',
        translator: (t) async {
          calls++;
          return '   ';
        },
        backoff: (_) async {},
      );
      expect(r, isNull);
      expect(calls, 3);
    });
  });

  group('runConcurrent（并发池）', () {
    test('每个 item 恰好处理一次', () async {
      final items = List.generate(20, (i) => i);
      final processed = <int>[];
      await DocumentTranslationService.runConcurrent<int>(
        items: items,
        concurrency: 4,
        task: (i) async {
          await Future<void>.delayed(Duration.zero);
          processed.add(i);
        },
      );
      expect(processed.length, 20);
      expect(processed.toSet(), items.toSet());
    });

    test('并发数大于 item 数也能完成', () async {
      var count = 0;
      await DocumentTranslationService.runConcurrent<int>(
        items: [1, 2],
        concurrency: 8,
        task: (_) async => count++,
      );
      expect(count, 2);
    });

    test('isCancelled 从一开始为 true → 不处理任何 item', () async {
      var count = 0;
      await DocumentTranslationService.runConcurrent<int>(
        items: [1, 2, 3],
        concurrency: 2,
        isCancelled: () => true,
        task: (_) async => count++,
      );
      expect(count, 0);
    });

    test('处理中途取消 → worker 在循环顶检查到取消即停', () async {
      var count = 0;
      var cancel = false;
      await DocumentTranslationService.runConcurrent<int>(
        items: List.generate(100, (i) => i),
        concurrency: 1,
        isCancelled: () => cancel,
        task: (_) async {
          count++;
          if (count >= 3) cancel = true;
        },
      );
      expect(count, 3);
    });
  });
}
