import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/animation_constants.dart';
import '../../core/l10n.dart';
import '../../services/haptics.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/onboarding_dialogs.dart';
import '../../widgets/onboarding_spotlight.dart';
import '../../providers/documents_provider.dart';
import '../../providers/onboarding_provider.dart';
import '../../providers/selection_provider.dart';
import '../../widgets/selection_pop_scope.dart';
import '../../services/snackbar_service.dart';
import '../../router/app_routes.dart';
import 'widgets/bookshelf_grid.dart';
import 'widgets/bookshelf_list.dart';
import 'widgets/doc_card_actions.dart';
import 'widgets/home_header.dart';
import 'widgets/selection_app_bar.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _kAnimDuration = kAnimSlow;
  static const _kAnimCurve = kAnimCurve;

  bool _onboardingScheduled = false;

  @override
  void initState() {
    super.initState();
    // length 2：推荐（左）/ 文献库（右）；initialIndex 1 → 默认打开文献库
    _tabController = TabController(length: 2, initialIndex: 1, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeStartOnboarding(),
    );
  }

  Future<void> _maybeStartOnboarding() async {
    if (_onboardingScheduled) return;
    final step = ref.read(onboardingProvider);
    if (step != OnboardingStep.welcome) return;
    _onboardingScheduled = true;

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    await _runOnboarding();
  }

  Future<void> _runOnboarding() async {
    final notifier = ref.read(onboardingProvider.notifier);
    final l10n = context.l10n;

    // ① 欢迎对话框
    final startSetup = await showOnboardingWelcomeDialog(context);
    if (!startSetup || !mounted) {
      notifier.complete();
      return;
    }

    // ② OCR 对话框
    notifier.advance(); // → ocrIntro
    final goToOcr = await showOnboardingOcrDialog(context);
    if (!mounted) return;

    notifier.advance(); // → ocrGetToken
    if (goToOcr) {
      await context.push(AppRoutes.settingsOverlayExtract);
      if (!mounted) return;
    }

    // ③ 高亮 Tools 按钮（跳过 OCR 子步骤）
    notifier.jumpTo(OnboardingStep.toolsHighlight);
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    await showOnboardingSpotlight(
      context: context,
      targetKey: HomeHeader.toolsButtonKey,
      message: l10n.onboardingToolsHint,
      actionLabel: l10n.onboardingGotIt,
      borderRadius: 20,
    );
    if (!mounted) return;

    // ④ AI 模型对话框
    notifier.advance(); // → aiIntro
    final goToAi = await showOnboardingAiDialog(context);
    if (!mounted) return;

    if (!goToAi) {
      notifier.complete();
      return;
    }

    // ⑤ 前往 AI 设置（AgentApiSection 负责后续 spotlight 引导）
    notifier.advance(); // → aiExpert
    await context.push(AppRoutes.settingsOverlayApi);
    if (!mounted) return;

    // 从 AI 设置返回时，如果引导未完成则标记完成
    if (ref.read(onboardingProvider) != OnboardingStep.completed) {
      notifier.complete();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 把选中文献移入某个收藏夹——先选目标收藏夹（含新建入口），再批量加入。
  Future<void> _addSelectedToFavorite() async {
    final selection = ref.read(selectionProvider);
    await DocCardActions.addToFavorite(
      context,
      ref,
      selection.selectedIds.toSet(),
      exitSelection: true,
    );
  }

  /// 批量删除选中文献
  Future<void> _deleteSelected() async {
    final selection = ref.read(selectionProvider);
    if (selection.selectedIds.isEmpty) return;

    final count = selection.selectedIds.length;
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        title: Text(l10n.batchDelete),
        content: Text(l10n.confirmDeleteDocuments(count)),
        actions: [
          TextButton(
            onPressed: () {
              Haptics.soft();
              Navigator.pop(context, false);
            },
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Haptics.soft();
              Navigator.pop(context, true);
            },
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    for (final id in selection.selectedIds.toList()) {
      await DocCardActions.delete(ref, id);
    }

    ref
        .read(snackBarServiceProvider)
        .showResult(message: l10n.deletedDocuments(count));
    ref.read(selectionProvider.notifier).exit();
  }

  /// 批量提取选中文献
  Future<void> _extractSelected() async {
    final selection = ref.read(selectionProvider);
    if (selection.selectedIds.isEmpty) return;
    final docs = ref.read(validDocsProvider);
    final selectedDocs = docs
        .where((d) => selection.selectedIds.contains(d.id))
        .toList();
    await DocCardActions.extract(
      context,
      ref,
      selectedDocs,
      exitSelection: true,
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

    return SelectionPopScope(
      sourceContext: 'library',
      onSelectAll: () {
        if (!allSelected) {
          ref.read(selectionProvider.notifier).toggleAll(allIds);
        }
      },
      onDeleteSelected: _deleteSelected,
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
                    ? SelectionAppBar(
                        key: const ValueKey('selection'),
                        useSafeArea: false,
                        onClose: () =>
                            ref.read(selectionProvider.notifier).exit(),
                        selectedCount: selection.selectedIds.length,
                        allSelected: allSelected,
                        onSelectAll: () => ref
                            .read(selectionProvider.notifier)
                            .toggleAll(allIds),
                        onExtract: _extractSelected,
                        onAddToFavorite: _addSelectedToFavorite,
                        onDelete: _deleteSelected,
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
              Expanded(child: _buildTabContent(isGrid)),
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
      tabs: [
        Tab(text: context.l10n.recommend),
        Tab(text: context.l10n.documentLibrary),
      ],
    );
  }

  void _restartOnboarding() {
    ref.read(onboardingProvider.notifier).jumpTo(OnboardingStep.welcome);
    _onboardingScheduled = false;
    _runOnboarding();
  }

  Widget _buildTabContent(bool isGrid) {
    return TabBarView(
      controller: _tabController,
      children: [
        Center(child: Text(context.l10n.recommendContent)),
        CustomScrollView(
          slivers: [
            if (isGrid)
              BookshelfGrid(onStartSetup: _restartOnboarding)
            else
              BookshelfList(onStartSetup: _restartOnboarding),
          ],
        ),
      ],
    );
  }
}
