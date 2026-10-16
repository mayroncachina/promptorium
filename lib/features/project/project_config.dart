import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaml/yaml.dart';

import '../specs/spec_file.dart';

/// Configuration of a project, kept in the repository
/// (`.promptorium/config.yml`) so the whole team shares it:
///
/// ```yaml
/// specs: docs/specs          # where the spec files live (default: specs)
/// testes: pytest -q          # command the step sessions run
/// branch-base: main          # branch of the worktrees / merge target
/// agente: implementer        # default agent of the step sessions
/// subagentes:                # called on every spec (besides its own)
///   - agente: spec-reviewer
///     quando: fim-da-spec
/// ```
@immutable
class ProjectConfig {
  const ProjectConfig({
    this.specsDir = defaultSpecsDir,
    this.testCommand,
    this.baseBranch,
    this.agent,
    this.subagents = const [],
  });

  static const defaultSpecsDir = 'specs';

  /// Path of the file inside the workspace.
  static const filePath = '.promptorium/config.yml';

  /// Folder of the spec files, relative to the workspace.
  final String specsDir;
  final String? testCommand;
  final String? baseBranch;
  final String? agent;
  final List<SpecSubagent> subagents;

  bool get isDefault =>
      specsDir == defaultSpecsDir &&
      testCommand == null &&
      baseBranch == null &&
      agent == null &&
      subagents.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is ProjectConfig &&
      other.specsDir == specsDir &&
      other.testCommand == testCommand &&
      other.baseBranch == baseBranch &&
      other.agent == agent &&
      listEquals(other.subagents, subagents);

  @override
  int get hashCode =>
      Object.hash(specsDir, testCommand, baseBranch, agent, subagents.length);

  /// Why [dir] cannot be the specs folder (null = valid): relative, no `..`,
  /// no spaces or odd characters, not inside `.git` / `.promptorium`.
  static String? validateSpecsDir(String dir) {
    final d = dir.trim();
    if (d.isEmpty) return 'Informe a pasta das specs.';
    if (!RegExp(r'^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$').hasMatch(d)) {
      return 'Use um caminho relativo simples (ex.: docs/specs).';
    }
    final parts = d.split('/');
    if (parts.any((p) => p == '.' || p == '..')) {
      return 'O caminho não pode ter "." ou "..".';
    }
    if (parts.first == '.git' || parts.first == '.promptorium') {
      return 'Escolha outra pasta.';
    }
    return null;
  }

  /// [picked] (an absolute folder from the chooser) as a path relative to
  /// the workspace, or null when it is the workspace itself or outside it.
  static String? relativeDir(String workspacePath, String picked) {
    String norm(String p) {
      var q = p.replaceAll('\\', '/');
      while (q.length > 1 && q.endsWith('/')) {
        q = q.substring(0, q.length - 1);
      }
      return q;
    }

    final root = norm(workspacePath);
    final dir = norm(picked);
    if (!dir.startsWith('$root/')) return null;
    final rel = dir.substring(root.length + 1);
    return rel.isEmpty ? null : rel;
  }

  /// Reads the YAML text; unknown / invalid values fall back to the defaults.
  factory ProjectConfig.parse(String text) {
    Object? y;
    try {
      y = loadYaml(text);
    } catch (_) {
      return const ProjectConfig();
    }
    if (y is! Map) return const ProjectConfig();
    String? str(String key) {
      final v = y is Map ? y[key] : null;
      final s = v == null ? '' : '$v'.trim();
      return s.isEmpty ? null : s;
    }

    final dir = str('specs');
    final doc = SpecDocument.parse('---\n$text\n---\n');
    return ProjectConfig(
      specsDir: dir != null && validateSpecsDir(dir) == null
          ? dir
          : defaultSpecsDir,
      testCommand: str('testes'),
      baseBranch: str('branch-base'),
      agent: str('agente'),
      subagents: doc.subagents,
    );
  }

  /// The file text (only what differs from the defaults).
  String toYaml() {
    final b = StringBuffer()
      ..writeln(
        '# Configuração do projeto no Promptorium (versionada com o repositório).',
      );
    if (specsDir != defaultSpecsDir) b.writeln('specs: $specsDir');
    if (testCommand != null) b.writeln('testes: ${_quote(testCommand!)}');
    if (baseBranch != null) b.writeln('branch-base: $baseBranch');
    if (agent != null) b.writeln('agente: $agent');
    if (subagents.isNotEmpty) {
      b.write(
        SpecDocument.parse('---\n---\n')
            .withSubagents(subagents)
            .split('---\n')[1],
      );
    }
    return b.toString();
  }

  static String _quote(String s) =>
      RegExp(r'^[A-Za-z0-9_./-][A-Za-z0-9 _./=-]*$').hasMatch(s) &&
          !s.endsWith(' ')
      ? s
      : '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  /// Config of the workspace at [workspacePath] (defaults when absent).
  static ProjectConfig loadSync(String workspacePath) {
    try {
      final f = File('$workspacePath/$filePath');
      return f.existsSync()
          ? ProjectConfig.parse(f.readAsStringSync())
          : const ProjectConfig();
    } catch (_) {
      return const ProjectConfig();
    }
  }

  /// Writes the file (removed when everything is the default).
  static Future<void> save(String workspacePath, ProjectConfig c) async {
    final f = File('$workspacePath/$filePath');
    if (c.isDefault) {
      if (await f.exists()) await f.delete();
      return;
    }
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(c.toYaml(), flush: true);
    await tmp.rename(f.path);
  }
}

/// Config of a workspace (by path). Invalidate after [ProjectConfig.save].
final projectConfigProvider = FutureProvider.family<ProjectConfig, String>(
  (ref, workspacePath) async => ProjectConfig.loadSync(workspacePath),
);
