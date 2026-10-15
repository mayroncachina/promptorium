import 'package:flutter/material.dart';

import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';

/// Small pieces shared by the steps of the Projeto screen
/// (docs/mockups/Projeto-*.dc.html, canvas "Promptorium — Novo projeto").

const projectLilac = AppColors.lilac;
const projectLilacBg = Color(0xFF1C1724);
const projectLilacBorder = Color(0xFF3B2F4A);
const projectRing = Color(0xFF3A4250);

/// Header of the main column: title, subtitle and actions.
class StepHeader extends StatelessWidget {
  const StepHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(width: 8),
          // Narrow windows: the actions wrap instead of squeezing the title.
          Flexible(
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
          ),
        ],
      ],
    ),
  );
}

/// Right column of a step (plan, CLAUDE.md, summary).
class SidePanel extends StatelessWidget {
  const SidePanel({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.footer,
    this.width = 340,
  });

  final String title;
  final Widget? trailing;
  final Widget child;
  final Widget? footer;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    decoration: const BoxDecoration(
      border: Border(left: BorderSide(color: AppColors.border)),
    ),
    // Material (not a colored box): list tiles inside paint their ink on it.
    child: Material(
      color: AppColors.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sectionTitleStyle,
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          Expanded(child: child),
          if (footer != null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: footer,
            ),
        ],
      ),
    ),
  );
}

/// "Voltar" + amber "Próximo: …" row of a step footer.
class StepNav extends StatelessWidget {
  const StepNav({
    super.key,
    this.onBack,
    required this.nextLabel,
    required this.onNext,
    this.nextKey,
  });

  final VoidCallback? onBack;
  final String nextLabel;
  final VoidCallback? onNext;
  final Key? nextKey;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (onBack != null) ...[
        SmallButton(label: 'Voltar', onTap: onBack, height: 34),
        const SizedBox(width: 8),
      ],
      Expanded(
        child: AmberButton(
          key: nextKey,
          label: nextLabel,
          onTap: onNext,
          height: 34,
          expand: true,
        ),
      ),
    ],
  );
}

/// Amber heading inside a panel (Resumo, MVP…).
class PlanHeading extends StatelessWidget {
  const PlanHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.amber,
      ),
    ),
  );
}

/// Rounded chip button (quick replies, stack alternatives).
class ChipButton extends StatelessWidget {
  const ChipButton({
    super.key,
    required this.label,
    required this.onTap,
    this.height = 28,
  });

  final String label;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: const BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.text),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lilac "AI action" button (Pedir outra proposta, Regerar com o planner).
class PlannerButton extends StatelessWidget {
  const PlannerButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SmallButton(
    label: label,
    onTap: onTap,
    color: projectLilac,
    border: projectLilacBorder,
    background: projectLilacBg,
  );
}

/// Colored box with a message (info, warning, error).
class NoticeBox extends StatelessWidget {
  const NoticeBox({
    super.key,
    required this.text,
    this.color = AppColors.teal,
    this.background = SessionColors.runningToolBg,
    this.border = SessionColors.runningToolBorder,
    this.action,
  });

  /// Amber box (warnings, open questions).
  const NoticeBox.warning({super.key, required this.text, this.action})
    : color = AppColors.amber,
      background = SessionColors.approvalBg,
      border = SessionColors.approvalBorder;

  /// Red box (failures).
  const NoticeBox.error({super.key, required this.text, this.action})
    : color = AppColors.red,
      background = SessionColors.delBg,
      border = SessionColors.stopBorder;

  final String text;
  final Color color;
  final Color background;
  final Color border;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: background,
      border: Border.all(color: border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: color, height: 1.4),
          ),
        ),
        if (action != null) ...[const SizedBox(width: 10), action!],
      ],
    ),
  );
}

/// Spinner + label while the planner runs.
class PlannerBusy extends StatelessWidget {
  const PlannerBusy(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: projectLilac),
      ),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(fontSize: 12, color: projectLilac)),
    ],
  );
}

/// Centered empty state of a step (title, text, one action).
class StepEmpty extends StatelessWidget {
  const StepEmpty({
    super.key,
    required this.title,
    required this.text,
    this.action,
  });

  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}
