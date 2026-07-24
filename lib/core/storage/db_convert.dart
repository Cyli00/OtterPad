import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../../data/models/book/document.dart';
import '../../data/models/book/highlight.dart';
import '../../data/models/book/history_entry.dart';
import '../../data/models/collection/favorite.dart';
import 'app_database.dart' as db;

/// 模型 ↔ Drift 行/companion 转换。
///
/// Drift 生成的行类 `Document`/`Highlight`/`Favorite` 与同名模型冲突，
/// 故本文件以 `db` 别名导入生成代码，行类用 `db.Xxx`，模型用裸名。
/// 模型字段与列的映射：authors/keywords 以 JSON 文本存；addedAt/createdAt
/// 存 epoch ms；highlights.content ↔ Highlight.text；highlights.docId ↔
/// Highlight.documentId。
///
/// 写入统一走 `insertOnConflictUpdate`（按 PK upsert 整行），FTS5 触发器
/// 据此自动同步 documents_fts。

// ─── documents ──────────────────────────────────────────────────────────────

Document documentFromRow(db.Document r) => Document(
      id: r.id,
      title: r.title,
      authors: (jsonDecode(r.authors) as List).cast<String>(),
      journal: r.journal,
      year: r.year,
      doi: r.doi,
      keywords: (jsonDecode(r.keywords) as List).cast<String>(),
      contentHash: r.contentHash,
      addedAt: DateTime.fromMillisecondsSinceEpoch(r.addedAt),
    );

db.DocumentsCompanion documentCompanion(Document d) =>
    db.DocumentsCompanion.insert(
      id: d.id,
      title: d.title,
      authors: jsonEncode(d.authors),
      journal: Value(d.journal),
      year: Value(d.year),
      doi: Value(d.doi),
      keywords: jsonEncode(d.keywords),
      contentHash: Value(d.contentHash),
      addedAt: d.addedAt.millisecondsSinceEpoch,
    );

// ─── highlights ─────────────────────────────────────────────────────────────

Highlight highlightFromRow(db.Highlight r) => Highlight(
      id: r.id,
      documentId: r.docId,
      text: r.content,
      note: r.note,
      color: r.color,
      groupId: r.groupId,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
    );

db.HighlightsCompanion highlightCompanion(Highlight h) =>
    db.HighlightsCompanion.insert(
      id: h.id,
      docId: h.documentId,
      content: h.text,
      note: Value(h.note),
      color: h.color,
      groupId: Value(h.groupId),
      createdAt: h.createdAt.millisecondsSinceEpoch,
    );

// ─── history ─────────────────────────────────────────────────────────────────

HistoryEntry historyFromRow(db.HistoryData r) => HistoryEntry(
      docId: r.docId,
      openedAt: DateTime.fromMillisecondsSinceEpoch(r.openedAt),
      progress: r.progress,
      anchorBlock: r.anchorBlock,
    );

db.HistoryCompanion historyCompanion(HistoryEntry e) =>
    db.HistoryCompanion.insert(
      docId: e.docId,
      openedAt: e.openedAt.millisecondsSinceEpoch,
      progress: Value(e.progress),
      anchorBlock: Value(e.anchorBlock),
    );

// ─── favorites ──────────────────────────────────────────────────────────────

db.FavoritesCompanion favoriteCompanion(Favorite f) =>
    db.FavoritesCompanion.insert(
      id: f.id,
      emoji: f.emoji,
      name: f.name,
      createdAt: f.createdAt.millisecondsSinceEpoch,
    );

db.FavoriteDocumentsCompanion favoriteDocumentCompanion(
  String favoriteId,
  String docId,
) =>
    db.FavoriteDocumentsCompanion.insert(favoriteId: favoriteId, docId: docId);

// ─── zotero_items ───────────────────────────────────────────────────────────

({String? docId, int version}) zoteroItemFromRow(db.ZoteroItem r) =>
    (docId: r.docId, version: r.version);

db.ZoteroItemsCompanion zoteroItemCompanion(
  String zoteroKey,
  String? docId,
  int version,
) =>
    db.ZoteroItemsCompanion.insert(
      zoteroKey: zoteroKey,
      docId: Value(docId),
      version: version,
    );

// ─── settings / meta ─────────────────────────────────────────────────────────

db.SettingsCompanion settingCompanion(String key, Object? value) =>
    db.SettingsCompanion.insert(settingKey: key, value: jsonEncode(value));

db.MetaCompanion metaCompanion(String key, String value) =>
    db.MetaCompanion.insert(metaKey: key, value: value);