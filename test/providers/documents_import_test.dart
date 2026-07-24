import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otter_pad/core/storage/app_database.dart' as db_lib;
import 'package:otter_pad/core/storage/storage.dart';
import 'package:otter_pad/data/models/book/document.dart';
import 'package:otter_pad/providers/documents_provider.dart';

Document _doc({required String title, String? doi}) => Document(
      id: '',
      title: title,
      authors: const [],
      doi: doi,
      contentHash: null,
      addedAt: DateTime.now(),
    );

void main() {
  late db_lib.AppDatabase db;

  setUp(() async {
    db = db_lib.AppDatabase(NativeDatabase.memory());
    await GStorage.initForTest(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('DocumentsNotifier.importDocuments', () {
    test('同 DOI 的批内重复只入库一篇，且为纯元数据', () async {
      final notifier = DocumentsNotifier();
      final results = await notifier.importDocuments([
        _doc(title: 'A', doi: '10.1/x'),
        _doc(title: 'A 大小写不同', doi: '10.1/X'),
      ]);

      // 结果与输入等长同序，重复项指向同一篇
      expect(results.length, 2);
      expect(results.first.id, isNotEmpty);
      expect(results[1].id, results[0].id);
      // 纯元数据：无 PDF
      expect(results.first.contentHash, isNull);
      // 实际只落盘一篇
      final rows = await db.select(db.documents).get();
      expect(rows.length, 1);
    });

    test('跨次调用对已存在文献判重', () async {
      final notifier = DocumentsNotifier();
      final first = await notifier.importDocuments([
        _doc(title: 'B', doi: '10.2/y'),
      ]);
      final second = await notifier.importDocuments([
        _doc(title: 'B 再次导入', doi: '10.2/y'),
      ]);

      expect(second.single.id, first.single.id);
      final rows = await db.select(db.documents).get();
      expect(rows.length, 1);
    });
  });
}