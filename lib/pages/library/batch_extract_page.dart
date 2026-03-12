import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/book/document.dart';
import '../../providers/api_provider.dart';
import '../../providers/documents_provider.dart';
import '../../providers/proxy_provider.dart';
import '../../services/batch_extract_service.dart';
import 'widgets/pdf_cover.dart';
import 'widgets/toolbar_bottom_sheet.dart';

// ─── 批量提取选择页面 ────────────────────────────────────────────────────────

class BatchExtractPage extends ConsumerStatefulWidget {
  const BatchExtractPage({super.key});

  @override
  ConsumerState<BatchExtractPage> createState() => _BatchExtractPageState();
}

class _BatchExtractPageState extends ConsumerState<BatchExtractPage> {
  final Set<String> _selectedIds = {};
  String _searchQuery = '';
  bool _searchActive = false;
  bool _showExtracted = false;
  final _searchController = TextEditingController();

  // 拖拽范围选择状态
  bool _isDragSelecting = false;
  int? _rangeAnchorIndex;
  List<Document> _filteredDocs = [];
  final List<GlobalKey> _itemKeys = [];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleAll(List<Document> docs) {
    final allIds = docs.map((d) => d.id).toSet();
    setState(() {
      if (_selectedIds.containsAll(allIds)) {
        _selectedIds.removeAll(allIds);
      } else {
        _selectedIds.addAll(allIds);
      }
    });
  }

  void _toggleItem(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectRange(int from, int to) {
    final start = (from < to ? from : to).clamp(0, _filteredDocs.length - 1);
    final end = (from < to ? to : from).clamp(0, _filteredDocs.length - 1);
    setState(() {
      for (int i = start; i <= end; i++) {
        _selectedIds.add(_filteredDocs[i].id);
      }
    });
  }

  /// 拖拽移动时，根据指针全局坐标命中列表项并扩展选择范围。
  void _onPointerMove(PointerMoveEvent event) {
    if (!_isDragSelecting || _rangeAnchorIndex == null) return;
    for (int i = 0; i < _itemKeys.length; i++) {
      final ctx = _itemKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(event.position)) {
        _selectRange(_rangeAnchorIndex!, i);
        break;
      }
    }
  }

  Future<void> _startExtraction() async {
    if (_selectedIds.isEmpty) return;

    final apiState = ref.read(docExtractApiProvider);
    if (apiState.apiKey.isEmpty || apiState.baseUrl.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        buildResultSnackBar(
          context: context,
          message: '请先在设置中配置文档提取 API（Base URL 和 Access Token）',
        ),
      );
      return;
    }

    final docs = _showExtracted
        ? ref.read(validDocsProvider)
        : ref.read(unextractedDocsProvider);
    final selectedDocs = docs
        .where((d) => _selectedIds.contains(d.id) && d.filePath.isNotEmpty)
        .toList();

