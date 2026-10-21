import '../claude/claude_args.dart';

/// Provider-specific presentation of the legacy persisted permission modes.
String permissionModeLabel(
  ClaudePermissionMode? mode, {
  String provider = 'claude',
}) {
  if (provider == 'codex' && mode == ClaudePermissionMode.skipPermissions) {
    return 'YOLO — sem aprovações e sem sandbox';
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

({String sandbox, String approval}) codexPermissionPolicy(
  ClaudePermissionMode? mode, {
  bool readOnly = false,
  bool refine = false,
}) {
  if (readOnly || mode == ClaudePermissionMode.plan) {
    return (sandbox: 'read-only', approval: 'never');
  }
  return (
    sandbox: mode == ClaudePermissionMode.skipPermissions
        ? 'danger-full-access'
        : 'workspace-write',
    approval: switch (mode) {
      ClaudePermissionMode.skipPermissions ||
      ClaudePermissionMode.dontAsk => 'never',
      ClaudePermissionMode.defaultMode => 'untrusted',
      _ => refine ? 'untrusted' : 'on-request',
    },
  );
}

String permissionModePreferenceKey(String provider) => provider == 'claude'
    ? 'session.permissionMode'
    : '$provider.session.permissionMode';
