import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 将正文排版宽度与原生 WebView 绘制画布分开。
class ReaderWebViewViewport extends StatefulWidget {
  const ReaderWebViewViewport({
    super.key,
    required this.onLayoutWidthChanged,
    required this.child,
    this.preserveSurfaceWidth = true,
  });

  final ValueChanged<double> onLayoutWidthChanged;
  final Widget child;
  final bool preserveSurfaceWidth;

  @override
  State<ReaderWebViewViewport> createState() => _ReaderWebViewViewportState();
}

class _ReaderWebViewViewportState extends State<ReaderWebViewViewport> {
  double? _layoutWidth;
  double? _surfaceWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (_layoutWidth != constraints.maxWidth) {
        _layoutWidth = constraints.maxWidth;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onLayoutWidthChanged(_layoutWidth!);
        });
      }
      // 桌面纹理在原生 setSize 完成前会沿用旧帧。画布只在实际需要更大
      // 空间时增长，侧栏开合只裁切并通知 HTML 重排，不缩放旧纹理。
      _surfaceWidth = widget.preserveSurfaceWidth
          ? math.max(
              _surfaceWidth ?? MediaQuery.sizeOf(context).width,
              constraints.maxWidth,
            )
          : constraints.maxWidth;
      return ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: _surfaceWidth,
          maxWidth: _surfaceWidth,
          child: SizedBox(width: _surfaceWidth, child: widget.child),
        ),
      );
    },
  );
}
