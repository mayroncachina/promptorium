import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/enums.dart';
import 'agent_file.dart';

export '../../data/db/enums.dart' show AgentScope;

/// Thrown by [AgentRepository] (invalid name, existing file, …).
class AgentException implements Exception {
  const AgentException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// An agent file found on disk.
@immutable
class AgentEntry {
  const AgentEntry({
    required this.scope,
    required this.path,
    required this.file,
    this.overridesGlobal = false,
    this.overriddenByProject = false,
  });

  final AgentScope scope;

  /// Absolute path of the `.md`.
  final String path;
  final AgentFile file;

  /// Project agent with the same name as a global one (the CLI uses this one).
  final bool overridesGlobal;

  /// Global agent hidden by a project agent with the same name.
  final bool overriddenByProject;

  String get name => file.name ?? '';
  bool get isProject => scope == AgentScope.project;
}

/// Agent names accepted by the editor (the CLI's convention: lowercase
/// letters, digits and hyphens).
final agentNamePattern = RegExp(r'^[a-z0-9][a-z0-9-]*$');

/// Reads and writes subagent files of `~/.claude/agents` (global) and
/// `<workspace>/.claude/agents` (project). [home] is injectable for tests.
class AgentRepository {
  AgentRepository({required this.home, this.workspacePath});

  /// Home directory (`~`); null = no global agents.
  final String? home;

  /// Workspace root; null = no project agents.
  final String? workspacePath;

  String? get globalDir => home == null ? null : '$home/.claude/agents';
  String? get projectDir =>
      workspacePath == null ? null : '$workspacePath/.claude/agents';

  String? dirFor(AgentScope scope) =>
      scope == AgentScope.global ? globalDir : projectDir;

  /// `<dir>/<name>.md`.
  String pathFor(String name, AgentScope scope) {
    final dir = dirFor(scope);
    if (dir == null) {
      throw AgentException(
        scope == AgentScope.project
            ? 'Selecione um workspace para salvar agentes de projeto.'
            : 'Diretório HOME desconhecido.',
      );
    }
    return '$dir/$name.md';
  }

  /// Every valid agent file (global first, then project; each sorted by
  /// name). Files without a valid frontmatter / name are skipped.
  Future<List<AgentEntry>> list() async {
    final global = await _scan(globalDir, AgentScope.global);
    final project = await _scan(projectDir, AgentScope.project);
    final projectNames = {for (final p in project) p.name};
    final globalNames = {for (final g in global) g.name};
    return [
      for (final g in global)
        AgentEntry(
          scope: g.scope,
          path: g.path,
          file: g.file,
          overriddenByProject: projectNames.contains(g.name),
        ),
      for (final p in project)
        AgentEntry(
          scope: p.scope,
          path: p.path,
          file: p.file,
          overridesGlobal: globalNames.contains(p.name),
        ),
    ];
  }

  /// The agent the CLI would use for [name] (project wins over global).
  Future<AgentEntry?> find(String name) async {
    AgentEntry? found;
    for (final e in await list()) {
      if (e.name == name && (found == null || e.isProject)) found = e;
    }
    return found;
  }

  Future<AgentFile> read(String path) async =>
      AgentFile.parse(await File(path).readAsString());

