import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../activities_state.dart';
import '../activity.dart';
import '../activity_actions.dart';
import 'robot_avatar.dart';

/// The robots in the Quadro (SPEC-076 R12–R14): the robot of the agent of a
/// card, the balloon of its request and the count in the bar.

/// What matters on a card first: a request or an error, then the turn
/// running, the gate, the CI fix, the PR, the queue.
int _cardRank(Activity a) {
  if (a.needsYou) return 0;
  return switch (a.kind) {
    ActivityKind.spec || ActivityKind.vibe || ActivityKind.prompt => 1,
    ActivityKind.ciFix => a.id.startsWith('session:') ? 1 : 3,
    ActivityKind.gate => 2,
    ActivityKind.pr => 4,
    ActivityKind.queued => 5,
    _ => 6,
  };
}

/// The activity a card shows (null = no robot: nothing live, or Feito).
Activity? cardActivityOf(Iterable<Activity> all, int specId) {
  Activity? best;
  for (final a in all) {
    if (a.specId != specId || !a.hasRobot) continue;
    if (best == null || _cardRank(a) < _cardRank(best)) best = a;
  }
  return best;
}

/// What a card needs from its activity; a record, so a rebuild only
/// happens when something on the card changes.
typedef CardRobotState = ({
  String id,
  String seed,
  ActivityPose pose,
  String label,
  bool needsYou,
  bool error,
  String status,
  String? request,
  ActivityAction action,
});

final cardRobotProvider = Provider.autoDispose.family<CardRobotState?, int>((
  ref,
  specId,
) {
  final a = ref.watch(
    activitiesProvider.select((all) {
      final a = cardActivityOf(all, specId);
      if (a == null) return null;
      return (
        id: a.id,
        seed: a.seed!,
        pose: a.pose,
        label: a.robotLabel ?? RobotIdentity.of(a.seed!).name,
        needsYou: a.needsYou,
        error: a.error,
        status: a.status,
        request: a.lastAction,
        action: a.action,
      );
    }),
  );
  return a;
});

/// The robot on the top right of a card, with its name below (R13). A
/// card in Review with nothing live has its robot waiting for your review
/// (the clipboard); Feito has none (R12).
class CardRobot extends ConsumerWidget {
  const CardRobot({
    super.key,
    required this.specId,
    required this.workspaceId,
    required this.code,
    required this.stage,
    this.onTap,
  });

  final int specId;
  final int workspaceId;
  final String code;
  final SpecStage stage;

  /// Opens the Atividades on this agent (R23).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (stage == SpecStage.done) return const SizedBox.shrink();
    var r = ref.watch(cardRobotProvider(specId));
    if (r == null && stage == SpecStage.review) {
      final seed = specSeed(workspaceId, code);
      r = (
        id: 'review:$specId',
        seed: seed,
        pose: ActivityPose.wait,
        label: RobotIdentity.of(seed).name,
        needsYou: false,
        error: false,
        status: 'esperando a sua revisão',
        request: null,
        action: ActivityAction.none,
      );
    }
    if (r == null) return const SizedBox.shrink();
    final name = RobotIdentity.of(r.seed).name;
    final robot = Tooltip(
      message: '$name · ${r.status}',
      child: Column(
        key: ValueKey('card-robot-$code'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF0E1014),
              borderRadius: BorderRadius.circular(8),
            ),
            child: RobotAvatar(
              seed: r.seed,
              pose: r.pose,
              size: 26,
              semanticLabel: '$name, ${r.status}',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            r.label,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
    if (onTap == null || r.id.startsWith('review:')) return robot;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: robot),
    );
  }
}

/// The request of the agent inside the card, with its button (R13):
/// "quer executar `flutter test` · Responder", "parou: … · Retomar".
class CardBalloon extends ConsumerWidget {
  const CardBalloon({super.key, required this.specId, required this.code});

  final int specId;
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(cardRobotProvider(specId));
    if (r == null || !r.needsYou) return const SizedBox.shrink();
    final err = r.error;
    final fg = err ? AppColors.red : AppColors.amberLight;
    final action = r.action == ActivityAction.none
        ? null
        : r.action == ActivityAction.stop
        ? null
        : r.action;
    return Container(
      key: ValueKey('card-balloon-$code'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(9, 5, 5, 5),
      decoration: BoxDecoration(
        color: (err ? AppColors.red : AppColors.amber).withValues(
          alpha: err ? .1 : .12,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (err ? AppColors.red : AppColors.amber).withValues(alpha: .35),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: err ? 'parou: ${r.status}' : r.status,
                    style: TextStyle(color: fg, fontWeight: FontWeight.w500),
                  ),
                  if (r.request != null && !err) ...[
                    const TextSpan(text: '  '),
                    TextSpan(
                      text: r.request,
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 10.5,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 6),
            SizedBox(
              height: 24,
              child: FilledButton(
                key: ValueKey('card-balloon-action-$code'),
                style: FilledButton.styleFrom(
                  backgroundColor: err
                      ? AppColors.red.withValues(alpha: .18)
                      : AppColors.amber,
                  foregroundColor: err
                      ? AppColors.red
                      : const Color(0xFF1A1206),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  textStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: () {
                  final a = cardActivityOf(
                    ref.read(activitiesProvider),
                    specId,
                  );
                  if (a != null) runActivityAction(context, ref, a);
                },
                child: Text(action.label),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `4 agentes trabalhando · 2 precisam de você` of a workspace (R14).
String boardAgentsLabel(Iterable<Activity> all, int workspaceId) {
  final mine = all.where((a) => a.workspaceId == workspaceId && a.hasRobot);
  final working = mine
      .where(
        (a) =>
            !a.needsYou &&
            a.column != ActivityColumn.backlog &&
            a.pose != ActivityPose.wait,
      )
      .length;
  final waiting = mine.where((a) => a.needsYou).length;
  return [
    if (working > 0)
      '$working ${working == 1 ? 'agente trabalhando' : 'agentes trabalhando'}',
    if (waiting > 0)
      '$waiting ${waiting == 1 ? 'precisa de você' : 'precisam de você'}',
  ].join(' · ');
}

/// The count of the Quadro's bar.
class BoardAgentsCount extends ConsumerWidget {
  const BoardAgentsCount({super.key, required this.workspaceId});

  final int workspaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = ref.watch(
      activitiesProvider.select((all) => boardAgentsLabel(all, workspaceId)),
    );
    if (label.isEmpty) return const SizedBox.shrink();
    final parts = label.split(' · ');
    final ask = parts.last.contains('precis') ? parts.last : null;
    final work = ask == null
        ? label
        : parts.first == ask
        ? null
        : parts.first;
    return Text.rich(
      TextSpan(
        children: [
          if (work != null) TextSpan(text: work),
          if (work != null && ask != null) const TextSpan(text: ' · '),
          if (ask != null)
            TextSpan(
              text: ask,
              style: const TextStyle(color: AppColors.amber),
            ),
        ],
      ),
      key: const ValueKey('board-agents'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
    );
  }
}
