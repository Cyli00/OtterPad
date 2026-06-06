import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/data/models/book/document.dart';
import 'package:otter_pad/services/document_metadata_checks.dart';

Document _doc({
  String id = 'id1',
  String title = 'A Reasonable Paper Title',
  List<String> authors = const [],
  String? doi,
  String? journal,
  String? year,
  String? contentHash,
}) => Document(
  id: id,
  title: title,
  authors: authors,
  doi: doi,
  journal: journal,
  year: year,
  contentHash: contentHash,
  addedAt: DateTime.now(),
);

void main() {
  group('小工具', () {
    test('isBlank', () {
      expect(DocumentMetadataChecks.isBlank(null), isTrue);
      expect(DocumentMetadataChecks.isBlank('  '), isTrue);
      expect(DocumentMetadataChecks.isBlank('x'), isFalse);
    });

    test('normalizeMetadataValue：trim，空→null', () {
      expect(DocumentMetadataChecks.normalizeMetadataValue(' a '), 'a');
      expect(DocumentMetadataChecks.normalizeMetadataValue('  '), isNull);
      expect(DocumentMetadataChecks.normalizeMetadataValue(null), isNull);
    });

    test('normalizeComparisonKey：小写 + 折叠空白', () {
      expect(
        DocumentMetadataChecks.normalizeComparisonKey('  Hello   World '),
        'hello world',
      );
    });
  });

  group('isDuplicate', () {
    test('DOI 一致（大小写无关）判重', () {
      expect(
        DocumentMetadataChecks.isDuplicate(
          _doc(doi: '10.1/X'),
          _doc(title: 'Different', doi: '10.1/x'),
        ),
        isTrue,
      );
    });

    test('无 DOI 时标题 + 年份一致判重', () {
      expect(
        DocumentMetadataChecks.isDuplicate(
          _doc(title: 'Same Title', year: '2020'),
          _doc(title: 'same  title', year: '2020'),
        ),
        isTrue,
      );
    });

    test('无 DOI 时标题 + 首作者一致判重', () {
      expect(
        DocumentMetadataChecks.isDuplicate(
          _doc(title: 'T', authors: const ['Jane Doe']),
          _doc(title: 't', authors: const ['jane doe']),
        ),
        isTrue,
      );
    });

    test('标题不同不判重', () {
      expect(
        DocumentMetadataChecks.isDuplicate(_doc(title: 'A'), _doc(title: 'B')),
        isFalse,
      );
    });
  });

  group('isComplete / needsRepair', () {
    test('完整元数据：complete=true、needsRepair=false', () {
      final d = _doc(
        title: 'Multiphoton Neurophotonics Advances',
        authors: const ['Jane Doe'],
        year: '2020',
        journal: 'Nature',
        contentHash: 'h',
      );
      expect(DocumentMetadataChecks.isComplete(d), isTrue);
      expect(DocumentMetadataChecks.needsRepair(d), isFalse);
    });

    test('无 contentHash → 不需修复（未落盘）', () {
      expect(
        DocumentMetadataChecks.needsRepair(
          _doc(title: 'Multiphoton Neurophotonics Advances'),
        ),
        isFalse,
      );
    });

    test('已落盘但缺作者 → 需修复', () {
      expect(
        DocumentMetadataChecks.needsRepair(
          _doc(
            title: 'Multiphoton Neurophotonics Advances',
            authors: const [],
            year: '2020',
            journal: 'Nature',
            contentHash: 'h',
          ),
        ),
        isTrue,
      );
    });
  });
}
