import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/animation_constants.dart';
import '../core/elevation.dart';
import '../core/design_tokens.dart';

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  String? barrierLabel,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel:
        barrierLabel ??
        MaterialLocalizations.of(context).modalBarrierDismissLabel,
    // Folio：浅一些的墨色遮罩 + 轻模糊，纸面仍隐约可见
    barrierColor: Colors.black.withAlpha(82),
    transitionDuration: kAnimSlow,
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      // scale 用 easeOutBack 轻回弹，fade 保持标准缓出
      final scaleCurved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: kAnimCurveReverse,
      );
      final fadeCurved = CurvedAnimation(
        parent: animation,
        curve: kAnimCurve,
        reverseCurve: kAnimCurveReverse,
      );
      // 减少动态效果：只保留淡入淡出。
      if (MediaQuery.disableAnimationsOf(context)) {
        return FadeTransition(opacity: fadeCurved, child: child);
      }
      return BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 4.0 * fadeCurved.value,
          sigmaY: 4.0 * fadeCurved.value,
        ),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(scaleCurved),
          child: FadeTransition(opacity: fadeCurved, child: child),
        ),
      );
    },
    pageBuilder: (context, animation, secondaryAnimation) {
      return Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: AppRadius.lgAll,
            boxShadow: AppShadows.dialog,
          ),
          child: builder(context),
        ),
      );
    },
  );
}
