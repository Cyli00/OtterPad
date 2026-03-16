import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/book/document.dart';
import '../../providers/documents_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../services/snackbar_service.dart';
import 'widgets/doc_card_actions.dart';
import 'widgets/pdf_cover.dart';

/// 批量删除选择页面
///
/// [favoriteId] 为 null 时显示全部有文件的文献（文献库模式）；
/// 非 null 时仅显示该收藏夹内的文献。
/// [initialSelectedId] 可预选中长按触发的那张卡片。
class BatchDeletePage extends ConsumerStatefulWidget {
  final String? favoriteId;
  final String? initialSelectedId;

  const BatchDeletePage({
    super.key,
    this.favoriteId,
    this.initialSelectedId,
  });

  @override
  ConsumerState<BatchDeletePage> createState() => _BatchDeletePageState();
}

class _BatchDeletePageState extends ConsumerState<BatchDeletePage> {
  final Set<String> _selectedIds = {};
  String _searchQuery = '';
  bool _searchActive = false;
  final _searchController = TextEditingController();

  // 拖拽范围选择状态
  bool _isDragSelecting = false;
  int? _rangeAnchorIndex;
  List<Document> _filteredDocs = [];
  final List<GlobalKey> _itemKeys = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialSelectedId != null) {
      _selectedIds.add(widget.initialSelectedId!);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 获取当前数据源的完整文献列表
  List<Document> _getSourceDocs() {
    if (widget.favoriteId != null) {
      final favorites = ref.watch(favoritesProvider);
      final fav = favorites.where((f) => f.id == widget.favoriteId).firstOrNull;
      if (fav == null) return [];

      final allDocs = ref.watch(documentsProvider);
      final pathSet = fav.docPaths.toSet();
      return allDocs.where((d) => pathSet.contains(d.filePath)).toList();
    }
    return ref.watch(validDocsProvider);
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

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final count = _selectedIds.length;
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定要删除 $count 篇文献吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    for (final id in _selectedIds.toList()) {
      DocCardActions.delete(ref, id);
    }

    ref.read(snackBarServiceProvider).showResult(
          message: '已删除 $count 篇文献',
        );

    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final docs = _getSourceDocs();
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
                      ? '批量删除'
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
                  onPressed: _deleteSelected,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text('删除选中（${_selectedIds.length} 篇）'),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.error,
                    foregroundColor: colorScheme.onError,
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
                            color:
                                colorScheme.onSurfaceVariant.withAlpha(160),
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
                    .scaleXY(
                        begin: 0.8,
                        end: 1,
                        duration: 200.ms,
                        curve: Curves.easeOutBack),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
