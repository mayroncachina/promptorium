/// Enums persisted with drift `textEnum<T>()` (stored by `name`).
///
/// ⚠ Stored by name: renaming a value is a schema migration.
library;

/// Lifecycle of a spec file (`specs/SPEC-NNN-*.md`, frontmatter `status`:
/// `ideia` / `rascunho` / `em-revisao` / `aprovada`; see `spec_file.dart`).
/// `done` is kept for rows written before Fase 8 (no frontmatter value).
enum SpecStatus { draft, review, approved, done, idea }

/// Kanban column of a task (Fase 8).
enum TaskStatus { backlog, running, review, done }

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
