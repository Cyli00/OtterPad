import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class MeasuredBox {
  const MeasuredBox(this.size, this.baseline);

  final Size size;

  /// 字母基线到顶部的距离；没有基线的 widget 取高度。
  final double baseline;
}

/// 在独立的 BuildOwner/PipelineOwner 中离屏布局 widget。
///
/// 分页前必须知道公式、表格的确切尺寸，而 [TextPainter] 只接受占位尺寸，
/// 所以这里复用同一棵离屏树逐个测量；结果与 RichText 里的 WidgetSpan 一致，
/// 前提是 widget 不依赖祖先提供的 MediaQuery/Theme。
class WidgetMeasurer {
  WidgetMeasurer() {
    _pipeline.rootNode = _root;
    _root.scheduleInitialLayout();
  }

  final _pipeline = PipelineOwner();
  final _buildOwner = BuildOwner(focusManager: FocusManager());
  final _root = _MeasureRoot();
  RenderObjectToWidgetElement<RenderBox>? _element;

  MeasuredBox measure(Widget widget, {required double maxWidth}) {
    _root.maxWidth = maxWidth;
    _element = RenderObjectToWidgetAdapter<RenderBox>(
      container: _root,
      child: Directionality(textDirection: TextDirection.ltr, child: widget),
    ).attachToRenderTree(_buildOwner, _element);
    _buildOwner.buildScope(_element!);
    _buildOwner.finalizeTree();
    _pipeline.flushLayout();
    return MeasuredBox(_root.child!.size, _root.baseline);
  }

  void dispose() {
    final element = _element;
    if (element == null) return;
    // 活动中的根元素不能直接 unmount：换成空子树，由 finalizeTree 回收。
    RenderObjectToWidgetAdapter<RenderBox>(
      container: _root,
    ).attachToRenderTree(_buildOwner, element);
    _buildOwner.buildScope(element);
    _buildOwner.finalizeTree();
    _element = null;
  }
}

class _MeasureRoot extends RenderObject
    with RenderObjectWithChildMixin<RenderBox> {
  double _maxWidth = double.infinity;
  double baseline = 0;

  set maxWidth(double value) {
    if (value == _maxWidth) return;
    _maxWidth = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) return;
    child.layout(BoxConstraints(maxWidth: _maxWidth), parentUsesSize: true);
    // 基线只允许父节点在 performLayout 期间读取。
    baseline = child.getDistanceToBaseline(TextBaseline.alphabetic)!;
  }

  @override
  void performResize() {}

  @override
  void debugAssertDoesMeetConstraints() {}

  @override
  Rect get paintBounds => Offset.zero & (child?.size ?? Size.zero);

  @override
  Rect get semanticBounds => paintBounds;
}
