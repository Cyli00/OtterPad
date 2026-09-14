import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/animation_constants.dart';
import '../../../core/l10n.dart';
import '../../../data/models/chat/chat_activity.dart';
import '../../../widgets/tactile_press.dart';

String _toolDetail(String value) {
  String describe(Object? data) {
    if (data is List) {
      return data.map(describe).where((s) => s.isNotEmpty).join('\n\n');
    }
    if (data is Map) {
      return [
        for (final key in [
          'query',
          'queries',
          'title',
          'url',
          'text',
          'content',
          'error_code',
        ])
          if (data[key] != null) describe(data[key]),
      ].join('\n');
    }
    return data is String ? data : '';
  }

  return value
      .split('\n\n')
      .map((part) {
        try {
          final text = describe(jsonDecode(part));
          return text.isEmpty ? part : text;
        } catch (_) {
          return part;
        }
      })
      .join('\n\n');
}

class ChatActivityView extends StatefulWidget {
  final List<ChatActivity> activities;
  final VoidCallback? onToggle;
  const ChatActivityView({super.key, required this.activities, this.onToggle});

  @override
  State<ChatActivityView> createState() => _ChatActivityViewState();
}

class _ChatActivityViewState extends State<ChatActivityView> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.activities.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final l10n = context.l10n;
    final running = widget.activities.any(
      (s) => s.status == ChatActivityStatus.running,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TactilePress(
            baseColor: Colors.transparent,
            onTap: () {
              widget.onToggle?.call();
              setState(() => _expanded = !_expanded);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  if (running)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      Symbols.account_tree_rounded,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      running ? l10n.chatProcessRunning : l10n.chatProcess,
                      style: text.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text('${widget.activities.length}', style: text.labelMedium),
                  const SizedBox(width: 6),
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
          AnimatedSize(
            alignment: Alignment.topCenter,
            duration: kAnim,
            curve: kAnimCurve,
            child: !_expanded
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final step in widget.activities)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  step.kind == ChatActivityKind.reasoning
                                      ? Symbols.neurology_rounded
                                      : Symbols.travel_explore_rounded,
                                  size: 16,
                                  color: cs.primary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 8,
                                        children: [
                                          Text(
                                            step.kind ==
                                                    ChatActivityKind.reasoning
                                                ? l10n.chatReasoning
                                                : step.name.contains('fetch') ||
                                                      step.name.contains(
                                                        'url_context',
                                                      )
                                                ? l10n.chatReadLink
                                                : l10n.searchToolLabel,
                                            style: text.labelMedium?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            switch (step.status) {
                                              ChatActivityStatus.running =>
                                                l10n.chatStepRunning,
                                              ChatActivityStatus.completed =>
                                                l10n.chatStepCompleted,
                                              ChatActivityStatus.failed =>
                                                l10n.chatStepFailed,
                                              ChatActivityStatus.cancelled =>
                                                l10n.chatStepCancelled,
                                            },
                                            style: text.bodySmall?.copyWith(
                                              color:
                                                  step.status ==
                                                      ChatActivityStatus.failed
                                                  ? cs.error
                                                  : cs.onSurfaceVariant,
                                            ),
                                          ),
                                          if (step.endedAt != null)
                                            Text(
                                              l10n.chatStepDuration(
                                                step.endedAt!
                                                    .difference(step.startedAt)
                                                    .inSeconds,
                                              ),
                                              style: text.bodySmall,
                                            ),
                                        ],
                                      ),
                                      if (step.text.isNotEmpty)
                                        Container(
                                          constraints: const BoxConstraints(
                                            maxHeight: 240,
                                          ),
                                          margin: const EdgeInsets.only(top: 6),
                                          padding: const EdgeInsets.only(
                                            left: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              left: BorderSide(
                                                color: cs.outlineVariant
                                                    .withAlpha(80),
                                              ),
                                            ),
                                          ),
                                          child: SingleChildScrollView(
                                            primary: false,
                                            child: SelectableText(
                                              step.kind == ChatActivityKind.tool
                                                  ? _toolDetail(step.text)
                                                  : step.text,
                                              style: text.bodySmall?.copyWith(
                                                color: cs.onSurfaceVariant,
                                                height: 1.4,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
