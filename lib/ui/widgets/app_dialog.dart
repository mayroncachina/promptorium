import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';

import '../theme/glass.dart';
import '../theme/motion.dart';
import 'motion_progress.dart';

/// [showDialog] with the app's rhythm (SPEC-034 R4): the scrim darkens in
/// [AppMotion.base] and the dialog grows from 0.96 in [AppMotion.emphasis]; on
/// closing it shrinks to 0.98 in [AppMotion.emphasisExit], the scrim in
/// [AppMotion.baseExit]. Everything else is [showDialog]'s: `Esc`, a click on
/// the scrim, the trapped focus, the focus handed back and the returned value.
///
/// With [origin], a rect in global coordinates, the dialog grows out of its
/// centre from [originScale] and leaves the same way (SPEC-033 R2).
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
  Rect? origin,
  double originScale = _enterScale,
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
      origin: origin,
      enterScale: origin == null ? _enterScale : originScale,
      exitScale: origin == null ? _exitScale : originScale,
    ),
  );
}

/// Blur behind a dialog with the glass effects on (SPEC-049 R5).
const dialogBlurSigma = 12.0;

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
    required this.enterScale,
    required this.exitScale,
    this.origin,
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
  final double enterScale;
  final double exitScale;
  final Rect? origin;

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
    double scaleAt(double t) => lerpDouble(enterScale, 1, t)!;
    return _dialog.leaving
        ? lerpDouble(
            scaleAt(_dialog.leftFrom),
            exitScale,
            _dialog.exitProgress,
          )!
        : scaleAt(_dialog.value);
  }

  /// Where the dialog scales from: [child] of [buildTransitions] fills the
  /// screen, so the point of [origin] is a fraction of the screen.
  Alignment _alignment(BuildContext context) {
    final centre = origin?.center;
    final size = MediaQuery.sizeOf(context);
    if (centre == null || size.isEmpty) return Alignment.center;
    return Alignment(
      centre.dx / size.width * 2 - 1,
      centre.dy / size.height * 2 - 1,
    );
  }

  @override
  Widget buildModalBarrier() {
    final color = barrierColor;
    if (color == null || color.a == 0 || offstage) {
      return super.buildModalBarrier();
    }
    final barrier = AnimatedModalBarrier(
      color: _scrim.drive(
        ColorTween(begin: color.withValues(alpha: 0), end: color),
      ),
      dismissible: barrierDismissible,
      semanticsLabel: barrierLabel,
      barrierSemanticsDismissible: semanticsDismissible,
    );
    // The glass dialog sits on a blur of the screen (SPEC-049 R5): one
    // region, the whole screen, growing with the scrim.
    return Stack(
      fit: StackFit.expand,
      children: [
        Builder(
          builder: (context) => !glassEffectsOf(context)
              ? const SizedBox.shrink()
              : IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _scrim,
                    builder: (context, _) => BackdropFilter(
                      key: const ValueKey('dialog-blur'),
                      filter: ImageFilter.blur(
                        sigmaX: dialogBlurSigma * _scrim.value,
                        sigmaY: dialogBlurSigma * _scrim.value,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
        ),
        barrier,
      ],
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
      builder: (context, child) => Transform.scale(
        scale: _scale,
        alignment: _alignment(context),
        child: child,
      ),
    ),
  );
}
