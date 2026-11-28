import 'package:flutter/material.dart';

import '../core/design_tokens.dart';
import 'rolling_number.dart';

/// 页面刊头：Folio 每页唯一的视觉重心。
///
/// 眉题（小号加宽字距）在上，衬线大标题在下；可选的计数跟在标题后面，
/// 用数字滚动，随文献增减逐位翻动。
class Masthead extends StatelessWidget {
  const Masthead({
    super.key,
    required this.title,
    this.eyebrow,
    this.count,
    this.countLabel,
    this.trailing,
    this.eyebrowTrailing,
  });

  final String title;
  final String? eyebrow;

  /// 计数；与 [countLabel] 一起渲染成「8 篇文献」。
  final int? count;

  /// 本地化的计数文案，参数是数字本身，如 `l10n.favoriteDocumentCount`。
  final String Function(int count)? countLabel;

  /// 与标题同行、靠右的内容（搜索框、工具按钮）。
  final Widget? trailing;

  /// 与眉题同行、靠右的内容（窄屏时的工具按钮）。
  final Widget? eyebrowTrailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final titleStyle = AppType.masthead(context);

    Widget titleRow = Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: AppSpace.x3,
      runSpacing: AppSpace.x1,
      children: [
        Text(title, style: titleStyle),
        if (count != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _CountLabel(
              count: count!,
              label: countLabel,
              style: theme.textTheme.titleMedium!.copyWith(
                fontFamily: titleStyle.fontFamily,
                fontFamilyFallback: titleStyle.fontFamilyFallback,
                fontWeight: FontWeight.w400,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );

    if (trailing != null) {
      titleRow = Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: titleRow),
          const SizedBox(width: AppSpace.x4),
          trailing!,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (eyebrow != null || eyebrowTrailing != null)
          SizedBox(
            height: eyebrowTrailing == null ? null : 36,
            child: Row(
              children: [
                if (eyebrow != null)
                  Expanded(
                    child: Text(
                      eyebrowText(eyebrow!),
                      style: AppType.eyebrow(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  const Spacer(),
                ?eyebrowTrailing,
              ],
            ),
          ),
        if (eyebrow != null) const SizedBox(height: AppSpace.x2),
        titleRow,
      ],
    );
  }
}

/// 把「{count} 篇文献」拆成前后缀，只让数字滚动。
class _CountLabel extends StatelessWidget {
  const _CountLabel({required this.count, required this.label, this.style});

  final int count;
  final String Function(int)? label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final full = label?.call(count) ?? '$count';
    final at = full.indexOf('$count');
    if (at < 0) return Text(full, style: style);
    final prefix = full.substring(0, at);
    final suffix = full.substring(at + '$count'.length);
    return Semantics(
      label: full,
      excludeSemantics: true,
      child: DefaultTextStyle.merge(
        style: style,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (prefix.isNotEmpty) Text(prefix, style: style),
            RollingNumber(count, style: style, suffix: suffix),
          ],
        ),
      ),
    );
  }
}
