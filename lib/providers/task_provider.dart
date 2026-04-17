import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../router/app_router.dart';
import '../router/app_routes.dart';
import '../services/batch_extract_service.dart';
import '../services/doc_extract_service.dart';
import '../services/identifier_resolver.dart';
import '../services/snackbar_service.dart';
import 'api_provider.dart';
import 'documents_provider.dart';

enum TaskType { addFiles, addByIdentifier, rebuild, redownloadPdf, extractDocument }

enum TaskStatus { running, completed, cancelled, failed }

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

class TaskNotifier extends StateNotifier<Map<TaskType, TaskInfo>> {
  final Ref _ref;

  TaskNotifier(this._ref) : super({});

  SnackBarService get _snackBar => _ref.read(snackBarServiceProvider);
  DocumentsNotifier get _docs => _ref.read(documentsProvider.notifier);
  GoRouter get _router => _ref.read(routerProvider);

  bool isRunning(TaskType type) =>
      state[type]?.status == TaskStatus.running;

  void cancelTask(TaskType type) {
    final task = state[type];
    if (task == null || task.status != TaskStatus.running) return;
    task.cancelToken.cancel();
    state = {...state, type: task.copyWith(status: TaskStatus.cancelled)};
    _snackBar.hide();
  }

  void _startTask(TaskType type, CancelToken token) {
    state = {
      ...state,
      type: TaskInfo(type: type, status: TaskStatus.running, cancelToken: token),
    };
  }

  void _finishTask(TaskType type, TaskStatus status) {
    state = {...state, type: state[type]!.copyWith(status: status)};
  }

  // ── 添加文件 ──

  Future<void> addFiles(List<String> paths) async {
    if (isRunning(TaskType.addFiles)) {
      _snackBar.showResult(message: '正在导入文件，请稍候');
      return;
    }

    final token = CancelToken();
    _startTask(TaskType.addFiles, token);

    var importedCount = 0;
    var duplicateCount = 0;
    var completeMetadataCount = 0;
    var partialMetadataCount = 0;
    AddFileResult? lastResult;

    try {
      for (int i = 0; i < paths.length; i++) {
        if (token.isCancelled) break;

        _snackBar.showProgress(
          current: i + 1,
          total: paths.length,
          fileName: p.basename(paths[i]),
          status: '正在提取 PDF 元数据...',
          onCancel: () => cancelTask(TaskType.addFiles),
        );

        lastResult = await _docs.addFile(paths[i], cancelToken: token);

        if (lastResult.type == AddFileResultType.duplicate) {
          duplicateCount++;
          continue;
        }

        importedCount++;
        if (lastResult.metadataStatus == MetadataStatus.complete) {
          completeMetadataCount++;
        } else if (lastResult.metadataStatus == MetadataStatus.partial) {
          partialMetadataCount++;
        }
      }

      _snackBar.hide();

      if (token.isCancelled) {
        _finishTask(TaskType.addFiles, TaskStatus.cancelled);
        return;
      }

      _finishTask(TaskType.addFiles, TaskStatus.completed);

      final unresolvedMetadataCount =
          importedCount - completeMetadataCount - partialMetadataCount;
      final message = _buildAddFileMessage(
        cancelled: token.isCancelled,
        totalFiles: paths.length,
        importedCount: importedCount,
        duplicateCount: duplicateCount,
        completeMetadataCount: completeMetadataCount,
        partialMetadataCount: partialMetadataCount,
        unresolvedMetadataCount: unresolvedMetadataCount,
        lastResult: lastResult,
      );
      _snackBar.showResult(message: message);
    } catch (_) {
      _snackBar.hide();
      _finishTask(TaskType.addFiles, TaskStatus.failed);
    }
  }

  // ── 通过标识符添加 ──

