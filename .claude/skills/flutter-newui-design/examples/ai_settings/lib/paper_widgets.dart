import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'paper_theme.dart';

class PaperHelp extends StatefulWidget {
  const PaperHelp(this.message, {super.key});
  final String message;
  @override
  State<PaperHelp> createState() => _PaperHelpState();
}

class _PaperHelpState extends State<PaperHelp> {
  final _buttonFocus = FocusNode();
  @override
  void dispose() {
    _buttonFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MenuAnchor(
    childFocusNode: _buttonFocus,
    style: const MenuStyle(padding: WidgetStatePropertyAll(EdgeInsets.zero)),
    menuChildren: [
      SizedBox(
        width: MediaQuery.sizeOf(context).width.clamp(0, 352) - 32,
        child: Focus(
          autofocus: true,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              widget.message,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      ),
    ],
    builder: (context, controller, _) => IconButton(
      focusNode: _buttonFocus,
      tooltip: widget.message,
      constraints: BoxConstraints(
        minWidth: PaperMetrics.target(Theme.of(context).platform),
        minHeight: PaperMetrics.target(Theme.of(context).platform),
      ),
      icon: const Icon(Symbols.help, size: 18, weight: 350, fill: 0),
      onPressed: () =>
          controller.isOpen ? controller.close() : controller.open(),
    ),
  );
}

enum PaperModelRole { expert, fast, image }

class PaperRoleIcon extends StatelessWidget {
  const PaperRoleIcon(this.role, {super.key, this.color, this.size = 22});
  final PaperModelRole role;
  final Color? color;
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Icon(
      switch (role) {
        PaperModelRole.expert => Symbols.psychology,
        PaperModelRole.fast => Symbols.bolt,
        PaperModelRole.image => Symbols.draw,
      },
      size: size,
      weight: 350,
      fill: 0,
      color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class PaperLabel extends StatelessWidget {
  const PaperLabel({
    super.key,
    required this.title,
    this.help,
    this.role,
    this.style,
  });
  final String title;
  final String? help;
  final PaperModelRole? role;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (role != null) ...[PaperRoleIcon(role!), const SizedBox(width: 8)],
      Flexible(
        child: Text(
          title,
          style: style ?? Theme.of(context).textTheme.titleSmall,
        ),
      ),
      if (help != null) PaperHelp(help!),
    ],
  );
}

class PaperSection extends StatelessWidget {
  const PaperSection({
    super.key,
    required this.title,
    required this.help,
    required this.children,
    this.action,
  });
  final String title;
  final String help;
  final List<Widget> children;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final heading = Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.only(bottom: 5),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: cs.primary, width: 2),
                      ),
                    ),
                    child: Text(
                      title,
                      style: theme.textTheme.titleLarge,
                      softWrap: true,
                    ),
                  ),
                ),
                PaperHelp(help),
              ],
            );
            if (action == null) return heading;
            return Row(
              children: [
                Expanded(child: heading),
                const SizedBox(width: 16),
                action!,
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, c) => Container(
            width: double.infinity,
            padding: const EdgeInsets.all(PaperMetrics.cardPadding),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: spaced(children, PaperMetrics.fieldGap),
            ),
          ),
        ),
      ],
    );
  }
}

List<Widget> spaced(List<Widget> children, double gap) => [
  for (var i = 0; i < children.length; i++) ...[
    if (i > 0) SizedBox(height: gap),
    children[i],
  ],
];

class PaperSubsection extends StatelessWidget {
  const PaperSubsection({
    super.key,
    required this.title,
    this.help,
    this.action,
    required this.children,
  });
  final String title;
  final String? help;
  final Widget? action;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, c) {
          final label = PaperLabel(
            title: title,
            help: help,
            style: Theme.of(context).textTheme.titleMedium,
          );
          if (action == null) return label;
          return Row(
            children: [
              Expanded(child: label),
              const SizedBox(width: 16),
              action!,
            ],
          );
        },
      ),
      const SizedBox(height: 16),
      ...spaced(children, PaperMetrics.fieldGap),
    ],
  );
}

class PaperFieldRow extends StatelessWidget {
  const PaperFieldRow({
    super.key,
    required this.label,
    this.hint,
    this.role,
    required this.child,
  });
  final String label;
  final String? hint;
  final PaperModelRole? role;
  final Widget child;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final title = PaperLabel(title: label, help: hint, role: role);
      if (c.maxWidth < 520 || MediaQuery.textScalerOf(context).scale(16) > 22) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: spaced([title, child], 4),
        );
      }
      return Row(
        children: [
          SizedBox(width: 180, child: title),
          const SizedBox(width: 24),
          Expanded(child: child),
        ],
      );
    },
  );
}

