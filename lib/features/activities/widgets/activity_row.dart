import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/providers/provider_logos.dart';
import '../../../ui/theme/tokens.dart';
import '../activity.dart';
import '../activity_actions.dart';
import 'robot_avatar.dart';

/// One line of the Atividades (SPEC-076 R18, R19, R21).

/// Widths of the columns (the canvas' grid).
const _robotW = 28.0;
const _activityW = 250.0;
const _stateW = 150.0;
const _timeW = 56.0;
const _useW = 56.0;
const _actionW = 96.0;

/// `4 min`, `1 h 12`, `agora`.
String activityElapsed(DateTime? since, DateTime now) {
  if (since == null) return '—';
  final m = now.difference(since).inMinutes;
  if (m < 1) return 'agora';
  if (m < 60) return '$m min';
  final rest = m % 60;
  return rest == 0
      ? '${m ~/ 60} h'
      : '${m ~/ 60} h ${rest.toString().padLeft(2, '0')}';
}

/// The robot's name in front of the subtitle (`Bruno · Em execução`),
/// and who works when it is not the Claude Code (`Codex · gpt-6.1-terra`,
/// SPEC-101 R15).
String activitySubtitle(Activity a) => [
  if (a.seed != null) RobotIdentity.of(a.seed!).name,
  if (a.subtitle.isNotEmpty) a.subtitle,
  if (a.provider case final p? when p != 'claude')
    providerModelLabel(p, a.model),
].join(' · ');

/// What a screen reader says of the line (R21).
String activitySemantics(Activity a, DateTime now) => [
  a.title,
  switch (a.column) {
    ActivityColumn.backlog => 'na fila',
    ActivityColumn.running => 'em execução',
    ActivityColumn.review => 'em review',
  },
  if (a.needsYou) 'precisa de você',
  a.status,
  if (a.startedAt != null) activityElapsed(a.startedAt, now),
].join(', ');

IconData activityIcon(ActivityKind k) => switch (k) {
  ActivityKind.release => Icons.sell_outlined,
  ActivityKind.dev => Icons.terminal,
  _ => Icons.smart_toy_outlined,
};

/// The header of the columns.
class ActivityHeaderRow extends StatelessWidget {
  const ActivityHeaderRow({super.key});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      letterSpacing: .8,
      color: AppColors.textMuted,
    );
    return const Padding(
      padding: EdgeInsets.fromLTRB(18, 10, 18, 8),
      child: Row(
        children: [
          SizedBox(width: _robotW + 10),
          SizedBox(
            width: _activityW,
            child: Text('ATIVIDADE', style: style),
          ),
          SizedBox(
            width: _stateW,
            child: Text('ESTADO', style: style),
          ),
          SizedBox(
            width: _timeW,
            child: Text('TEMPO', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(width: 12),
          Expanded(child: Text('ÚLTIMA AÇÃO', style: style)),
          SizedBox(
            width: _useW,
            child: Text('USO', style: style, textAlign: TextAlign.right),
          ),
          SizedBox(width: _actionW),
        ],
      ),
    );
  }
}

class ActivityRow extends ConsumerWidget {
  const ActivityRow({
    super.key,
    required this.activity,
    required this.selected,
    required this.now,
    required this.onTap,
    this.showWorkspace = false,
  });

  final Activity activity;
  final bool selected;
  final DateTime now;
  final VoidCallback onTap;

  /// Without groups, the workspace goes in the subtitle.
  final bool showWorkspace;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = activity;
    final tone = switch (a.tone) {
      ActivityTone.attention => AppColors.amber,
      ActivityTone.error => AppColors.red,
      ActivityTone.normal => AppColors.text,
    };
    final bg = a.needsYou
        ? (a.error ? AppColors.red : AppColors.amber).withValues(alpha: .05)
        : null;
    final sub = [
      if (showWorkspace) a.workspaceName,
      activitySubtitle(a),
    ].where((e) => e.isNotEmpty).join(' · ');
    return Semantics(
      selected: selected,
      button: true,
      label: activitySemantics(a, now),
      child: Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Material(
          color: selected
              ? AppColors.amber.withValues(alpha: .07)
              : bg ?? Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: onTap,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: selected
                      ? AppColors.amber.withValues(alpha: .4)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: _robotW,
                    child: Center(
                      child: a.seed != null
                          ? RobotAvatar(
                              seed: a.seed!,
                              pose: a.pose,
                              size: 22,
                              semanticLabel: RobotIdentity.of(a.seed!).name,
                            )
                          : Icon(
                              activityIcon(a.kind),
                              size: 16,
                              color: AppColors.textSecondary,
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: _activityW,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _Tag(a.kind.tag),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                a.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: _stateW,
                    child: _State(activity: a, color: tone),
                  ),
                  SizedBox(
                    width: _timeW,
                    child: Text(
                      activityElapsed(a.startedAt, now),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      a.lastAction ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 11.5,
                        color: a.error
                            ? AppColors.red
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _useW,
                    child: Text(
                      a.calls == null || a.calls == 0 ? '—' : '${a.calls} ch.',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _actionW,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _RowAction(activity: a),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 9.5,
        fontWeight: FontWeight.w600,
        color: AppColors.amberLight,
      ),
    ),
  );
}

class _State extends StatelessWidget {
  const _State({required this.activity, required this.color});

  final Activity activity;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final p = a.progress;
    final label = Text(
      a.status,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11.5, color: color),
    );
    if (a.needsYou) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(5),
          ),
          child: label,
        ),
      );
    }
    if (p == null) return label;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label,
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Tooltip(
            message: p.label,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: p.value.clamp(.04, 1),
                minHeight: 3,
                backgroundColor: Colors.white.withValues(alpha: .08),
                color: a.kind == ActivityKind.gate
                    ? AppColors.blue
                    : AppColors.teal,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RowAction extends ConsumerWidget {
  const _RowAction({required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = activity;
    if (a.action == ActivityAction.none) return const SizedBox.shrink();
    if (a.action == ActivityAction.stop) {
      return Tooltip(
        message: 'Parar',
        child: SizedBox(
          width: 26,
          height: 26,
          child: OutlinedButton(
            key: ValueKey('activity-action-${a.id}'),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: () => runActivityAction(context, ref, a),
            child: const Icon(Icons.stop, size: 13, color: AppColors.text),
          ),
        ),
      );
    }
    final strong =
        a.action == ActivityAction.respond ||
        a.action == ActivityAction.viewPlan;
    final color = a.error ? AppColors.red : AppColors.amber;
    return SizedBox(
      height: 26,
      child: OutlinedButton(
        key: ValueKey('activity-action-${a.id}'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          foregroundColor: strong || a.error ? color : AppColors.text,
          side: BorderSide(
            color: strong || a.error
                ? color.withValues(alpha: .55)
                : AppColors.border,
          ),
          textStyle: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        onPressed: () => runActivityAction(context, ref, a),
        child: Text(a.action.label),
      ),
    );
  }
}
