import 'package:flutter/material.dart';

import '../theme/motion.dart';
import 'motion_progress.dart';

/// How far a toast travels on its way in and out (R5).
const toastTravel = 8.0;

/// Exit of a toast with animations off. The messenger asserts when a queued
/// snack bar starts inside the call that hides the current one, which a zero
/// duration would do; one tick keeps them apart and nothing is seen moving.
const _instantExit = Duration(microseconds: 1);

extension AppToast on ScaffoldMessengerState {
  /// [showSnackBar] with the app's rhythm (SPEC-034 R5): [toast] rises
  /// [toastTravel] pixels with a fade in [AppMotion.base] and leaves the same
  /// way in [AppMotion.baseExit].
  ///
  /// [SnackBar] has no slide and [SnackBarThemeData] no animation, and its own
  /// entrance changes the height. So [toast] is drawn already in place, inside
  /// a transition driven by the messenger: the queue, the timer, `closed`, the
  /// action and `hideCurrentSnackBar` stay the messenger's.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showAppToast(
    SnackBar toast,
  ) {
    final animate = AppMotion.animate(context);
    return showSnackBar(
      _MotionSnackBar(toast),
      snackBarAnimationStyle: AnimationStyle(
        duration: animate ? AppMotion.base : Duration.zero,
        reverseDuration: animate ? AppMotion.baseExit : _instantExit,
      ),
    );
  }
}

/// Moves [child] up to its place and fades it in as [progress] goes to 1.
/// Only opacity and transform change (R13), and it never blocks input (R12).
class ToastMotion extends StatelessWidget {
  const ToastMotion({super.key, required this.progress, required this.child});

  final Animation<double> progress;
  final Widget child;

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: progress,
    child: AnimatedBuilder(
      animation: progress,
      child: child,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, toastTravel * (1 - progress.value)),
        child: child,
      ),
    ),
  );
}

/// What the messenger and the [Scaffold] handle: they read the fields passed
/// to super, and [withAnimation] keeps this class in the copy they show.
class _MotionSnackBar extends SnackBar {
  _MotionSnackBar(this.toast, {super.key, super.animation})
    : assert(toast.onVisible == null, 'showAppToast has no onVisible'),
      super(
        content: toast.content,
        width: toast.width,
        behavior: toast.behavior,
        duration: toast.duration,
        persist: toast.persist,
      );

  final SnackBar toast;

  @override
  SnackBar withAnimation(Animation<double> newAnimation, {Key? fallbackKey}) =>
      _MotionSnackBar(toast, key: key ?? fallbackKey, animation: newAnimation);

  @override
  State<SnackBar> createState() => _MotionSnackBarState();
}

class _MotionSnackBarState extends State<_MotionSnackBar> {
  late final _progress = MotionProgress(widget.animation!);
  late final _toast = widget.toast.withAnimation(kAlwaysCompleteAnimation);

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ToastMotion(progress: _progress, child: _toast);
}
