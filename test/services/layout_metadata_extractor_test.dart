import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/services/document_structure.dart';
import 'package:otter_pad/services/layout_metadata_extractor.dart';

void main() {
  test('doc_title 双语标题 → 取中文行', () {
    final blocks = [
      _block('1', 'header', [185, 95, 698, 178],
          '普通高等教育"十一五"国家级规划教材'),
      _block('2', 'doc_title', [62, 324, 956, 580],
          'Geometrical Optics, Aberrations and Optical Design\n几何光学 · 像差 · 光学设计'),
      _block('3', 'text', [786, 603, 954, 658], '（第三版）'),
      _block('4', 'text', [64, 691, 329, 760],
          '李晓彤 岑兆丰 编著\n范世福 主审'),
    ];

    final metadata = LayoutMetadataExtractor.extractFromFirstPage(blocks);
    expect(metadata.title, '几何光学 · 像差 · 光学设计');
  });

  test('封面作者行提取 — 编著角色取作者，主审排除', () {
    final blocks = [
      _block('2', 'doc_title', [62, 324, 956, 580],
          '几何光学 · 像差 · 光学设计'),
      _block('4', 'text', [64, 691, 329, 760],
          '李晓彤 岑兆丰 编著\n范世福 主审'),
    ];

    final metadata = LayoutMetadataExtractor.extractFromFirstPage(blocks);
    expect(metadata.authors, ['李晓彤', '岑兆丰']);
  });

  test('各种作者角色后缀 (主编/著/编/译)', () {
    final blocks = [
      _block('1', 'doc_title', [100, 100, 800, 300], '计算机科学导论'),
      _block('2', 'text', [100, 350, 400, 400], '张三 李四 主编'),
    ];
    final m1 = LayoutMetadataExtractor.extractFromFirstPage(blocks);
    expect(m1.authors, ['张三', '李四']);

    final blocks2 = [
      _block('1', 'doc_title', [100, 100, 800, 300], '算法导论'),
      _block('2', 'text', [100, 350, 400, 400], '王五 著'),
    ];
    final m2 = LayoutMetadataExtractor.extractFromFirstPage(blocks2);
    expect(m2.authors, ['王五']);
  });

  test('纯英文 doc_title → 直接用全文', () {
    final blocks = [
      _block('1', 'doc_title', [100, 100, 800, 300],
          'Introduction to Algorithms'),
    ];
    final metadata = LayoutMetadataExtractor.extractFromFirstPage(blocks);
    expect(metadata.title, 'Introduction to Algorithms');
  });

  test('作者行含多行——编著行和主审行分开', () {
    final blocks = [
      _block('1', 'doc_title', [100, 100, 800, 300], '数据结构'),
      _block('2', 'text', [100, 350, 400, 420], '严蔚敏 吴伟民 编著'),
      _block('3', 'text', [100, 450, 400, 500], '陈文博 主审'),
    ];
    final metadata = LayoutMetadataExtractor.extractFromFirstPage(blocks);
    expect(metadata.authors, ['严蔚敏', '吴伟民']);
  });

  test('无 doc_title → 返回空元数据', () {
    final blocks = [
      _block('1', 'text', [100, 100, 800, 300], '第一章 概述'),
      _block('2', 'text', [100, 350, 800, 600], '本章介绍基本概念'),
    ];

    final metadata = LayoutMetadataExtractor.extractFromFirstPage(blocks);
    expect(metadata.title, isNull);
    expect(metadata.authors, isEmpty);
  });
}

LayoutBlock _block(
  String id,
  String label,
  List<double> bbox, [
  String content = '',
]) {
  return LayoutBlock(
    blockId: id,
    blockLabel: label,
    blockBbox: bbox,
    blockContent: content,
  );
}
