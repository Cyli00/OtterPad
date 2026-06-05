import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../providers/summary_image_provider.dart';
import 'outline_panel.dart';

/// 大纲面板 body，由 [ReaderSheetHost] 弹出（移动端）。
///
/// 桌面端走 Scaffold endDrawer，不经过此 widget。
class ReaderOutlineSheetBody extends StatelessWidget {
  final String markdownContent;
  final String documentId;
  final ValueNotifier<SummaryImageState> summaryImageState;
  final ValueChanged<int> onNavigate;
  final VoidCallback onRegenerateSummary;

  const ReaderOutlineSheetBody({
    super.key,
    required this.markdownContent,
    required this.documentId,
    required this.summaryImageState,
    required this.onNavigate,
    required this.onRegenerateSummary,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: ColoredBox(
          color: cs.surface,
          child: Column(
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withAlpha(80),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: OutlinePanel(
                  key: ValueKey(markdownContent.hashCode),
                  markdownContent: markdownContent,
                  documentId: documentId,
                  summaryImageState: summaryImageState,
                  inSheet: true,
                  onNavigate: onNavigate,
                  onRegenerateSummary: onRegenerateSummary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
