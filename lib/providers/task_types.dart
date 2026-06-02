import 'package:dio/dio.dart';

/// 后台任务类型。新增任务先在这里加一个值。
enum TaskType { addFiles, addByIdentifier, rebuild, zoteroSync }

/// 任务运行状态。
enum TaskStatus { running, completed, cancelled, failed }

/// 任务运行信息：当前状态 + 关联的 CancelToken。
class TaskInfo {
  final TaskType type;
  final TaskStatus status;
  final CancelToken cancelToken;

  const TaskInfo({
    required this.type,
    required this.status,
    required this.cancelToken,
  });

  TaskInfo copyWith({TaskStatus? status}) => TaskInfo(
    type: type,
    status: status ?? this.status,
    cancelToken: cancelToken,
  );
}
