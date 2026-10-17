import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/agent_provider.dart' show PromptMode;
import '../../../data/providers.dart';
import '../../../ui/shell/navigation.dart';
import '../../../ui/theme/tokens.dart';
import '../../prompt/conversation_manager.dart';
import '../../sessions/timeline.dart';
import '../../sessions/timeline_provider.dart';
import '../../sessions/widgets/session_style.dart';

/// Pending `SPEC SUGESTÃO` of the workspace's specs.
final pendingSuggestionsProvider =
    StreamProvider.family<List<SpecSuggestion>, int>(
      (ref, workspaceId) =>
          ref.watch(specSuggestionsRepoProvider).watchPending(workspaceId),
    );

/// `Bash · flutter test` of the last tool call of [items] (null = none).
String? lastToolLine(List<TimelineItem> items, {String? root}) {
  for (final i in items.reversed) {
    if (i is ToolItem) {
      final target = toolTarget(i.name, i.input, root: root);
      return target.isEmpty ? i.name : '${i.name} · $target';
    }
  }
  return null;
}

/// Card line of a running session: its last tool call (from the live
/// timeline the manager already feeds) and the time in the step.
class LiveToolLine extends ConsumerWidget {
  const LiveToolLine({
    super.key,
    required this.session,
    required this.specCode,
  });

  final Session session;
  final String specCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(sessionTimelineProvider(session.id)).items;
    final line = lastToolLine(items, root: session.worktreePath);
    if (line == null) return const SizedBox.shrink();
    return Text(
      line,
      key: ValueKey('board-live-$specCode'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontFamily: AppFonts.mono,
        fontSize: 10,
        color: AppColors.teal,
      ),
    );
  }
}

/// First message of "Aplicar" on a suggestion: a Refinar conversation that
/// edits only the steps not done yet.
String applySuggestionPrompt(Spec spec, SpecSuggestion s) =>
    'Aplique à spec @${spec.path} (${spec.code}) a sugestão da sessão '
    '${s.steps == null ? '' : 'das etapas ${s.steps} '}: "${s.body}". '
    'Altere só requisitos que ainda não foram feitos (os feitos já têm '
    'commit nesta branch) e mantenha o formato "- Rn · texto" e o '
    'frontmatter. Antes de editar, resuma o que pretende mudar.';

/// Suggestions of the card's spec: Aplicar (opens Refinar in Prompt) /
/// Ignorar.
class SuggestionBanner extends ConsumerWidget {
  const SuggestionBanner({super.key, required this.spec});

  final Spec spec;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all =
        ref.watch(pendingSuggestionsProvider(spec.workspaceId)).value ??
        const <SpecSuggestion>[];
    final mine = [
      for (final s in all)
        if (s.specId == spec.id) s,
    ];
    if (mine.isEmpty) return const SizedBox.shrink();
    final s = mine.first;
    final repo = ref.read(specSuggestionsRepoProvider);
    return Container(
      key: ValueKey('board-suggestion-${spec.code}'),
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: SessionColors.approvalBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: SessionColors.approvalBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sugestão da sessão${s.steps == null ? '' : ' (${s.steps})'}'
            '${mine.length > 1 ? ' · +${mine.length - 1}' : ''}',
            style: const TextStyle(fontSize: 10, color: AppColors.amber),
          ),
          const SizedBox(height: 2),
          Text(
            s.body,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppColors.text),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              SmallButton(
                key: ValueKey('board-suggestion-apply-${spec.code}'),
                label: 'Aplicar',
                height: 24,
                onTap: () async {
                  final ws = await ref
                      .read(workspacesRepoProvider)
                      .getById(spec.workspaceId);
                  if (ws == null) return;
                  final id = await ref
                      .read(conversationManagerProvider.notifier)
                      .create(
                        workspace: ws,
                        text: applySuggestionPrompt(spec, s),
                        mode: PromptMode.refine,
                      );
                  await repo.setState(s.id, 'aplicada');
                  ref.read(selectedConversationProvider.notifier).select(id);
                  ref.read(navigationProvider.notifier).go(AppSection.prompt);
                },
              ),
              const SizedBox(width: 6),
              SmallButton(
                key: ValueKey('board-suggestion-ignore-${spec.code}'),
                label: 'Ignorar',
                height: 24,
                onTap: () => repo.setState(s.id, 'ignorada'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
