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
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      icon: const Icon(Symbols.help, size: 19, weight: 350, fill: 0),
      onPressed: () =>
          controller.isOpen ? controller.close() : controller.open(),
    ),
  );
}

enum PaperModelRole { expert, fast, image }

class PaperRoleIcon extends StatelessWidget {
  const PaperRoleIcon(this.role, {super.key});
  final PaperModelRole role;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Icon(
      switch (role) {
        PaperModelRole.expert => Symbols.psychology,
        PaperModelRole.fast => Symbols.bolt,
        PaperModelRole.image => Symbols.draw,
      },
      size: 22,
      weight: 350,
      fill: 0,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
  });
  final String title;
  final String help;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.only(bottom: 5),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: cs.primary, width: 2),
                  ),
                ),
                child: Text(title, style: theme.textTheme.titleLarge),
              ),
            ),
            PaperHelp(help),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, c) => Container(
            width: double.infinity,
            padding: EdgeInsets.all(c.maxWidth < 520 ? 16 : 24),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: spaced(children, 22),
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
      const SizedBox(height: 20),
      LayoutBuilder(
        builder: (context, c) {
          final label = PaperLabel(
            title: title,
            help: help,
            style: Theme.of(context).textTheme.titleMedium,
          );
          if (action == null) return label;
          if (c.maxWidth < 520 ||
              MediaQuery.textScalerOf(context).scale(16) > 22) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [label, const SizedBox(height: 8), action!],
            );
          }
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
      ...spaced(children, 16),
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
          children: spaced([title, child], 10),
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
                  minimumSize: const Size(0, 54),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
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
          labelPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
