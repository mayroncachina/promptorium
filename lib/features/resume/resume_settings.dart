import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repos/activity_events_repo.dart';
import '../../ui/theme/tokens.dart';
import '../agents/widgets/agent_style.dart';
import '../settings/settings_choices.dart';
import '../sessions/widgets/session_style.dart' show SmallButton;
import 'presence.dart';
import 'resume_summary.dart';

/// Configurações › Retomar de onde parei (SPEC-080 R14): when to show the
/// card, the time away, what enters "Terminou", the last seen time and
/// "Limpar o diário".

/// The choices of "Mostrar ao voltar depois de" (minutes; 0 = never).
const resumeAwayChoices = [15, 30, 60, 120, 0];

String awayChoiceLabel(int m) => switch (m) {
  0 => 'nunca',
  60 => '1 h',
  120 => '2 h',
  _ => '$m min',
};

/// The size of the journal.
final journalCountProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(activityEventsRepoProvider).watchCount(),
);

/// `hoje 09:12`, `ontem 21:02`, `—`.
String lastSeenLabel(DateTime? at, DateTime now) {
  if (at == null) return '—';
  final t = resumeTime(at, now);
  return t.contains(' ') ? t : 'hoje $t';
}

class ResumeSettingsView extends ConsumerWidget {
  const ResumeSettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final ctl = ref.read(appSettingsProvider.notifier);
    final onOpen = settings[AppSettingKeys.resumeOnOpen] != '0';
    final limit = awayLimitOf(settings);
    final minutes = limit?.inMinutes ?? 0;
    final hidden = ResumeKindGroup.decode(
      settings[AppSettingKeys.resumeHiddenKinds],
    );
    final presence = ref.watch(presenceProvider);
    final count = ref.watch(journalCountProvider).value ?? 0;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AgentCard(
          title: 'Mostrar ao abrir o app',
          children: [
            choices(
              keyPrefix: 'resume-open',
              values: const [('on', 'Ligado'), ('off', 'Desligado')],
              selected: onOpen ? 'on' : 'off',
              onTap: (v) => v == 'on'
                  ? ctl.remove(AppSettingKeys.resumeOnOpen)
                  : ctl.set(AppSettingKeys.resumeOnOpen, '0'),
            ),
            const SizedBox(height: 10),
            const Text(
              'Quando o visto por último tem mais que o tempo abaixo.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
        AgentCard(
          title: 'Mostrar ao voltar depois de',
          children: [
            choices(
              keyPrefix: 'resume-away',
              values: [
                for (final m in resumeAwayChoices) ('$m', awayChoiceLabel(m)),
              ],
              selected: '$minutes',
              onTap: (v) => v == '30'
                  ? ctl.remove(AppSettingKeys.resumeAwayMinutes)
                  : ctl.set(AppSettingKeys.resumeAwayMinutes, v),
            ),
            const SizedBox(height: 10),
            const Text(
              'Sem foco na janela, ou sem nenhuma tecla, clique ou rolagem '
              'no app.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
        AgentCard(
          title: 'O que entra em "Terminou"',
          children: [
            Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                for (final k in ResumeKindGroup.values)
                  InkWell(
                    key: ValueKey('resume-kind-${k.name}'),
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      final next = {...hidden};
                      if (!next.remove(k)) next.add(k);
                      if (next.isEmpty) {
                        ctl.remove(AppSettingKeys.resumeHiddenKinds);
                      } else {
                        ctl.set(
                          AppSettingKeys.resumeHiddenKinds,
                          ResumeKindGroup.encode(next),
                        );
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: !hidden.contains(k),
                          activeColor: AppColors.amber,
                          onChanged: null,
                          fillColor: WidgetStatePropertyAll(
                            hidden.contains(k)
                                ? Colors.transparent
                                : AppColors.amber,
                          ),
                          checkColor: AppColors.backgroundSolid,
                          side: const BorderSide(color: AppColors.inputBorder),
                        ),
                        Text(k.label, style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
        AgentCard(
          title: 'Diário',
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          text: 'Visto por último: ',
                          children: [
                            TextSpan(
                              text: lastSeenLabel(presence.lastSeenAt, now),
                              style: const TextStyle(fontFamily: AppFonts.mono),
                            ),
                          ],
                        ),
                        key: const ValueKey('resume-last-seen'),
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'O diário guarda $activityJournalDays dias · '
                        '$count ${count == 1 ? 'registro' : 'registros'}',
                        key: const ValueKey('resume-journal-count'),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                SmallButton(
                  key: const ValueKey('resume-clear'),
                  label: 'Limpar o diário',
                  color: AppColors.red,
                  border: AppColors.red.withValues(alpha: .5),
                  onTap: () => ref.read(activityEventsRepoProvider).clear(),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
