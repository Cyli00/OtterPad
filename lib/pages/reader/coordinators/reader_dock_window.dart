import 'dart:ui';

import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

/// 仅撤回侧栏自动增加的宽度，保留用户移动窗口或手动调宽的结果。
class ReaderDockWindow {
  double? _originalWidth;
  double? _expandedWidth;
  Future<void> _pending = Future.value();

  Future<bool> expand(double sidebarWidth) {
    final result = _pending.then((_) => _expand(sidebarWidth));
    _pending = result.then((_) {});
    return result;
  }

  Future<bool> _expand(double sidebarWidth) async {
    try {
      if (_expandedWidth != null) return true;
      if (await windowManager.isMaximized() ||
          await windowManager.isFullScreen()) {
        return false;
      }
      final bounds = await windowManager.getBounds();
      final displays = await screenRetriever.getAllDisplays();
      Rect? workArea;
      var largestOverlap = 0.0;
      for (final display in displays) {
        final position = display.visiblePosition;
        final size = display.visibleSize;
        if (position == null || size == null) continue;
        final area = position & size;
        final overlap = bounds.intersect(area);
        if (overlap.isEmpty) continue;
        final overlapSize = overlap.width * overlap.height;
        if (overlapSize > largestOverlap) {
          largestOverlap = overlapSize;
          workArea = area;
        }
      }
      if (workArea == null ||
          bounds.left < workArea.left ||
          bounds.right + sidebarWidth > workArea.right) {
        return false;
      }
      await windowManager.setBounds(
        Rect.fromLTWH(
          bounds.left,
          bounds.top,
          bounds.width + sidebarWidth,
          bounds.height,
        ),
      );
      _originalWidth = bounds.width;
      _expandedWidth = bounds.width + sidebarWidth;
      return true;
    } catch (_) {
      // 无法取得可靠的窗口/屏幕信息时，沿用窗口内展开。
      return false;
    }
  }

  Future<void> restore() {
    return _pending = _pending.then((_) async {
      final originalWidth = _originalWidth;
      final expandedWidth = _expandedWidth;
      _originalWidth = null;
      _expandedWidth = null;
      if (originalWidth == null || expandedWidth == null) return;
      try {
        if (await windowManager.isMaximized() ||
            await windowManager.isFullScreen()) {
          return;
        }
        final bounds = await windowManager.getBounds();
        if ((bounds.width - expandedWidth).abs() > 1) return;
        await windowManager.setBounds(
          Rect.fromLTWH(bounds.left, bounds.top, originalWidth, bounds.height),
        );
      } catch (_) {
        // 窗口已经关闭或插件不可用时无需恢复。
      }
    });
  }
}
