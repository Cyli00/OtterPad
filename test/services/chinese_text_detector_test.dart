import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/services/chinese_text_detector.dart';

void main() {
  group('ChineseTextDetector.isChinese', () {
    test('纯中文标题', () {
      expect(ChineseTextDetector.isChinese('基于深度学习的蛋白质结构预测'), true);
    });

    test('中英混合标题', () {
      expect(ChineseTextDetector.isChinese('COVID-19 疫情分析'), true);
    });

    test('少于阈值的中文字符', () {
      expect(ChineseTextDetector.isChinese('AB测试'), false);
      expect(ChineseTextDetector.isChinese('测'), false);
    });

    test('恰好达到阈值', () {
      expect(ChineseTextDetector.isChinese('测试中'), true);
    });

    test('纯英文', () {
      expect(ChineseTextDetector.isChinese('Machine Learning for Protein'), false);
    });

    test('空字符串', () {
      expect(ChineseTextDetector.isChinese(''), false);
    });

    test('自定义阈值', () {
      expect(ChineseTextDetector.isChinese('测', threshold: 1), true);
      expect(ChineseTextDetector.isChinese('机器学习', threshold: 5), false);
    });

    test('CJK Extension A 字符', () {
      expect(ChineseTextDetector.isChinese('㐀㐁㐂'), true);
    });
  });
}
