import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';

/// Copy button that answers in place (SPEC-077 R3): copies [text], turns
/// into "✓ Copiado" in teal for [CopyButton.copiedFor] and announces
/// [announcement] to the screen reader. No toast: the button is the answer.
/// A second click in that time copies again and restarts the time.
///
/// [iconOnly] shows just the icon (Copiar mensagem, Copiar comando); the
/// label then lives only in the tooltip and the semantics.
class CopyButton extends StatefulWidget {
  const CopyButton({
    super.key,
    required this.text,
    required this.semanticLabel,
    required this.announcement,
    this.label = 'Copiar',
    this.copiedLabel = 'Copiado',
    this.tooltip,
    this.iconOnly = false,
    this.emphasized = false,
    this.focusNode,
  });

  /// What goes to the clipboard, read at the click.
  final String Function() text;

  /// Read by the screen reader ("Copiar código SQL, 17 linhas").
  final String semanticLabel;

  /// Announced after copying ("Código copiado").
  final String announcement;
  final String label;
  final String copiedLabel;
  final String? tooltip;
  final bool iconOnly;

  /// More contrast, while the pointer is over what the button copies (R1).
  final bool emphasized;
  final FocusNode? focusNode;

  /// How long "Copiado" stays (R3).
  static const copiedFor = Duration(milliseconds: 1500);

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  Timer? _timer;
  bool _hover = false;
  bool _focused = false;

  bool get _copied => _timer?.isActive ?? false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final text = widget.text();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _timer?.cancel();
    setState(() {
      _timer = Timer(CopyButton.copiedFor, () {
        if (mounted) setState(() {});
      });
    });
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        widget.announcement,
        Directionality.of(context),
        assertiveness: Assertiveness.polite,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final copied = _copied;
    final keyboard =
        _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final color = copied
        ? AppColors.teal
        : (_hover || widget.emphasized || keyboard
              ? AppColors.text
              : AppColors.textSecondary);
    final borderColor = keyboard
        ? AppColors.amberLight
        : copied
        ? AppColors.teal.withValues(alpha: .45)
        : (_hover ? AppColors.borderHover : Colors.transparent);
    final radius = BorderRadius.circular(5);
    final icon = Icon(
      copied ? Icons.check : Icons.copy_outlined,
      size: 13,
      color: color,
    );
    final Widget content = widget.iconOnly
        ? SizedBox(width: 24, height: 24, child: Center(child: icon))
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(
              height: 24,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  const SizedBox(width: 6),
                  Text(
                    copied ? widget.copiedLabel : widget.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          );
    final button = Material(
      color: copied
          ? AppColors.teal.withValues(alpha: .10)
          : (_hover ? const Color(0x0AFFFFFF) : Colors.transparent),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: borderColor, width: keyboard ? 1.5 : 1),
      ),
      child: InkWell(
        focusNode: widget.focusNode,
        borderRadius: radius,
        onTap: _copy,
        onHover: (v) => setState(() => _hover = v),
        onFocusChange: (v) => setState(() => _focused = v),
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        child: ExcludeSemantics(child: content),
      ),
    );
    final tip = widget.tooltip;
    return MergeSemantics(
      child: Semantics(
        button: true,
        label: copied ? widget.copiedLabel : widget.semanticLabel,
        child: tip == null
            ? button
            : Tooltip(
                message: tip,
                excludeFromSemantics: true,
                waitDuration: const Duration(milliseconds: 400),
                child: button,
              ),
      ),
    );
  }
}
