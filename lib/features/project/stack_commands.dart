import 'package:flutter/foundation.dart';

import 'project_config.dart';
import 'project_plan.dart';
import 'stack_detect.dart';

/// The commands of the stack and the config.yml (SPEC-072 R11–R14): what
/// the config already has, what a template or a detection brings, and the
/// merge done at "Criar projeto", which only fills empty keys (the rule of
/// [applyDetection]).

/// The value of a command's key in [c] (null when absent).
String? configCommand(ProjectConfig c, String key) {
  final v = switch (key) {
    'install' => c.worktree.prepare,
    'run' => c.runCommand,
    'dev' => c.dev?.command,
    'test' => c.testCommand,
    'lint' => c.lintCommand,
    'format' => c.formatCommand,
    _ => null,
  };
  return v == null || v.trim().isEmpty ? null : v;
}

/// The commands a config (a template's) brings, pinned: the planner does
/// not change them (R11).
StackCommands commandsOfConfig(ProjectConfig c) {
  var out = const StackCommands();
  for (final k in StackCommands.keys) {
    if (configCommand(c, k) case final v?) {
      out = out.withValue(k, v, pin: true);
    }
  }
  return out;
}

/// The commands of a detection ("Detectar do repositório", R14).
StackCommands commandsOfDetection(StackDetection d) => StackCommands(
  install: d.prepare ?? '',
  test: d.tests ?? '',
  lint: d.lint ?? '',
  format: d.format ?? '',
);

/// `formatar:` needs the file: ` {arquivo}` is appended when missing (R13).
String withFileArg(String format) {
  final f = format.trim();
  return f.isEmpty || f.contains('{arquivo}') ? f : '$f {arquivo}';
}

/// One line of the merged config.yml shown in Revisar e criar (R13).
@immutable
class MergeLine {
  const MergeLine(this.key, this.value, {required this.added, this.note});

  /// The config.yml key (`executar`, `worktree.preparar`).
  final String key;
  final String value;

  /// `+` (enters now) or `=` (kept as it was).
  final bool added;

  /// "da stack", "já existia", "{arquivo} acrescentado"…
  final String? note;

  String get mark => added ? '+' : '=';
}

/// The result of [mergeStackCommands].
@immutable
class CommandsMerge {
  const CommandsMerge(this.config, this.lines);

  final ProjectConfig config;
  final List<MergeLine> lines;

  bool get changed => lines.any((l) => l.added);
  int get added => lines.where((l) => l.added).length;
  int get kept => lines.where((l) => !l.added).length;
}

/// Fills the empty keys of [config] with [commands]; what exists is never
/// overwritten (R13). The lines list the commands, `+` for the new ones and
/// `=` for the kept ones, plus `branch-base:` when set.
CommandsMerge mergeStackCommands(ProjectConfig config, StackCommands commands) {
  var out = config;
  final lines = <MergeLine>[];
  if (config.baseBranch case final b?) {
    lines.add(MergeLine('branch-base', b, added: false, note: 'do Começar'));
  }
  for (final k in StackCommands.keys) {
    final key = StackCommands.configKeys[k]!;
    if (configCommand(config, k) case final existing?) {
      lines.add(MergeLine(key, existing, added: false, note: 'já existia'));
      continue;
    }
    var v = commands[k].trim();
    if (v.isEmpty) continue;
    String note = 'da stack';
    if (k == 'format') {
      final f = withFileArg(v);
      if (f != v) note = 'da stack ({arquivo} acrescentado)';
      v = f;
    }
    out = switch (k) {
      'install' => out.copyWith(
        worktree: WorktreeConfig(
          copy: out.worktree.copy,
          prepare: v,
          basePort: out.worktree.basePort,
        ),
      ),
      'run' => out.copyWith(runCommand: () => v),
      'dev' => out.copyWith(dev: () => DevServerConfig(command: v)),
      'test' => out.copyWith(testCommand: () => v),
      'lint' => out.copyWith(lintCommand: () => v),
      _ => out.copyWith(formatCommand: () => v),
    };
    lines.add(MergeLine(key, v, added: true, note: note));
  }
  return CommandsMerge(out, lines);
}
