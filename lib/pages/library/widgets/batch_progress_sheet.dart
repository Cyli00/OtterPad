import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/api_provider.dart';
import '../../../providers/document_task_provider.dart';
import '../../../services/batch_extract_service.dart';
import 'package:material_symbols_icons/symbols.dart';

// ─── 批量提取进度 Sheet ────────────────────────────────────────────────────────

/// 以 ModalBottomSheet 展示批量提取进度，可从多选模式或其他入口触发。
///
/// 用法：
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   isDismissible: false,
///   enableDrag: false,
///   isScrollControlled: true,
///   backgroundColor: Colors.transparent,
///   builder: (_) => BatchProgressSheet(items: items, apiState: apiState),
/// );
/// ```
class BatchProgressSheet extends ConsumerStatefulWidget {
  final List<BatchExtractItem> items;
  final DocExtractApiState apiState;

  const BatchProgressSheet({
    super.key,
    required this.items,
    required this.apiState,
  });

  @override
  ConsumerState<BatchProgressSheet> createState() => _BatchProgressSheetState();
}

class _BatchProgressSheetState extends ConsumerState<BatchProgressSheet> {
  bool _finished = false;
  // 在 initState 中 cache notifier——Riverpod 3.x 禁止在 dispose() 中通过
  // ref.read 取 provider（widget 已 unmount-pending）。Notifier 生命周期由
  // provider 管理，可安全 cache 到字段。
  late final DocumentTaskNotifier _taskNotifier;

  @override
  void initState() {
    super.initState();
    _taskNotifier = ref.read(documentTaskProvider.notifier);
    unawaited(_run());
  }

  @override
  void dispose() {
    if (!_finished) {
      for (final item in widget.items) {
        _taskNotifier.cancelTask(
          DocumentTaskKey(
            type: DocumentTaskType.extractDocument,
            documentId: item.documentId,
          ),
        );
      }
    }
    super.dispose();
  }

  Future<void> _run() async {
    await _taskNotifier.extractBatch(
      items: widget.items,
      apiState: widget.apiState,
    );
    if (mounted) setState(() => _finished = true);
  }

