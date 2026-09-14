import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/animation_constants.dart';
import '../../../core/l10n.dart';
import '../../../widgets/tactile_press.dart';

class ChatUserQuote extends StatefulWidget {
  final String text;
  final VoidCallback? onLocate;
  final VoidCallback onToggle;
  const ChatUserQuote({
    super.key,
    required this.text,
    required this.onToggle,
    this.onLocate,
  });

  @override
  State<ChatUserQuote> createState() => _ChatUserQuoteState();
}

class _ChatUserQuoteState extends State<ChatUserQuote> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final label = _expanded
        ? context.l10n.chatCollapseQuote
        : context.l10n.chatExpandQuote;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Semantics(
              button: true,
              expanded: _expanded,
              label: label,
              child: Tooltip(
                message: label,
                child: TactilePress(
                  baseColor: Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    widget.onToggle();
                    setState(() => _expanded = !_expanded);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Symbols.format_quote_rounded,
                          size: 18,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: AnimatedSize(
                            duration: kAnim,
                            curve: kAnimCurve,
                            alignment: Alignment.topCenter,
                            child: Text(
                              widget.text,
                              maxLines: _expanded ? null : 2,
                              overflow: _expanded
                                  ? null
                                  : TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: _expanded ? .5 : 0,
                          duration: kAnimFast,
                          curve: kAnimCurve,
                          child: Icon(
                            Symbols.expand_more_rounded,
                            size: 18,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.onLocate != null)
            IconButton(
              tooltip: context.l10n.chatLocateSource,
              onPressed: widget.onLocate,
              icon: const Icon(Symbols.my_location_rounded, size: 18),
            ),
        ],
      ),
    );
  }
}
