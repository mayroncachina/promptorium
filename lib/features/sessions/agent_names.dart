import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agents/agent_file.dart';
import '../agents/agent_repository.dart';

/// A subagent offered by the "Nova sessão" dialog: the effective definition
/// for the workspace (a project agent replaces a global one with that name).
class AgentRef {
  const AgentRef({
    required this.name,
    required this.project,
    this.description,
    this.permissionMode,
    this.maxTurns,
    this.model,
    this.effort,
  });

  final String name;

  /// `<workspace>/.claude/agents` (overrides a global agent with that name).
  final bool project;
  final String? description;

  /// `permissionMode` of the frontmatter. `--agent` does not apply it to the
  /// main thread (sondado na Fase 7), so the dialog preselects it.
  final String? permissionMode;
  final int? maxTurns;

  /// `model` of the frontmatter (`--agent` runs the main thread with it).
  final String? model;

  /// `effort` of the frontmatter; the dialog preselects it (`--effort`).
  final String? effort;
}

/// `name:` (and `description:`) from the YAML frontmatter of an agent file,
/// or null when the file has no valid frontmatter / name.
({String name, String? description})? parseAgentFrontmatter(String source) {
  try {
    final f = AgentFile.parse(source);
    final name = f.name?.trim();
    if (name == null || name.isEmpty || f.value('name') is! String) {
      return null;
    }
    return (name: name, description: f.description);
  } on AgentFormatException {
    return null;
  }
}

/// The effective agents of [entries] (project wins), sorted by name.
List<AgentRef> effectiveAgents(List<AgentEntry> entries) {
  final byName = <String, AgentRef>{};
  for (final e in entries) {
    if (byName.containsKey(e.name) && !e.isProject) continue;
    byName[e.name] = AgentRef(
      name: e.name,
      project: e.isProject,
      description: e.file.description,
      permissionMode: e.file.permissionMode,
      maxTurns: e.file.maxTurns,
      model: e.file.model,
      effort: e.file.effort,
    );
  }
  return byName.values.toList()..sort((a, b) => a.name.compareTo(b.name));
}

/// Agents from `~/.claude/agents/*.md` and `<workspace>/.claude/agents/*.md`
/// ([AgentRepository]); a project agent replaces a global one with the same
/// name. Sorted by name.
Future<List<AgentRef>> listAgents({
  String? workspacePath,
  String? home,
}) async => effectiveAgents(
  await AgentRepository(home: home, workspacePath: workspacePath).list(),
);

/// Agents available for a workspace path (null = global only).
final agentListProvider = FutureProvider.family<List<AgentRef>, String?>(
  (ref, workspacePath) async => effectiveAgents(
    await ref.watch(agentEntriesProvider(workspacePath).future),
  ),
);