class PaperSelect extends StatelessWidget {
  const PaperSelect({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.badges = const [],
  });
  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;
  final List<String> badges;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final mobile =
        theme.platform == TargetPlatform.android ||
        theme.platform == TargetPlatform.iOS;
    return LayoutBuilder(
      builder: (context, c) => MenuAnchor(
        style: MenuStyle(
          maximumSize: WidgetStatePropertyAll(Size(c.maxWidth, 380)),
          minimumSize: WidgetStatePropertyAll(Size(c.maxWidth, 0)),
        ),
        menuChildren: [
          for (final option in options.entries)
            MenuItemButton(
              onPressed: () => onChanged(option.key),
              leadingIcon: option.key == value
                  ? Icon(Symbols.check, color: cs.primary)
                  : const SizedBox(width: 21),
              child: Text(option.value, style: theme.textTheme.labelMedium),
            ),
        ],
        builder: (context, controller, _) => Semantics(
          label: label,
          child: OutlinedButton(
            style:
                OutlinedButton.styleFrom(
                  minimumSize: Size(0, PaperMetrics.target(theme.platform)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  foregroundColor: cs.onSurface,
                  backgroundColor: cs.surfaceContainerLow,
                  side: BorderSide(color: cs.outlineVariant),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ).copyWith(
                  side: WidgetStateProperty.resolveWith(
                    (states) => BorderSide(
                      color: states.contains(WidgetState.focused)
                          ? cs.primary
                          : cs.outlineVariant,
                      width: states.contains(WidgetState.focused) ? 2 : 1,
                    ),
                  ),
                ),
            onPressed: () async {
              if (!mobile) {
                controller.isOpen ? controller.close() : controller.open();
                return;
              }
              final next = await showModalBottomSheet<String>(
                context: context,
                backgroundColor: cs.surfaceContainerLow,
                showDragHandle: true,
                builder: (context) => SafeArea(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        child: Text(label, style: theme.textTheme.titleMedium),
                      ),
                      for (final option in options.entries)
                        ListTile(
                          title: Text(option.value),
                          selected: option.key == value,
                          trailing: option.key == value
                              ? const Icon(Symbols.check)
                              : null,
                          onTap: () => Navigator.pop(context, option.key),
                        ),
                    ],
                  ),
                ),
              );
              if (next != null) onChanged(next);
            },
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        options[value] ?? value,
                        style: theme.textTheme.bodyLarge,
                        softWrap: true,
                      ),
                      if (badges.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final badge in badges)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme
                                        .extension<PaperColors>()!
                                        .selected,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    badge,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Symbols.expand_more, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PaperModelCard extends StatelessWidget {
  const PaperModelCard({
    super.key,
    required this.model,
    required this.selected,
    required this.onSelected,
    this.badges = const [],
  });
  final String model;
  final bool selected;
  final ValueChanged<String>? onSelected;
  final List<String> badges;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final colors = theme.extension<PaperColors>()!;
    final enabled = onSelected != null;
    return MergeSemantics(
      child: Semantics(
        label: model,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        enabled: enabled,
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            key: ValueKey('model-card-$model'),
            onPressed: enabled ? () => onSelected!(model) : null,
            style:
                OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 82),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  alignment: Alignment.centerLeft,
                  foregroundColor: cs.onSurface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ).copyWith(
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => selected
                        ? colors.selected
                        : states.contains(WidgetState.hovered)
                        ? colors.hover
                        : cs.surfaceContainerLow,
                  ),
                  side: WidgetStateBorderSide.resolveWith(
                    (states) => BorderSide(
                      color: states.contains(WidgetState.focused) || selected
                          ? cs.primary
                          : cs.outlineVariant,
                      width: states.contains(WidgetState.focused)
                          ? 2
                          : selected
                          ? 1.5
                          : 1,
                    ),
                  ),
                ),
            child: Row(
              children: [
                _PaperSelectionDot(selected: selected),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        model,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (badges.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final badge in badges)
                              _PaperBadge(label: badge),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Symbols.vital_signs,
                  size: 30,
                  weight: 300,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PaperRoleGroup extends StatelessWidget {
  const PaperRoleGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(height: 1, color: cs.outlineVariant),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class PaperRoleCard extends StatelessWidget {
  const PaperRoleCard({
    super.key,
    required this.role,
    required this.title,
    this.help,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final PaperModelRole role;
  final String title;
  final String? help;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String>? onChanged;

  Color _surface(PaperColors colors) => switch (role) {
    PaperModelRole.expert => colors.expertSurface,
    PaperModelRole.fast => colors.fastSurface,
    PaperModelRole.image => colors.imageSurface,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final colors = theme.extension<PaperColors>()!;
    final mobile =
        theme.platform == TargetPlatform.android ||
        theme.platform == TargetPlatform.iOS;
    final selectedValue = options[value] ?? value;

    return LayoutBuilder(
      builder: (context, c) => MenuAnchor(
        style: MenuStyle(
          maximumSize: WidgetStatePropertyAll(Size(c.maxWidth, 380)),
          minimumSize: WidgetStatePropertyAll(Size(c.maxWidth, 0)),
        ),
        menuChildren: [
          for (final option in options.entries)
            MenuItemButton(
              onPressed: onChanged == null
                  ? null
                  : () => onChanged!(option.key),
              leadingIcon: option.key == value
                  ? Icon(Symbols.check, color: cs.primary)
                  : const SizedBox(width: 21),
              child: Text(option.value, style: theme.textTheme.labelMedium),
            ),
        ],
        builder: (context, controller, _) => Semantics(
          label: title,
          value: selectedValue,
          button: true,
          enabled: onChanged != null,
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: ValueKey('role-card-${role.name}'),
              onPressed: onChanged == null
                  ? null
                  : () async {
                      if (!mobile) {
                        controller.isOpen
                            ? controller.close()
                            : controller.open();
                        return;
                      }
                      final next = await showModalBottomSheet<String>(
                        context: context,
                        backgroundColor: cs.surfaceContainerLow,
                        showDragHandle: true,
                        builder: (context) => SafeArea(
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 8,
                                ),
                                child: Text(
                                  title,
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                              for (final option in options.entries)
                                ListTile(
                                  title: Text(option.value),
                                  selected: option.key == value,
                                  trailing: option.key == value
                                      ? const Icon(Symbols.check)
                                      : null,
                                  onTap: () =>
                                      Navigator.pop(context, option.key),
                                ),
                            ],
                          ),
                        ),
                      );
                      if (next != null) onChanged!(next);
                    },
              style:
                  OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 72),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    alignment: Alignment.centerLeft,
                    foregroundColor: cs.onSurface,
                    shape: const RoundedRectangleBorder(),
                  ).copyWith(
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.hovered)
                          ? colors.hover
                          : Colors.transparent,
                    ),
                    side: const WidgetStatePropertyAll(BorderSide.none),
                  ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _surface(colors),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: PaperRoleIcon(
                        role,
                        size: 22,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                style: theme.textTheme.titleMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (help != null) PaperHelp(help!),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          selectedValue,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: value.isEmpty
                                ? cs.onSurfaceVariant
                                : cs.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(Symbols.expand_more, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaperSelectionDot extends StatelessWidget {
  const _PaperSelectionDot({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : kAnimFast,
      width: 22,
      height: 22,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? cs.primary : cs.outline,
          width: selected ? 2 : 1.5,
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? cs.primary : Colors.transparent,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _PaperBadge extends StatelessWidget {
  const _PaperBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: theme.extension<PaperColors>()!.selected,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: theme.textTheme.bodySmall),
    );
  }
}

class PaperChoice extends StatelessWidget {
  const PaperChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.preview,
    this.multiple = false,
  });
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final Widget? preview;
  final bool multiple;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Semantics(
        inMutuallyExclusiveGroup: !multiple,
        child: RawChip(
          label: preview ?? Text(label),
          selected: selected,
          onSelected: onSelected,
          showCheckmark: multiple,
          materialTapTargetSize: MaterialTapTargetSize.padded,
          labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          labelStyle: theme.textTheme.labelMedium,
          color: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? theme.extension<PaperColors>()!.selected
                : states.contains(WidgetState.hovered)
                ? theme.extension<PaperColors>()!.hover
                : theme.colorScheme.surfaceContainerLow,
          ),
          side: WidgetStateBorderSide.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.focused)
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: states.contains(WidgetState.focused) ? 2 : 1,
            ),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class PaperSlider extends StatelessWidget {
  const PaperSlider({
    super.key,
    required this.title,
    required this.help,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.resetLabel,
    this.onReset,
    this.decimals = 2,
  });
  final String title, help, resetLabel;
  final double value, min, max;
  final int divisions, decimals;
  final ValueChanged<double> onChanged;
  final VoidCallback? onReset;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(title, style: theme.textTheme.titleSmall),
                  ),
                  PaperHelp(help),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                value.toStringAsFixed(decimals),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                label: title,
                semanticFormatterCallback: (v) =>
                    '$title ${v.toStringAsFixed(decimals)}',
                onChanged: onChanged,
              ),
            ),
            IconButton(
              tooltip: resetLabel,
              onPressed: onReset,
              icon: const Icon(Symbols.restart_alt),
            ),
          ],
        ),
      ],
    );
  }
}
