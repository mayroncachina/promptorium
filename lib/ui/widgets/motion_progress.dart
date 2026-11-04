import 'dart:math' as math;

import 'package:flutter/animation.dart';

import '../theme/motion.dart';

/// The [parent] transition eased for the screen: [AppMotion.enter] on the way
/// in, [AppMotion.exit] on the way out.
///
/// Unlike a [CurvedAnimation] with two curves, a change of direction starts
/// from the value on screen, so nothing jumps when a toast or dialog closes
/// during its entrance (R12).
class MotionProgress extends Animation<double>
    with AnimationWithParentMixin<double> {
  /// [enterShare] and [exitShare] finish the movement within that share of
  /// [parent]'s run: the dialog scrim is shorter than the dialog it rides on.
  MotionProgress(this.parent, {this.enterShare = 1, this.exitShare = 1}) {
    parent.addStatusListener(_onStatus);
  }

  @override
  final Animation<double> parent;

  final double enterShare;
  final double exitShare;

  var _leaving = false;
  double _fromT = 0;
  double _fromValue = 0;

  /// True from the moment [parent] reverses until it stops.
  bool get leaving => _leaving;

  /// The value on screen when [leaving] began.
  double get leftFrom => _fromValue;

  /// How much of the way out is done, eased, from 0 to 1.
  double get exitProgress {
    if (_fromT <= 0) return 1;
    final p = (1 - parent.value / _fromT) / exitShare;
    return AppMotion.exit.transform(p.clamp(0.0, 1.0));
  }

  @override
  double get value {
    final t = parent.value;
    if (_leaving) return _fromValue * (1 - exitProgress);
    if (t >= 1) return 1;
    final p = (t - _fromT) / (1 - _fromT) / enterShare;
    final eased = AppMotion.enter.transform(math.min(p, 1));
    return _fromValue + (1 - _fromValue) * eased;
  }

  void _onStatus(AnimationStatus status) {
    switch (status) {
      case AnimationStatus.forward when _leaving:
      case AnimationStatus.reverse when !_leaving:
        _fromValue = value;
        _fromT = parent.value;
        _leaving = !_leaving;
      case AnimationStatus.dismissed:
      case AnimationStatus.completed:
        _leaving = false;
        _fromT = 0;
        _fromValue = 0;
      case AnimationStatus.forward:
      case AnimationStatus.reverse:
        break;
    }
  }

  void dispose() => parent.removeStatusListener(_onStatus);
}
