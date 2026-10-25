import 'dart:convert';
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
/// lint: ruff check           # extra check of the step gate
/// build: make build          # extra check of the step gate
/// formatar: ruff format {arquivo}  # after each edit (managed hook)
/// branch-base: main          # branch of the worktrees / merge target
/// agente: implementer        # default agent of the step sessions
/// subagentes:                # called on every spec (besides its own)
///   - agente: spec-reviewer
///     quando: fim-da-spec
/// verificacao:               # step gate (see `StepGate`)
///   tentativas: 1
///   timeout: 600
///   exigir-commit: true
///   exigir-arvore-limpa: true
///   contar-testes: sim       # fewer / more skipped tests fail the gate
/// bloquear-comandos:         # Bash commands refused by the managed hook
///   - "git push --force*"
/// worktree:
///   copiar: [.env]           # copied from the root into new worktrees
///   preparar: npm ci         # run once in a new worktree
///   porta-base: 4000         # PROMPTORIUM_PORT = porta-base + index
/// revisor:                   # automatic reviewer of a finished spec
///   ligado: true
///   modelo: haiku
///   orcamento: 0.30
///   rodadas: 2
/// autopilot:
///   paralelo: 3
///   orcamento-dia: 10
/// ```
///
/// Every key is optional; absent = the behaviour from before the key existed.
/// `verificacao:` of the config: how the step gate behaves.
@immutable
class VerificationConfig {
  const VerificationConfig({
    this.attempts = 1,
    this.timeoutSeconds = 600,
    this.requireCommit = true,
    this.requireCleanTree = true,
    this.countTests = true,
  });

  /// Automatic resends to the agent before asking the user.
  final int attempts;

  /// Per command.
  final int timeoutSeconds;
  final bool requireCommit;
  final bool requireCleanTree;

  /// `contar-testes`: the gate compares the count of `testes:` with the
  /// spec's last approved gate (SPEC-023 R2, R5).
  final bool countTests;

  bool get isDefault => this == const VerificationConfig();

  Duration get timeout => Duration(seconds: timeoutSeconds);

  @override
  bool operator ==(Object other) =>
      other is VerificationConfig &&
      other.attempts == attempts &&
      other.timeoutSeconds == timeoutSeconds &&
      other.requireCommit == requireCommit &&
      other.requireCleanTree == requireCleanTree &&
      other.countTests == countTests;

  @override
  int get hashCode => Object.hash(
    attempts,
    timeoutSeconds,
    requireCommit,
    requireCleanTree,
    countTests,
  );
}

/// `worktree:` of the config: what a new worktree needs to run.
@immutable
class WorktreeConfig {
  const WorktreeConfig({this.copy = const [], this.prepare, this.basePort});

  /// Files of the root copied into new worktrees (ignored ones only).
  final List<String> copy;

  /// Command run once in a new worktree (`npm ci`).
  final String? prepare;

  /// `PROMPTORIUM_PORT` = [basePort] + the worktree index.
  final int? basePort;

  bool get isDefault => copy.isEmpty && prepare == null && basePort == null;

  @override
  bool operator ==(Object other) =>
      other is WorktreeConfig &&
      listEquals(other.copy, copy) &&
      other.prepare == prepare &&
      other.basePort == basePort;

  @override
  int get hashCode => Object.hash(Object.hashAll(copy), prepare, basePort);
}

/// `revisor:` of the config: automatic review of a finished spec.
@immutable
class ReviewerConfig {
  const ReviewerConfig({
    this.enabled = false,
    this.model = 'haiku',
    this.budgetUsd = 0.30,
    this.rounds = 2,
  });

  final bool enabled;
  final String model;
  final double budgetUsd;

  /// Correction rounds before handing the spec to the user.
  final int rounds;

  bool get isDefault => this == const ReviewerConfig();

  @override
  bool operator ==(Object other) =>
      other is ReviewerConfig &&
      other.enabled == enabled &&
      other.model == model &&
      other.budgetUsd == budgetUsd &&
      other.rounds == rounds;

  @override
  int get hashCode => Object.hash(enabled, model, budgetUsd, rounds);
}

/// `autopilot:` of the config: limits of the Quadro's Autopilot.
@immutable
class AutopilotConfig {
  const AutopilotConfig({this.parallel, this.dailyBudgetUsd});

  /// Specs running at the same time (null = no limit).
  final int? parallel;

  /// Sum of the spec sessions' cost of the day (null = no limit).
  final double? dailyBudgetUsd;

  bool get isDefault => parallel == null && dailyBudgetUsd == null;

  @override
  bool operator ==(Object other) =>
      other is AutopilotConfig &&
      other.parallel == parallel &&
      other.dailyBudgetUsd == dailyBudgetUsd;

  @override
  int get hashCode => Object.hash(parallel, dailyBudgetUsd);
}

