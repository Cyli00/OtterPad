import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/services/metadata_names.dart';

void main() {
  group('formatPersonName', () {
    test('given + family', () {
      expect(MetadataNames.formatPersonName('Jane', 'Doe'), 'Jane Doe');
    });

    test('空 given → 只留 family（覆盖 PubMed/CrossRef 空 given 行为）', () {
      expect(MetadataNames.formatPersonName('', 'Doe'), 'Doe');
      expect(MetadataNames.formatPersonName(null, 'Doe'), 'Doe');
    });

    test('空 family → 只留 given', () {
      expect(MetadataNames.formatPersonName('Jane', ''), 'Jane');
      expect(MetadataNames.formatPersonName('Jane', null), 'Jane');
    });

    test('两者皆空 → 空串', () {
      expect(MetadataNames.formatPersonName(null, null), '');
      expect(MetadataNames.formatPersonName('  ', ''), '');
    });

    test('去除多余空白', () {
      expect(MetadataNames.formatPersonName(' Jane ', ' Doe '), 'Jane Doe');
    });
  });

  group('splitAuthorLine', () {
    test('逗号分隔', () {
      expect(MetadataNames.splitAuthorLine('A, B, C'), ['A', 'B', 'C']);
    });

    test('省略号归一为逗号', () {
      expect(MetadataNames.splitAuthorLine('A, B ... C'), ['A', 'B', 'C']);
    });

    test('去空白与空项', () {
      expect(MetadataNames.splitAuthorLine('A, , B,'), ['A', 'B']);
    });
  });
}
