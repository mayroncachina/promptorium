import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// Shows [bounds] at 100% when it fits, from the top and centered across;
  /// else zooms out until it does (SPEC-036 R11).
  void frame(Rect bounds) {
    final free = _free;
    if (free.isEmpty || bounds.isEmpty) return;
    final s = math.max(
      .2,
      math.min(
        1.0,
        math.min(
          (free.width - 40) / bounds.width,
          (free.height - 40) / bounds.height,
        ),
      ),
    );
    value = Matrix4.identity()
      ..translateByDouble(
        free.center.dx - bounds.center.dx * s,
        free.top + 20 - bounds.top * s,
        0,
        1,
      )
      ..scaleByDouble(s, s, s, 1);
  }

  /// Plain wheel moves, Ctrl + wheel and pinch zoom.
  void onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScaleEvent) {
      zoomTo(scale * event.scale);
    } else if (event is PointerScrollEvent) {
      if (HardwareKeyboard.instance.isControlPressed) {
        if (event.scrollDelta.dy < 0) {
          zoomIn();
        } else if (event.scrollDelta.dy > 0) {
          zoomOut();
        }
      } else if (event.kind != PointerDeviceKind.trackpad) {
        // InteractiveViewer already pans on trackpad scroll.
        panBy(-event.scrollDelta);
      }
    }
  }

  Map<ShortcutActivator, VoidCallback> get zoomShortcuts => {
    const SingleActivator(LogicalKeyboardKey.equal, control: true): zoomIn,
    const SingleActivator(LogicalKeyboardKey.equal, control: true, shift: true):
        zoomIn,
    const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true): zoomIn,
    const SingleActivator(LogicalKeyboardKey.minus, control: true): zoomOut,
    const SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true):
        zoomOut,
    const SingleActivator(LogicalKeyboardKey.digit0, control: true): reset,
    const SingleActivator(LogicalKeyboardKey.numpad0, control: true): reset,
  };

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
