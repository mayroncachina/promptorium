import 'package:flutter/foundation.dart';

import '../../ui/widgets/app_icon.dart';
import '../claude/claude_args.dart';
import '../claude/claude_event.dart';
import '../claude/claude_process.dart' show ImagePart;
import 'capabilities.dart';
import 'run_intent.dart';

export 'run_intent.dart';

export '../claude/claude_process.dart' show ImagePart;

/// Access mode of a Prompt conversation (plano, Fase 6).
enum PromptMode {
  /// Read-only: answers, never writes (see [ClaudeCodeProvider]).
  ask('Perguntar', 'só responde, não altera arquivos', 'somente leitura'),

  /// Proposes a plan before acting (`--permission-mode plan`).
  plan('Planejar', 'propõe um plano antes de agir', 'planejamento'),

  /// May edit the workspace folder (`--permission-mode acceptEdits`).
  edit('Editar', 'pode editar a pasta do workspace', 'pode editar'),

  /// Internal mode of "Refinar com IA" (Specs, DT-35): `--permission-mode
  /// default` without disallowed tools — reads freely, but every edit /
  /// command asks for approval inline. Not offered in the mode switch.
  refine('Refinar', 'edições pedem aprovação', 'edita com aprovação');

  const PromptMode(this.label, this.hint, this.access);

  /// Modes offered in the Prompt mode switch.
  static const selectable = [ask, plan, edit];

  final String label;

  /// Short hint next to the mode switch (mockup Prompt).
  final String hint;

  /// "Acesso" row of the context panel.
  final String access;

  static PromptMode fromName(String? name) =>
      values.asNameMap()[name] ?? PromptMode.ask;
}

/// How to start one agent process (SPEC-094 R4): only the app's intents,
/// plus typed [extras] of one provider that its adapter translates.
@immutable
class AgentStartOptions {
  const AgentStartOptions({
    required this.workingDirectory,
    required this.mode,
    this.yolo = false,
    this.sessionId,
    this.resumeId,
    this.forkSession = false,
    this.model,
    this.effort,
    this.appendSystemPrompt,
    this.jsonSchema,
    this.environment,
    this.appMcpConfigs = const [],
    this.appAllowedTools = const [],
    this.extras,
  });

  /// Options for an access intent ([AgentAccess.yolo] = edit + [yolo]).
  factory AgentStartOptions.forAccess(
    AgentAccess access, {
    required String workingDirectory,
    String? resumeId,
    bool forkSession = false,
    String? model,
    String? effort,
    String? appendSystemPrompt,
    String? jsonSchema,
    Map<String, String>? environment,
    ProviderExtras? extras,
  }) => AgentStartOptions(
    workingDirectory: workingDirectory,
    mode: switch (access) {
      AgentAccess.ask => PromptMode.ask,
      AgentAccess.plan => PromptMode.plan,
      AgentAccess.edit || AgentAccess.yolo => PromptMode.edit,
      AgentAccess.refine => PromptMode.refine,
    },
    yolo: access == AgentAccess.yolo,
    resumeId: resumeId,
    forkSession: forkSession,
    model: model,
    effort: effort,
    appendSystemPrompt: appendSystemPrompt,
    jsonSchema: jsonSchema,
    environment: environment,
    extras: extras,
  );

  final String workingDirectory;
  final PromptMode mode;

  /// No approvals, no sandbox (worktree only, R7).
  final bool yolo;

  /// New conversation id (UUID).
  final String? sessionId;

  /// Conversation to continue.
  final String? resumeId;
  final bool forkSession;

  /// Model alias / id; null or `inherit` = provider default.
  final String? model;

  /// Effort (null = provider default).
  final String? effort;
  final String? appendSystemPrompt;

  /// Output schema; only built when the provider has `structuredOutput`.
  final String? jsonSchema;
  final Map<String, String>? environment;

  /// Config of the app's own MCP server (SPEC-052); only built when the
  /// provider has `appMcpServer`.
  final List<String> appMcpConfigs;

