import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../data/models/book/document.dart';
import '../router/app_router.dart';
import '../router/app_routes.dart';
import '../services/identifier_resolver.dart';
import '../services/snackbar_service.dart';
import '../services/zotero_item_mapper.dart';
import '../services/zotero_sync_service.dart';
import 'document_lifecycle_provider.dart';
import 'documents_provider.dart';
import 'task_runner.dart';
import 'task_types.dart';
import 'zotero_sync_provider.dart';

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
        type: type,
        status: TaskStatus.running,
        cancelToken: token,
      ),
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

  DocumentLifecycleNotifier get _lifecycle =>
      _ref.read(documentLifecycleProvider);
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

          progress(
            ListenableProgress(
              current: i + 1,
              total: paths.length,
              status: '正在提取元数据: ${p.basename(paths[i])}',
            ),
          );

          lastResult = await _lifecycle.importPdf(paths[i], cancelToken: token);

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
        return TaskFinish.text(
          _buildAddFileMessage(
            cancelled: false,
            totalFiles: paths.length,
            importedCount: importedCount,
            duplicateCount: duplicateCount,
            completeMetadataCount: completeMetadataCount,
            partialMetadataCount: partialMetadataCount,
            unresolvedMetadataCount: unresolvedMetadataCount,
            lastResult: lastResult,
          ),
        );
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
          await _lifecycle.createByIdentifier(identifier, cancelToken: token),
      onSuccess: (r) {
        final (doc, addResult) = r;
        if (addResult == AddByIdentifierResult.duplicate) {
          return const TaskFinish.text('该文献已存在于文库中');
        }
        if (doc.contentHash == null) {
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
          return await _lifecycle.rebuildLibrary(
            cancelToken: token,
            onProgress: (rp) {
              if (token.isCancelled) return;
              progress(
                ListenableProgress(
                  current: rp.current ?? 0,
                  total: rp.total ?? 0,
                  status: '${rp.status} · ${rp.fileName}',
                ),
              );
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

  // ── Zotero 同步 ──

  /// 单向导入 Zotero 个人库。与 [rebuildLibrary] 同属库级后台任务：
  /// 进度 snackbar + 可取消。[fullResync] 时先清空簿记游标，回到 since=0 全量重拉。
  Future<void> syncZotero(String apiKey, {bool fullResync = false}) async {
    await runTask<int>(
      type: TaskType.zoteroSync,
      initialStatus: '正在拉取 Zotero 条目...',
      busyMessage: 'Zotero 同步正在进行中',
      cancelledMessage: '已取消 Zotero 同步',
      body: (token, progress) async {
        if (fullResync) await ZoteroSyncStore.clear();

        final result = await ZoteroSyncService.instance.fetchTopItems(
          apiKey: apiKey,
          sinceVersion: ZoteroSyncStore.libraryVersion,
          cancelToken: token,
          onProgress: (fetched, total) => progress(
            ListenableProgress(
              current: fetched,
              total: total,
              status: '正在拉取 Zotero 条目',
            ),
          ),
        );

        progress(
          const ListenableProgress(current: 0, total: 0, status: '正在导入文献...'),
        );

        // 跳过已导入的 zoteroKey 与非文献条目，映射出待导入的 Document。
        final docs = <Document>[];
        final keys = <String>[];
        final versions = <int>[];
        for (final item in result.items) {
          final key = item['key'] as String?;
          if (key == null || ZoteroSyncStore.hasItem(key)) continue;
          final doc = ZoteroItemMapper.toDocument(item);
          if (doc == null) continue;
          docs.add(doc);
          keys.add(key);
          versions.add((item['version'] as num?)?.toInt() ?? 0);
        }

        final before = _ref.read(documentsProvider).map((d) => d.id).toSet();
        final imported = await _lifecycle.importDocuments(docs);
        for (var i = 0; i < imported.length; i++) {
          await ZoteroSyncStore.recordItem(keys[i], imported[i].id, versions[i]);
        }
        await ZoteroSyncStore.setLibraryVersion(result.libraryVersion);
        return imported.where((d) => !before.contains(d.id)).length;
      },
      onSuccess: (addedCount) => TaskFinish.text(
        addedCount > 0 ? 'Zotero 同步完成，新增 $addedCount 篇' : 'Zotero 同步完成，暂无新增条目',
      ),
      onError: (e) {
        if (e is ZoteroSyncException) return TaskFinish.text('Zotero 同步失败：$e');
        if (e is DioException) return const TaskFinish.text('Zotero 同步失败：网络请求失败');
        return TaskFinish.text('Zotero 同步失败：$e');
      },
    );
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
