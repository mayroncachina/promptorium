import '../claude/claude_args.dart';
import 'agent_provider.dart';

/// Provider-specific presentation of the legacy persisted permission modes.
String permissionModeLabel(
  ClaudePermissionMode? mode, {
  String provider = 'claude',
}) {
  if (provider == 'codex') {
    // R7: the policy of each mode, as the App Server receives it.
    final access = AgentAccess.fromClaudeMode(mode);
    if (access != null) return codexAccessLabel(access);
  }
  return switch (mode) {
    null || ClaudePermissionMode.defaultMode => 'perguntar',
    ClaudePermissionMode.acceptEdits => 'aceitar edições',
    ClaudePermissionMode.plan => 'planejar',
    ClaudePermissionMode.auto => 'automático',
    ClaudePermissionMode.dontAsk => 'não perguntar',
    ClaudePermissionMode.skipPermissions => 'sem perguntar nada (perigoso)',
  };
}

/// Codex label of one access (R7): what the mode does and the policy the
/// App Server receives. Perguntar and Planejar share the policy but keep
/// their own names.
String codexAccessLabel(AgentAccess access) {
  final p = codexAccessPolicy(access);
  final what = switch (access) {
    AgentAccess.yolo => 'YOLO — sem aprovações e sem sandbox',
    AgentAccess.ask => 'perguntar — somente leitura, só responde',
    AgentAccess.plan => 'planejar — o sandbox impede escrita',
    AgentAccess.edit => 'editar — escreve com confirmação',
    AgentAccess.refine => 'perguntar — cada comando pede aprovação',
  };
  return '$what · ${p.sandbox} · ${p.approval}';
}

String permissionModeOption(
  ClaudePermissionMode mode, {
  required String provider,
}) => provider == 'codex'
    ? permissionModeLabel(mode, provider: provider)
    : '${mode.cliValue} — ${permissionModeLabel(mode)}';

String bypassWarning(String provider) => provider == 'codex'
    ? 'codex --yolo: o agente altera arquivos e executa comandos sem aprovação '
          'e sem sandbox, inclusive fora do worktree.'
    : '--dangerously-skip-permissions: o agente edita arquivos e roda qualquer '
          'comando sem pedir aprovação, inclusive fora do worktree. Use só em '
          'projetos e máquinas em que você confia.';

/// Codex policy of each access (SPEC-094 R7, values proved by SPEC-093):
/// Perguntar and Planejar = `read-only` + `never` (enforced by the
/// sandbox); Editar = `workspace-write` + `on-request`; Refinar = every
/// command asks (`untrusted`, valid on the App Server); YOLO =
/// `danger-full-access` + `never`, worktree only. [CodexExtras] may
/// override sandbox and approval.
({String sandbox, String approval}) codexAccessPolicy(
  AgentAccess access, {
  CodexExtras extras = const CodexExtras(),
}) {
  final base = switch (access) {
    AgentAccess.ask ||
    AgentAccess.plan => (sandbox: 'read-only', approval: 'never'),
    AgentAccess.edit => (sandbox: 'workspace-write', approval: 'on-request'),
    AgentAccess.refine => (sandbox: 'workspace-write', approval: 'untrusted'),
    AgentAccess.yolo => (sandbox: 'danger-full-access', approval: 'never'),
  };
  return (
    sandbox: extras.sandbox ?? base.sandbox,
    approval: extras.approval ?? base.approval,
  );
}

/// The interactive CLI (`codex resume` in the terminal): `-a untrusted`
/// exits with code 2 on 0.170 (SPEC-093 D3), so Refinar asks on request.
({String sandbox, String approval}) codexCliPolicy(AgentAccess access) {
  final p = codexAccessPolicy(access);
  return p.approval == 'untrusted'
      ? (sandbox: p.sandbox, approval: 'on-request')
      : p;
}

/// Legacy session mode → Codex access; `auto` and `dontAsk` are Claude
/// only and fail closed.
AgentAccess codexAccessFor(ClaudePermissionMode? mode) =>
    AgentAccess.fromClaudeMode(mode) ??
    (throw AgentUnavailable(
      'Codex: o modo ${mode?.cliValue} é só do Claude Code.',
    ));

String permissionModePreferenceKey(String provider) => provider == 'claude'
    ? 'session.permissionMode'
    : '$provider.session.permissionMode';