  /// Writes [file] in [scope] as `<name>.md`. [previousPath] is the file being
  /// edited: when the target differs (rename / move) it is deleted after the
  /// new one is written. Returns the path written.
  Future<String> save(
    AgentFile file,
    AgentScope scope, {
    String? previousPath,
  }) async {
    // Validated exactly as written (no trim): the name becomes the file name.
    final name = file.name ?? '';
    if (!agentNamePattern.hasMatch(name)) {
      throw const AgentException(
        'Nome inválido: use letras minúsculas, números e hífens '
        '(ex.: code-reviewer).',
      );
    }
    if ((file.description ?? '').trim().isEmpty) {
      throw const AgentException('Informe quando usar o agente (description).');
    }
    // Same scope and same name: keep the existing file name.
    final keep =
        previousPath != null &&
        File(previousPath).parent.path == dirFor(scope) &&
        (await _nameAt(previousPath)) == name;
    final target = keep ? previousPath : pathFor(name, scope);
    if (target != previousPath && await File(target).exists()) {
      throw AgentException('Já existe um agente em $target.');
    }
    final f = File(target);
    await f.parent.create(recursive: true);
    // Write next to it and rename: never leaves a half-written agent.
    final tmp = File('$target.promptorium-tmp');
    await tmp.writeAsString(file.serialize(), flush: true);
    await tmp.rename(target);
    if (previousPath != null && previousPath != target) {
      final old = File(previousPath);
      if (await old.exists()) await old.delete();
    }
    return target;
  }

  /// Deletes the agent file (the UI asks for confirmation first).
  Future<void> delete(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }

  Future<String?> _nameAt(String path) async {
    try {
      return (await read(path)).name;
    } catch (_) {
      return null;
    }
  }

  Future<List<AgentEntry>> _scan(String? dir, AgentScope scope) async {
    if (dir == null) return const [];
    final d = Directory(dir);
    if (!await d.exists()) return const [];
    final out = <AgentEntry>[];
    await for (final f in d.list()) {
      if (f is! File || !f.path.endsWith('.md')) continue;
      try {
        final file = AgentFile.parse(await f.readAsString());
        final name = file.name?.trim();
        if (name == null || name.isEmpty) continue;
        out.add(AgentEntry(scope: scope, path: f.path, file: file));
      } catch (_) {
        // unreadable / invalid file: ignored (the CLI ignores it too)
      }
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }
}

/// MCP server **names** (never their configuration) from `~/.claude.json`
/// (`mcpServers` and `projects[<workspace>].mcpServers`) and
/// `<workspace>/.mcp.json`. Read-only (anti-padrão 0.5: never edit
/// `~/.claude.json` by hand).
Future<List<String>> readMcpServerNames({
  String? home,
  String? workspacePath,
}) async {
  final names = <String>{};
  Future<Object?> readJson(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return null;
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  void add(Object? servers) {
    if (servers is Map) names.addAll(servers.keys.map((k) => '$k'));
  }

  if (home != null) {
    final j = await readJson('$home/.claude.json');
    if (j is Map) {
      add(j['mcpServers']);
      final projects = j['projects'];
      if (workspacePath != null && projects is Map) {
        final p = projects[workspacePath];
        if (p is Map) add(p['mcpServers']);
      }
    }
  }
  if (workspacePath != null) {
    final j = await readJson('$workspacePath/.mcp.json');
    if (j is Map) add(j['mcpServers']);
  }
  return names.toList()..sort();
}

// --- providers -----------------------------------------------------------------

/// Home directory used for `~/.claude/agents` and `~/.claude.json`.
/// Tests override it with a temporary directory.
final agentHomeProvider = Provider<String?>((ref) {
  final h = Platform.environment['HOME'];
  return h == null || h.isEmpty ? null : h;
});

final agentRepositoryProvider = Provider.family<AgentRepository, String?>(
  (ref, workspacePath) => AgentRepository(
    home: ref.watch(agentHomeProvider),
    workspacePath: workspacePath,
  ),
);

/// Agent files of a workspace (null = global only). Invalidate after saving.
final agentEntriesProvider = FutureProvider.family<List<AgentEntry>, String?>(
  (ref, workspacePath) =>
      ref.watch(agentRepositoryProvider(workspacePath)).list(),
);

/// MCP server names offered as chips in the agent editor.
final mcpServerNamesProvider = FutureProvider.family<List<String>, String?>(
  (ref, workspacePath) => readMcpServerNames(
    home: ref.watch(agentHomeProvider),
    workspacePath: workspacePath,
  ),
);
