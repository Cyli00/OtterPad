import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n.dart';
import '../providers/task_provider.dart';
import '../services/share_receiver_service.dart';
import '../services/snackbar_service.dart';

/// 桌面 OS 全窗口拖入宿主。合法 PDF 走 [taskProvider.addFiles]。
///
/// 拖入期间用 opaque overlay 盖住平台视图，避免 WebView 吞掉 OS 拖放。
class DesktopDropHost extends ConsumerStatefulWidget {
  const DesktopDropHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DesktopDropHost> createState() => _DesktopDropHostState();
}

class _DesktopDropHostState extends ConsumerState<DesktopDropHost> {
  bool _dragging = false;

  Future<void> _onDragDone(DropDoneDetails details) async {
    setState(() => _dragging = false);
    final l10n = context.l10n;
    final snackBar = ref.read(snackBarServiceProvider);
    final tasks = ref.read(taskProvider.notifier);

    final started = <Uint8List>[];
    try {
      final pdfs = <String>[];
      var rejected = false;
      for (final file in details.files) {
        final path = file.path;
        if (!path.toLowerCase().endsWith('.pdf')) {
          rejected = true;
          continue;
        }

        // macOS 沙盒：容器外文件必须先 start，hasPdfHeader / copy 才不会 EPERM。
        final bookmark = file.extraAppleBookmark;
        if (bookmark != null && bookmark.isNotEmpty) {
          final granted = await DesktopDrop.instance
              .startAccessingSecurityScopedResource(bookmark: bookmark);
          if (!granted) {
            rejected = true;
            continue;
          }
          started.add(bookmark);
        }

        if (await ShareReceiverService.hasPdfHeader(path)) {
          pdfs.add(path);
        } else {
          rejected = true;
        }
      }

      if (pdfs.isNotEmpty) {
        await tasks.addFiles(pdfs);
      }
      if (pdfs.isEmpty && rejected) {
        snackBar.showResult(message: l10n.dropPdfOnly);
      }
    } finally {
      for (final bookmark in started) {
        await DesktopDrop.instance.stopAccessingSecurityScopedResource(
          bookmark: bookmark,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: _onDragDone,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_dragging)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                child: ColoredBox(
                  color: cs.primary.withAlpha(24),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: CustomPaint(
                      painter: _DashedRRectPainter(color: cs.primary),
                      child: Center(
                        child: Text(
                          context.l10n.dropPdfToImport,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(28),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()..addRRect(rrect);
    const dash = 10.0;
    const gap = 6.0;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final end = dist + dash;
        canvas.drawPath(
          metric.extractPath(dist, end.clamp(0.0, metric.length)),
          paint,
        );
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color;
}
