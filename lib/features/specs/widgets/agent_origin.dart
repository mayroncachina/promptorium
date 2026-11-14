import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/session_manager.dart'
    show selectedSessionProvider, sessionTitle;

/// "Criada pelo agente" (SPEC-052 R6): a spec written through the
/// Promptorium MCP.
class AgentCreatedChip extends StatelessWidget {
  const AgentCreatedChip({super.key, this.small = false});

  final bool small;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8, vertical: 1),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.lilac.withValues(alpha: .6)),
    ),
    child: Text(
      'Criada pelo agente',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: small ? 10 : 11, color: AppColors.lilac),
    ),
  );
}

/// The session behind [sessionId] (null: a Prompt conversation or gone).
final _agentSessionProvider = FutureProvider.autoDispose
    .family<Session?, String>(
      (ref, sessionId) => ref.read(sessionsRepoProvider).getById(sessionId),
    );

String _when(DateTime at, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final hour =
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(n.year, n.month, n.day);
  if (day == today) return 'hoje às $hour';
  if (today.difference(day).inDays == 1) return 'ontem às $hour';
  return 'em ${at.day.toString().padLeft(2, '0')}/'
      '${at.month.toString().padLeft(2, '0')} às $hour';
}

/// Strip above the editor of a spec the agent created (SPEC-052 R6): the
/// session, a link to it, and its children (the specs that depend on it).
/// Deleting the draft is the usual action of the header.
class AgentOriginBanner extends ConsumerWidget {
  const AgentOriginBanner({super.key, required this.spec});

  final Spec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = spec.agentSession;
    if (id == null) return const SizedBox.shrink();
    final session = ref.watch(_agentSessionProvider(id)).value;
    final all = ref.watch(specsProvider(spec.workspaceId)).value ?? const [];
    final children = [
      for (final s in all)
        if (s.dependsOn.contains(spec.code)) s,
    ];
    final where = session == null
        ? 'numa conversa do Prompt'
        : 'na sessão “${sessionTitle(session)}”, ${_when(session.startedAt)}';
    final draft = spec.status == SpecStatus.draft;
    return Container(
      key: const ValueKey('spec-agent-origin'),
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.lilac.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.lilac.withValues(alpha: .4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 16, color: AppColors.lilac),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Criada pelo agente $where.'
                  '${draft ? ' É um rascunho: nada roda até você aprovar.' : ''}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (session != null)
                TextButton(
                  key: const ValueKey('spec-agent-open-session'),
                  onPressed: () {
                    ref.read(selectedSessionProvider.notifier).select(id);
                    ref
                        .read(navigationProvider.notifier)
                        .go(AppSection.sessions);
                  },
                  child: const Text(
                    'Abrir a sessão',
                    style: TextStyle(
                      fontSize: 12,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
            ],
          ),
          if (children.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Filhas · ${children.length}: '
              '${children.map((c) => '${c.code} ${c.title}').join(' · ')}',
              key: const ValueKey('spec-agent-children'),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
