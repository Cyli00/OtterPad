import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_logger.dart';
import '../core/rust_backend.dart';
import '../core/rust_models.dart';
import '../data/models/book/highlight.dart';
import '../src/rust/api.dart';
import '../utils/uuid.dart';

/// 按文献 id 管理的划线与笔记。数据在 Rust；删除文献时随之级联删除。
class HighlightNotifier extends AsyncNotifier<List<Highlight>> {
  HighlightNotifier(this.documentId);

  final String documentId;

  Backend get _rust => RustBackend.instance;

  @override
  Future<List<Highlight>> build() async {
    ref.watch(libraryEpochProvider);
    final notes = await _rust.notes(document: documentId);
    return [for (final n in notes) highlightFromRust(n)];
  }

  List<Highlight> get _current => state.value ?? const <Highlight>[];

  Future<void> _put(Highlight h) async {
    await _rust.putNote(note: highlightToRust(h));
    ref.invalidateSelf();
  }

  /// 新增标注并同步返回，便于阅读器立即绘制；写盘在后台完成。
  /// 同一文字、同一锚点已存在时返回 null。
  Highlight? add(
    String text, {
    String color = kDefaultHighlightColor,
    Map<String, dynamic>? anchor,
    String? groupId,
  }) {
    if (_current.any((h) => h.text == text && '${h.anchor}' == '$anchor')) {
      return null;
    }
    final highlight = Highlight(
      id: generateUuid(),
      documentId: documentId,
      text: text,
      color: color,
      groupId: groupId,
      anchor: anchor,
      createdAt: DateTime.now(),
    );
    state = AsyncData([..._current, highlight]);
    unawaited(
      _put(highlight).catchError((Object e, StackTrace st) {
        log.w('[Highlight] 标注保存失败：$documentId', error: e, stackTrace: st);
      }),
    );
    return highlight;
  }

  /// 按 id 新增或覆盖（阅读器标注的保存回调）。
  Future<void> save(Highlight highlight) async {
    final list = [..._current];
    final at = list.indexWhere((h) => h.id == highlight.id);
    if (at >= 0) {
      list[at] = highlight;
    } else {
      list.add(highlight);
    }
    state = AsyncData(list);
    await _put(highlight);
  }

  /// 只删除这一条，不联动同组。
  Future<void> delete(String id) async {
    state = AsyncData([
      for (final h in _current)
        if (h.id != id) h,
    ]);
    await _rust.deleteNote(id: id);
    ref.invalidateSelf();
  }

  Highlight? _find(String id) {
    for (final h in _current) {
      if (h.id == id) return h;
    }
    return null;
  }

  /// 删除标注；同一次跨段选择产生的同组标注一起删除。
  Future<void> remove(String highlightId) async {
    final target = _find(highlightId);
    if (target == null) return;
    final group = target.groupId;
    final ids = group == null
        ? [highlightId]
        : [
            for (final h in _current)
              if (h.groupId == group) h.id,
          ];
    for (final id in ids) {
      await _rust.deleteNote(id: id);
    }
    ref.invalidateSelf();
  }

  Future<void> updateColor(String highlightId, String color) async {
    final match = _find(highlightId);
    if (match != null) await _put(match.withColor(color));
  }

  Future<void> updateNote(String highlightId, String note) async {
    final match = _find(highlightId);
    if (match != null) await _put(match.withNote(note.isEmpty ? null : note));
  }
}

final highlightProvider =
    AsyncNotifierProvider.family<HighlightNotifier, List<Highlight>, String>(
      HighlightNotifier.new,
    );
