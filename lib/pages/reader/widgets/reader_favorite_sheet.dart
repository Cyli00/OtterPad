import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../data/models/collection/favorite.dart';
import 'reader_background.dart';

enum ReaderFavoritePickerMode { add, remove }

class ReaderFavoriteSelectionResult {
  final List<Favorite> favorites;

  const ReaderFavoriteSelectionResult(this.favorites);
}

Future<ReaderFavoriteSelectionResult?> showReaderFavoritePickerSheet({
  required BuildContext context,
  required String title,
  required List<Favorite> favorites,
  required String documentId,
  required ReaderFavoritePickerMode mode,
  Future<Favorite?> Function()? onCreateFavorite,
}) {
  return showModalBottomSheet<ReaderFavoriteSelectionResult>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => ReaderLocalTheme(
      child: _ReaderFavoritePickerContent(
        title: title,
        favorites: favorites,
        documentId: documentId,
        mode: mode,
        onCreateFavorite: onCreateFavorite,
      ),
    ),
  );
}

class _ReaderFavoritePickerContent extends StatefulWidget {
  final String title;
  final List<Favorite> favorites;
  final String documentId;
  final ReaderFavoritePickerMode mode;
  final Future<Favorite?> Function()? onCreateFavorite;

  const _ReaderFavoritePickerContent({
    required this.title,
    required this.favorites,
    required this.documentId,
    required this.mode,
    this.onCreateFavorite,
  });

  @override
  State<_ReaderFavoritePickerContent> createState() =>
      _ReaderFavoritePickerContentState();
}

class _ReaderFavoritePickerContentState
    extends State<_ReaderFavoritePickerContent> {
  late List<Favorite> _favorites;
  final Set<String> _selectedIds = {};
  bool _creating = false;

  bool get _isAddMode => widget.mode == ReaderFavoritePickerMode.add;

  @override
  void initState() {
    super.initState();
    _favorites = List.of(widget.favorites);
  }

  Future<void> _createFavorite() async {
    final onCreateFavorite = widget.onCreateFavorite;
    if (onCreateFavorite == null || _creating) return;

    setState(() => _creating = true);
    final favorite = await onCreateFavorite();
    if (!mounted) return;

    setState(() {
      _creating = false;
      if (favorite != null && !_favorites.any((f) => f.id == favorite.id)) {
        _favorites = [favorite, ..._favorites];
      }
    });
  }

  void _toggle(Favorite favorite) {
    final alreadyIn = favorite.documentIds.contains(widget.documentId);
    if (_isAddMode && alreadyIn) return;

    setState(() {
      if (!_selectedIds.add(favorite.id)) {
        _selectedIds.remove(favorite.id);
      }
    });
  }

  void _submit() {
    final selected = [
      for (final favorite in _favorites)
        if (_selectedIds.contains(favorite.id)) favorite,
    ];
    Navigator.pop(context, ReaderFavoriteSelectionResult(selected));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final maxH = MediaQuery.sizeOf(context).height * 0.7;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final confirmLabel = _isAddMode ? '添加' : '移出';

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  if (_isAddMode)
                    _CreateFavoriteSheetItem(
                      creating: _creating,
                      onTap: _createFavorite,
                    ),
                  for (final fav in _favorites)
                    _FavoritePickerSheetItem.favorite(
                      favorite: fav,
                      subtitle: _subtitleFor(fav),
                      checked: _checkedFor(fav),
                      enabled: _enabledFor(fav),
                      onTap: () => _toggle(fav),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, bottomPadding + 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _selectedIds.isEmpty ? null : _submit,
                    child: Text(confirmLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitleFor(Favorite favorite) {
    if (_isAddMode && favorite.documentIds.contains(widget.documentId)) {
      return '已包含当前文献';
    }
    return '${favorite.documentIds.length} 篇文献';
  }

  bool _checkedFor(Favorite favorite) {
    return (_isAddMode && favorite.documentIds.contains(widget.documentId)) ||
        _selectedIds.contains(favorite.id);
  }

  bool _enabledFor(Favorite favorite) {
    return !_isAddMode || !favorite.documentIds.contains(widget.documentId);
  }
}

class _CreateFavoriteSheetItem extends StatelessWidget {
  final bool creating;
  final VoidCallback onTap;

  const _CreateFavoriteSheetItem({required this.creating, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return InkWell(
      onTap: creating ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: creating
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                      ),
                    )
                  : Icon(
                      Symbols.add_rounded,
                      color: cs.primary,
                      size: 22,
                      fill: 1,
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '新建收藏夹',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '创建后可在下方勾选',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Symbols.chevron_right_rounded,
              color: cs.onSurfaceVariant.withAlpha(120),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoritePickerSheetItem extends StatelessWidget {
  final Favorite favorite;
  final String subtitle;
  final bool checked;
  final bool enabled;
  final VoidCallback onTap;

  const _FavoritePickerSheetItem.favorite({
    required this.favorite,
    required this.subtitle,
    required this.checked,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final activeColor = enabled ? cs.onSurface : cs.onSurfaceVariant;

    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                favorite.emoji,
                style: const TextStyle(fontSize: 22, height: 1.0),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    favorite.name,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: activeColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Checkbox(
              value: checked,
              onChanged: enabled ? (_) => onTap() : null,
            ),
          ],
        ),
      ),
    );
  }
}
