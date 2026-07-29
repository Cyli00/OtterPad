import 'package:flutter/widgets.dart';

/// 响应式布局断点
class Breakpoints {
  Breakpoints._();

  /// 手机最大宽度
  static const double mobile = 600;

  /// 平板最大宽度
  static const double tablet = 1200;
}

enum DeviceType { mobile, tablet, desktop }

/// 响应式布局工具类
class Responsive {
  Responsive._();

  static DeviceType getDeviceType(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < Breakpoints.mobile) {
      return DeviceType.mobile;
    } else if (width < Breakpoints.tablet) {
      return DeviceType.tablet;
    } else {
      return DeviceType.desktop;
    }
  }

  static bool isMobile(BuildContext context) {
    return getDeviceType(context) == DeviceType.mobile;
  }

  /// 是否显示侧边导航（平板及以上）
  static bool showNavigationRail(BuildContext context) {
    return !isMobile(context);
  }
}
