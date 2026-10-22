import 'package:flutter/material.dart';

class CanvasViewController extends TransformationController {
  Size viewport = Size.zero;

  /// Parts of [viewport] covered by floating panels; fits and zoom steps
  /// center on what is left.
  EdgeInsets padding = EdgeInsets.zero;

  double get scale => value.getMaxScaleOnAxis();
  Rect get _free => padding.deflateRect(Offset.zero & viewport);

  void zoomTo(double scale) {
    final next = scale.clamp(.5, 1.5);
    final center = _free.center;
    final scene = toScene(center);
    value = Matrix4.identity()
      ..translateByDouble(
        center.dx - scene.dx * next,
        center.dy - scene.dy * next,
        0,
        1,
      )
      ..scaleByDouble(next, next, next, 1);
  }

  void panBy(Offset delta) =>
      value = Matrix4.translationValues(delta.dx, delta.dy, 0)..multiply(value);

  void zoomIn() => zoomTo(scale + .1);
  void zoomOut() => zoomTo(scale - .1);
  void reset() => value = Matrix4.identity();
  void fit(Rect bounds) {
    final free = _free;
    if (free.isEmpty || bounds.isEmpty) return;
    final s = ((free.width - 40) / bounds.width).clamp(.5, 1.5).toDouble();
    final vertical = ((free.height - 40) / bounds.height).clamp(.5, 1.5);
    _center(bounds.center, s < vertical ? s : vertical.toDouble());
  }

  void fitSelection(Rect bounds) => _center(bounds.center, 1.3);
  void _center(Offset center, double scale) {
    final target = _free.center;
    value = Matrix4.identity()
      ..translateByDouble(
        target.dx - center.dx * scale,
        target.dy - center.dy * scale,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
  }
}
