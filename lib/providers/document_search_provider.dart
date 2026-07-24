import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/db_convert.dart';
import '../core/storage/storage.dart';
import '../data/models/book/document.dart';

/// 全文检索（FTS5 jieba 分词 + 拼音）+ doi/year LIKE 兜底。
///
/// FTS5 索引 title/authors/journal/keywords（[AppDatabase.ensureFts5] 建的
/// documents_fts 虚表 + 触发器自动同步）。doi（标识符）与 year（数字）不进 FTS，
/// 用列 LIKE 兜底，保持与旧 `Document.matchesQuery` 行为对齐。
///
/// **降级**：FTS5 扩展（sqlite3_simple）不可用或 documents_fts 表缺失时，
/// FTS5 查询抛错被吞，搜索退化为全字段 LIKE（含 title/authors/journal/keywords），
/// 保证搜索始终可用——见 GStorage.init 的扩展加载 try-catch。
Future<List<Document>> searchDocuments(String query) async {
  final q = query.trim();
  if (q.isEmpty) return const [];

  // FTS5 命中（jieba 分词 + 拼音）。扩展/表缺失时降级。
  final ftsDocs = <Document>[];
  try {
    final ftsRows = await GStorage.db.customSelect(
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
    // FTS5 不可用：ftsDocs 留空，下方 LIKE 兜底覆盖全字段。
  }

  // doi/year 列 LIKE 兜底；FTS5 不可用时再覆盖 title/authors/journal/keywords。
  final likeRows = await (GStorage.db.select(GStorage.db.documents)
        ..where((t) {
          var expr = t.doi.like('%$q%') | t.year.like('%$q%');
          if (ftsDocs.isEmpty) {
            expr = expr |
                t.title.like('%$q%') |
                t.authors.like('%$q%') |
                t.journal.like('%$q%') |
                t.keywords.like('%$q%');
          }
          return expr;
        }))
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
final documentSearchProvider =
    FutureProvider.autoDispose.family<List<Document>, String>(
  (ref, query) => searchDocuments(query),
);