  /// Read tools of the app's own MCP server (SPEC-052 R3): allowed in every
  /// mode, read-only ones included, because they never write.
  final List<String> appAllowedTools;

  /// Options of one provider (R4). Extras of another provider are a
  /// programming error in the adapter (R6).
  final ProviderExtras? extras;

  /// Access intent translated by each adapter (R7).
  AgentAccess get access => yolo
      ? AgentAccess.yolo
      : switch (mode) {
          PromptMode.ask => AgentAccess.ask,
          PromptMode.plan => AgentAccess.plan,
          PromptMode.edit => AgentAccess.edit,
          PromptMode.refine => AgentAccess.refine,
        };

  /// Claude extras (empty when none were given).
  ClaudeExtras get claude => switch (extras) {
    final ClaudeExtras e => e,
    _ => const ClaudeExtras(),
  };

  /// Codex extras (empty when none were given).
  CodexExtras get codex => switch (extras) {
    final CodexExtras e => e,
    _ => const CodexExtras(),
  };
}

/// One running agent process (a conversation turn loop).
///
/// Events use the Claude Code stream-json vocabulary ([ClaudeEvent]) — it is
/// what the timeline understands. Other providers (DT-08) must translate
/// their output into these events.
abstract interface class AgentRun {
  /// Parsed output (broadcast; buffered until the first listener).
  Stream<ClaudeEvent> get events;

  /// stderr / diagnostics.
  Stream<String> get logs;

  bool get isRunning;

  Future<int> get exitCode;

  /// Command line used (for logs and tests).
  List<String> get args;

  Future<void> send(String text, {List<ImagePart> images});

  /// Approves a permission request; [updatedPermissions] = "Sempre permitir".
  ///
  /// [updatedInput] replaces the tool input (answers of `AskUserQuestion`).
  Future<void> approve(
    String requestId, {
    List<Object?>? updatedPermissions,
    Map<String, dynamic>? updatedInput,
  });

  Future<void> deny(String requestId, String message);

  Future<int> stop({Duration timeout});
}

/// A coding-agent CLI the Prompt screen can talk to.
abstract interface class AgentProvider {
  /// Stored in `conversations.provider`.
  String get id;

  String get displayName;

  /// Icon of the provider button (plano, Fase 6 item 5).
  AppIconData get icon;

  /// false = listed as "em breve" and not selectable (DT-08).
  bool get enabled;

  /// Model choices; the first one is the default.
  List<String> get models;

  /// What this provider supports (SPEC-094 R1): services and screens ask
  /// this instead of comparing provider ids.
  ProviderCapabilities get capabilities;

  /// Starts a process. Throws [AgentUnavailable] when [enabled] is false.
  Future<AgentRun> start(AgentStartOptions options);
}

class AgentUnavailable implements Exception {
  const AgentUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Placeholder for providers not integrated yet (Codex, Gemini CLI — DT-08).
class ComingSoonProvider implements AgentProvider {
  ComingSoonProvider({
    required this.id,
    required this.displayName,
    required this.icon,
  });

  @override
  final String id;

  @override
  final String displayName;

  @override
  final AppIconData icon;

  @override
  bool get enabled => false;

  @override
  List<String> get models => const ['inherit'];

  @override
  ProviderCapabilities get capabilities =>
      ProviderCapabilities.acp(id, displayName);

  @override
  Future<AgentRun> start(AgentStartOptions options) =>
      Future.error(AgentUnavailable('$displayName ainda não está disponível.'));
}

/// A run that can report its context usage without a model turn
/// (Claude's `get_context_usage`, SPEC-087). Other providers do not
/// implement it: their readings come only from `usage`.
abstract interface class ContextUsageRun implements AgentRun {
  Future<void> requestContextUsage();
}

/// Optional lifecycle controls used by managed sessions.
abstract interface class ManagedAgentRun implements AgentRun {
  int get pid;
  Future<void> interrupt();
  Future<void> setPermissionMode(ClaudePermissionMode mode);
}
