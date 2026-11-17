import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../ui/shell/navigation.dart';
import '../session_manager.dart';
import '../sessions_screen.dart';
import 'replay_state.dart';
import 'replay_view.dart' show replayAvailable;

/// Every replay entry opens the same session, starting at its last step
/// (R12). Works through the container, so the caller's widget (a menu in a
/// dialog that closes) can be gone by the time the session row loads.
Future<void> openReplay(WidgetRef ref, String sessionId) => openReplayIn(
  ProviderScope.containerOf(ref.context, listen: false),
  sessionId,
);

Future<void> openReplayIn(ProviderContainer c, String sessionId) async {
  final session = await c.read(sessionsRepoProvider).getById(sessionId);
  if (session == null) return;
  if (!replayAvailable(
    session.status,
    alive: c.read(sessionManagerProvider).isAlive(sessionId),
  )) {
    return;
  }
  if (c.read(activeWorkspaceProvider)?.id != session.workspaceId) {
    await c.read(workspaceActionsProvider).select(session.workspaceId);
  }
  c.read(replayCursorProvider(sessionId).notifier).set(const ReplayCursor());
  c.read(sessionTabProvider(sessionId).notifier).set(SessionTab.replay);
  c.read(selectedSessionProvider.notifier).select(sessionId);
  c.read(splitSessionProvider.notifier).set(null);
  c.read(navigationProvider.notifier).go(AppSection.sessions);
}
