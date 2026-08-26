import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/animation_constants.dart';
import '../core/elevation.dart';

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
    barrierColor: Colors.black54,
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
            borderRadius: BorderRadius.circular(28),
            boxShadow: AppShadows.dialog,
          ),
          child: builder(context),
        ),
      );
    },
  );
}
