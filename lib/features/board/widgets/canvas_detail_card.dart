import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/theme/tokens.dart';

/// Hover and keyboard focus share the same accessible details overlay.
class CanvasDetailCard extends StatefulWidget {
  const CanvasDetailCard({
    super.key,
    required this.child,
    required this.details,
    this.focusable = true,
    this.width = 290,
  });
  final Widget child, details;

  /// False inside a node that is already one focus target (step dots).
  final bool focusable;
  final double width;
  @override
  State<CanvasDetailCard> createState() => _CanvasDetailCardState();
}

class _CanvasDetailCardState extends State<CanvasDetailCard> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  Timer? _timer;
  void _hide() {
    _timer?.cancel();
    _portal.hide();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hover = MouseRegion(
      onEnter: (_) {
        _timer = Timer(const Duration(milliseconds: 300), _portal.show);
      },
      onExit: (_) => _hide(),
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (_) => Positioned(
            width: widget.width,
            child: CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.bottomLeft,
              offset: const Offset(-4, 8),
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: CanvasColors.tooltip,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: SessionColors.selectedBorder),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 24,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.text,
                    ),
                    child: widget.details,
                  ),
                ),
              ),
            ),
          ),
          child: widget.child,
        ),
      ),
    );
    if (!widget.focusable) return hover;
    return Focus(
      onFocusChange: (v) {
        if (v) {
          _portal.show();
        } else {
          _hide();
        }
      },
      onKeyEvent: (_, e) {
        if (e.logicalKey == LogicalKeyboardKey.escape) {
          _hide();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: hover,
    );
  }
}
