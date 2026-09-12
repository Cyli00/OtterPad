import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../core/l10n.dart';
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
import 'zotero_local_import_provider.dart';

// 对外 re-export：外部只 import 'task_provider.dart' 即可拿到 TaskType/TaskStatus
export 'task_types.dart' show TaskType, TaskStatus, TaskInfo;

class TaskNotifier extends StateNotifier<Map<TaskType, TaskInfo>>
    with TaskRunner<Map<TaskType, TaskInfo>> {
  final Ref _ref;

  TaskNotifier(this._ref) : super({});

  AppLocalizations? get _l10n {
    final ctx = rootNavigatorKey.currentContext;
    return ctx != null ? AppLocalizations.of(ctx) : null;
  }

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
    AddFileResult? lastResult;

    await runTask<void>(
      type: TaskType.addFiles,
      initialStatus: _l10n?.preparingImport ?? '准备导入文件...',
      busyMessage: _l10n?.importingFilesBusy ?? '正在导入文件，请稍候',
      cancelledMessage: null, // 取消时用 _buildAddFileMessage 出更完整的摘要
      body: (token, progress) async {
        for (int i = 0; i < paths.length; i++) {
          if (token.isCancelled) break;

          progress(
            ListenableProgress(
              current: i + 1,
              total: paths.length,
              status: _l10n?.importingFile(p.basename(paths[i])) ?? '正在导入: ${p.basename(paths[i])}',
            ),
          );

          lastResult = await _lifecycle.importPdf(paths[i], cancelToken: token);

          if (lastResult!.type == AddFileResultType.duplicate) {
            duplicateCount++;
            continue;
          }
          importedCount++;
        }
      },
      onSuccess: (_) {
        return TaskFinish.text(
          _buildAddFileMessage(
            cancelled: false,
            totalFiles: paths.length,
            importedCount: importedCount,
            duplicateCount: duplicateCount,
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
      initialStatus: _l10n?.resolvingIdentifier(identifier) ?? '正在解析标识符: $identifier',
      busyMessage: _l10n?.resolvingIdentifierBusy ?? '正在解析标识符，请稍候',
      body: (token, _) async =>
          await _lifecycle.createByIdentifier(identifier, cancelToken: token),
      onSuccess: (r) {
        final (doc, addResult) = r;
        if (addResult == AddByIdentifierResult.duplicate) {
          return TaskFinish.text(_l10n?.documentAlreadyExists ?? '该文献已存在于文库中');
        }
        if (doc.contentHash == null) {
          return TaskFinish(
            message: _l10n?.addedDocumentNoPdf(doc.title) ?? '已添加「${doc.title}」，但未获取到关联 PDF',
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: _l10n?.goAdd ?? '去添加',
              onPressed: () => _router.push(AppRoutes.shelfNoFileEntries),
            ),
          );
        }
        return TaskFinish.text(_l10n?.addedDocumentTitle(doc.title) ?? '已添加: ${doc.title}');
      },
      onError: (e) {
        if (e is IdentifierResolveException) return TaskFinish.text(e.message);
        if (e is DioException) return TaskFinish.text(_l10n?.networkRequestFailedRetry ?? '网络请求失败，请稍后重试');
        return TaskFinish.text(_l10n?.addFailedError('$e') ?? '添加失败: $e');
      },
    );
  }

  // ── 重构文库 ──

  Future<void> rebuildLibrary() async {
    await runTask<RebuildResult?>(
      type: TaskType.rebuild,
      initialStatus: _l10n?.preparingRebuild ?? '准备重构文库...',
      busyMessage: _l10n?.rebuildInProgress ?? '文库重构正在进行中',
      cancelledMessage: _l10n?.rebuildCancelled ?? '已取消重构文库',
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
        var message = _l10n?.rebuildComplete ?? '文库重构完成';
        if (result != null) {
          final parts = <String>[];
          if (result.addedCount > 0) parts.add(_l10n?.rebuildAdded(result.addedCount) ?? '新增 ${result.addedCount} 篇');
          if (result.removedCount > 0) parts.add(_l10n?.rebuildRemoved(result.removedCount) ?? '清理 ${result.removedCount} 篇');
          if (result.repairedCount > 0) {
            parts.add(_l10n?.rebuildRepaired(result.repairedCount) ?? '修复元数据 ${result.repairedCount} 篇');
          }
          if (result.unresolvedCount > 0) {
            parts.add(_l10n?.rebuildUnresolved(result.unresolvedCount) ?? '仍有 ${result.unresolvedCount} 篇待补全元数据');
          }
          if (result.noFileCount > 0) {
            parts.add(_l10n?.rebuildNoFile(result.noFileCount) ?? '${result.noFileCount} 个无文件条目');
          }
          if (parts.isEmpty) {
            message += _l10n?.rebuildNormal ?? '，文库状态正常';
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
      initialStatus: _l10n?.fetchingZoteroItems ?? '正在拉取 Zotero 条目...',
      busyMessage: _l10n?.zoteroSyncInProgress ?? 'Zotero 同步正在进行中',
      cancelledMessage: _l10n?.zoteroSyncCancelled ?? '已取消 Zotero 同步',
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
              status: _l10n?.fetchingZoteroProgress ?? '正在拉取 Zotero 条目',
            ),
          ),
        );

        progress(
          ListenableProgress(current: 0, total: 0, status: _l10n?.importingDocuments ?? '正在导入文献...'),
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

        final before = (_ref.read(documentsProvider).value ?? const [])
            .map((d) => d.id)
            .toSet();
        final imported = await _lifecycle.importDocuments(docs);
        for (var i = 0; i < imported.length; i++) {
          await ZoteroSyncStore.recordItem(keys[i], imported[i].id, versions[i]);
        }
        await ZoteroSyncStore.setLibraryVersion(result.libraryVersion);
        return imported.where((d) => !before.contains(d.id)).length;
      },
      onSuccess: (addedCount) => TaskFinish.text(
        addedCount > 0 ? _l10n?.zoteroSyncCompleteAdded(addedCount) ?? 'Zotero 同步完成，新增 $addedCount 篇' : _l10n?.zoteroSyncCompleteNoNew ?? 'Zotero 同步完成，暂无新增条目',
      ),
      onError: (e) {
        if (e is ZoteroSyncException) return TaskFinish.text(_l10n?.zoteroSyncFailed('$e') ?? 'Zotero 同步失败：$e');
        if (e is DioException) return TaskFinish.text(_l10n?.zoteroSyncNetworkFailed ?? 'Zotero 同步失败：网络请求失败');
        return TaskFinish.text(_l10n?.zoteroSyncFailed('$e') ?? 'Zotero 同步失败：$e');
      },
    );
  }

  // ── 消息格式化 ──

  Future<ZoteroLocalImportResult?> importLocalZotero({
    required ZoteroLocalLibrary library,
    required String source,
    required List<ZoteroImportCandidate> candidates,
    required Map<String, String?> attachments,
  }) => runTask<ZoteroLocalImportResult>(
    type: TaskType.zoteroSync,
    initialStatus: _l10n?.importingDocuments ?? '',
    busyMessage: _l10n?.zoteroSyncInProgress,
    cancelledMessage: _l10n?.zoteroSyncCancelled,
    body: (token, progress) => _ref.read(zoteroLocalImportProvider).run(
      library: library, source: source, candidates: candidates,
      attachments: attachments, cancelToken: token,
      onProgress: (done, total) => progress(ListenableProgress(
        current: done, total: total, status: _l10n?.importingDocuments ?? '',
      )),
    ),
    onSuccess: (r) => TaskFinish(message: _l10n?.zoteroLocalResult(
      r.added, r.updated, r.copied, r.missing, r.kept, r.failedTitles.length)),
    onError: (e) => TaskFinish(message: _l10n == null ? null : zoteroLocalErrorMessage(_l10n!, e)),
  );

  String _buildAddFileMessage({
    required bool cancelled,
    required int totalFiles,
    required int importedCount,
    required int duplicateCount,
    required AddFileResult? lastResult,
  }) {
    if (totalFiles == 1 && lastResult?.document != null) {
      final doc = lastResult!.document!;
      if (lastResult.type == AddFileResultType.duplicate) {
        return _l10n?.existsInLibrary(doc.title) ?? '文库中已存在: ${doc.title}';
      }
      // 元数据异步提取，不在此报告状态
      return _l10n?.importedFile(doc.title) ?? '已导入: ${doc.title}';
    }

    final parts = <String>[];
    if (importedCount > 0) parts.add(_l10n?.importedCountPart(importedCount) ?? '导入 $importedCount 篇');
    if (duplicateCount > 0) parts.add(_l10n?.duplicateCountPart(duplicateCount) ?? '重复 $duplicateCount 篇');
    if (parts.isEmpty) {
      return cancelled ? _l10n?.importCancelledLabel ?? '已取消导入' : _l10n?.noFilesImported ?? '未导入任何文件';
    }
    final prefix = cancelled ? _l10n?.importCancelledLabel ?? '已取消导入' : _l10n?.importCompleteLabel ?? '导入完成';
    return '$prefix：${parts.join('，')}';
  }
}

final taskProvider =
    StateNotifierProvider<TaskNotifier, Map<TaskType, TaskInfo>>((ref) {
      return TaskNotifier(ref);
    });
