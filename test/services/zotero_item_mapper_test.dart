import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/services/zotero_item_mapper.dart';

void main() {
  group('ZoteroItemMapper.toDocument', () {
    test('journalArticle 完整映射', () {
      final doc = ZoteroItemMapper.toDocument({
        'key': 'ABCD1234',
        'version': 12,
        'data': {
          'itemType': 'journalArticle',
          'title': 'A Study of Otters',
          'creators': [
            {'creatorType': 'author', 'firstName': 'Jane', 'lastName': 'Doe'},
            {'creatorType': 'editor', 'firstName': 'Ed', 'lastName': 'Itor'},
          ],
          'publicationTitle': 'Journal of Aquatic Mammals',
          'date': '2021-03-05',
          'DOI': '10.1234/abcd.5678',
          'tags': [
            {'tag': 'otter'},
            {'tag': 'behavior'},
            {'tag': 'Otter'},
          ],
        },
      });

      expect(doc, isNotNull);
      expect(doc!.title, 'A Study of Otters');
      // 只取 author，editor 在有 author 时被排除
      expect(doc.authors, ['Jane Doe']);
      expect(doc.journal, 'Journal of Aquatic Mammals');
      expect(doc.year, '2021');
      expect(doc.doi, '10.1234/abcd.5678');
      // tags 去重保序（大小写归一）
      expect(doc.keywords, ['otter', 'behavior']);
      // id 由落盘时分配，映射阶段为空；无 PDF
      expect(doc.id, '');
      expect(doc.contentHash, isNull);
    });

    test('book 用 publisher 充当 journal，单字段 creator name', () {
      final doc = ZoteroItemMapper.toDocument({
        'key': 'BOOK0001',
        'version': 3,
        'data': {
          'itemType': 'book',
          'title': 'The Otter Encyclopedia',
          'creators': [
            {'creatorType': 'author', 'name': 'Otter Society'},
          ],
          'publisher': 'Aquatic Press',
          'date': '2019',
        },
      });

      expect(doc, isNotNull);
      expect(doc!.journal, 'Aquatic Press');
      expect(doc.authors, ['Otter Society']);
      expect(doc.year, '2019');
      expect(doc.doi, isNull);
    });

    test('没有 author 时退回其他 creator', () {
      final doc = ZoteroItemMapper.toDocument({
        'key': 'EDIT0001',
        'data': {
          'itemType': 'book',
          'title': 'Edited Volume',
          'creators': [
            {'creatorType': 'editor', 'firstName': 'Ed', 'lastName': 'Itor'},
          ],
        },
      });

      expect(doc!.authors, ['Ed Itor']);
    });

    test('附件/笔记/无标题条目返回 null', () {
      expect(
        ZoteroItemMapper.toDocument({
          'key': 'ATT0001',
          'data': {'itemType': 'attachment', 'title': 'fulltext.pdf'},
        }),
        isNull,
      );
      expect(
        ZoteroItemMapper.toDocument({
          'key': 'NOTE0001',
          'data': {'itemType': 'note'},
        }),
        isNull,
      );
      expect(
        ZoteroItemMapper.toDocument({
          'key': 'EMPTY001',
          'data': {'itemType': 'journalArticle', 'title': '   '},
        }),
        isNull,
      );
    });
  });
}
