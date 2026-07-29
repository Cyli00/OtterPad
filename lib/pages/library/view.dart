import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/animation_constants.dart';
import '../../core/l10n.dart';
import '../../services/haptics.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/onboarding_dialogs.dart';
import '../../widgets/onboarding_spotlight.dart';
import '../../providers/api_provider.dart';
import '../../providers/document_lifecycle_provider.dart';
import '../../providers/documents_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/onboarding_provider.dart';
import '../../providers/proxy_provider.dart';
import '../../providers/selection_provider.dart';
import '../../widgets/selection_pop_scope.dart';
import '../../services/batch_extract_service.dart';
import '../../services/ai_settings_prompt.dart';
import '../../services/snackbar_service.dart';
import '../../router/app_routes.dart';
import '../../utils/doc_paths.dart';
import '../shelf/widgets/create_favorite_dialog.dart';
import '../shelf/widgets/pick_favorite_sheet.dart';
import 'widgets/batch_progress_sheet.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartOnboarding());
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
      await context.push(AppRoutes.settingsExtract);
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
    await context.push(AppRoutes.settingsApi);
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
  ///
  /// Provider 层 `addDocuments` 自带去重；pick sheet 还会显示与每个收藏夹
  /// 的重叠度提示，让用户清楚有多少篇会被跳过。
  Future<void> _addSelectedToFavorite() async {
    final selection = ref.read(selectionProvider);
    if (selection.selectedIds.isEmpty) return;

    final favorites = ref.read(favoritesProvider).value ?? const [];
    final selectedIds = selection.selectedIds.toSet();

    final result = await showPickFavoriteSheet(
      context: context,
      favorites: favorites,
      selectedDocumentIds: selectedIds,
      onCreateFavorite: () async {
        final res = await showCreateFavoriteDialog(context);
        if (res == null) return null;
        return ref
            .read(favoritesProvider.notifier)
            .create(emoji: res['emoji']!, name: res['name']!);
      },
    );
    if (result == null) return;

    final added = await ref
        .read(documentLifecycleProvider)
        .addToFavoriteBatch(result.favoriteId, selectedIds);
    if (!mounted) return;
    final skipped = selectedIds.length - added;
    final l10n = context.l10n;
    final msg = skipped == 0
        ? l10n.documentsAddedCount(added)
        : l10n.documentsAddedSkipped(added, skipped);
    ref.read(snackBarServiceProvider).showResult(message: msg);
    ref.read(selectionProvider.notifier).exit();
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

    ref.read(snackBarServiceProvider).showResult(message: l10n.deletedDocuments(count));
    ref.read(selectionProvider.notifier).exit();
  }

  /// 批量提取选中文献
  Future<void> _extractSelected() async {
    final selection = ref.read(selectionProvider);
    if (selection.selectedIds.isEmpty) return;

    final apiState = ref.read(docExtractApiProvider);
    if (!await AiSettingsPrompt.ensureExtractConfigured(
      context: context,
      apiState: apiState,
    )) {
      return;
    }
    if (!mounted) return;

    final docs = ref.read(validDocsProvider);
    final selectedDocs = docs
        .where(
          (d) => selection.selectedIds.contains(d.id) && d.contentHash != null,
        )
        .toList();

    if (selectedDocs.isEmpty) {
      ref
          .read(snackBarServiceProvider)
          .showResult(message: context.l10n.noPdfFilesSelected);
      return;
    }

    final items = selectedDocs
        .map(
          (d) => BatchExtractItem(
            documentId: d.id,
            filePath: DocPaths.pdf(d.id),
            title: d.title,
          ),
        )
        .toList();

    // 提取前应用当前代理配置
    final proxyState = ref.read(proxyProvider);
    BatchExtractService.instance.applyProxy(
      proxyState.mode,
      proxyState.host,
      proxyState.port,
    );

    ref.read(selectionProvider.notifier).exit();

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BatchProgressSheet(items: items, apiState: apiState),
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
              Expanded(
                child: _buildTabContent(isGrid),
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
