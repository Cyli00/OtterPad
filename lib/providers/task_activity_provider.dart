import 'package:flutter/foundation.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

/// 进度型 SnackBar / 任务呈现处通用的进度数据。
///
/// 归属 Task Activity（progress DTO），由 `SnackBarService` re-export 以兼容旧 import。
class ListenableProgress {
  final int current;
  final int total;
  final String status;

  const ListenableProgress({
    required this.current,
    required this.total,
    required this.status,
  });
}

/// Task Activity 中的一个成员：一次正在运行的后台任务（Active Task）。
///
/// 由生产者（`TaskRunner.runTask` / `DocumentTaskNotifier` / 翻译等）汇报，
/// 携带稳定 [id]、[title]、进度 [progress] 与取消入口 [onCancel]。
@immutable
class ActiveTask {
  final int id;
  final String title;
  final ValueListenable<ListenableProgress> progress;
  final VoidCallback? onCancel;

  const ActiveTask({
    required this.id,
    required this.title,
    required this.progress,
    this.onCancel,
  });
}

/// Task Activity：应用中正在运行的后台任务的**活集合**，单一真值源。
///
/// 生产者 [report] / [finish]；呈现处（snackbar surface、未来的多文档任务面板）
/// 观察 [taskActivityProvider]，自行决定渲染（1 个显示完整进度，≥2 聚合）。
/// 仲裁不在此发生——这里只持有"哪些任务在跑"。
class TaskActivityNotifier extends StateNotifier<List<ActiveTask>> {
  TaskActivityNotifier() : super(const []);

  int _nextId = 0;

  /// 登记一个 Active Task，返回其稳定 id；用 [finish] 注销。
  int report({
    required ValueListenable<ListenableProgress> progress,
    String title = '',
    VoidCallback? onCancel,
  }) {
    final id = _nextId++;
    state = [
      ...state,
      ActiveTask(id: id, title: title, progress: progress, onCancel: onCancel),
    ];
    return id;
  }

  /// 注销一个 Active Task（完成 / 取消 / 失败统一走这里）。
  void finish(int id) {
    final next = [
      for (final task in state)
        if (task.id != id) task,
    ];
    if (next.length != state.length) state = next;
  }

  /// 取消当前全部 Active Task（聚合态"取消全部"）。
  void cancelAll() {
    for (final task in state) {
      task.onCancel?.call();
    }
  }
}

final taskActivityProvider =
    StateNotifierProvider<TaskActivityNotifier, List<ActiveTask>>((ref) {
      return TaskActivityNotifier();
    });
