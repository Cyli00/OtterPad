import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/l10n.dart';
import '../../../services/haptics.dart';
import '../../../utils/desktop.dart';
import '../../../widgets/app_context_menu.dart';
import '../../../widgets/hover_lift.dart';
import '../../../widgets/tactile_press.dart';
import '../../library/widgets/pdf_cover.dart';
import '../../../core/design_tokens.dart';
import '../../../core/elevation.dart';

class FavoriteCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? subtitleIcon;
  final List<String> pdfAssets;
  final int totalCount;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final double? maxWidth;
  final EdgeInsetsGeometry margin;

  const FavoriteCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.subtitleIcon,
    required this.pdfAssets,
    required this.totalCount,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.maxWidth,
    this.margin = const EdgeInsets.only(right: 16),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasMenu = onEdit != null || onDelete != null;

    return Padding(
      padding: margin,
      child: GestureDetector(
        onLongPressStart: hasMenu
            ? (d) {
                Haptics.medium();
                _showCardMenu(context, d.globalPosition);
              }
            : null,
        onSecondaryTapDown: hasMenu && isDesktopOs
            ? (d) => _showCardMenu(context, d.globalPosition)
            : null,
        child: HoverLift(
          enabled: isDesktopOs,
          // Folio：一张纸——纸色底 + 细线，静止不投影
          child: Container(
            width: _cardWidth(),
            height: 380,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: AppStroke.rule(cs)),
            ),
            child: TactilePress(
              baseColor: cs.surfaceContainerLowest,
              borderRadius: AppRadius.mdAll,
              pressedScale: 0.98,
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.x5,
                        AppSpace.x5,
                        AppSpace.x5,
                        AppSpace.x4,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: cs.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AppSpace.x1),
                          Row(
                            children: [
                              if (subtitleIcon != null) ...[
                                subtitleIcon!,
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: Text(
                                  subtitle,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontFeatures: AppType.tabular,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpace.x4),
                          Expanded(child: _buildCoverArea(context)),
                        ],
                      ),
                    ),
                  ),
                  // 底栏：细线上方一行文字链接，不再是灰色按钮块
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(top: AppStroke.side(cs)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.x5,
                        vertical: AppSpace.x3,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.l10n.viewLibraryTotal(totalCount),
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: cs.onSurface,
                                fontFeatures: AppType.tabular,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Symbols.arrow_forward_rounded,
                            size: 18,
                            color: cs.onSurface,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showCardMenu(BuildContext context, Offset position) async {
    final result = await showAppContextMenu<String>(
      context: context,
      globalPosition: position,
      items: [
        if (onEdit != null)
          AppContextMenuItem(
            value: 'edit',
            label: context.l10n.edit,
            icon: Symbols.edit_rounded,
          ),
        if (onDelete != null)
          AppContextMenuItem(
            value: 'delete',
            label: context.l10n.delete,
            icon: Symbols.delete_rounded,
            destructive: true,
          ),
      ],
    );
    if (result == 'edit') onEdit?.call();
    if (result == 'delete') onDelete?.call();
  }

  // ── 封面布局 ──

  double _getDynamicWidth() {
    final count = pdfAssets.length;
    if (count <= 1) return 200.0;
    if (count == 2) return 330.0;
    if (count == 3) return 280.0;
    if (count == 4) return 200.0;
    return 330.0;
  }

  double _cardWidth() {
    final desired = _getDynamicWidth();
    final maxW = maxWidth;
    if (maxW == null) return desired;
    const lo = 200.0;
    final hi = math.max(lo, maxW);
    return desired.clamp(lo, hi);
  }

  Widget _emptyCover(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.hairline),
        border: Border.all(color: AppStroke.rule(cs)),
      ),
      child: Center(
        child: Icon(Symbols.bookmark_rounded, color: cs.outline, size: 22),
      ),
    );
  }

  /// 每张封面都是一页纸：细线 + 贴边实影，和文献库网格一致。
  Widget _cover(BuildContext context, String? path) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.hairline),
        border: Border.all(color: AppStroke.rule(cs)),
        boxShadow: AppShadows.page,
      ),
      clipBehavior: Clip.antiAlias,
      child: path != null && path.isNotEmpty
          ? PdfCoverRender(assetPath: path)
          : _emptyCover(context),
    );
  }

  Widget _buildCoverArea(BuildContext context) {
    final count = pdfAssets.length;
    if (count == 0) {
      return Center(
        child: AspectRatio(aspectRatio: 0.72, child: _emptyCover(context)),
      );
    }
    if (count == 1) {
      return Center(
        child: AspectRatio(
          aspectRatio: 0.72,
          child: _cover(context, pdfAssets[0]),
        ),
      );
    }
    if (count == 2) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: AspectRatio(
              aspectRatio: 0.72,
              child: _cover(context, pdfAssets[0]),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AspectRatio(
              aspectRatio: 0.72,
              child: _cover(context, pdfAssets[1]),
            ),
          ),
        ],
      );
    }
    if (count == 3) {
      return Row(
        children: [
          Expanded(
            flex: 2,
            child: AspectRatio(
              aspectRatio: 0.72,
              child: _cover(context, pdfAssets[0]),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 1,
            child: Column(
              children: [
                Expanded(child: _cover(context, pdfAssets[1])),
                const SizedBox(height: 4),
                Expanded(child: _cover(context, pdfAssets[2])),
              ],
            ),
          ),
        ],
      );
    }
    if (count == 4) {
      return Center(
        child: AspectRatio(
          aspectRatio: 0.72,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _cover(context, pdfAssets[0])),
                    const SizedBox(width: 4),
                    Expanded(child: _cover(context, pdfAssets[1])),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _cover(context, pdfAssets[2])),
                    const SizedBox(width: 4),
                    Expanded(child: _cover(context, pdfAssets[3])),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    // count >= 5
    return Row(
      children: [
        Expanded(
          flex: 12,
          child: AspectRatio(
            aspectRatio: 0.72,
            child: _cover(context, pdfAssets[0]),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 11,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _cover(context, pdfAssets[1])),
                    const SizedBox(width: 3),
                    Expanded(child: _cover(context, pdfAssets[2])),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Expanded(
                child: Row(
                  children: [
                    Expanded(child: _cover(context, pdfAssets[3])),
                    const SizedBox(width: 3),
                    Expanded(child: _cover(context, pdfAssets[4])),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
