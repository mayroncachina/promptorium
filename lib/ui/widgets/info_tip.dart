import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// Code block of an [InfoTip]: one entry per line (`''` = blank line);
/// the lines in [highlight] (indexes) are drawn in amber.
@immutable
class InfoTipCode {
  const InfoTipCode(this.lines, {this.highlight = const {}});

  final List<String> lines;
  final Set<int> highlight;
}

/// The ⓘ icon with a rich tooltip (SPEC-048 R1, R7): a title, a text, an
/// optional code block, a rich [detail] paragraph and a muted [footnote].
///
/// It opens when the pointer rests on the icon (and stays open while the
/// pointer is over the card) and when the icon gets keyboard focus;
/// `Enter` / `Espaço` toggles it and `Esc` closes it. The card stays inside
/// the screen: below the icon, or above it when there is no room.
class InfoTip extends StatefulWidget {
  const InfoTip({
    super.key,
    required this.title,
    this.text,
    this.code,
    this.detail,
    this.footnote,
    this.semanticLabel,
    this.maxWidth = 440,
    this.iconSize = 18,
    this.hoverDelay = const Duration(milliseconds: 250),
    this.child,
  });

  final String title;
  final String? text;
  final InfoTipCode? code;

  /// Paragraph after the code (use [TextSpan]s with bold for names).
  final InlineSpan? detail;
  final String? footnote;

  /// Accessible name of the icon; default "Sobre: <title>".
  final String? semanticLabel;
  final double maxWidth;
  final double iconSize;

  /// Wait before opening on hover (focus opens at once).
  final Duration hoverDelay;

  /// What opens the card in place of the ⓘ (the model label of the Grafo,
  /// SPEC-045 R9); null = the icon.
  final Widget? child;

  @override
  State<InfoTip> createState() => InfoTipState();
}

@visibleForTesting
class InfoTipState extends State<InfoTip> {
  final _portal = OverlayPortalController();
  final _iconKey = GlobalKey();
  Timer? _open, _close;
  bool _hoverIcon = false, _hoverCard = false, _focused = false;

  bool get isOpen => _portal.isShowing;

  @override
  void dispose() {
    _open?.cancel();
    _close?.cancel();
    super.dispose();
  }

  void _show() {
    _open?.cancel();
    _close?.cancel();
    if (!_portal.isShowing && mounted) setState(_portal.show);
  }

  void _hide() {
    _open?.cancel();
    _close?.cancel();
    if (_portal.isShowing && mounted) setState(_portal.hide);
  }

  /// Closes a moment after the pointer left (time to reach the card).
  void _maybeHide() {
    _close?.cancel();
    _close = Timer(const Duration(milliseconds: 120), () {
      if (!_hoverIcon && !_hoverCard && !_focused) _hide();
    });
  }

  void _enterIcon() {
    _hoverIcon = true;
    _close?.cancel();
    if (_portal.isShowing) return;
    _open?.cancel();
    _open = Timer(widget.hoverDelay, _show);
  }

  void _exitIcon() {
    _hoverIcon = false;
    _open?.cancel();
    _maybeHide();
  }

  Rect? _iconRect() {
    final box = _iconKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final active = _portal.isShowing || _focused || _hoverIcon;
    final custom = widget.child;
    final icon = custom != null
        ? Container(
            key: _iconKey,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _focused ? AppColors.amber : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: custom,
          )
        : Container(
            key: _iconKey,
            width: widget.iconSize + 8,
            height: widget.iconSize + 8,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _focused ? AppColors.amber : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Icon(
              Icons.info_outline,
              size: widget.iconSize,
              color: active ? AppColors.amber : AppColors.textSecondary,
            ),
          );
    return Semantics(
      button: true,
      label: widget.semanticLabel ?? 'Sobre: ${widget.title}',
      hint: [widget.title, ?widget.text].join('. '),
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.help,
        // Any focus (Tab, or focus moved by code) opens it.
        onFocusChange: (v) {
          _focused = v;
          if (v) {
            _show();
          } else {
            _maybeHide();
          }
          if (mounted) setState(() {});
        },
        onShowHoverHighlight: (v) => v ? _enterIcon() : _exitIcon(),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => _portal.isShowing ? _hide() : _show(),
          ),
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) => _hide(),
          ),
        },
        child: GestureDetector(
          onTap: () => _portal.isShowing ? _hide() : _show(),
          child: OverlayPortal(
            controller: _portal,
            overlayChildBuilder: (context) {
              final anchor = _iconRect();
              if (anchor == null) return const SizedBox.shrink();
              return CustomSingleChildLayout(
                delegate: _TipLayout(anchor, widget.maxWidth),
                child: MouseRegion(
                  onEnter: (_) {
                    _hoverCard = true;
                    _close?.cancel();
                  },
                  onExit: (_) {
                    _hoverCard = false;
                    _maybeHide();
                  },
                  child: _card(),
                ),
              );
            },
            child: icon,
          ),
        ),
      ),
    );
  }

  Widget _card() {
    final code = widget.code;
    return Material(
      key: const ValueKey('info-tip-card'),
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderHover),
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
            fontSize: 12.5,
            height: 1.5,
            color: AppColors.text,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (widget.text != null) ...[
                const SizedBox(height: 6),
                Text(widget.text!),
              ],
              if (code != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < code.lines.length; i++)
                        Text(
                          code.lines[i].isEmpty ? ' ' : code.lines[i],
                          style: TextStyle(
                            fontFamily: AppFonts.mono,
                            fontSize: 12,
                            height: 1.6,
                            color: code.highlight.contains(i)
                                ? AppColors.amber
                                : AppColors.text,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (widget.detail != null) ...[
                const SizedBox(height: 10),
                Text.rich(widget.detail!),
              ],
              if (widget.footnote != null) ...[
                const SizedBox(height: 10),
                Text(
                  widget.footnote!,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Below [anchor] (above when it does not fit), kept inside the overlay
/// with a 12 px margin.
class _TipLayout extends SingleChildLayoutDelegate {
  _TipLayout(this.anchor, this.maxWidth);

  final Rect anchor;
  final double maxWidth;
  static const _margin = 12.0, _gap = 6.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final w = (constraints.maxWidth - 2 * _margin).clamp(0.0, maxWidth);
    return BoxConstraints(maxWidth: w, maxHeight: constraints.maxHeight);
  }

  @override
  Offset getPositionForChild(Size size, Size child) {
    final x = (anchor.left - 12).clamp(
      _margin,
      (size.width - child.width - _margin).clamp(_margin, double.infinity),
    );
    final below = anchor.bottom + _gap;
    final y = below + child.height <= size.height - _margin
        ? below
        : (anchor.top - _gap - child.height).clamp(_margin, double.infinity);
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_TipLayout old) =>
      old.anchor != anchor || old.maxWidth != maxWidth;
}