  Future<void> addByIdentifier(String identifier) async {
    if (isRunning(TaskType.addByIdentifier)) {
      _snackBar.showResult(message: '正在解析标识符，请稍候');
      return;
    }

    final token = CancelToken();
    _startTask(TaskType.addByIdentifier, token);

    _snackBar.showProgress(
      current: 1,
      total: 1,
      fileName: identifier,
      status: '正在解析标识符...',
      onCancel: () => cancelTask(TaskType.addByIdentifier),
      duration: const Duration(seconds: 30),
    );

    try {
      final (doc, addResult) =
          await _docs.addByIdentifier(identifier, cancelToken: token);

      _snackBar.hide();

      if (token.isCancelled) {
        _finishTask(TaskType.addByIdentifier, TaskStatus.cancelled);
        return;
      }

      _finishTask(TaskType.addByIdentifier, TaskStatus.completed);

      if (addResult == AddByIdentifierResult.duplicate) {
        _snackBar.showResult(message: '该文献已存在于文库中');
      } else if (doc.filePath.isEmpty) {
        _snackBar.showResult(
          message: '已添加「${doc.title}」，但未获取到关联 PDF',
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: '去添加',
            onPressed: () => _router.push(AppRoutes.shelfNoFileEntries),
          ),
        );
      } else {
        _snackBar.showResult(message: '已添加: ${doc.title}');
      }
    } on IdentifierResolveException catch (error) {
      _snackBar.hide();
      if (token.isCancelled) {
        _finishTask(TaskType.addByIdentifier, TaskStatus.cancelled);
        return;
      }
      _finishTask(TaskType.addByIdentifier, TaskStatus.failed);
      _snackBar.showResult(message: error.message);
    } on DioException {
      _snackBar.hide();
      if (token.isCancelled) {
        _finishTask(TaskType.addByIdentifier, TaskStatus.cancelled);
        return;
      }
      _finishTask(TaskType.addByIdentifier, TaskStatus.failed);
      _snackBar.showResult(message: '网络请求失败，请稍后重试');
    }
  }

  // ── 重构文库 ──

  Future<void> rebuildLibrary() async {
    if (isRunning(TaskType.rebuild)) {
      _snackBar.showResult(message: '文库重构正在进行中');
      return;
    }

    final token = CancelToken();
    _startTask(TaskType.rebuild, token);

    _snackBar.showProgress(
      fileName: 'NightReader 文库',
      status: '准备重构文库...',
      onCancel: () => cancelTask(TaskType.rebuild),
    );

    RebuildResult? result;
    try {
      result = await _docs.rebuild(
        cancelToken: token,
        onProgress: (progress) {
          if (token.isCancelled) return;
          _snackBar.showProgress(
            current: progress.current,
            total: progress.total,
            fileName: progress.fileName,
            status: progress.status,
            onCancel: () => cancelTask(TaskType.rebuild),
          );
        },
      );
    } on DioException {
      // CancelToken 取消时 Dio 会抛异常，静默处理
    }

    _snackBar.hide();

    if (token.isCancelled) {
      _finishTask(TaskType.rebuild, TaskStatus.cancelled);
    } else {
      _finishTask(TaskType.rebuild, TaskStatus.completed);
    }

    var message = token.isCancelled ? '已取消重构文库' : '文库重构完成';
    if (result != null) {
      final parts = <String>[];
      if (result.addedCount > 0) parts.add('新增 ${result.addedCount} 篇');
      if (result.removedCount > 0) parts.add('清理 ${result.removedCount} 篇');
      if (result.downloadedCount > 0) {
        parts.add('补回 PDF ${result.downloadedCount} 篇');
      }
      if (result.repairedCount > 0) {
        parts.add('修复元数据 ${result.repairedCount} 篇');
      }
      if (result.unresolvedCount > 0) {
        parts.add('仍有 ${result.unresolvedCount} 篇待补全元数据');
      }
      if (result.noFileCount > 0) {
        parts.add('${result.noFileCount} 个无文件条目');
      }
      if (parts.isEmpty) {
        message += '，文库状态正常';
      } else {
        message += '：${parts.join('，')}';
      }
    }

    _snackBar.showResult(message: message);
  }

  // ── 重新下载 PDF ──

  Future<void> redownloadPdf(String docId, String docTitle) async {
    if (isRunning(TaskType.redownloadPdf)) {
      _snackBar.showResult(message: '正在下载中，请稍候');
      return;
    }

    final token = CancelToken();
    _startTask(TaskType.redownloadPdf, token);

    _snackBar.showProgress(
      current: 1,
      total: 1,
      fileName: docTitle,
      status: '正在重新下载...',
      onCancel: () => cancelTask(TaskType.redownloadPdf),
      duration: const Duration(seconds: 30),
    );

    final success =
        await _docs.redownloadPdf(docId, cancelToken: token);

    _snackBar.hide();

    if (token.isCancelled) {
      _finishTask(TaskType.redownloadPdf, TaskStatus.cancelled);
      return;
    }

    _finishTask(
      TaskType.redownloadPdf,
      success ? TaskStatus.completed : TaskStatus.failed,
    );
    _snackBar.showResult(
      message: success ? '下载成功：$docTitle' : '下载失败，未找到可用的 PDF 源',
    );
  }

  // ── 文档提取 ──

  Future<void> extractDocument({
    required String filePath,
    required String title,
    required DocExtractApiState apiState,
    required void Function(String mdPath, String markdownContent) onSuccess,
  }) async {
    if (isRunning(TaskType.extractDocument)) {
      _snackBar.showResult(message: '正在提取文档，请稍候');
      return;
    }

    if (!apiState.isConfigured) {
      _snackBar.showResult(
        message: '请先在设置中配置文档提取 Access Token',
        action: SnackBarAction(
          label: '前往设置',
          onPressed: () => _router.push(AppRoutes.settingsExtract),
        ),
      );
      return;
    }

    final token = CancelToken();
    _startTask(TaskType.extractDocument, token);

    _snackBar.showProgress(
      fileName: title,
      status: '正在提交任务…',
      onCancel: () => cancelTask(TaskType.extractDocument),
      duration: const Duration(minutes: 10),
    );

    try {
      final result = await _extractAsync(
        filePath: filePath,
        title: title,
        apiState: apiState,
        cancelToken: token,
      );

      if (token.isCancelled) return;

      // saveResult 通常 1-2 秒内完成，无需中间 snackbar；
      // 30 秒超时兜底，防止异常阻塞
      final savedMdPath = await DocExtractService.instance
          .saveResult(filePath, result, token: apiState.apiKey, title: title)
          .timeout(const Duration(seconds: 30));

      if (token.isCancelled) return;

      _finishTask(TaskType.extractDocument, TaskStatus.completed);
      _snackBar.showResult(
        message: '文档提取完成：$title',
        duration: const Duration(seconds: 6),
      );
      onSuccess(savedMdPath, result.processedMarkdown ?? '');
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel || token.isCancelled) {
        _snackBar.showResult(message: '已取消提取');
      } else {
        _snackBar.showResult(message: '网络错误: ${e.message}');
      }
    } on DocExtractException catch (e) {
      _snackBar.showResult(message: e.message);
    } on BatchExtractException catch (e) {
      _snackBar.showResult(message: e.message);
    } catch (e) {
      _snackBar.showResult(message: '提取失败: $e');
    } finally {
      final task = state[TaskType.extractDocument];
      if (task?.status == TaskStatus.running) {
        _finishTask(
          TaskType.extractDocument,
          token.isCancelled ? TaskStatus.cancelled : TaskStatus.failed,
        );
      }
    }
  }

  /// 异步 Job API 优先，失败时 fallback 到同步 API（若已配置）。
  Future<DocExtractResult> _extractAsync({
    required String filePath,
    required String title,
    required DocExtractApiState apiState,
    required CancelToken cancelToken,
  }) async {
    try {
      return await BatchExtractService.instance.extractSingle(
        filePath: filePath,
        token: apiState.apiKey,
        state: apiState,
        onProgress: (status, extracted, total) {
          if (cancelToken.isCancelled) return;
          final pageInfo = total > 0 ? ' ($extracted/$total 页)' : '';
          _snackBar.showProgress(
            fileName: title,
            status: '$status$pageInfo',
            onCancel: () => cancelTask(TaskType.extractDocument),
            duration: const Duration(minutes: 10),
          );
        },
        cancelToken: cancelToken,
      );
    } catch (asyncError) {
      // 用户取消时直接抛出，不 fallback
      if (cancelToken.isCancelled ||
          (asyncError is DioException &&
              asyncError.type == DioExceptionType.cancel)) {
        rethrow;
      }

      // 无同步 fallback 配置，直接抛出原始错误
      if (!apiState.hasSyncFallback) rethrow;

      // fallback 到同步 API
      debugPrint('[TaskProvider] 异步提取失败，回退到同步 API: $asyncError');
      _snackBar.showProgress(
        fileName: title,
        status: '异步失败，尝试同步提取…',
        onCancel: () => cancelTask(TaskType.extractDocument),
        duration: const Duration(minutes: 10),
      );

      return DocExtractService.instance.extract(
        filePath: filePath,
        apiUrl: apiState.syncBaseUrl,
        token: apiState.apiKey,
        state: apiState,
        cancelToken: cancelToken,
      );
    }
  }

  // ── 消息格式化 ──

  String _buildAddFileMessage({
    required bool cancelled,
    required int totalFiles,
    required int importedCount,
    required int duplicateCount,
    required int completeMetadataCount,
    required int partialMetadataCount,
    required int unresolvedMetadataCount,
    required AddFileResult? lastResult,
  }) {
    if (totalFiles == 1 && lastResult?.document != null) {
      final doc = lastResult!.document!;
      if (lastResult.type == AddFileResultType.duplicate) {
        return '文库中已存在: ${doc.title}';
      }
      switch (lastResult.metadataStatus) {
        case MetadataStatus.complete:
          return '已导入并提取元数据: ${doc.title}';
        case MetadataStatus.partial:
          return '已导入 ${doc.title}，仅提取到部分元数据';
        case MetadataStatus.none:
          return '已导入 ${doc.title}，未识别到可用元数据';
      }
    }

    final parts = <String>[];
    if (importedCount > 0) parts.add('导入 $importedCount 篇');
    if (duplicateCount > 0) parts.add('重复 $duplicateCount 篇');
    if (completeMetadataCount > 0) {
      parts.add('完整元数据 $completeMetadataCount 篇');
    }
    if (partialMetadataCount > 0) {
      parts.add('部分元数据 $partialMetadataCount 篇');
    }
    if (unresolvedMetadataCount > 0) {
      parts.add('未识别元数据 $unresolvedMetadataCount 篇');
    }
    if (parts.isEmpty) {
      return cancelled ? '已取消导入' : '未导入任何文件';
    }
    final prefix = cancelled ? '已取消导入' : '导入完成';
    return '$prefix：${parts.join('，')}';
  }
}

final taskProvider =
    StateNotifierProvider<TaskNotifier, Map<TaskType, TaskInfo>>((ref) {
  return TaskNotifier(ref);
});
