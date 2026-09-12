import 'dart:async';
import '../core/app_logger.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show OrderingTerm;

import '../core/storage/app_database.dart' show AppDatabase;
import '../core/storage/app_database_provider.dart';
import '../core/storage/db_convert.dart';
import '../data/models/book/document.dart';
import 'documents_provider.dart' show validDocsProvider;

import '../data/models/book/history_entry.dart';

export '../data/models/book/history_entry.dart';

/// 阅读历史：按时间倒序的 HistoryEntry 列表（ADR-0001：Drift `watch()` 异步视图）。
///
/// 语义：同一 docId 只保留最近一次（重新打开 = 冒泡到顶），
/// 这样列表恒为"去重的最近阅读序列"。查询取最近 500（bubble 语义）。
class HistoryNotifier extends StreamNotifier<List<HistoryEntry>> {
  static const _maxEntries = 500;

  /// 进度写盘防抖：阅读器内部高频更新（Markdown 滚动每 500ms 触发一次）
  /// 时不立即 flush 到 Drift，2s 内最多一次磁盘写；reader dispose 时
  /// 调 [flushProgress] 强制立即落盘。
  Timer? _progressDebounce;
  static const _progressDebounceDelay = Duration(seconds: 2);
  HistoryEntry? _pendingProgress;

  @override
  Stream<List<HistoryEntry>> build() {
    final db = ref.watch(appDatabaseProvider);
    ref.onDispose(() => _progressDebounce?.cancel());
    return (db.select(db.history)
          ..orderBy([(t) => OrderingTerm.desc(t.openedAt)])
          ..limit(_maxEntries))
        .map(historyFromRow)
        .watch();
  }

  void reload() => ref.invalidateSelf();

  /// Drift 实例统一经 [appDatabaseProvider] 取（唯一来源，禁止直用 GStorage.db）。
  AppDatabase get _db => ref.read(appDatabaseProvider);

  Future<void> _upsert(HistoryEntry e) async {
    await _db.into(_db.history).insertOnConflictUpdate(historyCompanion(e));
  }

  Future<void> _delete(String docId) async {
    await (_db.delete(_db.history)..where((t) => t.docId.equals(docId))).go();
  }

  Future<void> _deleteMany(Iterable<String> docIds) async {
    if (docIds.isEmpty) return;
    await (_db.delete(_db.history)..where((t) => t.docId.isIn(docIds))).go();
  }

  /// 仅保留最近 _maxEntries 条（按 openedAt 倒序），其余从 Drift 删除。
  Future<void> _cap() async {
    await _db.customStatement(
      'DELETE FROM history WHERE docId NOT IN '
      '(SELECT docId FROM history ORDER BY openedAt DESC LIMIT $_maxEntries)',
    );
  }

  /// 按 docId 从 DB 查单条（唯一真值源）——不读 watch() 流 state，
  /// 避免冷启动流未 emit 时误判无记录。
  Future<HistoryEntry?> _findByDocId(String docId) async {
    final row = await (_db.select(
      _db.history,
    )..where((t) => t.docId.equals(docId))).getSingleOrNull();
    return row == null ? null : historyFromRow(row);
  }

  /// 记录一次阅读：已存在同 docId 时 upsert（冒泡到顶，进度/锚点继承旧 entry）。
  /// 旧 entry 从 DB 读——冷启动经「继续阅读」直入阅读器时流未 emit，
  /// 若读流 state 会误判 prev=null 把进度清零，阅读位置恢复
  /// （view.dart initState 读取）拿到的永远是 0。
  Future<void> record(String docId) async {
    final prev = await _findByDocId(docId);
    final entry = HistoryEntry(
      docId: docId,
      openedAt: DateTime.now(),
      progress: prev?.progress ?? 0.0,
      anchorBlock: prev?.anchorBlock,
    );
    await _upsert(entry);
    await _cap();
  }

  Future<void> removeDoc(String docId) => _delete(docId);

  Future<void> removeMany(Set<String> docIds) => _deleteMany(docIds);

  Future<void> clear() async {
    await _db.delete(_db.history).go();
  }

  /// 更新阅读进度。写盘走 2s 防抖；流自动刷新 state（ADR-0001 非乐观）。
  ///
  /// 仅更新已存在 entry 的 progress——`record(docId)` 在 reader 入口已建好
  /// entry，从未打开过的文献忽略。基准行优先取防抖窗口内的 pending，其次
  /// 查 DB（不读流 state：冷启动流未 emit 会误判无 entry 而丢进度）。
  Future<void> setProgress(
    String docId,
    double progress, {
    int? anchorBlock,
  }) async {
    final clamped = progress.clamp(0.0, 1.0).toDouble();
    var old = _pendingProgress?.docId == docId ? _pendingProgress : null;
    old ??= await _findByDocId(docId);
    if (old == null) return;
    // 同进度同锚点不写盘，避免无谓磁盘 IO
    if ((old.progress - clamped).abs() < 1e-4 &&
        old.anchorBlock == anchorBlock) {
      return;
    }
    final updated = HistoryEntry(
      docId: old.docId,
      openedAt: old.openedAt,
      progress: clamped,
      anchorBlock: anchorBlock,
    );

    _pendingProgress = updated;
    _progressDebounce?.cancel();
    _progressDebounce = Timer(_progressDebounceDelay, () {
      final pending = _pendingProgress;
      _pendingProgress = null;
      if (pending != null) {
        unawaited(
          _upsert(pending).catchError((Object e, StackTrace st) {
            log.w('[History] 进度保存失败', error: e, stackTrace: st);
          }),
        );
      }
    });
  }