@immutable
class ProjectConfig {
  const ProjectConfig({
    this.specsDir = defaultSpecsDir,
    this.testCommand,
    this.lintCommand,
    this.buildCommand,
    this.formatCommand,
    this.baseBranch,
    this.agent,
    this.subagents = const [],
    this.verification,
    this.blockedCommands = const [],
    this.worktree = const WorktreeConfig(),
    this.reviewer = const ReviewerConfig(),
    this.autopilot = const AutopilotConfig(),
    this.mergeMethod = 'merge',
    this.host,
    this.hostType,
  });

  static const defaultSpecsDir = 'specs';

  /// Path of the file inside the workspace.
  static const filePath = '.promptorium/config.yml';

  /// Folder of the spec files, relative to the workspace.
  final String specsDir;
  final String? testCommand;

  /// `lint:` / `build:`: extra commands of the step gate.
  final String? lintCommand;
  final String? buildCommand;

  /// `formatar:` run after each edit, `{arquivo}` = the edited file.
  final String? formatCommand;
  final String? baseBranch;
  final String? agent;
  final List<SpecSubagent> subagents;

  /// `verificacao:`; null = absent (defaults, see [gateEnabled]).
  final VerificationConfig? verification;

  /// `bloquear-comandos:` (glob, `*` = anything), added to the built-in list.
  final List<String> blockedCommands;
  final WorktreeConfig worktree;
  final ReviewerConfig reviewer;
  final AutopilotConfig autopilot;
  final String mergeMethod;
  final String? host, hostType;

  /// The verification in effect (defaults when absent).
  VerificationConfig get gate => verification ?? const VerificationConfig();

  /// The step gate runs when there is something to check: a command, or
  /// `verificacao:` written explicitly. Else the marker alone finishes a step
  /// (behaviour from before the gate).
  bool get gateEnabled =>
      testCommand != null ||
      lintCommand != null ||
      buildCommand != null ||
      verification != null;

  bool get isDefault =>
      specsDir == defaultSpecsDir && toYaml() == const ProjectConfig().toYaml();

  ProjectConfig copyWith({
    String? specsDir,
    String? Function()? testCommand,
    String? Function()? lintCommand,
    String? Function()? buildCommand,
    String? Function()? formatCommand,
    String? Function()? baseBranch,
    String? Function()? agent,
    List<SpecSubagent>? subagents,
    VerificationConfig? Function()? verification,
    List<String>? blockedCommands,
    WorktreeConfig? worktree,
    ReviewerConfig? reviewer,
    AutopilotConfig? autopilot,
    String? mergeMethod,
    String? host,
    String? hostType,
  }) => ProjectConfig(
    specsDir: specsDir ?? this.specsDir,
    testCommand: testCommand == null ? this.testCommand : testCommand(),
    lintCommand: lintCommand == null ? this.lintCommand : lintCommand(),
    buildCommand: buildCommand == null ? this.buildCommand : buildCommand(),
    formatCommand: formatCommand == null ? this.formatCommand : formatCommand(),
    baseBranch: baseBranch == null ? this.baseBranch : baseBranch(),
    agent: agent == null ? this.agent : agent(),
    subagents: subagents ?? this.subagents,
    verification: verification == null ? this.verification : verification(),
    blockedCommands: blockedCommands ?? this.blockedCommands,
    worktree: worktree ?? this.worktree,
    reviewer: reviewer ?? this.reviewer,
    autopilot: autopilot ?? this.autopilot,
    mergeMethod: mergeMethod ?? this.mergeMethod,
    host: host ?? this.host,
    hostType: hostType ?? this.hostType,
  );

  // The file text holds every field (only non-defaults are written).
  @override
  bool operator ==(Object other) =>
      other is ProjectConfig && other.toYaml() == toYaml();

  @override
  int get hashCode => toYaml().hashCode;

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
    final root = y;
    String? str(Object? v) {
      final s = v == null || v is Map || v is List ? '' : '$v'.trim();
      return s.isEmpty ? null : s;
    }

    int? integer(Object? v, {int min = 0}) {
      final n = v is int ? v : int.tryParse('${v ?? ''}'.trim());
      return n != null && n >= min ? n : null;
    }

    double? number(Object? v) {
      final n = v is num ? v.toDouble() : double.tryParse('${v ?? ''}'.trim());
      return n != null && n >= 0 ? n : null;
    }

    bool? boolean(Object? v) => switch (v) {
      bool b => b,
      'sim' || 'true' || 'yes' => true,
      'nao' || 'não' || 'false' || 'no' => false,
      _ => null,
    };

    List<String> strings(Object? v) =>
        v is List ? [for (final e in v) ?str(e)] : [?str(v)];

    Map<Object?, Object?> map(String key) =>
        root[key] is Map ? (root[key] as Map).cast() : const {};

