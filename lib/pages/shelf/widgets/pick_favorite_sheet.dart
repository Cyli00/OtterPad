import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../core/l10n.dart';
import '../../../services/haptics.dart';
import '../../../widgets/tactile_press.dart';

import '../../../data/models/collection/favorite.dart';

/// 选择一个目标收藏夹的结果。
class PickFavoriteResult {
  final String favoriteId;
  const PickFavoriteResult(this.favoriteId);
}

/// 选择一个目标收藏夹的底部 sheet——用于首页选择模式下"移入收藏夹"。
///
/// [selectedDocumentIds] 用来在每项展示该收藏夹与当前选中集合的重叠度
/// （"已含 X 篇 / 待入 Y 篇"）。完全覆盖时整项置灰阻止重复点选——provider
/// 层 `addDocuments` 也会去重作为双保险。
Future<PickFavoriteResult?> showPickFavoriteSheet({
  required BuildContext context,
  required List<Favorite> favorites,
  required Set<String> selectedDocumentIds,
  Future<Favorite?> Function()? onCreateFavorite,
}) {
  return showModalBottomSheet<PickFavoriteResult>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _PickFavoriteContent(
      favorites: favorites,
      selectedDocumentIds: selectedDocumentIds,
      onCreateFavorite: onCreateFavorite,
    ),
  );
}

class _PickFavoriteContent extends StatefulWidget {
  final List<Favorite> favorites;
  final Set<String> selectedDocumentIds;
  final Future<Favorite?> Function()? onCreateFavorite;

  const _PickFavoriteContent({
    required this.favorites,
    required this.selectedDocumentIds,
    this.onCreateFavorite,
  });

  @override
  State<_PickFavoriteContent> createState() => _PickFavoriteContentState();
}

class _PickFavoriteContentState extends State<_PickFavoriteContent> {
  late List<Favorite> _favorites;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _favorites = List.of(widget.favorites);
  }

  Future<void> _createFavorite() async {
    final cb = widget.onCreateFavorite;
    if (cb == null || _creating) return;

    setState(() => _creating = true);
    final fav = await cb();
    if (!mounted) return;

    setState(() {
      _creating = false;
      if (fav != null && !_favorites.any((f) => f.id == fav.id)) {
        _favorites = [..._favorites, fav];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final maxH = MediaQuery.sizeOf(context).height * 0.7;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final total = widget.selectedDocumentIds.length;

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
                  context.l10n.addingDocumentsTo(total),
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
                  if (widget.onCreateFavorite != null)
                    _CreateFavoriteItem(
                      creating: _creating,
                      onTap: _createFavorite,
                    ),
                  for (final fav in _favorites)
                    _buildFavoriteItem(theme, fav),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, bottomPadding + 16),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Haptics.soft();
                    Navigator.pop(context);
                  },
                  child: Text(context.l10n.cancel),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoriteItem(ThemeData theme, Favorite fav) {
    final existing = fav.documentIds.toSet();
    final overlap = widget.selectedDocumentIds
        .where(existing.contains)
        .length;
    final newCount = widget.selectedDocumentIds.length - overlap;
    final allIncluded = newCount == 0;
    final l10n = context.l10n;
    final subtitle = allIncluded
        ? l10n.allSelectedAlreadyHere(widget.selectedDocumentIds.length)
        : overlap == 0
        ? l10n.currentDocumentCount(fav.documentIds.length)
        : l10n.overlapAndNew(overlap, newCount);

    return _FavoriteItem(
      favorite: fav,
      subtitle: subtitle,
      disabled: allIncluded,
      onTap: () => Navigator.pop(context, PickFavoriteResult(fav.id)),
    );
  }
}

class _FavoriteItem extends StatelessWidget {
  final Favorite favorite;
  final String subtitle;
  final bool disabled;
  final VoidCallback onTap;

  const _FavoriteItem({
    required this.favorite,
    required this.subtitle,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final titleColor = disabled ? cs.onSurfaceVariant : cs.onSurface;

    return TactilePress(
      onTap: disabled ? null : onTap,
      baseColor: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.primaryContainer.withAlpha(disabled ? 80 : 255),
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
                    color: titleColor,
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
          if (!disabled)
            Icon(
              Symbols.chevron_right_rounded,
              color: cs.onSurfaceVariant.withAlpha(120),
            ),
        ],
      ),
    );
  }
}

class _CreateFavoriteItem extends StatelessWidget {
  final bool creating;
  final VoidCallback onTap;

  const _CreateFavoriteItem({required this.creating, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return TactilePress(
      onTap: creating ? null : onTap,
      baseColor: Colors.transparent,
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
            child: Text(
              context.l10n.createFavorite,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
          Icon(
            Symbols.chevron_right_rounded,
            color: cs.onSurfaceVariant.withAlpha(120),
          ),
        ],
      ),
    );
  }
}
