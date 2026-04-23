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
import 'task_runner.dart';
import 'task_types.dart';

// 对外 re-export：外部只 import 'task_provider.dart' 即可拿到 TaskType/TaskStatus
export 'task_types.dart' show TaskType, TaskStatus, TaskInfo;

class TaskNotifier extends StateNotifier<Map<TaskType, TaskInfo>>
    with TaskRunner<Map<TaskType, TaskInfo>> {
  final Ref _ref;

  TaskNotifier(this._ref) : super({});

  // ── TaskRunner hooks ──

  @override
  SnackBarService get snackBar => _ref.read(snackBarServiceProvider);

  @override
  bool isTaskRunning(TaskType type) =>
      state[type]?.status == TaskStatus.running;

  @override
  void markTaskStarted(TaskType type, CancelToken token) {
    state = {
      ...state,
      type: TaskInfo(
          type: type, status: TaskStatus.running, cancelToken: token),
    };
  }

  @override
  void markTaskFinished(TaskType type, TaskStatus status) {
    final current = state[type];
    if (current == null) return;
    state = {...state, type: current.copyWith(status: status)};
  }

  // 兼容旧 API 名（外部调用方沿用）
  bool isRunning(TaskType type) => isTaskRunning(type);

  DocumentsNotifier get _docs => _ref.read(documentsProvider.notifier);
  GoRouter get _router => _ref.read(routerProvider);

  /// 外部主动取消任务。只负责触发 token.cancel()，
  /// 状态和 SnackBar 清理由 runTask 的 catch 分支统一完成。
  void cancelTask(TaskType type) {
    final task = state[type];
    if (task?.status != TaskStatus.running) return;
    if (!task!.cancelToken.isCancelled) task.cancelToken.cancel();
  }

  // ── 添加文件 ──

  Future<void> addFiles(List<String> paths) async {
    // 这些计数器在 body 内累加，在 onSuccess 内被 _buildAddFileMessage 消费
    var importedCount = 0;
    var duplicateCount = 0;
    var completeMetadataCount = 0;
    var partialMetadataCount = 0;
    AddFileResult? lastResult;

    await runTask<void>(
      type: TaskType.addFiles,
      initialStatus: '准备导入文件...',
      busyMessage: '正在导入文件，请稍候',
      cancelledMessage: null, // 取消时用 _buildAddFileMessage 出更完整的摘要
      body: (token, progress) async {
        for (int i = 0; i < paths.length; i++) {
          if (token.isCancelled) break;

          progress(ListenableProgress(
            current: i + 1,
            total: paths.length,
            status: '正在提取元数据: ${p.basename(paths[i])}',
          ));

          lastResult = await _docs.addFile(paths[i], cancelToken: token);

          if (lastResult!.type == AddFileResultType.duplicate) {
            duplicateCount++;
            continue;
          }
          importedCount++;
          if (lastResult!.metadataStatus == MetadataStatus.complete) {
            completeMetadataCount++;
          } else if (lastResult!.metadataStatus == MetadataStatus.partial) {
            partialMetadataCount++;
          }
        }
      },
      onSuccess: (_) {
        final unresolvedMetadataCount =
            importedCount - completeMetadataCount - partialMetadataCount;
        return TaskFinish.text(_buildAddFileMessage(
          cancelled: false,
          totalFiles: paths.length,
          importedCount: importedCount,
          duplicateCount: duplicateCount,
          completeMetadataCount: completeMetadataCount,
          partialMetadataCount: partialMetadataCount,
          unresolvedMetadataCount: unresolvedMetadataCount,
          lastResult: lastResult,
        ));
      },
    );
  }

  // ── 通过标识符添加 ──

  Future<void> addByIdentifier(String identifier) async {
    await runTask<(dynamic, AddByIdentifierResult)>(
      type: TaskType.addByIdentifier,
      initialStatus: '正在解析标识符: $identifier',
      busyMessage: '正在解析标识符，请稍候',
      body: (token, _) async =>
          await _docs.addByIdentifier(identifier, cancelToken: token),
      onSuccess: (r) {
        final (doc, addResult) = r;
        if (addResult == AddByIdentifierResult.duplicate) {
          return const TaskFinish.text('该文献已存在于文库中');
        }
        if (doc.filePath.isEmpty) {
          return TaskFinish(
            message: '已添加「${doc.title}」，但未获取到关联 PDF',
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: '去添加',
              onPressed: () => _router.push(AppRoutes.shelfNoFileEntries),
            ),
          );
        }
        return TaskFinish.text('已添加: ${doc.title}');
      },
      onError: (e) {
        if (e is IdentifierResolveException) return TaskFinish.text(e.message);
        if (e is DioException) return const TaskFinish.text('网络请求失败，请稍后重试');
        return TaskFinish.text('添加失败: $e');
      },
    );
  }

  // ── 重构文库 ──

  Future<void> rebuildLibrary() async {
    await runTask<RebuildResult?>(
      type: TaskType.rebuild,
      initialStatus: '准备重构文库...',
      busyMessage: '文库重构正在进行中',
      cancelledMessage: '已取消重构文库',
      body: (token, progress) async {
        try {
          return await _docs.rebuild(
            cancelToken: token,
            onProgress: (rp) {
              if (token.isCancelled) return;
              progress(ListenableProgress(
                current: rp.current ?? 0,
                total: rp.total ?? 0,
                status: '${rp.status} · ${rp.fileName}',
              ));
            },
          );
        } on DioException {
          // CancelToken 取消时 Dio 会抛异常，取消情况下静默返回 null
          if (token.isCancelled) return null;
          rethrow;
        }
      },
      onSuccess: (result) {
        var message = '文库重构完成';
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
        return TaskFinish.text(message);
      },
    );
  }

  // ── 重新下载 PDF ──

  Future<void> redownloadPdf(String docId, String docTitle) async {
    await runTask<bool>(
      type: TaskType.redownloadPdf,
      initialStatus: '正在重新下载: $docTitle',
      busyMessage: '正在下载中，请稍候',
      body: (token, _) async =>
          await _docs.redownloadPdf(docId, cancelToken: token),
      onSuccess: (success) => TaskFinish.text(
        success ? '下载成功：$docTitle' : '下载失败，未找到可用的 PDF 源',
      ),
    );
  }

  // ── 文档提取 ──

  Future<void> extractDocument({
    required String filePath,
    required String title,
    required DocExtractApiState apiState,
    required void Function(String mdPath, String markdownContent) onSuccess,
  }) async {
    // 前置条件检查（不走 runTask，因为是"没开始就失败"的直接提示）
    if (!apiState.isConfigured) {
      snackBar.showResult(
        message: '请先在设置中配置文档提取 Access Token',
        action: SnackBarAction(
          label: '前往设置',
          onPressed: () => _router.push(AppRoutes.settingsExtract),
        ),
      );
      return;
    }

    await runTask<({String mdPath, String markdown})>(
      type: TaskType.extractDocument,
      initialStatus: '正在提交任务: $title',
      busyMessage: '正在提取文档，请稍候',
      cancelledMessage: '已取消提取',
      body: (token, progress) async {
        final result = await _extractAsync(
          filePath: filePath,
          title: title,
          apiState: apiState,
          cancelToken: token,
          progress: progress,
        );
        if (token.isCancelled) {
          throw DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.cancel,
          );
        }
        // saveResult 通常 1-2 秒；30 秒超时兜底防止异常阻塞
        final savedMdPath = await DocExtractService.instance
            .saveResult(filePath, result,
                token: apiState.apiKey, title: title)
            .timeout(const Duration(seconds: 30));
        return (mdPath: savedMdPath, markdown: result.processedMarkdown ?? '');
      },
      onSuccess: (r) {
        onSuccess(r.mdPath, r.markdown);
        return TaskFinish(
          message: '文档提取完成：$title',
          duration: const Duration(seconds: 6),
        );
      },
      onError: (e) {
        if (e is DocExtractException) return TaskFinish.text(e.message);
        if (e is BatchExtractException) return TaskFinish.text(e.message);
        if (e is DioException) {
          return TaskFinish.text('网络错误: ${e.message}');
        }
        return TaskFinish.text('提取失败: $e');
      },
    );
  }

  /// 异步 Job API 优先，失败时 fallback 到同步 API（若已配置）。
  Future<DocExtractResult> _extractAsync({
    required String filePath,
    required String title,
    required DocExtractApiState apiState,
    required CancelToken cancelToken,
    required void Function(ListenableProgress) progress,
  }) async {
    try {
      return await BatchExtractService.instance.extractSingle(
        filePath: filePath,
        token: apiState.apiKey,
        state: apiState,
        onProgress: (status, extracted, total) {
          if (cancelToken.isCancelled) return;
          progress(ListenableProgress(
            current: extracted,
            total: total,
            status: total > 0 ? '$status · $title' : '$status · $title',
          ));
        },
        cancelToken: cancelToken,
      );
    } catch (asyncError) {
      // 用户取消直接抛出，不 fallback
      if (cancelToken.isCancelled ||
          (asyncError is DioException &&
              asyncError.type == DioExceptionType.cancel)) {
        rethrow;
      }
      // 无同步 fallback 配置，直接抛原始错误
      if (!apiState.hasSyncFallback) rethrow;

      debugPrint('[TaskProvider] 异步提取失败，回退到同步 API: $asyncError');
      progress(ListenableProgress(
        current: 0,
        total: 0,
        status: '异步失败，尝试同步提取 · $title',
      ));

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