  BatchExtractProgress _buildProgress(
    Map<DocumentTaskKey, DocumentTaskInfo> tasks,
  ) {
    final statuses = widget.items.map((item) {
      final key = DocumentTaskKey(
        type: DocumentTaskType.extractDocument,
        documentId: item.documentId,
      );
      final info = tasks[key];
      if (info == null) {
        return BatchJobStatus(
          documentId: item.documentId,
          title: item.title,
          state: _finished ? BatchJobState.cancelled : BatchJobState.pending,
        );
      }
      final state = switch (info.status) {
        DocumentTaskStatus.queued => BatchJobState.pending,
        DocumentTaskStatus.running => BatchJobState.running,
        DocumentTaskStatus.completed => BatchJobState.done,
        DocumentTaskStatus.failed => BatchJobState.failed,
        DocumentTaskStatus.cancelled => BatchJobState.cancelled,
      };
      return BatchJobStatus(
        documentId: item.documentId,
        title: item.title,
        state: state,
        error: info.error?.toString(),
        extractedPages: info.progress.current,
        totalPages: info.progress.total,
        savedPath: info.result as String?,
      );
    }).toList();
    final completed = statuses
        .where(
          (s) =>
              s.state == BatchJobState.done ||
              s.state == BatchJobState.failed ||
              s.state == BatchJobState.cancelled,
        )
        .length;
    final succeeded = statuses
        .where((s) => s.state == BatchJobState.done)
        .length;
    final failed = statuses
        .where(
          (s) =>
              s.state == BatchJobState.failed ||
              s.state == BatchJobState.cancelled,
        )
        .length;
    final active = statuses.cast<BatchJobStatus?>().firstWhere(
      (s) =>
          s != null &&
          (s.state == BatchJobState.pending ||
              s.state == BatchJobState.submitted ||
              s.state == BatchJobState.running),
      orElse: () => null,
    );
    return BatchExtractProgress(
      total: widget.items.length,
      completed: completed,
      succeeded: succeeded,
      failed: failed,
      currentTitle: active?.title ?? '',
      statuses: statuses,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final progress = _buildProgress(ref.watch(documentTaskProvider));

    final total = progress.total;
    final completed = progress.completed;
    final succeeded = progress.succeeded;
    final failed = progress.failed;
    final isRunning = completed < total;

    final statusText = isRunning
        ? (progress.currentTitle.isEmpty
              ? '等待任务启动...'
              : '正在处理「${progress.currentTitle}」')
        : (failed == 0
              ? '全部提取完成，共 $succeeded 篇'
              : '提取完成：成功 $succeeded 篇，失败 $failed 篇');

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.72,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // 拖拽条
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // 标题区域
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isRunning ? '批量提取中' : '提取完成',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          statusText,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (isRunning)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  else
                    Icon(
                      failed == 0
                          ? Symbols.check_circle_rounded
                          : Symbols.warning_amber_rounded,
                      color: failed == 0
                          ? colorScheme.primary
                          : colorScheme.error,
                      size: 28,
                    ),
                ],
              ),
            ),

            // 总进度条
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: isRunning
                            ? (total > 0 ? completed / total : null)
                            : 1.0,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          failed > 0 && !isRunning
                              ? colorScheme.error
                              : colorScheme.primary,
                        ),
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$completed / $total',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            Divider(height: 1, color: colorScheme.outlineVariant.withAlpha(80)),

            // Job 状态列表
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: progress.statuses.length,
                itemBuilder: (context, index) {
                  final s = progress.statuses[index];
                  final key = DocumentTaskKey(
                    type: DocumentTaskType.extractDocument,
                    documentId: s.documentId,
                  );
                  final task = ref.read(documentTaskProvider)[key];
                  return JobStatusTile(
                    title: s.title,
                    state: s.state,
                    extractedPages: s.extractedPages,
                    totalPages: s.totalPages,
                    error: s.error,
                    statusText: task?.progress.status,
                  );
                },
              ),
            ),

            // 操作按钮
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: isRunning
                    ? OutlinedButton.icon(
                        onPressed: () {
                          final notifier = ref.read(
                            documentTaskProvider.notifier,
                          );
                          for (final item in widget.items) {
                            notifier.cancelTask(
                              DocumentTaskKey(
                                type: DocumentTaskType.extractDocument,
                                documentId: item.documentId,
                              ),
                            );
                          }
                          Navigator.pop(context);
                        },
                        icon: const Icon(Symbols.cancel),
                        label: const Text('取消提取'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Symbols.check_rounded),
                        label: Text(failed == 0 ? '完成' : '关闭（$failed 篇失败）'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          backgroundColor: failed == 0
                              ? colorScheme.primary
                              : colorScheme.error,
                          foregroundColor: failed == 0
                              ? colorScheme.onPrimary
                              : colorScheme.onError,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 单个 Job 状态行 ──────────────────────────────────────────────────────────

class JobStatusTile extends StatelessWidget {
  final String title;
  final BatchJobState state;
  final int extractedPages;
  final int totalPages;
  final String? error;
  final String? statusText;

  const JobStatusTile({
    super.key,
    required this.title,
    required this.state,
    this.extractedPages = 0,
    this.totalPages = 0,
    this.error,
    this.statusText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final (
      Widget leading,
      String subtitle,
      Color subtitleColor,
    ) = switch (state) {
      BatchJobState.pending => (
        Icon(
          Symbols.schedule_rounded,
          color: colorScheme.onSurfaceVariant,
          size: 20,
        ),
        statusText ?? '等待提交',
        colorScheme.onSurfaceVariant,
      ),
      BatchJobState.submitted => (
        Icon(Symbols.cloud_upload, color: colorScheme.primary, size: 20),
        '已提交，等待处理',
        colorScheme.onSurfaceVariant,
      ),
      BatchJobState.running => (
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary,
            value: totalPages > 0 ? extractedPages / totalPages : null,
          ),
        ),
        statusText ??
            (totalPages > 0 ? '提取中 $extractedPages / $totalPages 页' : '提取中...'),
        colorScheme.onSurfaceVariant,
      ),
      BatchJobState.done => (
        Icon(
          Symbols.check_circle_rounded,
          color: colorScheme.primary,
          size: 20,
        ),
        totalPages > 0 ? '完成（共 $totalPages 页）' : '提取完成',
        colorScheme.onSurfaceVariant,
      ),
      BatchJobState.failed => (
        Icon(Symbols.error_rounded, color: colorScheme.error, size: 20),
        error ?? '提取失败',
        colorScheme.error,
      ),
      BatchJobState.cancelled => (
        Icon(
          Symbols.cancel_rounded,
          color: colorScheme.onSurfaceVariant,
          size: 20,
        ),
        '已取消',
        colorScheme.onSurfaceVariant,
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 24, child: Center(child: leading)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: subtitleColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
