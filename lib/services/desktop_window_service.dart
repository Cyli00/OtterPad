import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../utils/desktop.dart';
import '../core/animation_constants.dart';
import 'display_metrics.dart';

/// 窗口向外拓宽结果
class WindowExpandResult {
  final bool success;
  final Rect? preExpandBounds;
  final double expandedWidth;

  const WindowExpandResult({
    required this.success,
    this.preExpandBounds,
    this.expandedWidth = 0.0,
  });

  static const failure = WindowExpandResult(success: false);
}

/// 桌面窗口尺寸与停靠几何服务。
///
/// 负责右侧面板展开时向外拓宽窗口（而非向内挤占正文阅读空间），
/// 并在收起时按原样复原。
class DesktopWindowService {
  DesktopWindowService._();

  /// 根据当前窗口矩形、欲增加宽度与显示器工作区，计算向外拓宽后的窗口矩形。
  ///
  /// - 默认向右拓宽，左缘保持不动；
  /// - 若右缘超出工作区，则窗口向左平移，保证窗口完整落在屏幕工作区内；
  /// - 若工作区总宽度小于目标宽度，则宽度限制为工作区宽度，左缘贴紧工作区左侧；
  /// - 若窗口已占满工作区宽度，返回当前 bounds，表示无法向外拓宽。
  static Rect computeRightExpansionBounds({
    required Rect currentBounds,
    required double deltaWidth,
    required Rect workArea,
  }) {
    if (deltaWidth <= 0) return currentBounds;
    final targetWidth = currentBounds.width + deltaWidth;
    double newLeft = currentBounds.left;
    double finalWidth = targetWidth;

    if (finalWidth > workArea.width) {
      finalWidth = workArea.width;
      newLeft = workArea.left;
    } else if (newLeft + finalWidth > workArea.right) {
      newLeft = math.max(workArea.left, workArea.right - finalWidth);
    }

    if (finalWidth <= currentBounds.width) {
      return currentBounds;
    }

    return Rect.fromLTWH(
      newLeft,
      currentBounds.top,
      finalWidth,
      currentBounds.height,
    );
  }

  /// 根据当前窗口矩形、欲减少宽度、最小宽度限制与展开前矩形，计算收起后的窗口矩形。
  ///
  /// - 若提供 [preExpandBounds] 且用户在展开期间未大幅挪动/手动缩放窗口，
  ///   优先精确还原展开前的位置与宽度（抵消展开时的向左避让平移）；
  /// - 否则保留当前左缘，宽度扣减 [deltaWidth] 并 clamp 至 [minWidth]。
  static Rect computeRightContractionBounds({
    required Rect currentBounds,
    required double deltaWidth,
    required double minWidth,
    Rect? preExpandBounds,
  }) {
    if (preExpandBounds != null) {
      final widthDiff = currentBounds.width - preExpandBounds.width;
      final isNearExpectedWidth = (widthDiff - deltaWidth).abs() <= 8.0;
      final isNearExpectedTop =
          (currentBounds.top - preExpandBounds.top).abs() <= 16.0;
      if (isNearExpectedWidth && isNearExpectedTop) {
        return Rect.fromLTWH(
          preExpandBounds.left,
          currentBounds.top,
          preExpandBounds.width,
          currentBounds.height,
        );
      }
    }

    final targetWidth = math.max(minWidth, currentBounds.width - deltaWidth);
    return Rect.fromLTWH(
      currentBounds.left,
      currentBounds.top,
      targetWidth,
      currentBounds.height,
    );
  }

  /// 在桌面端向右拓宽窗口。
  static Future<WindowExpandResult> expandWindowRight(
    double deltaWidth, {
    bool animate = true,
  }) async {
    if (!isDesktopOs || deltaWidth <= 0) {
      return WindowExpandResult.failure;
    }
    try {
      if (await windowManager.isMaximized() ||
          await windowManager.isFullScreen()) {
        return WindowExpandResult.failure;
      }

      final bounds = await windowManager.getBounds();
      final displays = await screenRetriever.getAllDisplays();
      final primary = await screenRetriever.getPrimaryDisplay();

      final center = bounds.center;
      Display currentDisplay = primary;
      for (final d in displays) {
        final pos = d.visiblePosition ?? Offset.zero;
        final size = d.visibleSize ?? d.size;
        final rect = Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);
        if (rect.contains(center)) {
          currentDisplay = d;
          break;
        }
      }

      final workLeft = currentDisplay.visiblePosition?.dx ?? 0.0;
      final workTop = currentDisplay.visiblePosition?.dy ?? 0.0;
      final workWidth =
          currentDisplay.visibleSize?.width ?? currentDisplay.size.width;
      final workHeight =
          currentDisplay.visibleSize?.height ?? currentDisplay.size.height;
      final workArea = Rect.fromLTWH(workLeft, workTop, workWidth, workHeight);

      final newBounds = computeRightExpansionBounds(
        currentBounds: bounds,
        deltaWidth: deltaWidth,
        workArea: workArea,
      );

      if (newBounds.width <= bounds.width + 1.0) {
        return WindowExpandResult.failure;
      }

      await _setBounds(bounds, newBounds, animate: animate);

      return WindowExpandResult(
        success: true,
        preExpandBounds: bounds,
        expandedWidth: newBounds.width - bounds.width,
      );
    } catch (_) {
      return WindowExpandResult.failure;
    }
  }

  /// 在桌面端收回向右拓宽的窗口。
  static Future<bool> contractWindowRight(
    double deltaWidth, {
    Rect? preExpandBounds,
    bool animate = true,
  }) async {
    if (!isDesktopOs || deltaWidth <= 0) return false;
    try {
      if (await windowManager.isMaximized() ||
          await windowManager.isFullScreen()) {
        return false;
      }

      final bounds = await windowManager.getBounds();
      final display = await queryPrimaryDisplay();
      final minSize = resolveWindowMinimumSize(display);

      final newBounds = computeRightContractionBounds(
        currentBounds: bounds,
        deltaWidth: deltaWidth,
        minWidth: minSize.width,
        preExpandBounds: preExpandBounds,
      );

      if (newBounds.width >= bounds.width - 1.0) {
        return false;
      }

      await _setBounds(bounds, newBounds, animate: animate);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _setBounds(
    Rect from,
    Rect to, {
    required bool animate,
  }) async {
    if (!animate) {
      await windowManager.setBounds(to);
      return;
    }
    final watch = Stopwatch()..start();
    while (true) {
      final t = (watch.elapsedMicroseconds / kAnim.inMicroseconds).clamp(
        0.0,
        1.0,
      );
      await windowManager.setBounds(
        Rect.lerp(from, to, kAnimCurve.transform(t))!,
      );
      if (t >= 1) break;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }
}
