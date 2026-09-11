import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:screen_retriever/screen_retriever.dart';

/// 主显示器尺寸信息（仅桌面端可查）。
///
/// 单位统一为逻辑像素：
/// - [logicalSize]：**系统选择的分辨率**——系统缩放后的逻辑分辨率，Flutter 的
///   窗口坐标与布局均以它为基准；
/// - [workArea]：逻辑像素下扣除任务栏 / Dock 后的可用区（取不到时回落整屏）；
/// - [scaleFactor]：系统缩放（Windows 200% 记 2.0）。
///
/// [physicalSize] 由逻辑分辨率 × 缩放还原，即**面板物理分辨率**（4K 屏 @200%
/// 还原出 3840×2160）。窗口尺寸推导只用逻辑分辨率：布局可读性取决于逻辑像素，
/// 与面板密度无关。
class DisplayMetrics {
  const DisplayMetrics({
    required this.logicalSize,
    required this.workArea,
    required this.scaleFactor,
  });

  final Size logicalSize;
  final Size workArea;
  final double scaleFactor;

  Size get physicalSize =>
      Size(logicalSize.width * scaleFactor, logicalSize.height * scaleFactor);
}

/// 查询主显示器；插件不可用或返回非法尺寸时返回 null，由调用方回退常量。
Future<DisplayMetrics?> queryPrimaryDisplay() async {
  try {
    final display = await screenRetriever.getPrimaryDisplay();
    final logical = display.size;
    if (logical.width <= 0 || logical.height <= 0) return null;
    final visible = display.visibleSize;
    return DisplayMetrics(
      logicalSize: logical,
      workArea: (visible != null && visible.width > 0 && visible.height > 0)
          ? visible
          : logical,
      scaleFactor: (display.scaleFactor ?? 1).toDouble(),
    );
  } catch (_) {
    // 插件缺失 / 无显示器：交给调用方用回退常量
    return null;
  }
}

/// 窗口最小尺寸下限：低于此值设置页主从分栏（600）与阅读器 dock（640）全部退化。
const double _kMinWindowWidth = 640;
const double _kMinWindowHeight = 480;

/// 最小尺寸上限：超大屏上按比例放大会把窗口锁死（3440 宽屏半屏 = 1720）。
const double _kMinWindowWidthCap = 960;
const double _kMinWindowHeightCap = 640;

/// 首次启动的窗口尺寸（放不下时按可用工作区收缩）。
const Size _kPreferredWindowSize = Size(1280, 800);

/// 取不到显示器信息时的保守回退（原硬编码值）。
const Size _kFallbackWindowMinimumSize = Size(720, 480);

/// 由显示器信息推导窗口最小尺寸。
///
/// 取可用工作区的一半起步，落在上下限之间；工作区比下限还窄时取工作区本身，
/// 避免出现「最小尺寸大于屏幕」导致窗口无法完整显示。
Size resolveWindowMinimumSize(DisplayMetrics? metrics) {
  if (metrics == null) return _kFallbackWindowMinimumSize;
  final work = metrics.workArea;
  final double w = (work.width * 0.5).clamp(
    _kMinWindowWidth,
    _kMinWindowWidthCap,
  );
  final double h = (work.height * 0.5).clamp(
    _kMinWindowHeight,
    _kMinWindowHeightCap,
  );
  return Size(math.min(w, work.width), math.min(h, work.height));
}

/// 首次启动窗口尺寸：[_kPreferredWindowSize] 与工作区取小，且不低于 [minimum]。
Size resolveInitialWindowSize(DisplayMetrics? metrics, Size minimum) {
  if (metrics == null) return _kPreferredWindowSize;
  final work = metrics.workArea;
  return Size(
    math.max(math.min(_kPreferredWindowSize.width, work.width), minimum.width),
    math.max(
      math.min(_kPreferredWindowSize.height, work.height),
      minimum.height,
    ),
  );
}
