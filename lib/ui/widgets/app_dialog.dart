import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../theme/motion.dart';
import 'motion_progress.dart';

/// [showDialog] with the app's rhythm (SPEC-034 R4): the scrim darkens in
/// [AppMotion.base] and the dialog grows from 0.96 in [AppMotion.emphasis]; on
/// closing it shrinks to 0.98 in [AppMotion.emphasisExit], the scrim in
/// [AppMotion.baseExit]. Everything else is [showDialog]'s: `Esc`, a click on
/// the scrim, the trapped focus, the focus handed back and the returned value.
///
/// It pushes its own route because [showGeneralDialog] has a single duration
/// for both directions.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  TraversalEdgeBehavior? traversalEdgeBehavior,
  bool? requestFocus,
}) {
  assert(debugCheckHasMaterialLocalizations(context));
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  return navigator.push<T>(
    _AppDialogRoute<T>(
      context: context,
      builder: builder,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierColor:
          barrierColor ??
          DialogTheme.of(context).barrierColor ??
          Theme.of(context).dialogTheme.barrierColor ??
          Colors.black54,
      barrierDismissible: barrierDismissible,
      barrierLabel: barrierLabel,
      useSafeArea: useSafeArea,
      settings: routeSettings,
      anchorPoint: anchorPoint,
      traversalEdgeBehavior:
          traversalEdgeBehavior ?? TraversalEdgeBehavior.closedLoop,
      requestFocus: requestFocus,
      enter: AppMotion.duration(context, AppMotion.emphasis),
      exit: AppMotion.duration(context, AppMotion.emphasisExit),
    ),
  );
}

/// Scale of a dialog that has not arrived yet, and of one that is leaving.
const _enterScale = 0.96;
const _exitScale = 0.98;

/// The scrim runs on the dialog's clock, in its own shorter time.
final _scrimEnterShare =
    AppMotion.base.inMicroseconds / AppMotion.emphasis.inMicroseconds;
final _scrimExitShare =
    AppMotion.baseExit.inMicroseconds / AppMotion.emphasisExit.inMicroseconds;

class _AppDialogRoute<T> extends DialogRoute<T> {
  _AppDialogRoute({
    required super.context,
    required super.builder,
    required this._enter,
    required this._exit,
    super.themes,
    required Color super.barrierColor,
    super.barrierDismissible,
    super.barrierLabel,
    super.useSafeArea,
    super.settings,
    super.requestFocus,
    super.anchorPoint,
    super.traversalEdgeBehavior,
  });

  final Duration _enter;
  final Duration _exit;

  late final MotionProgress _dialog;
  late final MotionProgress _scrim;

  @override
  Duration get transitionDuration => _enter;

  @override
  Duration get reverseTransitionDuration => _exit;

  @override
  void install() {
    super.install();
    _dialog = MotionProgress(animation!);
    _scrim = MotionProgress(
      animation!,
      enterShare: _scrimEnterShare,
      exitShare: _scrimExitShare,
    );
  }

  @override
  void dispose() {
    _dialog.dispose();
    _scrim.dispose();
    super.dispose();
  }

  double get _scale {
    double scaleAt(double t) => lerpDouble(_enterScale, 1, t)!;
    return _dialog.leaving
        ? lerpDouble(
            scaleAt(_dialog.leftFrom),
            _exitScale,
            _dialog.exitProgress,
          )!
        : scaleAt(_dialog.value);
  }

  @override
  Widget buildModalBarrier() {
    final color = barrierColor;
    if (color == null || color.a == 0 || offstage) {
      return super.buildModalBarrier();
    }
    return AnimatedModalBarrier(
      color: _scrim.drive(
        ColorTween(begin: color.withValues(alpha: 0), end: color),
      ),
      dismissible: barrierDismissible,
      semanticsLabel: barrierLabel,
      barrierSemanticsDismissible: semanticsDismissible,
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(
    opacity: _dialog,
    child: AnimatedBuilder(
      animation: _dialog,
      child: child,
      builder: (context, child) => Transform.scale(scale: _scale, child: child),
    ),
  );
}
