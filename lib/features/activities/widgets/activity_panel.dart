import 'package:flutter/material.dart';

import '../../../ui/providers/provider_logos.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ui/theme/tokens.dart';
import '../../../ui/widgets/app_dialog.dart';
import '../../prompt/conversation_manager.dart';
import '../../sessions/session_manager.dart';
import '../../sessions/widgets/session_style.dart'
    show AmberButton, SmallButton;
import '../activity.dart';
import '../activity_actions.dart';
import '../automation_pause.dart';
import 'activity_row.dart';
import 'robot_avatar.dart';

/// The selected activity (SPEC-076 R20): who it is, what it is doing now
/// and the buttons.
class ActivityPanel extends ConsumerWidget {
  const ActivityPanel({super.key, required this.activity, required this.now});

  final Activity activity;
  final DateTime now;

  String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = activity;
    final name = a.seed == null ? null : RobotIdentity.of(a.seed!).name;
    final hasTurn = a.sessionId != null || a.conversationId != null;
    final live = a.id.startsWith('session:') || a.id.startsWith('conv:');
    final paused =
        a.sessionId != null &&
        ref.watch(pauseAfterTurnProvider).contains(a.sessionId);
    final canPause =
        a.sessionId != null &&
        a.specId != null &&
        a.id.startsWith('session:') &&
        !a.error;

    Widget fact(String label, String value, {Widget? child, Key? key}) =>
        Padding(
          key: key,
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child:
                    child ??
                    Text(
                      value,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppFonts.mono,
                        fontSize: 11.5,
                      ),
                    ),
              ),
            ],
          ),
        );

    return Column(
      key: ValueKey('activity-panel-${a.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0E1014),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: a.seed == null
                        ? Icon(
                            activityIcon(a.kind),
                            color: AppColors.textSecondary,
                          )
                        : RobotAvatar(seed: a.seed!, pose: a.pose, size: 36),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${a.workspaceName} · ${a.kind.tag}'.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .8,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          a.title,
                          key: const ValueKey('activity-panel-title'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            ?name,
                            a.status,
                            if (a.startedAt != null)
                              'há ${activityElapsed(a.startedAt, now)}',
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: switch (a.tone) {
                              ActivityTone.attention => AppColors.amber,
                              ActivityTone.error => AppColors.red,
                              ActivityTone.normal => AppColors.textSecondary,
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (name != null)
                fact(
                  'Agente',
                  [
                    name,
                    ?a.agentName,
                    // SPEC-096 R3: "Codex · gpt-6.2-sol" beside the Claude.
                    a.provider == null || a.provider == 'claude'
                        ? a.model
                        : providerModelLabel(a.provider!, a.model),
                    ?a.mode,
                  ].nonNulls.join(' · '),
                ),
              if (a.branch != null) fact('Branch', a.branch!),
              if (a.tasks.isNotEmpty)
                fact(
                  'Tarefas',
                  '',
                  key: const ValueKey('activity-panel-tasks'),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        for (final (i, t) in a.tasks.indexed) ...[
                          if (i > 0) const TextSpan(text: ' · '),
                          TextSpan(
                            text: t.done ? '${t.id} ✓' : t.id,
                            style: TextStyle(
                              color: t.current
                                  ? AppColors.teal
                                  : t.done
                                  ? AppColors.textSecondary
                                  : AppColors.text,
                              fontWeight: t.current
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ],
                    ),
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              if (a.calls != null && a.calls! > 0)
                fact(
                  'Neste turno',
                  [
                    '${a.calls} ${a.calls == 1 ? 'chamada' : 'chamadas'}',
                    if (a.files != null && a.files! > 0)
                      '${a.files} ${a.files == 1 ? 'arquivo' : 'arquivos'}',
                  ].join(' · '),
                ),
              if (a.weight != null)
                fact(
                  'Peso na janela de 5 h',
                  '≈ ${(a.weight! * 100).round()}%',
                ),
              if (a.progress case final p?) fact('Progresso', p.label),
              if (a.specId != null) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('activity-panel-board'),
                    onPressed: () => openInBoard(ref, a),
                    icon: const Icon(Icons.view_kanban_outlined, size: 15),
                    label: const Text(
                      'Ver no Quadro',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
              if (a.recent.isNotEmpty || a.lastText != null) ...[
                const SizedBox(height: 10),
                const Text(
                  'AGORA',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .8,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                for (final r in a.recent)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 44,
                          child: Text(
                            _hhmm(r.at),
                            style: const TextStyle(
                              fontFamily: AppFonts.mono,
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            r.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppFonts.mono,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (a.lastText case final t?)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 44),
                    child: Text(
                      '"$t"',
                      key: const ValueKey('activity-panel-text'),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: AmberButton(
                      key: const ValueKey('activity-panel-open'),
                      label: a.conversationId != null
                          ? 'Abrir conversa'
                          : a.sessionId != null
                          ? 'Abrir sessão'
                          : 'Abrir',
                      expand: true,
                      height: 34,
                      onTap: () => openActivity(ref, a),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SmallButton(
                    key: const ValueKey('activity-panel-message'),
                    label: 'Mensagem…',
                    height: 34,
                    onTap: hasTurn && live
                        ? () => _message(context, ref, a)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SmallButton(
                      key: const ValueKey('activity-panel-pause'),
                      label: paused
                          ? 'Pausa após o turno ✓'
                          : 'Pausar após o turno',
                      expand: true,
                      height: 34,
                      color: paused ? AppColors.amber : AppColors.text,
                      onTap: canPause
                          ? () => ref
                                .read(pauseAfterTurnProvider.notifier)
                                .toggle(a.sessionId!)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SmallButton(
                    key: const ValueKey('activity-panel-stop'),
                    label: 'Parar',
                    height: 34,
                    color: AppColors.red,
                    border: AppColors.red.withValues(alpha: .5),
                    onTap: a.action == ActivityAction.stop || (live && !a.error)
                        ? () => runActivityAction(
                            context,
                            ref,
                            a,
                            ActivityAction.stop,
                          )
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// "Mensagem…": one message to the session or conversation, without
  /// leaving the Atividades.
  Future<void> _message(BuildContext context, WidgetRef ref, Activity a) async {
    final ctl = TextEditingController();
    final text = await showAppDialog<String>(
      context: context,
      barrierColor: AppColors.scrim,
      builder: (context) => AlertDialog(
        key: const ValueKey('activity-message-dialog'),
        backgroundColor: AppColors.panel,
        title: Text(
          'Mensagem para ${a.specCode ?? a.title}',
          style: const TextStyle(fontSize: 15),
        ),
        content: SizedBox(
          width: 420,
          child: TextField(
            key: const ValueKey('activity-message-field'),
            controller: ctl,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              hintText: 'Vai para o agente quando o turno atual acabar.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('activity-message-send'),
            onPressed: () => Navigator.of(context).pop(ctl.text),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (text == null || text.trim().isEmpty) return;
    if (a.conversationId case final c?) {
      await ref.read(conversationManagerProvider.notifier).send(c, text);
    } else if (a.sessionId case final s?) {
      await ref.read(sessionManagerProvider.notifier).send(s, text);
    }
  }
}
