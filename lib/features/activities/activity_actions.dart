import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dev/dev_server.dart';
import '../../data/providers.dart';
import '../../ui/shell/navigation.dart';
import '../../ui/theme/tokens.dart';
import '../../ui/widgets/app_dialog.dart';
import '../../ui/widgets/app_toast.dart';
import '../board/board_screen.dart'
    show boardFocusSpecProvider, boardSelectedSpecProvider;
import '../prompt/compare/compare_controller.dart';
import '../prompt/conversation_manager.dart';
import '../repository/releases/release_dispatcher.dart';
import '../repository/repository_screen.dart' show repositoryTabProvider;
import '../review/ci_fixer.dart';
import '../review/pr_babysitter.dart';
import '../sessions/session_manager.dart';
import 'activity.dart';

/// What the buttons of an activity do (SPEC-076 R13, R19), in the Quadro's
/// balloon and in the Atividades.

/// Opens the workspace of [a] first: its session, conversation or card
/// lives there.
Future<void> _enter(WidgetRef ref, Activity a) async {
  final active = ref.read(activeWorkspaceProvider);
  if (active?.id != a.workspaceId) {
    await ref.read(workspaceActionsProvider).select(a.workspaceId);
  }
}

/// Abrir sessão / Responder: the session, or the conversation in Prompt.
Future<void> openActivity(WidgetRef ref, Activity a) async {
  await _enter(ref, a);
  final nav = ref.read(navigationProvider.notifier);
  if (a.conversationId case final c?) {
    ref.read(selectedConversationProvider.notifier).select(c);
    nav.go(AppSection.prompt);
  } else if (a.sessionId case final s?) {
    ref.read(selectedSessionProvider.notifier).select(s);
    nav.go(AppSection.sessions);
  } else if (a.kind == ActivityKind.release) {
    ref.read(repositoryTabProvider.notifier).select('releases');
    nav.go(AppSection.repository);
  } else if (a.kind == ActivityKind.planner) {
    nav.go(a.title == 'Nova spec' ? AppSection.specs : AppSection.project);
  } else if (a.specId != null) {
    await openInBoard(ref, a);
  }
}

/// "Ver no Quadro" (R23): the workspace's Quadro with the card in focus.
Future<void> openInBoard(WidgetRef ref, Activity a) async {
  final spec = a.specId;
  if (spec == null) return;
  await _enter(ref, a);
  ref.read(boardSelectedSpecProvider.notifier).select(spec);
  ref.read(boardFocusSpecProvider.notifier).select(spec);
  ref.read(navigationProvider.notifier).go(AppSection.tasks);
}

void _toast(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showAppToast(SnackBar(content: Text(text)));
}

/// "Parar" asks first for an agent: the turn on its way is lost (P9).
Future<bool> confirmStop(BuildContext context, Activity a) async {
  if (a.kind != ActivityKind.spec &&
      a.kind != ActivityKind.vibe &&
      a.kind != ActivityKind.prompt) {
    return true;
  }
  return await showAppDialog<bool>(
        context: context,
        barrierColor: AppColors.scrim,
        builder: (context) => AlertDialog(
          key: const ValueKey('activity-stop-dialog'),
          backgroundColor: AppColors.panel,
          title: Text(
            'Parar ${a.specCode ?? a.title}?',
            style: const TextStyle(fontSize: 15),
          ),
          content: const Text(
            'O turno em andamento é interrompido. O que já foi gravado fica.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const ValueKey('activity-stop-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Parar'),
            ),
          ],
        ),
      ) ??
      false;
}

/// Stops [a] (R19): the session or conversation, the dev server, the
/// release, the CI fix.
Future<void> stopActivity(WidgetRef ref, Activity a) async {
  switch (a.kind) {
    case ActivityKind.dev:
      final wt = a.devWorktree;
      if (wt != null) await ref.read(devServerProvider(wt)).stop();
    case ActivityKind.release:
      await ref.read(releaseDispatcherProvider.notifier).cancel(a.workspaceId);
    case ActivityKind.ciFix when !a.id.startsWith('session:'):
      final s = a.sessionId;
      if (s != null) await ref.read(ciFixerProvider.notifier).cancel(s);
    default:
      if ((a.conversationId, a.compareSide) case (final c?, final side?)) {
        await ref.read(compareControllerProvider.notifier).stop(c, side);
      } else if (a.conversationId case final c?) {
        await ref.read(conversationManagerProvider.notifier).stop(c);
      } else if (a.sessionId case final s?) {
        await ref.read(sessionManagerProvider.notifier).stop(s);
      }
  }
}

/// The button of the row / balloon.
Future<void> runActivityAction(
  BuildContext context,
  WidgetRef ref,
  Activity a, [
  ActivityAction? action,
]) async {
  try {
    switch (action ?? a.action) {
      case ActivityAction.respond || ActivityAction.viewPlan:
        await openActivity(ref, a);
      case ActivityAction.resume:
        final s = a.sessionId;
        if (s == null) {
          await openInBoard(ref, a);
        } else {
          await ref.read(sessionManagerProvider.notifier).continueSession(s);
          if (context.mounted) {
            _toast(context, 'Retomando ${a.specCode ?? a.title}');
          }
        }
      case ActivityAction.stop:
        if (!await confirmStop(context, a)) return;
        await stopActivity(ref, a);
      case ActivityAction.now:
        final s = a.sessionId;
        if (s != null) await ref.read(prBabysitterProvider.notifier).check(s);
      case ActivityAction.none:
        await openActivity(ref, a);
    }
  } on Exception catch (e) {
    if (context.mounted) _toast(context, '$e');
  }
}