  /// reader dispose / 退出阅读器时调，强制立即写盘，避免崩溃丢最后一次更新。
  Future<void> flushProgress() async {
    if (_progressDebounce?.isActive ?? false) {
      _progressDebounce!.cancel();
      _progressDebounce = null;
      final pending = _pendingProgress;
      _pendingProgress = null;
      if (pending != null) await _upsert(pending);
    }
  }
}

final historyProvider =
    StreamNotifierProvider<HistoryNotifier, List<HistoryEntry>>(
      HistoryNotifier.new,
    );

/// 派生：docId → 阅读进度。中间层隔离高频 progress 更新——
/// 卡片经 [docProgressProvider] 按 docId select 订阅，只在自己那一条进度
/// 变化时重建；书架顶层不再 watch 整个 historyProvider（此前阅读器每
/// 500ms 的 setProgress 会让导航栈下层的书架页全列表 rebuild）。
final _progressByDocProvider = Provider<Map<String, double>>((ref) {
  final history = ref.watch(historyProvider).value ?? const <HistoryEntry>[];
  return {for (final e in history) e.docId: e.progress};
});

/// 单文档阅读进度（无记录 = 0.0）。select 在值未变时抑制重建。
final docProgressProvider = Provider.family<double, String>((ref, docId) {
  return ref.watch(_progressByDocProvider.select((m) => m[docId] ?? 0.0));
});

/// 历史分组区段：一个日期桶及其下属文档列表。
enum HistoryPeriod { today, yesterday, thisWeek, thisMonth, month }

class HistorySection {
  final HistoryPeriod period;
  final DateTime? month;
  final List<Document> docs;
  const HistorySection({required this.period, required this.docs, this.month});
}

/// 派生：按日期桶分组后的历史视图。
///
/// 桶顺序（从上到下）：今天 / 昨天 / 本周 / 本月 / YYYY年M月…
/// 每个桶互斥——靠分支顺序隐式保证优先级。
final historySectionsProvider = Provider<List<HistorySection>>((ref) {
  final history = ref.watch(historyProvider).value ?? const <HistoryEntry>[];
  // 只索引有文件的文献——无 PDF 的元数据条目（contentHash == null）不能打开阅读器，
  // 出现在历史里只会让人困惑、点了无反应。
  final docs = ref.watch(validDocsProvider);
  final byId = {for (final d in docs) d.id: d};

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  // 本周起点：今天往前推 7 天（不含边界）
  final weekStart = today.subtract(const Duration(days: 7));
  final monthStart = DateTime(now.year, now.month, 1);

  final todayDocs = <Document>[];
  final yesterdayDocs = <Document>[];
  final thisWeekDocs = <Document>[];
  final thisMonthDocs = <Document>[];
  final olderBuckets = <DateTime, List<Document>>{};

  for (final entry in history) {
    final doc = byId[entry.docId];
    if (doc == null) continue; // 指向已删除的文档，跳过
    final d = DateTime(
      entry.openedAt.year,
      entry.openedAt.month,
      entry.openedAt.day,
    );
    if (!d.isBefore(today)) {
      todayDocs.add(doc);
    } else if (d == yesterday) {
      yesterdayDocs.add(doc);
    } else if (d.isAfter(weekStart)) {
      thisWeekDocs.add(doc);
    } else if (!d.isBefore(monthStart)) {
      thisMonthDocs.add(doc);
    } else {
      final key = DateTime(entry.openedAt.year, entry.openedAt.month);
      olderBuckets.putIfAbsent(key, () => <Document>[]).add(doc);
    }
  }

  final sections = <HistorySection>[];
  if (todayDocs.isNotEmpty) {
    sections.add(HistorySection(period: HistoryPeriod.today, docs: todayDocs));
  }
  if (yesterdayDocs.isNotEmpty) {
    sections.add(
      HistorySection(period: HistoryPeriod.yesterday, docs: yesterdayDocs),
    );
  }
  if (thisWeekDocs.isNotEmpty) {
    sections.add(
      HistorySection(period: HistoryPeriod.thisWeek, docs: thisWeekDocs),
    );
  }
  if (thisMonthDocs.isNotEmpty) {
    sections.add(
      HistorySection(period: HistoryPeriod.thisMonth, docs: thisMonthDocs),
    );
  }
  olderBuckets.forEach((month, docs) {
    sections.add(
      HistorySection(period: HistoryPeriod.month, month: month, docs: docs),
    );
  });

  return sections;
});

/// 当前历史中仍然有效的文档总数（已过滤掉已删除文档）
final historyCountProvider = Provider<int>((ref) {
  return ref
      .watch(historySectionsProvider)
      .fold<int>(0, (sum, s) => sum + s.docs.length);
});
