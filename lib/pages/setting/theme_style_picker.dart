import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:motor/motor.dart';

import '../../core/design_tokens.dart';
import '../../core/l10n.dart';
import '../../core/animation_constants.dart';
import '../../providers/theme_provider.dart';
import '../../services/haptics.dart';

/// 主题风格选择器：每张卡片用真实的 [FolioPalette] 渲染一页缩略界面，
/// 选中态是加粗的强调色描边 + 右上角勾选。
class ThemeStylePicker extends ConsumerWidget {
  const ThemeStylePicker({super.key});

  static String label(AppLocalizations l10n, ThemeStyle s) => switch (s) {
    ThemeStyle.paper => l10n.themeStylePaper,
    ThemeStyle.vivid => l10n.themeStyleVivid,
    ThemeStyle.mist => l10n.themeStyleMist,
    ThemeStyle.moss => l10n.themeStyleMoss,
    ThemeStyle.dusk => l10n.themeStyleDusk,
    ThemeStyle.graphite => l10n.themeStyleGraphite,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(themeProvider);
    final seed = state.useDynamicColor
        ? theme.colorScheme.primary
        : state.seedColor;
    final l10n = context.l10n;

    return SizedBox(
      height: 156,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: ThemeStyle.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final style = ThemeStyle.values[i];
          return _StyleCard(
            label: label(l10n, style),
            scheme: FolioPalette.scheme(seed, theme.brightness, style),
            selected: state.style == style,
            onTap: () {
              Haptics.soft();
              ref.read(themeProvider.notifier).setStyle(style);
            },
          );
        },
      ),
    );
  }
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.label,
    required this.scheme,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final ColorScheme scheme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = scheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: SingleMotionBuilder(
          motion: kMotionSpatialFast,
          value: selected ? 1.0 : 0.0,
          builder: (context, t, _) {
            return Column(
              children: [
                Container(
                  width: 104,
                  height: 120,
                  padding: EdgeInsets.all(3 * t),
                  decoration: ShapeDecoration(
                    shape: AppShape.of(
                      AppRadius.md + 4,
                      side: BorderSide(
                        color: Color.lerp(cs.outlineVariant, cs.primary, t)!,
                        width: 1 + 1.5 * t,
                      ),
                    ),
                  ),
                  child: ClipRSuperellipse(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Stack(
                      children: [
                        Positioned.fill(child: _MiniPage(s: s)),
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Opacity(
                            opacity: t.clamp(0, 1),
                            child: Transform.scale(
                              scale: .6 + .4 * t,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: s.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Symbols.check_rounded,
                                  size: 14,
                                  weight: 700,
                                  color: s.onPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? cs.onSurface : cs.onSurfaceVariant,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 一页缩略界面：背景、两张书卡、一条胶囊导航。
class _MiniPage extends StatelessWidget {
  const _MiniPage({required this.s});
  final ColorScheme s;

  @override
  Widget build(BuildContext context) {
    Widget bar(double w, Color c, [double h = 4]) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(h),
      ),
    );
    Widget book(Color c) => Expanded(
      child: Container(
        height: 46,
        decoration: ShapeDecoration(color: c, shape: AppShape.of(8)),
      ),
    );
    return ColoredBox(
      color: s.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            bar(42, s.onSurface, 5),
            const SizedBox(height: 5),
            bar(26, s.onSurfaceVariant.withValues(alpha: .6), 3),
            const SizedBox(height: 10),
            Row(
              children: [
                book(s.primaryContainer),
                const SizedBox(width: 6),
                book(s.tertiaryContainer),
              ],
            ),
            const Spacer(),
            Container(
              height: 16,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: ShapeDecoration(
                color: s.surfaceContainerHigh,
                shape: const StadiumBorder(),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  bar(18, s.primary, 8),
                  bar(8, s.outline, 3),
                  bar(8, s.outline, 3),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
