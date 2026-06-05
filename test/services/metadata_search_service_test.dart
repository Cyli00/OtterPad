import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/services/metadata_search_service.dart';

void main() {
  group('diceCoefficient', () {
    test('完全相同', () {
      expect(
        MetadataSearchService.diceCoefficient('hello', 'hello'),
        1.0,
      );
    });

    test('完全不同', () {
      expect(
        MetadataSearchService.diceCoefficient('abc', 'xyz'),
        0.0,
      );
    });

    test('部分重叠', () {
      final score = MetadataSearchService.diceCoefficient('night', 'nacht');
      expect(score, greaterThan(0.0));
      expect(score, lessThan(1.0));
    });

    test('中文标题匹配', () {
      final score = MetadataSearchService.diceCoefficient(
        '基于深度学习的蛋白质结构预测',
        '基于深度学习的蛋白质结构预测方法',
      );
      expect(score, greaterThan(0.7));
    });

    test('中文标题不匹配', () {
      final score = MetadataSearchService.diceCoefficient(
        '基于深度学习的蛋白质结构预测',
        '量子计算在药物发现中的应用',
      );
      expect(score, lessThan(0.3));
    });

    test('单字符字符串', () {
      expect(MetadataSearchService.diceCoefficient('a', 'b'), 0.0);
    });

    test('空字符串', () {
      expect(MetadataSearchService.diceCoefficient('', ''), 1.0);
      expect(MetadataSearchService.diceCoefficient('abc', ''), 0.0);
    });

    test('英文学术标题 - 高相似度', () {
      final score = MetadataSearchService.diceCoefficient(
        'attention is all you need',
        'attention is all you need for transformers',
      );
      expect(score, greaterThan(0.7));
    });

    test('英文学术标题 - 低相似度', () {
      final score = MetadataSearchService.diceCoefficient(
        'attention is all you need',
        'deep reinforcement learning from human feedback',
      );
      expect(score, lessThan(0.3));
    });
  });

  group('normalizeForComparison', () {
    test('去标点', () {
      expect(
        MetadataSearchService.normalizeForComparison('Hello, World!'),
        'hello world',
      );
    });

    test('保留中文', () {
      expect(
        MetadataSearchService.normalizeForComparison('基于(深度)学习'),
        '基于 深度 学习',
      );
    });

    test('折叠空白', () {
      expect(
        MetadataSearchService.normalizeForComparison('  a   b  '),
        'a b',
      );
    });

    test('保留数字', () {
      expect(
        MetadataSearchService.normalizeForComparison('COVID-19'),
        'covid 19',
      );
    });
  });
}
