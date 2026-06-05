import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/services/chinese_name_utils.dart';

void main() {
  group('ChineseNameUtils.splitChineseName', () {
    test('单姓', () {
      final result = ChineseNameUtils.splitChineseName('李明');
      expect(result.family, '李');
      expect(result.given, '明');
    });

    test('单姓三字名', () {
      final result = ChineseNameUtils.splitChineseName('王小明');
      expect(result.family, '王');
      expect(result.given, '小明');
    });

    test('复姓', () {
      final result = ChineseNameUtils.splitChineseName('欧阳锋');
      expect(result.family, '欧阳');
      expect(result.given, '锋');
    });

    test('复姓 - 司马', () {
      final result = ChineseNameUtils.splitChineseName('司马懿');
      expect(result.family, '司马');
      expect(result.given, '懿');
    });

    test('复姓 - 上官', () {
      final result = ChineseNameUtils.splitChineseName('上官婉儿');
      expect(result.family, '上官');
      expect(result.given, '婉儿');
    });

    test('少数民族 - 含中点', () {
      final result = ChineseNameUtils.splitChineseName('阿依·努尔');
      expect(result.family, '阿依');
      expect(result.given, '努尔');
    });

    test('少数民族 - 多段中点', () {
      final result = ChineseNameUtils.splitChineseName('买买提·艾力·哈斯木');
      expect(result.family, '买买提');
      expect(result.given, '艾力·哈斯木');
    });

    test('单字姓名', () {
      final result = ChineseNameUtils.splitChineseName('龙');
      expect(result.family, '龙');
      expect(result.given, '');
    });

    test('空字符串', () {
      final result = ChineseNameUtils.splitChineseName('');
      expect(result.family, '');
      expect(result.given, '');
    });
  });

  group('ChineseNameUtils.parseAuthorList', () {
    test('中文分号分隔', () {
      expect(
        ChineseNameUtils.parseAuthorList('李明；王强；张华'),
        ['李明', '王强', '张华'],
      );
    });

    test('英文分号分隔', () {
      expect(
        ChineseNameUtils.parseAuthorList('李明; 王强; 张华'),
        ['李明', '王强', '张华'],
      );
    });

    test('中文逗号分隔', () {
      expect(
        ChineseNameUtils.parseAuthorList('李明，王强，张华'),
        ['李明', '王强', '张华'],
      );
    });

    test('尾部带「等」', () {
      expect(
        ChineseNameUtils.parseAuthorList('李明; 王强等'),
        ['李明', '王强'],
      );
    });

    test('空字符串', () {
      expect(ChineseNameUtils.parseAuthorList(''), isEmpty);
    });

    test('单个作者', () {
      expect(
        ChineseNameUtils.parseAuthorList('欧阳锋'),
        ['欧阳锋'],
      );
    });
  });

  group('ChineseNameUtils.isChineseName', () {
    test('中文名', () {
      expect(ChineseNameUtils.isChineseName('李明'), true);
    });

    test('英文名', () {
      expect(ChineseNameUtils.isChineseName('John Smith'), false);
    });

    test('中英混合', () {
      expect(ChineseNameUtils.isChineseName('Li 明'), true);
    });
  });
}
