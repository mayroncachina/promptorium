import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/claude/claude_args.dart';
import '../../../core/git/git_service.dart';
import '../../../core/memory/handoff.dart';
import '../../../core/providers/capabilities.dart';
import '../../../core/providers/provider_availability.dart';
import '../../../core/providers/run_intent.dart';
import '../../../data/providers.dart';
import '../../resume/activity_journal.dart';
import '../../../ui/shell/navigation.dart';
import '../session_manager.dart';
import 'continue_link.dart';
import 'session_summary.dart' show providerWords;

/// "Continuar no Codex" / "Continuar no Claude" (SPEC-099): the work of a
/// session goes to the other agent in a new session, in the same worktree
/// and branch, linked to the first one. The provider never changes in the
/// middle of a run (decision 4 of #332): the origin is ended, the new
/// session starts with an explicit handoff and nothing switches by itself.

/// The other provider of [provider] (null = none: only Claude ⇄ Codex).
String? continueTarget(String provider) => switch (provider) {
  'claude' => 'codex',
  'codex' => 'claude',
  _ => null,
};

/// "Continuar no Codex" / "Continuar no Claude".
String continueLabel(String target) =>
    target == 'codex' ? 'Continuar no Codex' : 'Continuar no Claude';

/// R1: why the action is disabled.
abstract final class ContinueReasons {
  static const busy = 'Espere o turno acabar ou pare a sessão';
  static const step =
      'Sessões de etapa trocam de provedor pela execução da spec (SPEC-101)';
  static String targetOff(String target) =>
      '${providerWords(target)} não está ligado nas Sessões';
  static const noSandboxRoot =
      'Sem o sandbox, o Codex só roda em worktree: esta sessão está na raiz';
}

/// Whether the button shows and why it is disabled (R1, P4).
@immutable
class ContinueAvailability {
  const ContinueAvailability.hidden() : visible = false, reason = null, target = null;
  const ContinueAvailability.ready(this.target) : visible = true, reason = null;
  const ContinueAvailability.disabled(this.target, this.reason)
    : visible = true;

  final bool visible;
  final String? target;

  /// Null = it can be used.
  final String? reason;

  bool get enabled => visible && reason == null;
}

/// R1: the button shows only with both providers installed, on a free
/// session (P4: hidden in step sessions, whose provider is the spec run's).
/// Disabled while the origin works or waits for an approval (decision 4),
/// or while the target is off in Sessões or not logged in.
ContinueAvailability continueAvailability({
  required Session session,
  required bool busy,
  required int approvals,
  required ProviderAvailability? origin,
  required ProviderAvailability? target,
  required ProviderFlows flows,
  required String? workspacePath,
}) {
  final to = continueTarget(session.provider);
  if (to == null) return const ContinueAvailability.hidden();
  if (session.specId != null || session.duelId != null) {
    return const ContinueAvailability.hidden();
  }
  if (session.id.startsWith(vibeSessionPrefix) ||
      session.status == SessionStatus.merged) {
    return const ContinueAvailability.hidden();
  }
  bool installed(ProviderAvailability? a) =>
      a != null && a.status != ProviderStatus.missing;
  if (!installed(origin) || !installed(target)) {
    return const ContinueAvailability.hidden();
  }
  if (busy || approvals > 0) {
    return ContinueAvailability.disabled(to, ContinueReasons.busy);
  }
  if (!flows.allows(to, AppFlow.sessions) || !target!.available) {
    return ContinueAvailability.disabled(to, ContinueReasons.targetOff(to));
  }
  if (to == 'codex' &&
      !target.sandboxAvailable &&
      session.worktreePath == workspacePath) {
    return ContinueAvailability.disabled(to, ContinueReasons.noSandboxRoot);
  }
  return ContinueAvailability.ready(to);
}

