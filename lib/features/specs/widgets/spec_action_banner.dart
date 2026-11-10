import 'dart:async';
import 'dart:ui' show FontFeature, SemanticsRole;

import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../spec_action.dart';
import 'spec_header.dart' show Kbd;
import '../../../ui/theme/ambient.dart';

/// Progress indicator of the spec actions (SPEC-025 R2, R11): a spinner, or
/// a still icon when the system asks for reduced motion.
class ActionSpinner extends StatelessWidget {
  const ActionSpinner({
    super.key,
    this.size = 14,
    this.color = AppColors.amber,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) {
      return Icon(
        Icons.hourglass_top,
        key: const ValueKey('spec-action-spinner-still'),
        size: size,
        color: color,
      );
    }
    return AmbientSpinner(
      key: const ValueKey('spec-action-spinner'),
      size: size,
      strokeWidth: 2,
      color: color,
    );
  }
}

/// Time since [startedAt], "1 min 12 s", updated every second (R3).
class ElapsedText extends StatefulWidget {
  const ElapsedText({
    super.key,
    required this.startedAt,
    this.color = AppColors.textSecondary,
    this.fontSize = 12,
  });

  final DateTime startedAt;
  final Color color;
  final double fontSize;

  @override
  State<ElapsedText> createState() => _ElapsedTextState();
}

class _ElapsedTextState extends State<ElapsedText> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = formatElapsed(DateTime.now().difference(widget.startedAt));
    return Semantics(
      label: 'Tempo decorrido: $text',
      excludeSemantics: true,
      child: Text(
        text,
        key: const ValueKey('spec-action-elapsed'),
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          fontFamily: AppFonts.mono,
          fontSize: widget.fontSize,
          color: widget.color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// "Cancelar geração" with the Esc chip (R3, R9); [focusNode] takes the
/// focus when the strip appears from the keyboard (R11).
class CancelGenerationButton extends StatelessWidget {
  const CancelGenerationButton({
    super.key,
    required this.onTap,
    this.focusNode,
  });

  final VoidCallback onTap;

  /// Focused when the strip appears from the keyboard (R11).
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(6);
    return Tooltip(
      message: 'Interrompe o agente; a spec não muda (Esc).',
      waitDuration: const Duration(milliseconds: 500),
      child: MergeSemantics(
        child: Semantics(
          button: true,
          label: 'Cancelar geração (Esc)',
          child: Material(
            color: AppColors.panel,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: const BorderSide(color: AppColors.border),
            ),
            child: InkWell(
              key: const ValueKey('spec-action-cancel'),
              focusNode: focusNode,
              onTap: onTap,
              borderRadius: radius,
              focusColor: AppColors.amber.withValues(alpha: .25),
              hoverColor: Colors.white.withValues(alpha: .08),
              child: const SizedBox(
                height: 32,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: ExcludeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close, size: 15, color: AppColors.text),
                        SizedBox(width: 6),
                        Text(
                          'Cancelar geração',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(fontSize: 13, color: AppColors.text),
                        ),
                        SizedBox(width: 8),
                        Kbd('Esc'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Status strip of a long action, above the editor (R3): what runs, why the
/// spec is read-only, the elapsed time and "Cancelar geração".
class SpecActionBanner extends StatelessWidget {
  const SpecActionBanner({
    super.key,
    required this.title,
    required this.startedAt,
    required this.onCancel,
    this.cancelFocus,
  });

  final String title;
  final DateTime startedAt;
  final VoidCallback onCancel;
  final FocusNode? cancelFocus;

  static const reason =
      'A spec fica somente leitura até terminar, para que nada do que você '
      'escrever seja sobrescrito.';

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('spec-action-banner'),
    margin: const EdgeInsets.fromLTRB(20, 12, 20, 4),
    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
    decoration: BoxDecoration(
      color: AppColors.amberTint,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: SessionColors.approvalBorder),
    ),
    child: Row(
      children: [
        const ActionSpinner(size: 16),
        const SizedBox(width: 14),
        Expanded(
          child: Semantics(
            container: true,
            // A status is a polite live region: announced when it appears
            // (Flutter rejects liveRegion together with this role).
            role: SemanticsRole.status,
            label: '$title $reason',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  key: const ValueKey('spec-action-title'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  reason,
                  style: TextStyle(fontSize: 12.5, color: AppColors.text),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        ElapsedText(startedAt: startedAt),
        const SizedBox(width: 12),
        CancelGenerationButton(onTap: onCancel, focusNode: cancelFocus),
      ],
    ),
  );
}

/// Failure alert of an action (R8): the cause, the spec unchanged and
/// unlocked, "Tentar de novo" and "Fechar aviso".
class SpecActionError extends StatelessWidget {
  const SpecActionError({
    super.key,
    required this.title,
    required this.cause,
    required this.onRetry,
    required this.onClose,
  });

  final String title;
  final String cause;
  final VoidCallback? onRetry;
  final VoidCallback onClose;

  static const unchanged =
      'A spec não foi alterada e está liberada para edição.';

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('spec-action-error'),
    margin: const EdgeInsets.fromLTRB(20, 12, 20, 4),
    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
    decoration: BoxDecoration(
      color: SessionColors.delBg,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: SessionColors.stopBorder),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.error_outline, size: 16, color: AppColors.red),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Semantics(
            container: true,
            // Assertive live region.
            role: SemanticsRole.alert,
            label: '$title $cause $unchanged',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  key: const ValueKey('spec-action-error-title'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$cause $unchanged',
                  key: const ValueKey('spec-action-error-cause'),
                  style: const TextStyle(fontSize: 12.5, color: AppColors.text),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        if (onRetry != null)
          _ErrorButton(
            key: const ValueKey('spec-action-retry'),
            label: 'Tentar de novo',
            icon: Icons.refresh,
            onTap: onRetry!,
          ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Fechar aviso',
          waitDuration: const Duration(milliseconds: 500),
          child: Semantics(
            button: true,
            label: 'Fechar aviso',
            child: InkWell(
              key: const ValueKey('spec-action-error-close'),
              onTap: onClose,
              borderRadius: BorderRadius.circular(6),
              focusColor: AppColors.amber.withValues(alpha: .25),
              child: const SizedBox(
                width: 32,
                height: 32,
                child: ExcludeSemantics(
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _ErrorButton extends StatelessWidget {
  const _ErrorButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(6);
    return Material(
      color: AppColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        focusColor: AppColors.amber.withValues(alpha: .25),
        hoverColor: Colors.white.withValues(alpha: .08),
        child: SizedBox(
          height: 32,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: AppColors.text),
                const SizedBox(width: 6),
                Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(fontSize: 13, color: AppColors.text),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
