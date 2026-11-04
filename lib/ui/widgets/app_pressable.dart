import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/material.dart';

import '../theme/motion.dart';

/// Hover and press of a card, list row or button (SPEC-034 R6).
///
/// [child] keeps its own InkWell, semantics, focus and keys: this widget only
/// listens to the pointer, so it takes no part in the gesture arena and a
/// [Draggable] around it still works. Hover fades layers in, press scales, and
/// neither touches the layout (R13).
///
/// InkWell's `hoverColor` cannot do the fade: its `hoverDuration` also delays
/// the focus highlight, and a card's opaque background hides the ink. Pass
/// `hoverColor: Colors.transparent` to the InkWell of a child using [hoverTint].
class AppPressable extends StatefulWidget {
  const AppPressable({
    super.key,
    required this.child,
    this.enabled = true,
    this.borderRadius = BorderRadius.zero,
    this.hoverTint,
    this.hoverBorder,
    this.hoverShadow,
  });

  /// Same strength as the theme's `hoverColor`, for dark surfaces.
  static const tint = Color(0x0AFFFFFF);

  /// Takes amber to `#F6B662` and red to `#F58F85`, as in the prototype.
  static const primaryTint = Color(0x2BFFFFFF);

  static const cardShadow = [
    BoxShadow(color: Color(0x59000000), blurRadius: 14, offset: Offset(0, 4)),
  ];

  /// Scale while pressed.
  static const pressedScale = 0.98;

  static PointerDownEvent? _claimed;

  /// Keeps a press from reaching the [AppPressable]s around the control it
  /// landed on. Use as `Listener.onPointerDown` of nested controls that have
  /// no [AppPressable] of their own, so a card does not shrink with its menu.
  static void claim(PointerDownEvent event) =>
      _claimed = (event.original ?? event) as PointerDownEvent;

  final Widget child;

  /// False ignores hover and press, as on a disabled button.
  final bool enabled;

  /// Shape of the hover layers: the same as [child]'s.
  final BorderRadius borderRadius;

  final Color? hoverTint;
  final Color? hoverBorder;
  final List<BoxShadow>? hoverShadow;

  @override
  State<AppPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<AppPressable> {
  var _hovered = false;
  var _pressed = false;

  // A pointer can end after this state is gone: a Draggable swaps its child
  // when the drag starts, and the listener still gets the pointer up.
  void _hover(bool value) {
    if (mounted && _hovered != value) setState(() => _hovered = value);
  }

  void _press(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  void _down(PointerDownEvent event) {
    if (!widget.enabled || event.buttons != kPrimaryButton) return;
    // Pointer events reach the innermost listener first.
    if (identical(AppPressable._claimed, event.original ?? event)) return;
    AppPressable.claim(event);
    _press(true);
  }

  @override
  Widget build(BuildContext context) {
    final hovered = _hovered && widget.enabled;
    final pressed = _pressed && widget.enabled;
    final border = widget.hoverBorder;
    // Must stay opaque: a translucent region fails the hit test of whatever is
    // around it, and a Draggable would never see the pointer.
    return MouseRegion(
      // Dragging another card over this one is not hovering it.
      onEnter: (event) => _hover(!event.down),
      onExit: (_) => _hover(false),
      child: Listener(
        onPointerDown: _down,
        onPointerUp: (_) => _press(false),
        onPointerCancel: (_) => _press(false),
        child: AnimatedScale(
          scale: pressed ? AppPressable.pressedScale : 1,
          duration: AppMotion.duration(
            context,
            pressed ? AppMotion.quick : AppMotion.quickExit,
          ),
          curve: pressed ? AppMotion.enter : AppMotion.exit,
          child: Stack(
            fit: StackFit.passthrough,
            clipBehavior: Clip.none,
            children: [
              HoverLayer(
                visible: hovered,
                decoration: BoxDecoration(
                  borderRadius: widget.borderRadius,
                  boxShadow: widget.hoverShadow,
                ),
              ),
              widget.child,
              HoverLayer(
                visible: hovered,
                decoration: BoxDecoration(
                  color: widget.hoverTint,
                  borderRadius: widget.borderRadius,
                  border: border == null ? null : Border.all(color: border),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// [decoration] fading over the whole of a [Stack] in `quick`, only by opacity.
class HoverLayer extends StatelessWidget {
  const HoverLayer({
    super.key,
    required this.visible,
    required this.decoration,
  });

  final bool visible;
  final Decoration decoration;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: AppMotion.duration(
          context,
          visible ? AppMotion.quick : AppMotion.quickExit,
        ),
        curve: visible ? AppMotion.enter : AppMotion.exit,
        child: DecoratedBox(decoration: decoration),
      ),
    ),
  );
}
