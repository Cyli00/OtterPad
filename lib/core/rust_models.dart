import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/book/document.dart';
import '../data/models/book/highlight.dart';
import '../data/models/book/history_entry.dart';
import '../data/models/collection/favorite.dart';
import '../src/rust/api/types.dart' as rust;
import '../src/rust/library.dart' as rust;
import '../src/rust/storage/models.dart' as rust;
import 'storage/json_data.dart';

/// 文献库数据的版本号。Rust 是唯一写入方，没有变更通知：数据 provider 都
/// watch 它，任何经 Rust 写入文献、收藏、历史或笔记后调用 [bumpLibrary]。
final libraryEpochProvider = NotifierProvider<_LibraryEpoch, int>(
  _LibraryEpoch.new,
);

class _LibraryEpoch extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

void bumpLibrary(Ref ref) => ref.read(libraryEpochProvider.notifier).bump();

/// Rust 的 u32 上限；列表查询一次取全量。
const kAllRows = 0xFFFFFFFF;

int _ms(DateTime time) => time.millisecondsSinceEpoch;
DateTime _time(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

Document documentFromRust(rust.Document d) => Document(
  id: d.id,
  title: d.title,
  authors: d.authors,
  journal: d.journal,
  year: d.year,
  doi: d.doi,
  keywords: d.keywords,
  contentHash: d.contentHash,
  addedAt: _time(d.addedAt),
);

rust.Document documentToRust(Document d) => rust.Document(
  id: d.id,
  title: d.title,
  authors: d.authors,
  journal: d.journal,
  year: d.year,
  doi: d.doi,
  keywords: d.keywords,
  contentHash: d.contentHash,
  addedAt: _ms(d.addedAt),
);

Favorite favoriteFromRust(rust.Favorite f) => Favorite(
  id: f.id,
  emoji: f.emoji,
  name: f.name,
  documentIds: f.documentIds,
  createdAt: _time(f.createdAt),
);

rust.Favorite favoriteToRust(Favorite f) => rust.Favorite(
  id: f.id,
  emoji: f.emoji,
  name: f.name,
  documentIds: f.documentIds,
  createdAt: _ms(f.createdAt),
);

HistoryEntry historyFromRust(rust.History h) => HistoryEntry(
  docId: h.documentId,
  openedAt: _time(h.openedAt),
  progress: h.progress,
  anchorBlock: h.anchorBlock,
);

rust.History historyToRust(HistoryEntry h) => rust.History(
  documentId: h.docId,
  openedAt: _ms(h.openedAt),
  progress: h.progress,
  anchorBlock: h.anchorBlock,
);

Highlight highlightFromRust(rust.Note n) => Highlight(
  id: n.id,
  documentId: n.documentId,
  text: n.content,
  note: n.note,
  color: n.color,
  groupId: n.groupId,
  anchor: n.anchor == null
      ? null
      : (fromJsonData(n.anchor!) as Map?)?.cast<String, dynamic>(),
  createdAt: _time(n.createdAt),
);

rust.Note highlightToRust(Highlight h) => rust.Note(
  id: h.id,
  documentId: h.documentId,
  content: h.text,
  note: h.note,
  color: h.color,
  groupId: h.groupId,
  anchor: h.anchor == null ? null : toJsonData(h.anchor),
  createdAt: _ms(h.createdAt),
);
