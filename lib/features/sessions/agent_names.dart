import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaml/yaml.dart';

/// A subagent definition found on disk (only what the "Nova sessão" dialog
/// needs; the full editor is Fase 7).
class AgentRef {
  const AgentRef({required this.name, required this.project, this.description});

  final String name;

  /// `<workspace>/.claude/agents` (overrides a global agent with that name).
  final bool project;
  final String? description;
}

/// `name:` (and `description:`) from the YAML frontmatter of an agent file,
/// or null when the file has no valid frontmatter / name.
({String name, String? description})? parseAgentFrontmatter(String source) {
  final text = source.replaceFirst('﻿', '');
  final lines = text.split('\n');
  if (lines.isEmpty || lines.first.trim() != '---') return null;
  final end = lines.indexWhere((l) => l.trim() == '---', 1);
  if (end < 0) return null;
  try {
    final doc = loadYaml(lines.sublist(1, end).join('\n'));
    if (doc is! YamlMap) return null;
    final name = doc['name'];
    if (name is! String || name.trim().isEmpty) return null;
    final desc = doc['description'];
    return (name: name.trim(), description: desc is String ? desc : null);
  } catch (_) {
    return null;
  }
}

/// Agents from `~/.claude/agents/*.md` and `<workspace>/.claude/agents/*.md`;
/// a project agent replaces a global one with the same name. Sorted by name.
Future<List<AgentRef>> listAgents({String? workspacePath, String? home}) async {
  final byName = <String, AgentRef>{};
  Future<void> scan(String dir, bool project) async {
    final d = Directory(dir);
    if (!await d.exists()) return;
    await for (final f in d.list()) {
      if (f is! File || !f.path.endsWith('.md')) continue;
      try {
        final fm = parseAgentFrontmatter(await f.readAsString());
        if (fm == null) continue;
        byName[fm.name] = AgentRef(
          name: fm.name,
          project: project,
          description: fm.description,
        );
      } catch (_) {
        // unreadable file: ignore
      }
    }
  }

  final h = home ?? Platform.environment['HOME'];
  if (h != null && h.isNotEmpty) await scan('$h/.claude/agents', false);
  if (workspacePath != null) await scan('$workspacePath/.claude/agents', true);
  return byName.values.toList()..sort((a, b) => a.name.compareTo(b.name));
}

/// Agents available for a workspace path (null = global only).
final agentListProvider = FutureProvider.family<List<AgentRef>, String?>(
  (ref, workspacePath) => listAgents(workspacePath: workspacePath),
);
