// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:hive/hive.dart';

import '../core/storage/storage.dart';
import '../data/models/book/document.dart';
import 'documents_provider.dart';

/// 单次阅读事件：记录文档 id 与打开时间。
///
/// 阅读历史作为独立事件流存储，而非 Document 模型的衍生字段——
/// 这样后续要加阅读时长/进度/次数等维度时不必改动 Document。
class HistoryEntry {
  final String docId;
  final DateTime openedAt;

  const HistoryEntry({required this.docId, required this.openedAt});

  Map<String, dynamic> toMap() => {
        'docId': docId,
        'openedAt': openedAt.toIso8601String(),
      };

  factory HistoryEntry.fromMap(Map map) => HistoryEntry(
        docId: map['docId'] as String,
        openedAt: DateTime.parse(map['openedAt'] as String),
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
  final docs = ref.watch(documentsProvider);
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
