import 'package:flutter/foundation.dart';

import '../../ui/widgets/app_icon.dart';
import '../claude/claude_event.dart';
import '../claude/claude_process.dart' show ImagePart;

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

/// How to start one agent process.
@immutable
class AgentStartOptions {
  const AgentStartOptions({
    required this.workingDirectory,
    required this.mode,
    this.sessionId,
    this.resumeId,
    this.forkSession = false,
    this.model,
    this.effort,
    this.autocompact,
    this.maxBudgetUsd,
    this.mcpAllowedTools = const [],
    this.mcpDisallowedTools = const [],
  });

  final String workingDirectory;
  final PromptMode mode;

  /// New conversation id (UUID).
  final String? sessionId;

  /// Conversation to continue.
  final String? resumeId;
  final bool forkSession;

  /// Model alias / id; null or `inherit` = provider default.
  final String? model;

  /// `--effort` (null = provider default).
  final String? effort;

  /// `--autocompact` (null = provider default).
  final String? autocompact;
  final double? maxBudgetUsd;

  /// MCP tools marked "Permitido" (`mcp__srv__tool`, Fase 11). Ignored by
  /// the read-only modes ([PromptMode.ask], [PromptMode.refine]).
  final List<String> mcpAllowedTools;

  /// MCP tools marked "Bloqueado" (always applied).
  final List<String> mcpDisallowedTools;
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
  Future<AgentRun> start(AgentStartOptions options) =>
      Future.error(AgentUnavailable('$displayName ainda não está disponível.'));
}