/// Decision 3 of #332: the access of the origin in the target. Perguntar
/// stays read-only, Editar writes with confirmation and YOLO only because
/// the session is in a worktree. Claude-only modes (`auto`, `dontAsk`)
/// become Editar. Without the Codex sandbox (decision 15) the Codex runs
/// only with full access in a worktree; null = it cannot run here.
ClaudePermissionMode? convertAccess(
  String? originMode, {
  required String target,
  required bool worktree,
  bool noSandbox = false,
}) {
  final access =
      AgentAccess.fromClaudeMode(ClaudePermissionMode.fromCli(originMode)) ??
      AgentAccess.edit;
  if (target == 'codex' && noSandbox) {
    return worktree ? ClaudePermissionMode.skipPermissions : null;
  }
  if (access == AgentAccess.yolo && !worktree) {
    return ClaudePermissionMode.acceptEdits;
  }
  return access.legacyMode;
}

/// "Editar · escreve com confirmação".
String accessWords(ClaudePermissionMode? mode) =>
    switch (AgentAccess.fromClaudeMode(mode) ?? AgentAccess.edit) {
      AgentAccess.ask => 'Perguntar · só leitura',
      AgentAccess.plan => 'Planejar · só leitura',
      AgentAccess.edit => 'Editar · escreve com confirmação',
      AgentAccess.refine => 'Perguntar · cada ação pede aprovação',
      AgentAccess.yolo => 'YOLO · sem aprovações, só no worktree',
    };

/// "Parser de front-matter (Codex)": the title of the new session, without
/// stacking suffixes along a chain.
String continuedTitle(String title, String target) {
  final base = title
      .replaceFirst(RegExp(r'\s*\((Codex|Claude|Claude Code)\)\s*$'), '')
      .trim();
  return '$base (${target == 'codex' ? 'Codex' : 'Claude'})';
}

/// What stays behind (R3): what only exists in the origin's provider.
typedef LeftBehind = ({String kind, String value, String tag});

List<LeftBehind> leftBehind(Session s, {String? target, double? budgetUsd}) {
  final to = target ?? continueTarget(s.provider);
  if (s.provider != 'claude' || to == 'claude') return const [];
  return [
    // Decision 7: `.claude/agents` only in Claude.
    if (s.agentName != null && s.agentName!.isNotEmpty)
      (kind: 'agente', value: s.agentName!, tag: 'Só Claude Code'),
    // Decision 5: the Codex has no cost in US$.
    if (budgetUsd != null && budgetUsd > 0)
      (
        kind: 'orçamento',
        value: 'US\$ ${budgetUsd.toStringAsFixed(2)}',
        tag: 'Só Claude Code',
      ),
  ];
}

/// The first message of the new session (R4.4, R7): it goes to the message
/// field and only leaves when the person sends it (P1).
String continueMessage({
  required String originTitle,
  required String originProvider,
  required ContinuePath path,
  Handoff? handoff,
  String? summary,
  bool cut = true,
}) {
  final from = '"$originTitle" (${providerWords(originProvider)})';
  switch (path) {
    case ContinuePath.aiMemory:
      if (handoff != null) {
        return 'Continue o trabalho da sessão $from neste worktree. A '
            'passagem ${handoff.id} do ai-memory foi entregue no início; se '
            'não estiver no seu contexto, aceite-a com memory_handoff_accept '
            'passando handoff_id "${handoff.id}". Confira o git status e '
            'siga pelos próximos passos.';
      }
      if (!cut) {
        return 'Continue o trabalho da sessão $from neste worktree. A '
            'passagem do ai-memory é entregue no início; se não estiver no '
            'seu contexto, leia-a com memory_handoff_list. Confira o git '
            'status e siga pelos próximos passos.';
      }
      return 'Continue o trabalho da sessão $from neste worktree. A sessão '
          'foi cortada sem passagem: leia o que o ai-memory capturou dela '
          '(memory_handoff_list, memory_briefing). Confira o git status e '
          'siga a partir daí.';
    case ContinuePath.summary:
    case ContinuePath.terminal:
      return summary ?? 'Continue o trabalho da sessão $from neste worktree.';
  }
}

/// What the dialog decided.
@immutable
class ContinueRequest {
  const ContinueRequest({
    required this.origin,
    required this.target,
    required this.title,
    required this.model,
    required this.effort,
    required this.mode,
    required this.path,
    required this.message,
    this.handoff,
    this.handoffOwner,
  });

