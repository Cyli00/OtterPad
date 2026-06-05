import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/services/document_metadata_parser.dart';

void main() {
  group('CNKI 中文文件名解析 {标题}_{作者}', () {
    test('真实案例：丹参川芎论文', () {
      final meta = DocumentMetadataParser.parseFilePath(
        '丹参川芎两药主要活性成分治疗缺血性脑卒中药理作用及临床应用研究_王启秀.pdf',
      );
      expect(meta.title, '丹参川芎两药主要活性成分治疗缺血性脑卒中药理作用及临床应用研究');
      expect(meta.authors, ['王启秀']);
    });

    test('单姓三字作者', () {
      final meta = DocumentMetadataParser.parseText('基于深度学习的图像识别_李明华');
      expect(meta.title, '基于深度学习的图像识别');
      expect(meta.authors, ['李明华']);
    });

    test('复姓作者', () {
      final meta = DocumentMetadataParser.parseText('中医药研究进展_欧阳锋');
      expect(meta.title, '中医药研究进展');
      expect(meta.authors, ['欧阳锋']);
    });

    test('标题本身含下划线时按最后一个下划线拆', () {
      final meta = DocumentMetadataParser.parseText('深度学习_图像识别_张三');
      expect(meta.title, '深度学习_图像识别');
      expect(meta.authors, ['张三']);
    });

    test('英文文件名不受影响（无中文）', () {
      final meta = DocumentMetadataParser.parseText('attention_is_all_you_need');
      expect(meta.title, isNull);
      expect(meta.authors, isEmpty);
    });

    test('作者段为英文时不拆', () {
      final meta = DocumentMetadataParser.parseText('中医药研究进展_review');
      expect(meta.title, isNull);
      expect(meta.authors, isEmpty);
    });

    test('作者段超过 4 字时不拆（避免把标题尾段误当作者）', () {
      final meta = DocumentMetadataParser.parseText('某某研究_这显然不是一个人名');
      expect(meta.title, isNull);
      expect(meta.authors, isEmpty);
    });

    test('无下划线时不拆', () {
      final meta = DocumentMetadataParser.parseText('纯中文标题没有作者后缀');
      expect(meta.title, isNull);
      expect(meta.authors, isEmpty);
    });

    test('年份开头格式优先于 CNKI 格式', () {
      // {year}-{author}-{title} 应走原有结构化解析，不被 CNKI 分支拦截
      final meta = DocumentMetadataParser.parseText('2021-Smith-机器学习_导论');
      expect(meta.year, '2021');
      expect(meta.authors, ['Smith']);
    });
  });
}
