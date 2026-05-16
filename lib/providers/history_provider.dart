import 'dart:async';

// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:hive/hive.dart';

import '../core/storage/storage.dart';
import '../data/models/book/document.dart';
import 'documents_provider.dart' show validDocsProvider;

/// 单次阅读事件：记录文档 id、打开时间、阅读进度。
///
/// 阅读历史作为独立事件流存储，而非 Document 模型的衍生字段——
/// 这样后续要加阅读时长/进度/次数等维度时不必改动 Document。
///
/// `progress` 含义：0.0 = 未读/未滚动；1.0 = 读到底。PDF 模式用
/// `currentPage / totalPages`，Markdown 模式用 `scrollTop / (scrollHeight - viewHeight)`。
/// 老版本 Hive 数据无 `progress` 字段时回退 0.0。
class HistoryEntry {
  final String docId;
  final DateTime openedAt;
  final double progress;

  const HistoryEntry({
    required this.docId,
    required this.openedAt,
    this.progress = 0.0,
  });

  HistoryEntry copyWith({DateTime? openedAt, double? progress}) {
    return HistoryEntry(
      docId: docId,
      openedAt: openedAt ?? this.openedAt,
      progress: progress ?? this.progress,
    );
  }

  Map<String, dynamic> toMap() => {
        'docId': docId,
        'openedAt': openedAt.toIso8601String(),
        'progress': progress,
      };

  factory HistoryEntry.fromMap(Map map) => HistoryEntry(
        docId: map['docId'] as String,
        openedAt: DateTime.parse(map['openedAt'] as String),
        progress: (map['progress'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0.0,
      );
}

/// 阅读历史：按时间倒序的 HistoryEntry 列表。
///
/// 语义：同一 docId 只保留最近一次（重新打开 = 冒泡到顶），
/// 这样列表恒为"去重的最近阅读序列"。
class HistoryNotifier extends StateNotifier<List<HistoryEntry>> {
  final Box _box;
  static const _key = 'entries';
  static const _maxEntries = 500;

  /// 进度写盘防抖：阅读器内部高频更新（Markdown 滚动每 500ms 触发一次）
  /// 时不立即 flush 到 Hive，2s 内最多一次磁盘写；reader dispose 时
  /// 调 [flushProgress] 强制立即落盘。
  Timer? _progressDebounce;
  static const _progressDebounceDelay = Duration(seconds: 2);

  HistoryNotifier(this._box) : super(<HistoryEntry>[]) {
    _load();
  }

  void _load() {
    final raw = _box.get(_key) as List<dynamic>?;
    if (raw == null) return;
    state = raw
        .map((e) => HistoryEntry.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> _save() async {
    await _box.put(_key, state.map((e) => e.toMap()).toList());
  }

  /// 记录一次阅读：已存在同 docId 时先移除再插入顶部（冒泡）。
  void record(String docId) {
    final now = DateTime.now();
    final next = <HistoryEntry>[
      HistoryEntry(docId: docId, openedAt: now),
      ...state.where((e) => e.docId != docId),
    ];
    if (next.length > _maxEntries) {
      next.removeRange(_maxEntries, next.length);
    }
    state = next;
    _save();
  }

  void removeDoc(String docId) {
    final next = state.where((e) => e.docId != docId).toList();
    if (next.length == state.length) return;
    state = next;
    _save();
  }

  void removeMany(Set<String> docIds) {
    if (docIds.isEmpty) return;
    final next = state.where((e) => !docIds.contains(e.docId)).toList();
    if (next.length == state.length) return;
    state = next;
    _save();
  }

  void clear() {
    if (state.isEmpty) return;
    state = <HistoryEntry>[];
    _save();
  }

  /// 更新阅读进度。state 立即更新（让网格卡片 UI 实时刷新），写盘走 2s 防抖。
  ///
  /// 注意：仅更新已存在 entry 的 progress；如果文献从未打开过（无 HistoryEntry）
  /// 则直接忽略——`record(docId)` 在 reader 入口已经先建好 entry 了。
  void setProgress(String docId, double progress) {
    final clamped = progress.clamp(0.0, 1.0);
    final idx = state.indexWhere((e) => e.docId == docId);
    if (idx < 0) return;
    final old = state[idx];
    // 同进度不动 state，避免无谓 rebuild
    if ((old.progress - clamped).abs() < 1e-4) return;
    final next = [...state];
    next[idx] = old.copyWith(progress: clamped);
    state = next;

    _progressDebounce?.cancel();
    _progressDebounce = Timer(_progressDebounceDelay, _save);
  }

  /// reader dispose / 退出阅读器时调，强制立即写盘，避免崩溃丢最后一次更新。
  Future<void> flushProgress() async {
    if (_progressDebounce?.isActive ?? false) {
      _progressDebounce!.cancel();
      _progressDebounce = null;
      await _save();
    }
  }

  @override
  void dispose() {
    _progressDebounce?.cancel();
    super.dispose();
  }
}

final historyProvider =
    StateNotifierProvider<HistoryNotifier, List<HistoryEntry>>((ref) {
  return HistoryNotifier(GStorage.history);
});

/// 历史分组区段：一个日期桶及其下属文档列表。
class HistorySection {
  final String label;
  final List<Document> docs;
  const HistorySection({required this.label, required this.docs});
}

/// 派生：按日期桶分组后的历史视图。
///
/// 桶顺序（从上到下）：今天 / 昨天 / 本周 / 本月 / YYYY年M月…
/// 每个桶互斥——靠分支顺序隐式保证优先级。
final historySectionsProvider = Provider<List<HistorySection>>((ref) {
  final history = ref.watch(historyProvider);
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
  final olderBuckets = <String, List<Document>>{};

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
      final key = '${entry.openedAt.year}年${entry.openedAt.month}月';
      olderBuckets.putIfAbsent(key, () => <Document>[]).add(doc);
    }
  }

  final sections = <HistorySection>[];
  if (todayDocs.isNotEmpty) {
    sections.add(HistorySection(label: '今天', docs: todayDocs));
  }
  if (yesterdayDocs.isNotEmpty) {
    sections.add(HistorySection(label: '昨天', docs: yesterdayDocs));
  }
  if (thisWeekDocs.isNotEmpty) {
    sections.add(HistorySection(label: '本周', docs: thisWeekDocs));
  }
  if (thisMonthDocs.isNotEmpty) {
    sections.add(HistorySection(label: '本月', docs: thisMonthDocs));
  }
  olderBuckets.forEach((label, docs) {
    sections.add(HistorySection(label: label, docs: docs));
  });

  return sections;
});

/// 当前历史中仍然有效的文档总数（已过滤掉已删除文档）
final historyCountProvider = Provider<int>((ref) {
  return ref
      .watch(historySectionsProvider)
      .fold<int>(0, (sum, s) => sum + s.docs.length);
});