  final Session origin;
  final String target;
  final String title;
  final String model;
  final String? effort;
  final ClaudePermissionMode mode;
  final ContinuePath path;
  final String message;
  final Handoff? handoff;
  final String? handoffOwner;
}

/// The journal line (R11): "Trabalho passado do Claude Code para o Codex".
JournalEntry handoffJournalEntry({
  required int workspaceId,
  required String sessionId,
  required String originTitle,
  required String from,
  required String to,
  DateTime? at,
}) => JournalEntry(
  workspaceId: workspaceId,
  kind: JournalKind.session,
  outcome: JournalOutcome.ok,
  title: originTitle,
  detail:
      'Trabalho passado do ${providerWords(from)} para o ${providerWords(to)}',
  sessionId: sessionId,
  at: at ?? DateTime.now(),
);

/// Ends the origin, opens the new session and links both (R4, R8, R9).
class ContinueController {
  ContinueController(this.ref);

  final Ref ref;

  SessionManager get _manager => ref.read(sessionManagerProvider.notifier);

  /// Files not committed in the worktree: they stay there (R3: nothing is
  /// copied nor stashed). Empty when git fails.
  Future<List<String>> uncommitted(String worktree) async {
    try {
      final st = await ref.read(gitServiceFactoryProvider)(worktree).status();
      return [for (final e in st) e.path];
    } on GitException catch (e) {
      debugPrint('continuar: git status de $worktree — $e');
      return const [];
    }
  }

  /// Ends the origin's live process cleanly (R4.1: its `SessionEnd` writes
  /// the handoff) without recording "parada"; it becomes "Concluída".
  Future<void> endOrigin(String id) async {
    if (_manager.isAlive(id)) await _manager.release(id);
    final repo = ref.read(sessionsRepoProvider);
    final s = await repo.getById(id);
    if (s != null &&
        s.status != SessionStatus.merged &&
        s.status != SessionStatus.completed) {
      await repo.setStatus(id, SessionStatus.completed);
    }
  }

  /// Opens the new session in the same worktree and branch (no `git
  /// worktree add`, no stash), idle with [ContinueRequest.message] in its
  /// field (P1), linked to the origin (P5). Returns the new id.
  Future<String> start(ContinueRequest r) async {
    final o = r.origin;
    final ws = await ref.read(workspacesRepoProvider).getById(o.workspaceId);
    if (ws == null) throw const SessionException('Workspace não encontrado.');
    final inWorktree = o.worktreePath != ws.path;
    final record = ContinuationRecord(
      fromId: o.id,
      fromTitle: o.title ?? o.id,
      fromProvider: o.provider,
      toProvider: r.target,
      path: r.path,
      at: DateTime.now(),
      handoff: r.path == ContinuePath.aiMemory ? r.handoff : null,
      handoffOwner: r.path == ContinuePath.aiMemory ? r.handoffOwner : null,
      text: r.path == ContinuePath.summary ? r.message : null,
    );
    await endOrigin(o.id);
    final id = await _manager.create(
      NewSessionRequest(
        workspace: ws,
        title: r.title,
        prompt: r.message,
        provider: r.target,
        model: r.model,
        effort: r.effort,
        permissionMode: r.mode,
        useWorktree: false,
        worktreePath: inWorktree ? o.worktreePath : null,
        branch: inWorktree ? o.branch : null,
        baseBranch: inWorktree ? o.baseBranch : null,
        taskId: o.taskId,
        draft: true,
        parentSessionId: o.id,
        startEvent: record.toJson(),
      ),
    );
    await writeJournal(
      ref.read(activityEventsRepoProvider),
      handoffJournalEntry(
        workspaceId: ws.id,
        sessionId: id,
        originTitle: o.title ?? o.id,
        from: o.provider,
        to: r.target,
      ),
    );
    ref.read(selectedSessionProvider.notifier).select(id);
    ref.read(navigationProvider.notifier).go(AppSection.sessions);
    return id;
  }
}

final continueControllerProvider = Provider(ContinueController.new);
