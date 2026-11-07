import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/l10n.dart';
import '../../../services/haptics.dart';

/// 图表查看器中的一项：位图路径与题注（含已有的题注译文）。
class FigureView {
  const FigureView({
    required this.path,
    required this.caption,
    this.translation,
  });

  final String path;
  final String caption;
  final String? translation;
}

/// 全屏查看图表：左右翻页、双指或滚轮缩放，可就当前图问 AI。
Future<void> showFigureViewer(
  BuildContext context,
  List<FigureView> figures, {
  int initialIndex = 0,
  void Function(FigureView figure)? onAskAi,
}) {
  if (figures.isEmpty) return Future.value();
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, _, _) => _FigureViewer(
        figures: figures,
        initialIndex: initialIndex.clamp(0, figures.length - 1),
        onAskAi: onAskAi,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _FigureViewer extends StatefulWidget {
  const _FigureViewer({
    required this.figures,
    required this.initialIndex,
    this.onAskAi,
  });

  final List<FigureView> figures;
  final int initialIndex;
  final void Function(FigureView figure)? onAskAi;

  @override
  State<_FigureViewer> createState() => _FigureViewerState();
}

class _FigureViewerState extends State<_FigureViewer> {
  late final _pages = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final figure = widget.figures[_index];
    final theme = Theme.of(context);
    final text = theme.textTheme.bodyMedium?.copyWith(color: Colors.white);
    final onAskAi = widget.onAskAi;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: widget.figures.length > 1
            ? Text('${_index + 1} / ${widget.figures.length}')
            : null,
        actions: [
          if (onAskAi != null)
            IconButton(
              tooltip: context.l10n.askAi,
              icon: const Icon(Symbols.auto_awesome_rounded),
              onPressed: () {
                Haptics.soft();
                Navigator.pop(context);
                onAskAi(figure);
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: widget.figures.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => InteractiveViewer(
                maxScale: 6,
                child: Center(
                  child: Image.file(
                    File(widget.figures[i].path),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        Text(context.l10n.imageNotFound, style: text),
                  ),
                ),
              ),
            ),
          ),
          if (figure.caption.isNotEmpty || figure.translation != null)
            SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (figure.caption.isNotEmpty)
                        Text(figure.caption, style: text),
                      if (figure.translation case final t?) ...[
                        const SizedBox(height: 8),
                        Text(t, style: text?.copyWith(color: Colors.white70)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
