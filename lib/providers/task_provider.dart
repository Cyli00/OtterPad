import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../core/l10n.dart';
import '../router/app_router.dart';
import '../router/app_routes.dart';
import '../core/otter_error_text.dart';
import '../core/rust_backend.dart';
import '../core/rust_models.dart';
import '../services/snackbar_service.dart';
import '../src/rust/api/zotero.dart';
import '../src/rust/error.dart';
import '../src/rust/sync/zotero/store.dart';
import 'document_lifecycle_provider.dart';
import 'documents_provider.dart';
import 'task_runner.dart';
import 'task_types.dart';
import 'zotero_local_errors.dart';

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
      initialStatus: _l10n?.preparingImport ?? '正在准备导入',
      busyMessage: _l10n?.importingFilesBusy ?? '正在导入文件，请稍候',
      cancelledMessage: null, // 取消时用 _buildAddFileMessage 出更完整的摘要
      body: (token, progress) async {
        for (int i = 0; i < paths.length; i++) {
          if (token.isCancelled) break;

          progress(
            ListenableProgress(
              current: i + 1,
              total: paths.length,
              status:
                  _l10n?.importingFile(p.basename(paths[i])) ??
                  '正在导入 · ${p.basename(paths[i])}',
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
          tone: importedCount > 0 ? null : SnackTone.info,
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
      initialStatus:
          _l10n?.resolvingIdentifier(identifier) ?? '正在解析标识符 · $identifier',
      busyMessage: _l10n?.resolvingIdentifierBusy ?? '正在解析标识符，请稍候',
      // 元数据解析完进入 PDF 下载阶段，状态文案随之推进。
      body: (token, progress) => _lifecycle.createByIdentifier(
        identifier,
        cancelToken: token,
        onFetchingPdf: () => progress(
          ListenableProgress(
            current: 0,
            total: 0,
            status: _l10n?.downloadingPdf ?? '正在下载 PDF',
          ),
        ),
      ),
      onSuccess: (r) {
        final (doc, addResult) = r;
        if (addResult == AddByIdentifierResult.duplicate) {
          return TaskFinish.text(
            _l10n?.documentAlreadyExists ?? '该文献已存在于文库中',
            tone: SnackTone.info,
          );
        }
        if (doc.contentHash == null) {
          return TaskFinish(
            tone: SnackTone.info,
            message:
                _l10n?.addedDocumentNoPdf(doc.title) ??
                '已添加「${doc.title}」，但未获取到关联 PDF',
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: _l10n?.goAdd ?? '去添加',
              onPressed: () => _router.push(AppRoutes.shelfNoFileEntries),
            ),
          );
        }
        return TaskFinish.text(
          _l10n?.addedDocumentTitle(doc.title) ?? '已添加「${doc.title}」',
        );
      },
      onError: (e) {
        final l10n = _l10n;
        if (l10n == null) return TaskFinish.text('$e');
        if (e is OtterError && e.code == ErrorCode.network) {
          return TaskFinish.text(l10n.networkRequestFailedRetry);
        }
        return TaskFinish.text(l10n.addFailedError(errorText(l10n, e)));
      },
    );
  }

  // ── 重构文库 ──

  Future<void> rebuildLibrary() async {
    await runTask<RebuildResult?>(
      type: TaskType.rebuild,
      initialStatus: _l10n?.preparingRebuild ?? '正在准备重构文库',
      busyMessage: _l10n?.rebuildInProgress ?? '正在重构文库，请稍候',
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
                  status: rp.fileName.isEmpty
                      ? rp.status
                      : '${rp.status} · ${rp.fileName}',
                ),
              );
            },
          );
        } catch (e) {
          if (token.isCancelled && isCancellation(e)) return null;
          rethrow;
        }
      },
      onSuccess: (result) {
        var message = _l10n?.rebuildComplete ?? '文库重构完成';
        if (result != null) {
          final parts = <String>[];
          if (result.addedCount > 0) {
            parts.add(
              _l10n?.rebuildAdded(result.addedCount) ??
                  '新增 ${result.addedCount} 篇',
            );
          }
          if (result.removedCount > 0) {
            parts.add(
              _l10n?.rebuildRemoved(result.removedCount) ??
                  '清理 ${result.removedCount} 篇',
            );
          }
          if (result.repairedCount > 0) {
            parts.add(
              _l10n?.rebuildRepaired(result.repairedCount) ??
                  '修复元数据 ${result.repairedCount} 篇',
            );
          }
          if (result.unresolvedCount > 0) {
            parts.add(
              _l10n?.rebuildUnresolved(result.unresolvedCount) ??
                  '仍有 ${result.unresolvedCount} 篇待补全元数据',
            );
          }
          if (result.noFileCount > 0) {
            parts.add(
              _l10n?.rebuildNoFile(result.noFileCount) ??
                  '${result.noFileCount} 个无文件条目',
            );
          }
          if (parts.isEmpty) {
            message += _l10n?.rebuildNormal ?? '，文库状态正常';
          } else {
            message += '，${parts.join('，')}';
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
      initialStatus: _l10n?.fetchingZoteroItems ?? '正在拉取 Zotero 条目',
      busyMessage: _l10n?.zoteroSyncInProgress ?? '正在同步 Zotero，请稍候',
      cancelledMessage: _l10n?.zoteroSyncCancelled ?? '已取消 Zotero 同步',
      body: (token, progress) async {
        final report = await _zoteroReport(
          RustBackend.instance.syncZotero(
            full: fullResync,
            taskId: rustTaskId('zotero', token),
          ),
          (fetched, total) => progress(
            ListenableProgress(
              current: fetched,
              total: total,
              status: _l10n?.fetchingZoteroProgress ?? '正在拉取 Zotero 条目',
            ),
          ),
        );
        return report.added.toInt();
      },
      onSuccess: (addedCount) => TaskFinish.text(
        addedCount > 0
            ? _l10n?.zoteroSyncCompleteAdded(addedCount) ??
                  'Zotero 同步完成，新增 $addedCount 篇'
            : _l10n?.zoteroSyncCompleteNoNew ?? 'Zotero 同步完成，暂无新增条目',
      ),
      onError: (e) {
        final l10n = _l10n;
        if (l10n == null) return TaskFinish.text('$e');
        if (e is OtterError && e.code == ErrorCode.network) {
          return TaskFinish.text(l10n.zoteroSyncNetworkFailed);
        }
        return TaskFinish.text(l10n.zoteroSyncFailed(errorText(l10n, e)));
      },
    );
  }

  /// 本地 Zotero 导入；[selections] 为条目与所选 PDF 附件。
  Future<ImportReport?> importLocalZotero({
    required LocalZoteroSnapshot snapshot,
    required String? directory,
    required List<LocalSelection> selections,
  }) => runTask<ImportReport>(
    type: TaskType.zoteroSync,
    initialStatus: _l10n?.importingDocuments ?? '',
    busyMessage: _l10n?.zoteroSyncInProgress,
    cancelledMessage: _l10n?.zoteroSyncCancelled,
    body: (token, progress) => _zoteroReport(
      RustBackend.instance.importLocalZotero(
        snapshot: snapshot,
        directory: directory,
        selections: selections,
        taskId: rustTaskId('zotero-local', token),
      ),
      (done, total) => progress(
        ListenableProgress(
          current: done,
          total: total,
          status: _l10n?.importingDocuments ?? '',
        ),
      ),
    ),
    onSuccess: (r) => TaskFinish(
      message: _l10n?.zoteroLocalResult(
        r.added.toInt(),
        r.updated.toInt(),
        r.copied.toInt(),
        r.missing.toInt(),
        r.kept.toInt(),
        r.failedKeys.length,
      ),
    ),
    onError: (e) => TaskFinish(
      message: _l10n == null ? null : zoteroLocalErrorMessage(_l10n!, e),
    ),
  );

  /// 等待 Zotero 导入流结束并刷新文库。
  Future<ImportReport> _zoteroReport(
    Stream<ZoteroEvent> events,
    void Function(int done, int total) onProgress,
  ) async {
    try {
      await for (final event in events) {
        switch (event) {
          case ZoteroEvent_Progress(:final progress):
            onProgress(progress.fetched.toInt(), progress.total?.toInt() ?? 0);
          case ZoteroEvent_Imported(:final report):
            return report;
          case ZoteroEvent_Failed(:final error):
            throw error;
          case ZoteroEvent_LocalReady():
        }
      }
      throw const OtterError(
        code: ErrorCode.cancelled,
        detail: 'zotero stream ended',
      );
    } finally {
      bumpLibrary(_ref);
    }
  }

  // ── 消息格式化 ──

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
        return _l10n?.existsInLibrary(doc.title) ?? '文库中已存在「${doc.title}」';
      }
      // 元数据异步提取，不在此报告状态
      return _l10n?.importedFile(doc.title) ?? '已导入「${doc.title}」';
    }

    final parts = <String>[];
    if (importedCount > 0) {
      parts.add(
        _l10n?.importedCountPart(importedCount) ?? '导入 $importedCount 篇',
      );
    }
    if (duplicateCount > 0) {
      parts.add(
        _l10n?.duplicateCountPart(duplicateCount) ?? '重复 $duplicateCount 篇',
      );
    }
    if (parts.isEmpty) {
      return cancelled
          ? _l10n?.importCancelledLabel ?? '已取消导入'
          : _l10n?.noFilesImported ?? '未导入任何文件';
    }
    final prefix = cancelled
        ? _l10n?.importCancelledLabel ?? '已取消导入'
        : _l10n?.importCompleteLabel ?? '导入完成';
    return '$prefix，${parts.join('，')}';
  }
}

final taskProvider =
    StateNotifierProvider<TaskNotifier, Map<TaskType, TaskInfo>>((ref) {
      return TaskNotifier(ref);
    });
