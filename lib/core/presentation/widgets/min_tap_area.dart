import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The smallest tap target Android's accessibility guidelines allow.
const double kMinTapTarget = 48;

/// Lets a small control be tapped from a [minSize] square around it
/// without changing its size or the layout around it — the tick beside a
/// to-do keeps its 26 dp circle, but a thumb landing near it still counts.
///
/// Wrap the control's own [GestureDetector] (or button) in this. A tap in
/// the margin is passed to the control as if it landed on its centre.
/// The margin only reaches as far as the parent's own bounds, and a sibling
/// painted on top still takes taps that land on it.
class MinTapArea extends SingleChildRenderObjectWidget {
  final double minSize;

  const MinTapArea({
    super.key,
    this.minSize = kMinTapTarget,
    required Widget super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMinTapArea(minSize);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderMinTapArea).minSize = minSize;
  }
}

class _RenderMinTapArea extends RenderProxyBox {
  _RenderMinTapArea(this.minSize);

  double minSize;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final s = size;
    final dx = math.max(0.0, (minSize - s.width) / 2);
    final dy = math.max(0.0, (minSize - s.height) / 2);
    final area = Rect.fromLTRB(-dx, -dy, s.width + dx, s.height + dy);
    if (!area.contains(position)) return false;
    // A tap in the margin lands on the control's centre, so a round one
    // (whose corners don't count) still takes it.
    final inside = (Offset.zero & s).contains(position)
        ? position
        : s.center(Offset.zero);
    return hitTestChildren(result, position: inside);
  }
}
