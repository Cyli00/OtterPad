import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../data/models/book/document.dart';
import 'app_database.dart' show AppDatabase;
import 'db_convert.dart';

class ZoteroLocalRecord {
  const ZoteroLocalRecord(this.documentId, this.metadata, this.attachmentKey);
  final String documentId;
  final Document metadata;
  final String? attachmentKey;
}

class ZoteroLocalStore {
  const ZoteroLocalStore(this.database);
  final AppDatabase database;

  String _key(String source, String itemKey) =>
      'zotero_local:${sha256.convert(utf8.encode(source))}:$itemKey';

  Future<ZoteroLocalRecord?> read(String source, String itemKey) async {
    final row = await (database.select(
      database.meta,
    )..where((t) => t.metaKey.equals(_key(source, itemKey)))).getSingleOrNull();
    if (row == null) return null;
    final data = jsonDecode(row.value) as Map<String, dynamic>;
    return ZoteroLocalRecord(
      data['documentId'] as String,
      Document.fromJson(data['metadata'] as Map<String, dynamic>),
      data['attachmentKey'] as String?,
    );
  }

  Future<void> write(String source, String itemKey, ZoteroLocalRecord record) =>
      database
          .into(database.meta)
          .insertOnConflictUpdate(
            metaCompanion(
              _key(source, itemKey),
              jsonEncode({
                'documentId': record.documentId,
                'metadata': record.metadata.toJson(),
                'attachmentKey': record.attachmentKey,
              }),
            ),
          );

  Future<void> removeDocument(String documentId) async {
    final rows = await (database.select(
      database.meta,
    )..where((t) => t.metaKey.like('zotero_local:%'))).get();
    for (final row in rows) {
      final data = jsonDecode(row.value) as Map<String, dynamic>;
      if (data['documentId'] == documentId) {
        await (database.delete(
          database.meta,
        )..where((t) => t.metaKey.equals(row.metaKey))).go();
      }
    }
  }
}
