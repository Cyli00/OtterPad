import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/app_database.dart' show AppDatabase;
import '../core/storage/app_database_provider.dart';
import '../core/storage/db_convert.dart';
import '../data/models/book/document.dart';

/// 全文检索（FTS5 jieba 分词 + 拼音）+ 全字段 LIKE 兜底。
///
/// FTS5 索引 title/authors/journal/keywords（[AppDatabase.ensureFts5] 建的
/// documents_fts 虚表 + 触发器自动同步），提供分词/拼音召回。LIKE 恒查全
/// 字段（title/authors/journal/keywords/doi/year）：doi/year 不进 FTS 靠它
/// 覆盖，同时补足 FTS 分词召不回的任意子串命中（如搜 "nation" 命中
/// "information..."），对齐旧 `Document.matchesQuery` 行为。
///
/// **降级**：FTS5 扩展（sqlite3_simple）不可用或 documents_fts 表缺失时，
/// FTS5 查询抛错被吞、命中并入为空，结果即纯全字段 LIKE，搜索始终可用
/// （ADR-0005；扩展加载见 GStorage.init）。
Future<List<Document>> searchDocuments(AppDatabase db, String query) async {
  final q = query.trim();
  if (q.isEmpty) return const [];

  // FTS5 命中（jieba 分词 + 拼音）。扩展/表缺失时降级。
  final ftsDocs = <Document>[];
  try {
    final ftsRows = await db.customSelect(
      'SELECT d.id, d.title, d.authors, d.journal, d.year, d.doi, d.keywords, '
      'd.contentHash, d.addedAt '
      'FROM documents_fts f JOIN documents d ON d.id = f.id '
      'WHERE documents_fts MATCH jieba_query(?)',
      variables: [Variable.withString(q)],
    ).get();
    for (final r in ftsRows) {
      ftsDocs.add(Document(
        id: r.read<String>('id'),
        title: r.read<String>('title'),
        authors: (jsonDecode(r.read<String>('authors')) as List).cast<String>(),
        journal: r.read<String?>('journal'),
        year: r.read<String?>('year'),
        doi: r.read<String?>('doi'),
        keywords:
            (jsonDecode(r.read<String>('keywords')) as List).cast<String>(),
        contentHash: r.read<String?>('contentHash'),
        addedAt: DateTime.fromMillisecondsSinceEpoch(r.read<int>('addedAt')),
      ));
    }
  } catch (_) {
    // FTS5 不可用：ftsDocs 留空，纯靠下方全字段 LIKE。
  }

  // 全字段 LIKE（见文档注释），与 FTS 命中合并。
  final likeRows = await (db.select(db.documents)
        ..where(
          (t) =>
              t.title.like('%$q%') |
              t.authors.like('%$q%') |
              t.journal.like('%$q%') |
              t.keywords.like('%$q%') |
              t.doi.like('%$q%') |
              t.year.like('%$q%'),
        ))
      .get();
  final likeDocs = likeRows.map(documentFromRow).toList();

  // 合并去重（FTS 命中优先）
  final seen = <String>{};
  final result = <Document>[];
  for (final d in [...ftsDocs, ...likeDocs]) {
    if (seen.add(d.id)) result.add(d);
  }
  return result;
}

/// 搜索结果（异步）。autoDispose：查询串变更后旧 family 项自动释放。
/// 库实例经 [appDatabaseProvider]（唯一来源）：备份恢复 reopen 后
/// invalidate 连带失效缓存的搜索结果，重查新库。
final documentSearchProvider =
    FutureProvider.autoDispose.family<List<Document>, String>(
  (ref, query) => searchDocuments(ref.watch(appDatabaseProvider), query),
);
