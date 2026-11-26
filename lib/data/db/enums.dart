/// Enums persisted with drift `textEnum<T>()` (stored by `name`).
///
/// ⚠ Stored by name: renaming a value is a schema migration.
library;

/// Lifecycle of a spec file (`specs/SPEC-NNN-*.md`, frontmatter `status`:
/// `ideia` / `rascunho` / `em-revisao` / `aprovada`; see `spec_file.dart`).
/// `done` is kept for rows written before Fase 8 (no frontmatter value).
///
/// `archived`: a finished spec the user put away; hidden from the Specs list
/// and the Quadro unless "Arquivadas" is on.
enum SpecStatus { draft, review, approved, done, idea, archived }

/// Kanban column of a task (Fase 8). Tasks are no longer shown (schema v8:
/// the spec is the card); kept for the rows written before.
enum TaskStatus { backlog, running, review, done }

/// What a row of `specs` is (SPEC-069 R3, schema v25): a spec written by
/// the person, or a VIBE, the minimal spec "Fazer como tarefa" writes by
/// itself (`docs/vibe/VIBE-NNN-<slug>.md`, its own number series).
enum SpecKind {
  spec('SPEC'),
  vibe('VIBE');

  const SpecKind(this.prefix);

  /// Prefix of the code (`SPEC-001`, `VIBE-007`).
  final String prefix;

  /// The kind of a code (`VIBE-007` → vibe); null when it is neither.
  static SpecKind? ofCode(String code) {
    for (final k in values) {
      if (RegExp('^${k.prefix}-\\d+\$').hasMatch(code)) return k;
    }
    return null;
  }
}

/// State of the GitHub issue of a spec (SPEC-074 R9, schema v28).
enum IssueState { open, closed, notFound }

/// Column of a spec in the Quadro (schema v8).
enum SpecStage { backlog, running, review, done }

/// State of a sprint (schema v21): at most one is active per workspace.
enum SprintState { planned, active, done }

/// State of one step (requirement) of a spec (schema v8).
enum StepStatus {
  pending,
  running,
  done,

  /// The session ended without `ETAPA CONCLUÍDA`: waits for the user.
  needsInput,

  /// Marked done by the agent; the gate (tests, commit…) is running or the
  /// agent is fixing what it found (schema v9).
  verifying,
}

/// State of a Claude Code session (Fase 5).
enum SessionStatus {
  /// Process alive, producing events.
  running,

  /// Process alive, waiting on a `control_request` answer.
  waitingApproval,

  /// App closed / crashed while running — can be resumed with `--resume`.
  interrupted,

  /// `result` with `subtype: success`.
  completed,

  /// `result` with an `error_*` subtype or the process died.
  failed,

  /// Stopped by the user.
  stopped,

  /// Merged by the Review (Fase 9): worktree removed, cannot be resumed.
  merged;

  /// Whether the session no longer runs (sets `endedAt`).
  bool get isTerminal => switch (this) {
    running || waitingApproval => false,
    interrupted || completed || failed || stopped || merged => true,
  };
}

/// Where an agent is defined: `~/.claude/agents` or `<repo>/.claude/agents`.
enum AgentScope { global, project }

/// Rule for one MCP tool (Fase 11): `--allowedTools` / ask / `--disallowedTools`.
enum McpRule { allow, ask, block }

/// Outcome of one attempt of a step (`step_runs`, schema v19; SPEC-035).
enum StepRunResult {
  /// The gate passed.
  passed,

  /// The gate failed and the step stopped (waits for the user).
  failed,

  /// The gate failed and the step went up a rung of the ladder.
  escalated,

  /// The step left this provider for the other one because of the quota
  /// (SPEC-109 R5, R6): neither a failure nor an escalation.
  diverted,
}

/// What spent a turn (`usage_entries.source`, schema v30; SPEC-081 R2).
enum UsageSource {
  /// The session of a step (`REVn` included).
  etapa,

  /// The automatic reviewer (`claude -p`, by round).
  revisor,

  /// A turn the CI fixer sent to the session of the spec.
  ci,

  /// A conversation with `conversations.specId`.
  vibe,

  /// A conversation with `refineSpecCode`.
  refino,

  /// The step classifier and step decisions of the Orchestrator.
  orquestrador,

  /// The verification of the spec and the answers to its questions.
  verificacao,

  /// Anything else that runs on a spec (prototype screens).
  outros,

  /// A turn without a spec (free Prompt, loose sessions, Projeto).
  livre,
}
