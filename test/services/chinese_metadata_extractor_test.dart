import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/services/chinese_metadata_extractor.dart';

void main() {
  // 模拟 pdfrx loadText() 的线性化输出：版面顺序大致保留，但无字号/坐标。
  // 取自用户提供的《中华中医药学刊》首页。
  const realPageText = '''
第44卷 第1期 中 华 中 医 药 学 刊 Vol.44 No.1
2026年1月 CHINESE ARCHIVES OF TRADITIONAL CHINESE MEDICINE Jan.2026
DOI:10.13193/j.issn.1673-7717.2026.01.040
丹参川芎两药主要活性成分治疗缺血性脑卒中药理作用及临床应用研究
王启秀1，张威2，周鸿飞1，2，刘峻2
（1.辽宁中医药大学,辽宁 沈阳 110847;2.辽宁中医药大学附属医院,辽宁 沈阳 110032）
''';

  const knownTitle = '丹参川芎两药主要活性成分治疗缺血性脑卒中药理作用及临床应用研究';

  group('ChineseMetadataExtractor 真实首页', () {
    test('提取完整 4 位作者', () {
      final meta = ChineseMetadataExtractor.parseFromText(
        realPageText,
        knownTitle: knownTitle,
      );
      expect(meta.authors, ['王启秀', '张威', '周鸿飞', '刘峻']);
    });

    test('提取期刊名', () {
      final meta = ChineseMetadataExtractor.parseFromText(
        realPageText,
        knownTitle: knownTitle,
      );
      expect(meta.journal, '中华中医药学刊');
    });

    test('提取年份', () {
      final meta = ChineseMetadataExtractor.parseFromText(
        realPageText,
        knownTitle: knownTitle,
      );
      expect(meta.year, '2026');
    });

    test('提取正文 DOI', () {
      final meta = ChineseMetadataExtractor.parseFromText(
        realPageText,
        knownTitle: knownTitle,
      );
      expect(meta.doi, '10.13193/j.issn.1673-7717.2026.01.040');
    });
  });

  // 取自《石油勘探与开发》真实首页（pypdf 提取）：标题后紧跟 8 位作者，
  // 标题前有「文章编号：1000-0747(2026)...」——曾被误当作者。
  const petroleumText = '''
2026 年 6 月 PETROLEUM EXPLORATION AND DEVELOPMENT Vol.53 No.3
文章编号： 1000-0747(2026)03-0000-15     DOI: 10.11698/PED.20250534
中国非常规天然气地质特征、开发技术与发展前景
邹才能 1, 2, 3 ，于荣泽 1, 2, 3 ，董大忠 1, 2, 3 ，张晓伟 1, 2, 3 ，陈艳鹏 1, 2, 3 ，
郑马嘉 1, 2, 3 ，刘翰林 1, 2, 3 ，高金亮 1, 2, 3
（1. 中国石油勘探开发研究院，北京 100083 ；2. 国家能源页岩气研发中心）
基金项目：中国石油天然气股份有限公司科技项目
摘要： 依托中国最新勘探开发成果...
''';

  const petroleumTitle = '中国非常规天然气地质特征、开发技术与发展前景';

  group('石油勘探与开发 8 作者（文章编号误判回归）', () {
    test('提取完整 8 位作者，不含「文章编号」', () {
      final meta = ChineseMetadataExtractor.parseFromText(
        petroleumText,
        knownTitle: petroleumTitle,
      );
      expect(meta.authors, [
        '邹才能', '于荣泽', '董大忠', '张晓伟',
        '陈艳鹏', '郑马嘉', '刘翰林', '高金亮',
      ]);
      expect(meta.authors, isNot(contains('文章编号')));
    });

    test('提取正文 DOI', () {
      final meta = ChineseMetadataExtractor.parseFromText(
        petroleumText,
        knownTitle: petroleumTitle,
      );
      expect(meta.doi, '10.11698/ped.20250534');
    });

    test('「文章编号」即使落在作者区也被黑名单挡下', () {
      // 模拟标题定位失败（knownTitle 不匹配）时，文章编号不应作为作者泄漏
      const text = '文章编号：1000-0747 张三，李四 摘要：...';
      final meta = ChineseMetadataExtractor.parseFromText(text);
      expect(meta.authors, isNot(contains('文章编号')));
    });

    test('年份取正文「2026 年」（正常字体）', () {
      final meta = ChineseMetadataExtractor.parseFromText(
        petroleumText,
        knownTitle: petroleumTitle,
      );
      expect(meta.year, '2026');
    });

    test('「年」字乱码时从文章编号 (YYYY) 兜底，优先于 DOI 投稿年', () {
      // 正文无「YYYY 年」；文章编号含出版年 2026，DOI 含投稿年 2025
      const text =
          '文章编号： 1000-0747(2026)03-0000-15 DOI: 10.11698/PED.20250534 某标题 张三';
      final meta = ChineseMetadataExtractor.parseFromText(text);
      expect(meta.year, '2026');
    });
  });

  group('isNonPersonName 非人名识别（修复检测复用）', () {
    test('识别页眉非人名词', () {
      expect(ChineseMetadataExtractor.isNonPersonName('文章编号'), true);
      expect(ChineseMetadataExtractor.isNonPersonName('基金项目'), true);
      expect(ChineseMetadataExtractor.isNonPersonName('中图分类'), true);
    });

    test('真实人名返回 false', () {
      expect(ChineseMetadataExtractor.isNonPersonName('邹才能'), false);
      expect(ChineseMetadataExtractor.isNonPersonName('王启秀'), false);
      expect(ChineseMetadataExtractor.isNonPersonName('欧阳锋'), false);
    });
  });

  group('边界与降级', () {
    test('空文本返回空元数据', () {
      final meta = ChineseMetadataExtractor.parseFromText('');
      expect(meta.hasAny, false);
    });

    test('无 knownTitle 时期刊保守留空（页眉边界不可靠）', () {
      final meta = ChineseMetadataExtractor.parseFromText(realPageText);
      expect(meta.journal, isNull);
      // DOI / 年份是强信号，无标题也能拿到
      expect(meta.doi, '10.13193/j.issn.1673-7717.2026.01.040');
      expect(meta.year, '2026');
    });

    test('单作者', () {
      const text = '某某期刊学报\n基于深度学习的图像识别方法\n李明华\n（1.某大学）';
      final meta = ChineseMetadataExtractor.parseFromText(
        text,
        knownTitle: '基于深度学习的图像识别方法',
      );
      expect(meta.authors, ['李明华']);
    });

    test('年份从 DOI 兜底（正文无「年」字）', () {
      const text = 'DOI:10.13193/j.issn.1673-7717.2026.01.040 标题 张三';
      final meta = ChineseMetadataExtractor.parseFromText(text);
      expect(meta.year, '2026');
    });

    test('无机构锚点时退守标题后区域提取作者', () {
      const text = '某学刊\n中医药临床研究进展\n王启秀，张威，刘峻\n摘要：本文...';
      final meta = ChineseMetadataExtractor.parseFromText(
        text,
        knownTitle: '中医药临床研究进展',
      );
      expect(meta.authors, ['王启秀', '张威', '刘峻']);
    });
  });
}
