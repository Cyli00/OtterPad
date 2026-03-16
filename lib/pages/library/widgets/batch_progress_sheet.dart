import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../providers/api_provider.dart';
import '../../../services/batch_extract_service.dart';

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
class BatchProgressSheet extends StatefulWidget {
  final List<BatchExtractItem> items;
  final DocExtractApiState apiState;

  const BatchProgressSheet({
    super.key,
    required this.items,
    required this.apiState,
  });

  @override
  State<BatchProgressSheet> createState() => _BatchProgressSheetState();
}

class _BatchProgressSheetState extends State<BatchProgressSheet> {
  final _cancelToken = CancelToken();
  BatchExtractProgress? _progress;
  bool _isRunning = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    if (_isRunning) _cancelToken.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    try {
      await BatchExtractService.instance.extractBatch(
        items: widget.items,
        apiBaseUrl: widget.apiState.baseUrl,
        token: widget.apiState.apiKey,
        state: widget.apiState,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
        onJobUpdate: (_) {
          if (mounted) setState(() {});
        },
        cancelToken: _cancelToken,
      );
    } catch (_) {}
    if (mounted) setState(() => _isRunning = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final progress = _progress;

    final total = progress?.total ?? widget.items.length;
    final completed = progress?.completed ?? 0;
    final succeeded = progress?.succeeded ?? 0;
    final failed = progress?.failed ?? 0;

    final statusText = _isRunning
        ? (progress == null
            ? '准备中...'
            : (progress.currentTitle.isEmpty
                ? '正在轮询任务状态...'
                : '正在提交「${progress.currentTitle}」'))
        : (failed == 0
            ? '全部提取完成，共 $succeeded 篇'
            : '提取完成：成功 $succeeded 篇，失败 $failed 篇');

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.72,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
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
                          _isRunning ? '批量提取中' : '提取完成',
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
                  if (_isRunning)
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  else
                    Icon(
                      failed == 0
                          ? Icons.check_circle_rounded
                          : Icons.warning_amber_rounded,
                      color:
                          failed == 0 ? colorScheme.primary : colorScheme.error,
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
                        value: _isRunning
                            ? (total > 0 ? completed / total : null)
                            : 1.0,
                        backgroundColor:
                            colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          failed > 0 && !_isRunning
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
            Divider(
                height: 1,
                color: colorScheme.outlineVariant.withAlpha(80)),

            // Job 状态列表
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount:
                    progress?.statuses.length ?? widget.items.length,
                itemBuilder: (context, index) {
                  if (progress == null) {
                    return JobStatusTile(
                      title: widget.items[index].title,
                      state: BatchJobState.pending,
                    );
                  }
                  final s = progress.statuses[index];
                  return JobStatusTile(
                    title: s.title,
                    state: s.state,
                    extractedPages: s.extractedPages,
                    totalPages: s.totalPages,
                    error: s.error,
                  );
                },
              ),
            ),

            // 操作按钮
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: _isRunning
                    ? OutlinedButton.icon(
                        onPressed: () {
                          _cancelToken.cancel();
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.cancel_outlined),
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
                        icon: const Icon(Icons.check_rounded),
                        label: Text(
                          failed == 0 ? '完成' : '关闭（$failed 篇失败）',
                        ),
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

  const JobStatusTile({
    super.key,
    required this.title,
    required this.state,
    this.extractedPages = 0,
    this.totalPages = 0,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final (Widget leading, String subtitle, Color subtitleColor) =
        switch (state) {
      BatchJobState.pending => (
          Icon(Icons.schedule_rounded,
              color: colorScheme.onSurfaceVariant, size: 20),
          '等待提交',
          colorScheme.onSurfaceVariant,
        ),
      BatchJobState.submitted => (
          Icon(Icons.cloud_upload_outlined,
              color: colorScheme.primary, size: 20),
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
          totalPages > 0 ? '提取中 $extractedPages / $totalPages 页' : '提取中...',
          colorScheme.onSurfaceVariant,
        ),
      BatchJobState.done => (
          Icon(Icons.check_circle_rounded,
              color: colorScheme.primary, size: 20),
          totalPages > 0 ? '完成（共 $totalPages 页）' : '提取完成',
          colorScheme.onSurfaceVariant,
        ),
      BatchJobState.failed => (
          Icon(Icons.error_rounded, color: colorScheme.error, size: 20),
          error ?? '提取失败',
          colorScheme.error,
        ),
      BatchJobState.cancelled => (
          Icon(Icons.cancel_rounded,
              color: colorScheme.onSurfaceVariant, size: 20),
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
