import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'l10n.dart';
import 'paper_theme.dart';
import 'paper_widgets.dart';

bool paperMobile(BuildContext context) => switch (Theme.of(context).platform) {
  TargetPlatform.android || TargetPlatform.iOS => true,
  _ => false,
};

Future<T?> showPaperDialog<T>(BuildContext context, WidgetBuilder builder) =>
    showDialog<T>(
      context: context,
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: .42),
      animationStyle: AnimationStyle(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : kAnim,
        reverseDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : kAnimFast,
        curve: kAnimCurve,
      ),
      builder: builder,
    );

class PaperDialog extends StatelessWidget {
  const PaperDialog({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
  });
  final String title;
  final List<Widget> children, actions;
  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    surfaceTintColor: Colors.transparent,
    elevation: 6,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    titlePadding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
    contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
    actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
    actionsOverflowButtonSpacing: 8,
    title: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        IconButton(
          tooltip: context.l10n.close,
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Symbols.close),
        ),
      ],
    ),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: spaced(children, 16),
      ),
    ),
    actions: actions,
  );
}

class PaperActionRow extends StatelessWidget {
  const PaperActionRow({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.help,
    this.status,
    this.action,
  });
  final String title;
  final String? help, status, action;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Icon(
        icon,
        size: 24,
        weight: 350,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PaperLabel(title: title, help: help),
            if (status != null)
              Text(status!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
      const SizedBox(width: 8),
      if (action != null && MediaQuery.textScalerOf(context).scale(16) < 23)
        OutlinedButton(onPressed: onTap, child: Text(action!))
      else
        IconButton(
          tooltip: title,
          onPressed: onTap,
          icon: const Icon(Symbols.arrow_forward),
        ),
    ],
  );
}

class PaperNotice extends StatelessWidget {
  const PaperNotice({
    super.key,
    required this.title,
    required this.message,
    this.error = false,
    this.action,
  });
  final String title, message;
  final bool error;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: error ? cs.error : cs.outlineVariant),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              error ? Symbols.error : Symbols.info,
              color: error ? cs.error : cs.onSurfaceVariant,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(message, style: Theme.of(context).textTheme.bodyMedium),
                  if (action != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: action!,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

ScaffoldFeatureController<SnackBar, SnackBarClosedReason> paperSnack(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  bool error = false,
}) {
  final cs = Theme.of(context).colorScheme;
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  return messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      width: MediaQuery.sizeOf(context).width >= 600 ? 420 : null,
      margin: MediaQuery.sizeOf(context).width < 600
          ? const EdgeInsets.all(16)
          : null,
      backgroundColor: cs.inverseSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      showCloseIcon: true,
      closeIconColor: cs.onInverseSurface,
      content: Row(
        children: [
          Icon(
            error ? Symbols.error : Symbols.check_circle,
            color: cs.onInverseSurface,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: cs.onInverseSurface),
            ),
          ),
        ],
      ),
      action: actionLabel == null
          ? null
          : SnackBarAction(
              label: actionLabel,
              textColor: cs.onInverseSurface,
              onPressed: onAction ?? () {},
            ),
    ),
  );
}

class PaperOptions extends StatelessWidget {
  const PaperOptions({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.help,
    this.icons = const {},
    this.availableWidth,
  });
  final String label, value;
  final double? availableWidth;
  final String? help;
  final Map<String, String> options;
  final Map<String, IconData> icons;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      PaperLabel(title: label, help: help),
      const SizedBox(height: 4),
      if (availableWidth != null)
        _segments(context, BoxConstraints(maxWidth: availableWidth!))
      else
        LayoutBuilder(builder: _segments),
    ],
  );

  Widget _segments(BuildContext context, BoxConstraints constraints) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final colors = theme.extension<PaperColors>()!;
    final style = theme.textTheme.labelLarge!;
    // 预留勾选位，切换时文字不横跳；按真实字宽决定是否纵向排列。
    var itemWidth = 48.0;
    for (final text in options.values) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.width + 76;
      if (width > itemWidth) itemWidth = width;
      painter.dispose();
    }
    final vertical = itemWidth * options.length > constraints.maxWidth;
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<String>(
        // Flutter 渲染对象不更新 expandedInsets 状态，换轴时重新创建。
        key: ValueKey(vertical),
        direction: vertical ? Axis.vertical : Axis.horizontal,
        expandedInsets: vertical ? null : EdgeInsets.zero,
        showSelectedIcon: false,
        segments: [
          for (final e in options.entries)
            ButtonSegment(
              value: e.key,
              label: Semantics(
                checked: e.key == value,
                // SegmentedButton 不向内部按钮传递 minimumSize，以内容约束保证命中高度。
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: PaperMetrics.target(theme.platform) - 16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ExcludeSemantics(
                        child: SizedBox(
                          width: 20,
                          child: e.key == value
                              ? const Icon(Symbols.check, size: 20, weight: 400)
                              : icons[e.key] == null
                              ? null
                              : Icon(icons[e.key], size: 20, weight: 350),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(e.value, textAlign: TextAlign.center),
                      ),
                      const SizedBox(width: 26),
                    ],
                  ),
                ),
              ),
            ),
        ],
        selected: {value},
        onSelectionChanged: onChanged == null
            ? null
            : (values) => onChanged!(values.single),
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(style),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          animationDuration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : kAnimFast,
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colors.selected
                : cs.surfaceContainerLow,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? cs.onSurface.withValues(alpha: .38)
                : cs.onSurface,
          ),
          overlayColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.focused)
                ? cs.primary.withValues(alpha: .16)
                : states.contains(WidgetState.pressed)
                ? cs.primary.withValues(alpha: .12)
                : states.contains(WidgetState.hovered)
                ? cs.primary.withValues(alpha: .06)
                : Colors.transparent,
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.focused)
                  ? cs.primary
                  : cs.outlineVariant,
              width: states.contains(WidgetState.focused) ? 2 : 1,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
    );
  }
}