    final dir = str(root['specs']);
    final doc = SpecDocument.parse('---\n$text\n---\n');
    const dv = VerificationConfig();
    final v = map('verificacao');
    final w = map('worktree');
    const dr = ReviewerConfig();
    final r = map('revisor');
    final a = map('autopilot');
    return ProjectConfig(
      mergeMethod:
          ['merge', 'squash', 'rebase'].contains(map('merge')['metodo'])
          ? '${map('merge')['metodo']}'
          : 'merge',
      host: str(map('hospedagem')['host']),
      hostType: str(map('hospedagem')['tipo']),
      specsDir: dir != null && validateSpecsDir(dir) == null
          ? dir
          : defaultSpecsDir,
      testCommand: str(root['testes']),
      lintCommand: str(root['lint']),
      buildCommand: str(root['build']),
      formatCommand: str(root['formatar']),
      baseBranch: str(root['branch-base']),
      agent: str(root['agente']),
      subagents: doc.subagents,
      verification: root['verificacao'] is Map
          ? VerificationConfig(
              attempts: integer(v['tentativas']) ?? dv.attempts,
              timeoutSeconds:
                  integer(v['timeout'], min: 1) ?? dv.timeoutSeconds,
              requireCommit: boolean(v['exigir-commit']) ?? dv.requireCommit,
              requireCleanTree:
                  boolean(v['exigir-arvore-limpa']) ?? dv.requireCleanTree,
              countTests: boolean(v['contar-testes']) ?? dv.countTests,
            )
          : null,
      blockedCommands: strings(root['bloquear-comandos']),
      worktree: WorktreeConfig(
        copy: [
          for (final f in strings(w['copiar']))
            if (_safeRelative(f)) f,
        ],
        prepare: str(w['preparar']),
        basePort: integer(w['porta-base'], min: 1),
      ),
      reviewer: ReviewerConfig(
        enabled: boolean(r['ligado']) ?? dr.enabled,
        model: str(r['modelo']) ?? dr.model,
        budgetUsd: number(r['orcamento']) ?? dr.budgetUsd,
        rounds: integer(r['rodadas']) ?? dr.rounds,
      ),
      autopilot: AutopilotConfig(
        parallel: integer(a['paralelo'], min: 1),
        dailyBudgetUsd: number(a['orcamento-dia']),
      ),
    );
  }

  /// Relative path without `..` (files copied into a worktree).
  static bool _safeRelative(String p) =>
      p.isNotEmpty &&
      !p.startsWith('/') &&
      !p.split('/').any((s) => s == '..' || s.isEmpty);

  /// The file text (only what differs from the defaults).
  String toYaml() {
    final b = StringBuffer()
      ..writeln(
        '# Configuração do projeto no Promptorium (versionada com o repositório).',
      );
    if (specsDir != defaultSpecsDir) b.writeln('specs: $specsDir');
    if (testCommand != null) b.writeln('testes: ${_quote(testCommand!)}');
    if (lintCommand != null) b.writeln('lint: ${_quote(lintCommand!)}');
    if (buildCommand != null) b.writeln('build: ${_quote(buildCommand!)}');
    if (formatCommand != null) {
      b.writeln('formatar: ${_quote(formatCommand!)}');
    }
    if (baseBranch != null) b.writeln('branch-base: $baseBranch');
    if (agent != null) b.writeln('agente: $agent');
    if (subagents.isNotEmpty) {
      b.write(
        SpecDocument.parse('---\n---\n')
            .withSubagents(subagents)
            .split('---\n')[1],
      );
    }
    if (verification case final v?) {
      b
        ..writeln('verificacao:')
        ..writeln('  tentativas: ${v.attempts}')
        ..writeln('  timeout: ${v.timeoutSeconds}')
        ..writeln('  exigir-commit: ${v.requireCommit}')
        ..writeln('  exigir-arvore-limpa: ${v.requireCleanTree}');
      if (!v.countTests) b.writeln('  contar-testes: nao');
    }
    if (blockedCommands.isNotEmpty) {
      b.writeln('bloquear-comandos:');
      for (final c in blockedCommands) {
        b.writeln('  - ${jsonEncode(c)}');
      }
    }
    if (!worktree.isDefault) {
      b.writeln('worktree:');
      if (worktree.copy.isNotEmpty) {
        b.writeln('  copiar: [${worktree.copy.map(jsonEncode).join(', ')}]');
      }
      if (worktree.prepare != null) {
        b.writeln('  preparar: ${_quote(worktree.prepare!)}');
      }
      if (worktree.basePort != null) {
        b.writeln('  porta-base: ${worktree.basePort}');
      }
    }
    if (mergeMethod != 'merge') {
      b.writeln('merge:\n  metodo: $mergeMethod');
    }
    if (host != null && hostType != null) {
      b.writeln(
        'hospedagem:\n  host: ${jsonEncode(host)}\n  tipo: ${jsonEncode(hostType)}',
      );
    }
    if (!reviewer.isDefault) {
      b
        ..writeln('revisor:')
        ..writeln('  ligado: ${reviewer.enabled}')
        ..writeln('  modelo: ${reviewer.model}')
        ..writeln('  orcamento: ${reviewer.budgetUsd}')
        ..writeln('  rodadas: ${reviewer.rounds}');
    }
    if (!autopilot.isDefault) {
      b.writeln('autopilot:');
      if (autopilot.parallel != null) {
        b.writeln('  paralelo: ${autopilot.parallel}');
      }
      if (autopilot.dailyBudgetUsd != null) {
        b.writeln('  orcamento-dia: ${autopilot.dailyBudgetUsd}');
      }
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
