import 'package:flutter/material.dart';

import '../../../data/db/enums.dart';
import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_pressable.dart';

/// What the list shows for a session (DB status + whether the process lives).
enum SessionLook {
  running('Executando', AppColors.teal),
  waiting('Aguardando', AppColors.amber),
  idle('Ociosa', AppColors.blue),
  done('Concluída', AppColors.blue),
  failed('Falhou', AppColors.red),
  interrupted('Interrompida', AppColors.textMuted),
  stopped('Parada', AppColors.textMuted),
  merged('Merge feito', AppColors.teal);

  const SessionLook(this.label, this.color);

  final String label;
  final Color color;

  /// `completed` with a live process = idle (waiting for the next message).
  static SessionLook of(SessionStatus s, {required bool alive}) => switch (s) {
    SessionStatus.running => alive ? running : interrupted,
    SessionStatus.waitingApproval => alive ? waiting : interrupted,
    SessionStatus.completed => alive ? idle : done,
    SessionStatus.failed => failed,
    SessionStatus.interrupted => interrupted,
    SessionStatus.stopped => stopped,
    SessionStatus.merged => merged,
  };
}

String formatCost(double v) => '\$${v.toStringAsFixed(2)}';

/// `12m 40s`, `1h 05m`, `45s`.
String formatDuration(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  if (h > 0) return '${h}h ${two(m)}m';
  if (m > 0) return '${m}m ${two(s)}s';
  return '${s}s';
}

/// Compact age for the list: `3m`, `2h`, `4d`.
String formatAge(Duration d) {
  if (d.inDays > 0) return '${d.inDays}d';
  if (d.inHours > 0) return '${d.inHours}h';
  if (d.inMinutes > 0) return '${d.inMinutes}m';
  return '${d.inSeconds < 0 ? 0 : d.inSeconds}s';
}

String formatClock(DateTime? t) {
  if (t == null) return '';
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(l.hour)}:${two(l.minute)}';
}

const sectionTitleStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.8,
  color: AppColors.textSecondary,
);

class Dot extends StatelessWidget {
  const Dot(this.color, {super.key, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// 30px bordered button of the mockups (header actions, Negar).
class SmallButton extends StatelessWidget {
  const SmallButton({
    super.key,
    required this.label,
    required this.onTap,
    this.color = AppColors.text,
    this.border = AppColors.border,
    this.background = AppColors.panel,
    this.height = 30,
    this.fontSize = 12,
    this.expand = false,
    this.semanticLabel,
    this.focusColor,
    this.icon,
    this.trailing,
    this.fontWeight,
  });

  final String label;
  final VoidCallback? onTap;
  final FontWeight? fontWeight;

  /// Optional icon before the label and widget after it (`Ctrl+S`).
  final IconData? icon;
  final Widget? trailing;

  /// Accessible label (SPEC-021 R11); null keeps the visible [label].
  final String? semanticLabel;

  /// Highlight while focused by keyboard (null = theme default).
  final Color? focusColor;
  final Color color;
  final Color border;
  final Color background;
  final double height;
  final double fontSize;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(6);
    final enabled = onTap != null;
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
      ),
    );
    final button = Opacity(
      opacity: enabled ? 1 : 0.5,
      child: AppPressable(
        enabled: enabled,
        borderRadius: radius,
        hoverTint: AppPressable.tint,
        hoverBorder: border == AppColors.border ? AppColors.borderHover : null,
        child: Material(
          color: background,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: border),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            focusColor: focusColor,
            hoverColor: Colors.transparent,
            child: Container(
              height: height,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              width: expand ? double.infinity : null,
              child: icon == null && trailing == null
                  ? (semanticLabel == null
                        ? text
                        : ExcludeSemantics(child: text))
                  : ExcludeSemantics(
                      excluding: semanticLabel != null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, size: 14, color: color),
                            const SizedBox(width: 6),
                          ],
                          Flexible(child: text),
                          if (trailing != null) ...[
                            const SizedBox(width: 8),
                            trailing!,
                          ],
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
    if (semanticLabel == null) return button;
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: enabled,
        label: semanticLabel,
        child: button,
      ),
    );
  }
}

/// Amber primary button (Enviar, Aprovar, Criar). [busy] shows a spinner
/// before the label and ignores taps, without the disabled look.
class AmberButton extends StatelessWidget {
  const AmberButton({
    super.key,
    required this.label,
    required this.onTap,
    this.height = 30,
    this.expand = false,
    this.focusNode,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onTap;
  final double height;
  final bool expand;
  final FocusNode? focusNode;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(6);
    final tap = busy ? null : onTap;
    final text = Text(
      label,
      maxLines: 1,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.onAmber,
      ),
    );
    return Opacity(
      opacity: onTap == null && !busy ? 0.5 : 1,
      child: AppPressable(
        enabled: tap != null,
        borderRadius: radius,
        hoverTint: AppPressable.primaryTint,
        child: Material(
          color: AppColors.amber,
          shape: RoundedRectangleBorder(borderRadius: radius),
          child: InkWell(
            onTap: tap,
            focusNode: focusNode,
            borderRadius: radius,
            hoverColor: Colors.transparent,
            child: Container(
              height: height,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              width: expand ? double.infinity : null,
              child: busy
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onAmber,
                          ),
                        ),
                        const SizedBox(width: 8),
                        text,
                      ],
                    )
                  : text,
            ),
          ),
        ),
      ),
    );
  }
}

/// Grey tag of the session header (`TASK-012`, `implementer · Sonnet`).
class InfoTag extends StatelessWidget {
  const InfoTag(this.text, {super.key, this.mono = false});

  final String text;
  final bool mono;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 11,
        color: AppColors.textSecondary,
        fontFamily: mono ? AppFonts.mono : null,
      ),
    ),
  );
}
