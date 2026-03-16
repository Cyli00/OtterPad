import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/api_provider.dart';
import '../../providers/documents_provider.dart';
import '../../providers/proxy_provider.dart';
import '../../providers/selection_provider.dart';
import '../../services/batch_extract_service.dart';
import '../../services/snackbar_service.dart';
import 'widgets/batch_progress_sheet.dart';
import 'widgets/bookshelf_grid.dart';
import 'widgets/bookshelf_list.dart';
import 'widgets/doc_card_actions.dart';
import 'widgets/home_header.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _kAnimDuration = Duration(milliseconds: 300);
  static const _kAnimCurve = Curves.easeOutCubic;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 批量删除选中文献
  Future<void> _deleteSelected() async {
    final selection = ref.read(selectionProvider);
    if (selection.selectedIds.isEmpty) return;

    final count = selection.selectedIds.length;
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

    for (final id in selection.selectedIds.toList()) {
      DocCardActions.delete(ref, id);
    }

    ref.read(snackBarServiceProvider).showResult(
          message: '已删除 $count 篇文献',
        );
    ref.read(selectionProvider.notifier).exit();
  }

  /// 批量提取选中文献
  Future<void> _extractSelected() async {
    final selection = ref.read(selectionProvider);
    if (selection.selectedIds.isEmpty) return;

    final apiState = ref.read(docExtractApiProvider);
    if (apiState.apiKey.isEmpty || apiState.baseUrl.isEmpty) {
      ref.read(snackBarServiceProvider).showResult(
            message: '请先在设置中配置文档提取 API（Base URL 和 Access Token）',
          );
      return;
    }

    final docs = ref.read(validDocsProvider);
    final selectedDocs = docs
        .where((d) =>
            selection.selectedIds.contains(d.id) && d.filePath.isNotEmpty)
        .toList();

    if (selectedDocs.isEmpty) {
      ref.read(snackBarServiceProvider).showResult(
            message: '所选文献中无本地 PDF 文件，无法提取',
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

    ref.read(selectionProvider.notifier).exit();

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BatchProgressSheet(
        items: items,
        apiState: apiState,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isGrid = ref.watch(viewModeProvider);
    final selection = ref.watch(selectionProvider);
    final isSelectionMode =
        selection.isActive && selection.sourceContext == 'library';

    final docs = ref.watch(validDocsProvider);
    final allIds = docs.map((d) => d.id).toSet();
    final allSelected =
        allIds.isNotEmpty && selection.selectedIds.containsAll(allIds);

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 600;
    final buttonSize = isMobile ? 36.0 : 40.0;

    return PopScope(
      canPop: !isSelectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          ref.read(selectionProvider.notifier).exit();
        }
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: Column(
            children: [
              // ── 顶栏：搜索栏 ↔ 选择栏 平滑交叉淡入 ──
              AnimatedSwitcher(
                duration: _kAnimDuration,
                switchInCurve: _kAnimCurve,
                switchOutCurve: _kAnimCurve,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: isSelectionMode
                    ? _buildSelectionRow(
                        theme: theme,
                        cs: cs,
                        isMobile: isMobile,
                        buttonSize: buttonSize,
                        selection: selection,
                        allIds: allIds,
                        allSelected: allSelected,
                      )
                    : const HomeHeader(key: ValueKey('normal')),
              ),
              // ── TabBar：选择模式下折叠 ──
              ClipRect(
                child: AnimatedAlign(
                  duration: _kAnimDuration,
                  curve: _kAnimCurve,
                  heightFactor: isSelectionMode ? 0.0 : 1.0,
                  alignment: Alignment.topCenter,
                  child: _buildTabBar(cs),
                ),
              ),
              // ── 内容区 ──
              Expanded(
                child: isSelectionMode
                    ? _buildSelectionContent(isGrid)
                    : _buildTabContent(isGrid),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(ColorScheme cs) {
    return TabBar(
      controller: _tabController,
      isScrollable: true,
      tabAlignment: TabAlignment.center,
      indicatorSize: TabBarIndicatorSize.label,
      indicatorWeight: 3.0,
      indicatorColor: cs.primary,
      labelColor: cs.primary,
      labelStyle: const TextStyle(fontWeight: FontWeight.bold),
      unselectedLabelColor: cs.onSurfaceVariant,
      dividerColor: Colors.transparent,
      tabs: const [
        Tab(text: '文献库'),
        Tab(text: '推荐'),
        Tab(text: '会议日程'),
      ],
    );
  }

  Widget _buildTabContent(bool isGrid) {
    return TabBarView(
      controller: _tabController,
      children: [
        CustomScrollView(
          slivers: [
            if (isGrid) const BookshelfGrid() else const BookshelfList(),
          ],
        ),
        const Center(child: Text('推荐内容')),
        const Center(child: Text('会议日程')),
      ],
    );
  }

  Widget _buildSelectionContent(bool isGrid) {
    return CustomScrollView(
      slivers: [
        if (isGrid) const BookshelfGrid() else const BookshelfList(),
      ],
    );
  }

  /// 选择模式顶栏 — 与 HomeHeader 等高，按钮尺寸一致
  Widget _buildSelectionRow({
    required ThemeData theme,
    required ColorScheme cs,
    required bool isMobile,
    required double buttonSize,
    required SelectionState selection,
    required Set<String> allIds,
    required bool allSelected,
  }) {
    final iconSize = buttonSize * 0.5;
    final hasSelection = selection.selectedIds.isNotEmpty;

    return Padding(
      key: const ValueKey('selection'),
      padding: EdgeInsets.only(
        left: 16.0,
        right: 16.0,
        top: isMobile ? 4.0 : 8.0,
        bottom: 16.0,
      ),
      child: SizedBox(
        height: isMobile ? 44 : 48,
        child: Row(
          children: [
            SizedBox(
              width: buttonSize,
              height: buttonSize,
              child: IconButton(
                onPressed: () =>
                    ref.read(selectionProvider.notifier).exit(),
                icon: Icon(Icons.close_rounded, size: iconSize),
                padding: EdgeInsets.zero,
                tooltip: '退出多选',
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '已选 ${selection.selectedIds.length}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            _actionButton(
              icon: allSelected
                  ? Icons.deselect_rounded
                  : Icons.select_all_rounded,
              size: buttonSize,
              iconSize: iconSize,
              onPressed: () =>
                  ref.read(selectionProvider.notifier).toggleAll(allIds),
              tooltip: allSelected ? '取消全选' : '全选',
              backgroundColor: cs.primaryContainer,
              foregroundColor: cs.primary,
            ),
            const SizedBox(width: 8),
            _actionButton(
              icon: Icons.auto_awesome_rounded,
              size: buttonSize,
              iconSize: iconSize,
              onPressed: hasSelection ? _extractSelected : null,
              tooltip: '文本提取',
              backgroundColor: cs.primaryContainer,
              foregroundColor: cs.primary,
            ),
            const SizedBox(width: 8),
            _actionButton(
              icon: Icons.delete_outline_rounded,
              size: buttonSize,
              iconSize: iconSize,
              onPressed: hasSelection ? _deleteSelected : null,
              tooltip: '删除',
              backgroundColor: cs.errorContainer,
              foregroundColor: cs.error,
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required double size,
    required double iconSize,
    required VoidCallback? onPressed,
    required String tooltip,
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    return SizedBox(
      width: size,
      height: size,
      child: IconButton.filled(
        onPressed: onPressed,
        icon: Icon(icon, size: iconSize),
        tooltip: tooltip,
        style: IconButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