    if (selectedDocs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        buildResultSnackBar(
          context: context,
          message: '所选文献中无本地 PDF 文件，无法提取',
        ),
      );
      return;
    }

    final items = selectedDocs
        .map((d) => BatchExtractItem(
              documentId: d.id,
              filePath: d.filePath,
              title: d.title,
            ))
        .toList();

    // 提取前应用当前代理配置
    final proxyState = ref.read(proxyProvider);
    BatchExtractService.instance
        .applyProxy(proxyState.mode, proxyState.host, proxyState.port);

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _BatchProgressSheet(
        items: items,
        apiState: apiState,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final docs = _showExtracted
        ? ref.watch(validDocsProvider)
        : ref.watch(unextractedDocsProvider);
    _filteredDocs = _searchQuery.isEmpty
        ? docs
        : docs.where((d) => d.matchesQuery(_searchQuery)).toList();

    // 同步 GlobalKey 列表与过滤后文献列表的长度
    while (_itemKeys.length < _filteredDocs.length) {
      _itemKeys.add(GlobalKey());
    }
    while (_itemKeys.length > _filteredDocs.length) {
      _itemKeys.removeLast();
    }

    final allIds = _filteredDocs.map((d) => d.id).toSet();
    final allSelected =
        allIds.isNotEmpty && _selectedIds.containsAll(allIds);

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        scrolledUnderElevation: 1,
        title: _searchActive
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: theme.textTheme.titleMedium,
                decoration: InputDecoration(
                  hintText: '搜索文献、作者、关键词...',
                  hintStyle: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  _selectedIds.isEmpty
                      ? '批量提取'
                      : '已选 ${_selectedIds.length} 篇',
                  key: ValueKey(_selectedIds.isEmpty),
                ),
              ),
        actions: [
          if (_searchActive)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: '关闭搜索',
              onPressed: () => setState(() {
                _searchActive = false;
                _searchQuery = '';
                _searchController.clear();
              }),
            )
          else
            IconButton(
              icon: const Icon(Icons.search_rounded),
              tooltip: '搜索',
              onPressed: () => setState(() => _searchActive = true),
            ),
          IconButton(
            icon: Icon(
              _showExtracted
                  ? Icons.filter_alt_off_rounded
                  : Icons.filter_alt_rounded,
            ),
            tooltip: _showExtracted ? '隐藏已提取的文献' : '显示已提取的文献',
            onPressed: () {
              setState(() {
                _showExtracted = !_showExtracted;
                _selectedIds.clear(); // 切换时清空当前选择，避免混淆
              });
            },
          ),
          IconButton(
            icon: Icon(
              allSelected
                  ? Icons.deselect_rounded
                  : Icons.select_all_rounded,
            ),
            tooltip: allSelected ? '取消全选' : '全选',
            onPressed: () => _toggleAll(_filteredDocs),
          ),
        ],
      ),
      body: _filteredDocs.isEmpty
          ? Center(
              child: Text(
                '暂无文献',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : Listener(
              onPointerMove: _onPointerMove,
              onPointerUp: (_) {
                if (_isDragSelecting) {
                  setState(() {
                    _isDragSelecting = false;
                    _rangeAnchorIndex = null;
                  });
                }
              },
              child: CustomScrollView(
                slivers: [
                  // 操作提示
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: Text(
                        '点按选择 · 长按并拖动以批量选择',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withAlpha(160),
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                        16, 4, 16, _selectedIds.isEmpty ? 16 : 104),
                    sliver: SliverList.separated(
                      itemCount: _filteredDocs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final doc = _filteredDocs[index];
                        final isSelected = _selectedIds.contains(doc.id);
                        return _SelectableDocCard(
                          key: _itemKeys[index],
                          doc: doc,
                          isSelected: isSelected,
                          onTap: () => _toggleItem(doc.id),
                          onLongPress: () {
                            HapticFeedback.mediumImpact();
                            setState(() {
                              _isDragSelecting = true;
                              _rangeAnchorIndex = index;
                              _selectedIds.add(doc.id);
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: _selectedIds.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton.icon(
                  onPressed: _startExtraction,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: Text('开始提取（${_selectedIds.length} 篇）'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

// ─── 可选择文献卡片 ────────────────────────────────────────────────────────────

class _SelectableDocCard extends StatelessWidget {
  final Document doc;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _SelectableDocCard({
    super.key,
    required this.doc,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedContainer(
      duration: 150.ms,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isSelected
            ? colorScheme.primaryContainer.withAlpha(80)
            : colorScheme.surfaceContainerLow,
        border: Border.all(
          color: isSelected
              ? colorScheme.primary.withAlpha(160)
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // PDF 封面缩略图
                if (doc.filePath.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 60,
                      height: 84,
                      child: PdfCoverRender(
                        assetPath: doc.filePath,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                // 文献元数据
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 2),
                      Text(
                        doc.title,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (doc.authors.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          doc.authors.join(', '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (doc.journal != null &&
                          doc.journal!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          doc.journal!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant.withAlpha(160),
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                // 选择指示器
                const SizedBox(width: 8),
                Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  key: ValueKey(isSelected),
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
                  size: 24,
                )
                    .animate(target: isSelected ? 1 : 0)
                    .scaleXY(begin: 0.8, end: 1, duration: 200.ms, curve: Curves.easeOutBack),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── 批量提取进度 Sheet ────────────────────────────────────────────────────────

class _BatchProgressSheet extends StatefulWidget {
  final List<BatchExtractItem> items;
  final DocExtractApiState apiState;

  const _BatchProgressSheet({
    required this.items,
    required this.apiState,
  });

  @override
  State<_BatchProgressSheet> createState() => _BatchProgressSheetState();
}

class _BatchProgressSheetState extends State<_BatchProgressSheet> {
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
                    return _JobStatusTile(
                      title: widget.items[index].title,
                      state: BatchJobState.pending,
                    );
                  }
                  final s = progress.statuses[index];
                  return _JobStatusTile(
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

class _JobStatusTile extends StatelessWidget {
  final String title;
  final BatchJobState state;
  final int extractedPages;
  final int totalPages;
  final String? error;

  const _JobStatusTile({
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
