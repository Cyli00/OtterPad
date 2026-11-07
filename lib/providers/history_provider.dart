import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_logger.dart';
import '../core/rust_backend.dart';
import '../core/rust_models.dart';
import '../data/models/book/document.dart';
import '../data/models/book/history_entry.dart';
import '../src/rust/api.dart';
import 'documents_provider.dart' show validDocsProvider;

export '../data/models/book/history_entry.dart';

/// 阅读历史：按打开时间倒序，同一文献只保留最近一次（重新打开即冒泡到顶）。
class HistoryNotifier extends AsyncNotifier<List<HistoryEntry>> {
  static const _maxEntries = 500;

  /// 阅读器高频上报进度，2s 内最多写一次；退出阅读器时 [flushProgress]。
  Timer? _progressDebounce;
  static const _progressDebounceDelay = Duration(seconds: 2);
  HistoryEntry? _pendingProgress;

  Backend get _rust => RustBackend.instance;

  @override
  Future<List<HistoryEntry>> build() async {
    ref.watch(libraryEpochProvider);
    ref.onDispose(() => _progressDebounce?.cancel());
    final rows = await _rust.history(limit: _maxEntries, offset: 0);
    return [for (final h in rows) historyFromRust(h)];
  }

  void reload() => ref.invalidateSelf();

  Future<HistoryEntry?> _find(String docId) async {
    final pending = _pendingProgress;
    if (pending?.docId == docId) return pending;
    for (final entry in state.value ?? const <HistoryEntry>[]) {
      if (entry.docId == docId) return entry;
    }
    for (final h in await _rust.history(limit: kAllRows, offset: 0)) {
      if (h.documentId == docId) return historyFromRust(h);
    }
    return null;
  }

  /// 本地更新列表，不重读全部历史（进度写入频繁）。
  void _apply(HistoryEntry entry, {bool bubble = false}) {
    final list = [...?state.value];
    final at = list.indexWhere((e) => e.docId == entry.docId);
    if (at >= 0) list.removeAt(at);
    list.insert(bubble || at < 0 ? 0 : at, entry);
    state = AsyncData(list);
  }

  /// 记录一次打开：冒泡到顶，继承旧进度与锚点。
  Future<void> record(String docId) async {
    final prev = await _find(docId);
    final entry = HistoryEntry(
      docId: docId,
      openedAt: DateTime.now(),
      progress: prev?.progress ?? 0.0,
      anchorBlock: prev?.anchorBlock,
    );
    await _rust.recordHistory(entry: historyToRust(entry));
    _apply(entry, bubble: true);
  }

  Future<void> removeDoc(String docId) async {
    await _rust.clearHistory(document: docId);
    ref.invalidateSelf();
  }

  Future<void> clear() async {
    await _rust.clearHistory();
    ref.invalidateSelf();
  }

  /// 更新已有记录的进度与锚点；从未打开过的文献忽略。写盘 2s 防抖。
  Future<void> setProgress(
    String docId,
    double progress, {
    String? anchorBlock,
  }) async {
    final clamped = progress.clamp(0.0, 1.0).toDouble();
    final old = await _find(docId);
    if (old == null) return;
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
    _apply(updated);
    _progressDebounce?.cancel();
    _progressDebounce = Timer(_progressDebounceDelay, () {
      final pending = _pendingProgress;
      _pendingProgress = null;
      if (pending == null) return;
      unawaited(
        _rust.recordHistory(entry: historyToRust(pending)).catchError((
          Object e,
          StackTrace st,
        ) {
          log.w('[History] 进度保存失败', error: e, stackTrace: st);
        }),
      );
    });
  }

  /// 退出阅读器时立即写入待保存的进度。
  Future<void> flushProgress() async {
    _progressDebounce?.cancel();
    _progressDebounce = null;
    final pending = _pendingProgress;
    _pendingProgress = null;
    if (pending != null) {
      await _rust.recordHistory(entry: historyToRust(pending));
    }
  }
}

final historyProvider =
    AsyncNotifierProvider<HistoryNotifier, List<HistoryEntry>>(
      HistoryNotifier.new,
    );

/// 单文档阅读进度（无记录 = 0.0）。select 在值未变时抑制重建。
/// 直接选择历史流，避免 Sliver 布局中读取卡片时补算中间 Map，
/// 再同步失效其他进度 provider，触发 ProviderScope 在构建期刷新。
final docProgressProvider = Provider.family<double, String>((ref, docId) {
  return ref.watch(
    historyProvider.select((history) {
      for (final entry in history.value ?? const <HistoryEntry>[]) {
        if (entry.docId == docId) return entry.progress;
      }
      return 0.0;
    }),
  );
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
