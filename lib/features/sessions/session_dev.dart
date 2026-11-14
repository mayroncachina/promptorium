import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/worktree_setup.dart';
import '../../data/providers.dart';
import '../project/project_config.dart';

/// What a spec session needs to run the project's `dev:` (SPEC-051).
@immutable
class SessionDev {
  const SessionDev({
    required this.config,
    required this.worktree,
    required this.root,
    this.port,
    this.specCode,
  });

  final DevServerConfig config;
  final String worktree;
  final String root;

  /// `porta-base + índice`; null = the app picks a free one (P4).
  final int? port;
  final String? specCode;

  /// `worktreeEnvironment` without the port (the server sets it).
  Map<String, String> get environment =>
      worktreeEnvironment(root: root, worktree: worktree, specCode: specCode);

  @override
  bool operator ==(Object other) =>
      other is SessionDev &&
      other.config == config &&
      other.worktree == worktree &&
      other.root == root &&
      other.port == port &&
      other.specCode == specCode;

  @override
  int get hashCode => Object.hash(config, worktree, root, port, specCode);
}

/// The `dev:` of a spec session (null = no `dev:` or not a spec session:
/// the old "Abrir preview :porta" stays, R1).
final sessionDevProvider = Provider.autoDispose.family<SessionDev?, String>((
  ref,
  sessionId,
) {
  final ws = ref.watch(activeWorkspaceProvider);
  if (ws == null) return null;
  final config = ref.watch(projectConfigProvider(ws.path)).value;
  final dev = config?.dev;
  if (dev == null) return null;
  final session = (ref.watch(sessionsProvider(ws.id)).value ?? const [])
      .where((s) => s.id == sessionId)
      .firstOrNull;
  if (session == null || session.specId == null) return null;
  final spec = (ref.watch(specsProvider(ws.id)).value ?? const [])
      .where((x) => x.id == session.specId)
      .firstOrNull;
  final base = config!.worktree.basePort;
  final index = spec?.worktreeIndex;
  return SessionDev(
    config: dev,
    worktree: session.worktreePath,
    root: ws.path,
    port: base == null || index == null ? null : base + index,
    specCode: spec?.code,
  );
});
