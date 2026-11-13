import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/ambient.dart';
import '../theme/motion.dart';
import '../theme/tokens.dart';
import 'app_icon.dart';

/// The amber call to action of the title bar ("Nova spec", SPEC-053 R1–R6):
/// one short answer to the mouse, the press and the keyboard focus, and a
/// slow breathing glow while [attention] asks for the first spec.
class CtaButton extends StatefulWidget {
  const CtaButton({
    super.key,
    required this.label,
    required this.onTap,
    this.attention = false,
  });

  final String label;
  final VoidCallback onTap;

  /// The workspace has no spec yet (R4): the glow breathes until the person
  /// hovers or focuses the button.
  final bool attention;

  /// Fill on hover (R1).
  static const hoverFill = Color(0xFFF6B662);

  /// Keyboard focus ring (R3): 13,6:1 on the base of the backdrop.
  static const focusRing = Color(0xFFFFD08A);

  /// Period of the breathing glow (R4).
  static const breathPeriod = Duration(milliseconds: 2400);

  /// The light that crosses the button once on hover (R1).
  static const sheenDuration = Duration(milliseconds: 450);

  @override
  State<CtaButton> createState() => _CtaButtonState();
}

class _CtaButtonState extends State<CtaButton> with TickerProviderStateMixin {
  late final AnimationController _hover = AnimationController(
    vsync: this,
    duration: AppMotion.quick,
  );
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: CtaButton.sheenDuration,
  );
  AnimationController? _breath;
  bool _pressed = false;
  bool _focused = false;

  /// Hovered or focused once: the breathing stops for good (R4).
  bool _met = false;

  bool get _motion => AppMotion.animate(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBreath();
  }

  @override
  void didUpdateWidget(CtaButton old) {
    super.didUpdateWidget(old);
    if (old.attention != widget.attention) _syncBreath();
  }

  /// R4, R6: only with attention, motion and before the first meeting; on
  /// the ambient clock (24 frames/s).
  void _syncBreath() {
    final want = widget.attention && !_met && _motion;
    if (want && _breath == null) {
      _breath = AnimationController(
        vsync: AmbientVsync(context),
        duration: CtaButton.breathPeriod,
      )..repeat();
    } else if (!want && _breath != null) {
      _breath!.dispose();
      _breath = null;
    }
  }

  void _meet() {
    if (_met) return;
    setState(() {
      _met = true;
      _syncBreath();
    });
  }

  void _enter() {
    _meet();
    if (_motion) {
      _hover.forward();
      _sheen.forward(from: 0);
    } else {
      _hover.value = 1;
    }
  }

  void _exit() {
    if (_motion) {
      _hover.reverse();
    } else {
      _hover.value = 0;
    }
  }

  @override
  void dispose() {
    _hover.dispose();
    _sheen.dispose();
    _breath?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = _motion;
    const radius = BorderRadius.all(Radius.circular(9));
    final button = AnimatedBuilder(
      animation: Listenable.merge([_hover, _sheen, ?_breath]),
      builder: (context, _) {
        final h = Curves.easeOut.transform(_hover.value);
        final b = _breath == null
            ? 0.0
            : (1 - math.cos(_breath!.value * 2 * math.pi)) / 2;
        final glow = math.max(h * (_pressed ? .3 : .45), b * .5);
        return AnimatedScale(
          scale: _pressed && motion ? .97 : 1,
          duration: const Duration(milliseconds: 100),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color.lerp(AppColors.amber, CtaButton.hoverFill, h),
              borderRadius: radius,
              boxShadow: [
                if (glow > 0.01) ...[
                  BoxShadow(
                    color: AppColors.amber.withValues(alpha: glow),
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: AppColors.amber.withValues(alpha: glow),
                    blurRadius: 22,
                  ),
                ],
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                children: [
                  Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform.rotate(
                          key: const ValueKey('cta-plus'),
                          angle: motion ? h * math.pi / 2 : 0,
                          child: AppIcon(
                            AppIcons.plus,
                            size: 14,
                            color: AppColors.onAmber,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onAmber,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (motion && _sheen.isAnimating)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: FractionalTranslation(
                          key: const ValueKey('cta-sheen'),
                          translation: Offset(-1.4 + 4.4 * _sheen.value, 0),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: .45,
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0x00FFFFFF),
                                    Color(0x61FFFFFF),
                                    Color(0x00FFFFFF),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (v) {
          if (v) _meet();
          setState(() => _focused = v);
        },
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: MouseRegion(
          onEnter: (_) => _enter(),
          onExit: (_) => _exit(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (_) => setState(() => _pressed = false),
            // R2: the press never delays the action.
            onTap: widget.onTap,
            child: Container(
              key: const ValueKey('cta-focus-ring'),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.circular(12)),
                border: Border.all(
                  color: _focused
                      ? CtaButton.focusRing
                      : const Color(0x00000000),
                  width: 2,
                ),
              ),
              child: button,
            ),
          ),
        ),
      ),
    );
  }
}
