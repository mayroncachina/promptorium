import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/theme/tokens.dart';
import '../conversation_events.dart';
import '../restore/restore_service.dart';
import '../session_manager.dart';
import '../timeline_provider.dart';
import 'session_style.dart';
import 'undo_dialog.dart';

/// "Turno 4 · 14:02".
String restorePointTitle(RestorePoint p) =>
    'Turno ${p.turn} · ${formatClock(p.startedAt)}';

/// "41 arquivos · 1 commit", "só leitura · nada mudou", "em andamento",
/// "1 arquivo · 2 não commitados guardados" (R9).
String restorePointSummary(RestorePoint p) {
  if (p.endedAt == null) return 'em andamento';
  if (p.changedFiles == 0 && p.commits == 0) return 'só leitura · nada mudou';
  final parts = <String>[
    '${p.changedFiles} arquivo${p.changedFiles == 1 ? '' : 's'}',
    if (p.commits > 0) '${p.commits} commit${p.commits == 1 ? '' : 's'}',
    if (p.files > 0)
      '${p.files} não commitado${p.files == 1 ? '' : 's'} guardado'
          '${p.files == 1 ? '' : 's'}',
  ];
  return parts.join(' · ');
}

/// Tooltip of the marker on a message (R10): "Ponto de restauração: 14:02 ·
/// 3 arquivos não commitados guardados".
String restorePointTooltip(RestorePoint p) {
  final kept = p.files == 0
      ? 'sem alterações não commitadas'
      : '${p.files} arquivo${p.files == 1 ? '' : 's'} não commitado'
            '${p.files == 1 ? '' : 's'} guardado${p.files == 1 ? '' : 's'}';
  return 'Ponto de restauração: ${formatClock(p.startedAt)} · $kept';
}

/// "Pontos de restauração" of the session's right panel (SPEC-084 R9):
/// one item per turn, newest first, at most five ("Ver todos (12)").
class RestorePointsSection extends ConsumerStatefulWidget {
  const RestorePointsSection({super.key, required this.session});

  final Session session;

  @override
  ConsumerState<RestorePointsSection> createState() =>
      _RestorePointsSectionState();
}

class _RestorePointsSectionState extends ConsumerState<RestorePointsSection> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final points =
        ref.watch(sessionRestorePointsProvider(s.id)).value ??
        const <RestorePoint>[];
    if (points.isEmpty) return const SizedBox.shrink();
    final busy = ref.watch(
      sessionManagerProvider.select((x) => x.live[s.id]?.busy ?? false),
    );
    final active = lastUndoable(points);
    // SPEC-110 R9: the points whose undo took the conversation too.
    final reverts = points.any((p) => p.state == RestoreState.undone)
        ? ref.watch(sessionTimelineProvider(s.id)).timeline.conversationReverts
        : const <int, ConversationRevert>{};
    final shown = _all ? points : points.take(5).toList();
    return Column(
      key: const ValueKey('restore-points-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        const Row(
          children: [
            Expanded(
              child: Text('PONTOS DE RESTAURAÇÃO', style: sectionTitleStyle),
            ),
            Icon(Icons.history_rounded, size: 14, color: AppColors.teal),
          ],
        ),
        const SizedBox(height: 10),
        for (final p in shown)
          _PointItem(
            key: ValueKey('restore-point-${p.turn}'),
            point: p,
            current: p.id == active?.id,
            conversation: reverts[p.id],
            onUndo: () => openUndoDialog(context, ref, session: s, point: p),
            onRedo: p.state == RestoreState.undone && p.undoneSha != null
                ? () => openUndoDialog(
                    context,
                    ref,
                    session: s,
                    point: p,
                    redo: true,
                  )
                : null,
            canUndo: p.state != RestoreState.undone,
            busy: busy,
          ),
        if (points.length > 5)
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              key: const ValueKey('restore-points-all'),
              onTap: () => setState(() => _all = !_all),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Text(
                  _all ? 'Ver menos' : 'Ver todos (${points.length})',
                  style: const TextStyle(fontSize: 12, color: AppColors.teal),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PointItem extends StatelessWidget {
  const _PointItem({
    super.key,
    required this.point,
    required this.current,
    required this.onUndo,
    required this.onRedo,
    required this.canUndo,
    required this.busy,
    this.conversation,
  });

  /// The revert of the agent's conversation made with the undo of [point].
  final ConversationRevert? conversation;
  final RestorePoint point;
  final bool current;
  final VoidCallback onUndo;
  final VoidCallback? onRedo;
  final bool canUndo;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final undone = point.state == RestoreState.undone;
    final redone = point.state == RestoreState.redone;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: current || undone ? SessionColors.selectedBg : null,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: current || undone
              ? SessionColors.selectedBorder
              : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        restorePointTitle(point),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    if (undone || redone) ...[
                      const SizedBox(width: 6),
                      _StateBadge(undone ? 'desfeito' : 'refeito'),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  restorePointSummary(point),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (undone && conversation != null)
                  Text(
                    [
                      'arquivos e conversa',
                      if (onRedo != null)
                        conversation!.copyId == null
                            ? 'sem cópia da conversa'
                            : 'Refazer usa a cópia de '
                                  '${formatClock(conversation!.copyAt)}',
                    ].join(' · '),
                    key: ValueKey('restore-conversation-${point.turn}'),
                    maxLines: 2,
                    style: const TextStyle(fontSize: 11, color: AppColors.red),
                  ),
              ],
            ),
          ),
          if (onRedo != null)
            SmallButton(
              key: ValueKey('restore-redo-${point.turn}'),
              label: 'Refazer',
              height: 26,
              onTap: busy ? null : onRedo,
            ),
          if (canUndo)
            PopupMenuButton<String>(
              key: ValueKey('restore-menu-${point.turn}'),
              tooltip: 'Opções do ponto',
              icon: const Icon(
                Icons.more_horiz,
                size: 16,
                color: AppColors.textSecondary,
              ),
              color: AppColors.panelSolid,
              onSelected: (_) => onUndo(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'undo',
                  child: Text(
                    'Voltar a antes deste turno…',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: AppColors.amber),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 11, color: AppColors.amber),
    ),
  );
}

/// "◷ ponto" beside the time of a message of the timeline (R10): the point
/// of the turn that message opened; a click opens the undo window.
class RestorePointMarker extends StatelessWidget {
  const RestorePointMarker({super.key, required this.point, this.onTap});

  final RestorePoint point;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: restorePointTooltip(point),
    child: InkWell(
      key: ValueKey('restore-marker-${point.turn}'),
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.teal.withValues(alpha: 0.6)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, size: 11, color: AppColors.teal),
            SizedBox(width: 3),
            Text(
              'ponto',
              style: TextStyle(fontSize: 10, color: AppColors.teal),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The point of each message of the timeline that opened a turn (R10): the
/// first message at or after the point was recorded (whole seconds in the
/// database), within a minute.
Map<Object, RestorePoint> restorePointsByMessage(
  List<Object> messages,
  DateTime? Function(Object m) at,
  List<RestorePoint> points,
) {
  final out = <Object, RestorePoint>{};
  final taken = <int>{};
  final sorted = [...points]
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  for (final p in sorted) {
    for (var i = 0; i < messages.length; i++) {
      if (taken.contains(i)) continue;
      final t = at(messages[i]);
      if (t == null || t.isBefore(p.startedAt)) continue;
      if (t.difference(p.startedAt) > const Duration(minutes: 1)) break;
      out[messages[i]] = p;
      taken.add(i);
      break;
    }
  }
  return out;
}
