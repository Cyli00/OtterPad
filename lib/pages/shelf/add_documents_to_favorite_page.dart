import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/models/book/document.dart';
import '../../services/haptics.dart';
import '../../data/models/collection/favorite.dart';
import '../../providers/document_lifecycle_provider.dart';
import '../../providers/documents_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/history_provider.dart';
import '../../services/snackbar_service.dart';
import '../../core/l10n.dart';
import '../library/widgets/doc_list_card.dart';

/// 收藏夹"添加文献"页面。
///
/// 全屏列表 + 顶部搜索 + 右下角"确认 / 取消"。已在收藏夹的文献做灰度处理且
/// 不可点选；用户确认后 pop（返回值无关，本页内部直接调用 lifecycleProvider
/// 完成批量加入并 SnackBar 反馈，让调用方逻辑保持最小）。
class AddDocumentsToFavoritePage extends ConsumerStatefulWidget {
  final Favorite favorite;

  const AddDocumentsToFavoritePage({super.key, required this.favorite});

  @override
  ConsumerState<AddDocumentsToFavoritePage> createState() =>
      _AddDocumentsToFavoritePageState();
}

class _AddDocumentsToFavoritePageState
    extends ConsumerState<AddDocumentsToFavoritePage> {
  final _selectedIds = <String>{};
  final _searchController = TextEditingController();
  String _query = '';
  bool _submitting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(Document doc) {
    if (_query.isEmpty) return true;
    final lower = _query.toLowerCase();
    if (doc.title.toLowerCase().contains(lower)) return true;
    for (final a in doc.authors) {
      if (a.toLowerCase().contains(lower)) return true;
    }
    if (doc.year?.toLowerCase().contains(lower) == true) return true;
    if (doc.journal?.toLowerCase().contains(lower) == true) return true;
    return false;
  }

  void _toggleSelected(String docId) {
    setState(() {
      if (!_selectedIds.add(docId)) _selectedIds.remove(docId);
    });
  }

  /// 全选/反选当前搜索结果中**可选**的文献（已在收藏夹的不参与）。
  /// 全部已勾选时点击 → 把这些 id 从已选集合移除；否则 → 全部加入。
  void _toggleSelectAll(Set<String> selectableIds) {
    if (selectableIds.isEmpty) return;
    setState(() {
      if (_selectedIds.containsAll(selectableIds)) {
        _selectedIds.removeAll(selectableIds);
      } else {
        _selectedIds.addAll(selectableIds);
      }
    });
  }

  Future<void> _onCancel() async {
    context.pop();
  }

  Future<void> _onConfirm() async {
    if (_selectedIds.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    final added = await ref
        .read(documentLifecycleProvider)
        .addToFavoriteBatch(widget.favorite.id, _selectedIds);
    if (!mounted) return;
    ref.read(snackBarServiceProvider).showResult(message: context.l10n.addedDocumentsToFavorite(added));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // 只展示有文件的文献——无文件条目按全应用规则不可收藏，需先挂载 PDF 后
    // 才会出现在 validDocsProvider 中。
    final docs = ref.watch(validDocsProvider);
    final favorites = ref.watch(favoritesProvider);
    final history = ref.watch(historyProvider);
    final progressByDoc = {for (final e in history) e.docId: e.progress};

    final currentFavorite = favorites.firstWhere(
      (f) => f.id == widget.favorite.id,
      orElse: () => widget.favorite,
    );
    final alreadyIn = currentFavorite.documentIds.toSet();

    final filtered = [
      for (final d in docs)
        if (_matches(d)) d,
    ];
    // 全选只覆盖"当前可选"——已在收藏夹的不计入。
    final selectableIds = {
      for (final d in filtered)
        if (!alreadyIn.contains(d.id)) d.id,
    };
    final allSelected =
        selectableIds.isNotEmpty && _selectedIds.containsAll(selectableIds);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        leading: IconButton(
          onPressed: () {
            Haptics.soft();
            _onCancel();
          },
          icon: const Icon(Symbols.arrow_back_rounded),
        ),
        titleSpacing: 0,
        title: _SearchField(
          controller: _searchController,
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
        actions: [
          IconButton(
            onPressed: selectableIds.isEmpty
                ? null
                : () {
                    Haptics.soft();
                    _toggleSelectAll(selectableIds);
                  },
            icon: Icon(
              allSelected
                  ? Symbols.deselect_rounded
                  : Symbols.select_all_rounded,
            ),
            tooltip: allSelected ? context.l10n.deselectAll : context.l10n.selectAll,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            if (filtered.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    docs.isEmpty ? context.l10n.libraryEmpty : context.l10n.noDocumentsFound,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final doc = filtered[i];
                  final included = alreadyIn.contains(doc.id);
                  final selected = _selectedIds.contains(doc.id);
                  final card = DocListCard(
                    doc: doc,
                    progress: progressByDoc[doc.id] ?? 0.0,
                    isSelectionMode: true,
                    isSelected: selected,
                    onSelectionTap: included ? null : () => _toggleSelected(doc.id),
                  );
                  if (!included) return card;

                  return Stack(
                    children: [
                      IgnorePointer(child: Opacity(opacity: 0.4, child: card)),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: _IncludedBadge(),
                      ),
                    ],
                  );
                },
              ),
            Positioned(
              right: 16,
              bottom: 16,
              child: _BottomActions(
                selectedCount: _selectedIds.length,
                submitting: _submitting,
                onCancel: _onCancel,
                onConfirm: _selectedIds.isEmpty ? null : _onConfirm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Symbols.search_rounded, size: 20),
          hintText: context.l10n.searchDocumentHint,
          filled: true,
          fillColor: cs.surfaceContainerHighest,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _IncludedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.bookmark_rounded, size: 14, color: cs.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            context.l10n.alreadyInThisFavorite,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  final int selectedCount;
  final bool submitting;
  final VoidCallback onCancel;
  final VoidCallback? onConfirm;

  const _BottomActions({
    required this.selectedCount,
    required this.submitting,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      elevation: 6,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: submitting
                  ? null
                  : () {
                      Haptics.soft();
                      onCancel();
                    },
              child: Text(context.l10n.cancel),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: submitting || onConfirm == null
                  ? null
                  : () {
                      Haptics.soft();
                      onConfirm!();
                    },
              icon: submitting
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.onPrimary,
                      ),
                    )
                  : const Icon(Symbols.check_rounded, size: 18),
              label: Text(selectedCount == 0 ? context.l10n.confirm : context.l10n.selectedCount(selectedCount)),
            ),
          ],
        ),
      ),
    );
  }
}
