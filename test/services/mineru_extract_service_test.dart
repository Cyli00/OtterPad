import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/providers/api_provider.dart';
import 'package:otter_pad/services/mineru_extract_service.dart';
import 'package:otter_pad/services/mineru_parse_options.dart';

/// MinerU 请求体构造（单文件解析 / 批量文件解析共用同一形状）。
void main() {
  group('buildUploadRequest', () {
    test('单个文件解析：model_version 默认 vlm，files 长度 1', () {
      const state = DocExtractApiState(
        provider: DocExtractProvider.mineru,
        mineruIsOcr: true,
        mineruEnableFormula: false,
        mineruEnableTable: false,
        mineruLanguage: 'en',
      );
      final body = MinerUExtractService.buildUploadRequest(state, [
        (name: 'source.pdf', dataId: 'doc_a'),
      ]);
      expect(body['model_version'], 'vlm');
      expect(body['enable_formula'], false);
      expect(body['enable_table'], false);
      expect(body['language'], 'en');
      final files = body['files'] as List;
      expect(files.length, 1);
      expect(files.single, {
        'name': 'source.pdf',
        'is_ocr': true,
        'data_id': 'doc_a',
      });
    });

    test('页码范围按文件发送，额外格式按请求发送', () {
      final state = const DocExtractApiState().copyWith(
        mineruModelVersion: 'pipeline',
        mineruPageRanges: ' 2，4-6, 8--2 ',
        mineruExtraFormats: ['docx', 'latex'],
      );
      final body = MinerUExtractService.buildUploadRequest(state, [
        (name: 'a.pdf', dataId: 'a'),
        (name: 'b.pdf', dataId: 'b'),
      ]);
      expect(body['model_version'], 'pipeline');
      expect(body['extra_formats'], ['docx', 'latex']);
      expect(body.containsKey('page_ranges'), isFalse);
      for (final file in body['files'] as List) {
        expect(file['page_ranges'], '2,4-6,8--2');
      }
    });

    test('默认省略可选范围和额外格式，支持全部文档语言', () {
      for (final language in MinerUParseOptions.languages) {
        final body = MinerUExtractService.buildUploadRequest(
          DocExtractApiState(mineruLanguage: language),
          [(name: 'a.pdf', dataId: 'a')],
        );
        expect(body['language'], language);
        expect(body.containsKey('extra_formats'), isFalse);
        expect(
          (body['files'] as List).single.containsKey('page_ranges'),
          isFalse,
        );
      }
    });

    test('拒绝无效范围和非 PDF 模型', () {
      for (final range in ['0', '3-1', '2,', '1---2', 'abc', '1-0']) {
        expect(MinerUParseOptions.isValidPageRanges(range), isFalse);
        expect(
          () => MinerUExtractService.buildUploadRequest(
            DocExtractApiState(mineruPageRanges: range),
            [(name: 'a.pdf', dataId: 'a')],
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => MinerUExtractService.buildUploadRequest(
          const DocExtractApiState(mineruModelVersion: 'MinerU-HTML'),
          [(name: 'a.pdf', dataId: 'a')],
        ),
        throwsArgumentError,
      );
    });

    test('批量文件解析：多 data_id，默认开启公式/表格、中文', () {
      const state = DocExtractApiState(provider: DocExtractProvider.mineru);
      final body = MinerUExtractService.buildUploadRequest(state, [
        (name: 'a.pdf', dataId: 'id_a'),
        (name: 'b.pdf', dataId: 'id_b'),
      ]);
      expect(body['enable_formula'], isTrue);
      expect(body['enable_table'], isTrue);
      expect(body['language'], 'ch');
      final files = body['files'] as List;
      expect(files.length, 2);
      expect(files[0]['is_ocr'], isFalse);
      expect(files.map((f) => f['data_id']), ['id_a', 'id_b']);
    });
  });
}
