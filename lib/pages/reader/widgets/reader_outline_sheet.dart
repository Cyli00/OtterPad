import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../data/models/book/document.dart';
import '../chat/document_chat_page.dart';
import '../../../providers/summary_image_provider.dart';
import 'outline_panel.dart';

/// 大纲面板 body，由 [ReaderSheetHost] 弹出（窄屏 / 无 dock）。
///
/// 宽屏走停靠栏内的 [OutlinePanel]，不经过此 widget。
class ReaderOutlineSheetBody extends StatelessWidget {
  final String markdownContent;
  final String documentId;
  final Document document;
  final LocateQuoteInReader? onLocateQuote;
  final ValueNotifier<SummaryImageState> summaryImageState;
  final ValueListenable<int>? figuresEpoch;
  final ValueChanged<int> onNavigate;
  final VoidCallback onUploadSummaryImage;

  const ReaderOutlineSheetBody({
    super.key,
    required this.markdownContent,
    required this.documentId,
    required this.document,
    this.onLocateQuote,
    required this.summaryImageState,
    this.figuresEpoch,
    required this.onNavigate,
    required this.onUploadSummaryImage,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
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
              document: document,
              onLocateQuote: onLocateQuote,
              summaryImageState: summaryImageState,
              figuresEpoch: figuresEpoch,
              onNavigate: onNavigate,
              onUploadSummaryImage: onUploadSummaryImage,
            ),
          ),
        ],
      ),
    );
  }
}
