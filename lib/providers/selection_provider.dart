import 'package:flutter/foundation.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

/// 多选模式状态
///
/// [sourceContext] 区分来源页面，确保不同页面的选择互不干扰：
/// - `'library'`：主文献库
/// - `'favorite:<id>'`：收藏夹详情页
/// - `'nofile'`：无文件条目页
@immutable
class SelectionState {
  final bool isActive;
  final Set<String> selectedIds;
  final String? sourceContext;
  final String? anchorId;

  const SelectionState({
    this.isActive = false,
    this.selectedIds = const {},
    this.sourceContext,
    this.anchorId,
  });

  static const _unset = Object();

  SelectionState copyWith({
    bool? isActive,
    Set<String>? selectedIds,
    String? sourceContext,
    Object? anchorId = _unset,
  }) {
    return SelectionState(
      isActive: isActive ?? this.isActive,
      selectedIds: selectedIds ?? this.selectedIds,
      sourceContext: sourceContext ?? this.sourceContext,
      anchorId: identical(anchorId, _unset)
          ? this.anchorId
          : anchorId as String?,
    );
  }
}

class SelectionNotifier extends StateNotifier<SelectionState> {
  SelectionNotifier() : super(const SelectionState());

  /// 长按卡片进入多选模式，预选中触发的卡片
  void enter(String docId, String sourceContext) {
    state = SelectionState(
      isActive: true,
      selectedIds: {docId},
      sourceContext: sourceContext,
      anchorId: docId,
    );
  }

  /// 切换选中/取消；取消后若无选中项仍保持多选模式
  void toggle(String docId) {
    if (!state.isActive) return;
    final ids = Set<String>.from(state.selectedIds);
    if (ids.contains(docId)) {
      ids.remove(docId);
    } else {
      ids.add(docId);
    }
    state = state.copyWith(selectedIds: ids);
  }

  /// 全选/取消全选
  void toggleAll(Set<String> allIds) {
    if (!state.isActive) return;
    if (state.selectedIds.containsAll(allIds)) {
      state = state.copyWith(selectedIds: {});
    } else {
      state = state.copyWith(selectedIds: {...state.selectedIds, ...allIds});
    }
  }

  /// 从 [anchorId] 到 [toId] 含端点，并入当前选中集合。
  void selectRange({required List<String> orderedIds, required String toId}) {
    if (!state.isActive) return;
    final fromId = state.anchorId ?? toId;
    var from = orderedIds.indexOf(fromId);
    final to = orderedIds.indexOf(toId);
    if (to < 0) return;
    if (from < 0) from = to;
    final start = from < to ? from : to;
    final end = from < to ? to : from;
    state = state.copyWith(
      selectedIds: {
        ...state.selectedIds,
        ...orderedIds.sublist(start, end + 1),
      },
    );
  }

  /// 退出多选模式，清空所有状态
  void exit() {
    state = const SelectionState();
  }
}

final selectionProvider =
    StateNotifierProvider<SelectionNotifier, SelectionState>(
      (ref) => SelectionNotifier(),
    );
