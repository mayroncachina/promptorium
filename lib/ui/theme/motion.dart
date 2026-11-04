import 'package:flutter/widgets.dart';

/// Motion tokens (SPEC-034 R1): every new animation uses these values, and
/// leaving is always faster than arriving.
abstract final class AppMotion {
  /// Hover, press, focus.
  static const quick = Duration(milliseconds: 120);
  static const quickExit = Duration(milliseconds: 80);

  /// Toast, dialog scrim, new event, step status.
  static const base = Duration(milliseconds: 160);
  static const baseExit = Duration(milliseconds: 110);

  /// Dialog, card that changes column.
  static const emphasis = Duration(milliseconds: 220);
  static const emphasisExit = Duration(milliseconds: 150);

  /// Section change and the sidebar highlight; the old screen leaves at once.
  static const section = Duration(milliseconds: 640);

  /// Arrives fast and lands slowly.
  static const enter = Cubic(.2, .8, .2, 1);

  /// Accelerates out of the way.
  static const exit = Cubic(.4, 0, 1, 1);

  /// Off in the test suite (test/flutter_test_config.dart): tests of other
  /// subjects keep their fixed pumps. Tests of motion turn it back on.
  @visibleForTesting
  static bool enabled = true;

  /// False when the system asks for reduced motion (R11).
  static bool animate(BuildContext context) =>
      enabled && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  /// [duration], or zero when animations are off (R11).
  static Duration duration(BuildContext context, Duration duration) =>
      animate(context) ? duration : Duration.zero;
}
