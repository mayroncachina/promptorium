import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/agent_provider.dart' show PromptMode;
import '../../data/providers.dart';
import '../../ui/shell/navigation.dart';
import '../../ui/theme/tokens.dart';
import '../board/board_screen.dart'
    show
        boardFocusSpecProvider,
        boardGraphViewProvider,
        boardSelectedSpecProvider;
import '../specs/spec_service.dart'
    show selectedSpecProvider, specServiceProvider;
import 'conversation_manager.dart' show conversationManagerProvider;

/// Screen a refine conversation was opened from (SPEC-021).
enum RefineSource {
  /// "Refinar com IA" on the Specs screen.
  specs,

  /// "Aplicar" on a suggestion of a board card.
  board;

  /// Null for unknown values and old conversations (null column).
  static RefineSource? fromName(String? name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// Spec and screen a refine conversation came from (stored in
/// `conversations.refine_spec_code` / `refine_origin`).
typedef RefineOrigin = ({String specCode, RefineSource source});

/// Origin of a refine conversation (null for other modes and for refine
/// conversations created before SPEC-021, R6).
RefineOrigin? refineOriginOf(Conversation c) {
  if (PromptMode.fromName(c.mode) != PromptMode.refine) return null;
  final code = c.refineSpecCode;
  final source = RefineSource.fromName(c.refineOrigin);
  if (code == null || code.isEmpty || source == null) return null;
  return (specCode: code, source: source);
}

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// "Edição pendente" warning (R8): true = go back anyway.
Future<bool> _confirmPending(BuildContext context, int count) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.scrim,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('prompt-back-pending-dialog'),
      backgroundColor: AppColors.panel,
      title: const Text('Edição pendente', style: TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: Text(
          count == 1
              ? 'O agente tem uma edição aguardando a sua aprovação. Ela '
                    'continua pendente na conversa se você voltar.'
              : 'O agente tem $count edições aguardando a sua aprovação. '
                    'Elas continuam pendentes na conversa se você voltar.',
          style: const TextStyle(fontSize: 13),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('prompt-back-stay'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Ficar na conversa'),
        ),
        TextButton(
          key: const ValueKey('prompt-back-anyway'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Voltar mesmo assim'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// "Voltar à spec" (SPEC-021 R3–R5, R7, R8, R10): opens the spec [c] was
/// refining on the screen it came from, after re-reading the file from disk.
/// Only navigates: the conversation stays selected and alive, approvals stay
/// pending and no status (spec or suggestion) changes.
Future<void> backToSpec(
  BuildContext context,
  WidgetRef ref,
  Conversation c,
) async {
  final origin = refineOriginOf(c);
  if (origin == null) return;
  final code = origin.specCode;
  final ws = await ref.read(workspacesRepoProvider).getById(c.workspaceId);
  Spec? spec;
  String? text;
  if (ws != null) {
    spec = await ref.read(specsRepoProvider).getByCode(ws.id, code);
    if (spec != null) {
      try {
        text = await ref.read(specServiceProvider).read(ws, spec);
      } catch (_) {
        text = null;
      }
    }
  }
  if (!context.mounted) return;
  // R5: removed or renamed (the lookup is by the stored code).
  if (ws == null || spec == null || text == null) {
    _snack(context, 'A spec $code não foi encontrada.');
    return;
  }
  // R8: warn about edits still waiting for approval.
  final pending = ref.read(conversationManagerProvider).approvalsOf(c.id);
  if (pending.isNotEmpty && !await _confirmPending(context, pending.length)) {
    return;
  }
  try {
    await ref.read(specServiceProvider).sync(ws);
  } catch (e) {
    if (context.mounted) _snack(context, 'Falha ao ler specs/: $e');
    return;
  }
  ref.read(selectedSpecProvider.notifier).select(spec.id);
  final nav = ref.read(navigationProvider.notifier);
  switch (origin.source) {
    case RefineSource.specs:
      // The Specs screen is mounted again and its `_load` reads the file.
      nav.go(AppSection.specs);
    case RefineSource.board:
      ref.read(boardGraphViewProvider.notifier).set(false);
      ref.read(boardSelectedSpecProvider.notifier).select(spec.id);
      ref.read(boardFocusSpecProvider.notifier).select(spec.id);
      nav.go(AppSection.tasks);
  }
}
