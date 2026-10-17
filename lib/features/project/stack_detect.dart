import 'dart:io';

import 'package:flutter/foundation.dart';

import 'project_config.dart';
import 'project_memory.dart';

/// "Analisar repositório" (UX v2, U6): reads the files of a repository that
/// already has code and proposes how the Promptorium should work in it
/// (test, lint and format commands, what to run to prepare a worktree).
/// Pure file inspection: no model call.

@immutable
class StackDetection {
  const StackDetection({
    required this.name,
    this.tests,
    this.lint,
    this.format,
    this.prepare,
    this.evidence = const [],
  });

  /// `Flutter`, `Node.js`, `Python`, `Rust`, `Go`, `Desconhecida`.
  final String name;
  final String? tests;
  final String? lint;

  /// `formatar:` with `{arquivo}`.
  final String? format;

  /// `worktree.preparar:` (dependencies).
  final String? prepare;

  /// Files that led to it (`pubspec.yaml`…).
  final List<String> evidence;

  bool get isUnknown => name == 'Desconhecida';

  String get summary => [
    name,
    if (tests != null) 'testes: $tests',
    if (lint != null) 'lint: $lint',
    if (format != null) 'formatar: $format',
    if (prepare != null) 'preparar: $prepare',
  ].join(' · ');
}

/// Detection by the marker files at the root of [path].
Future<StackDetection> detectStack(String path) async {
  bool has(String f) => File('$path/$f').existsSync();
  if (has('pubspec.yaml')) {
    final flutter = File('$path/pubspec.yaml')
        .readAsStringSync()
        .contains(RegExp(r'^\s{2}flutter:', multiLine: true));
    return StackDetection(
      name: flutter ? 'Flutter' : 'Dart',
      tests: flutter ? 'flutter test' : 'dart test',
      lint: flutter ? 'flutter analyze' : 'dart analyze',
      format: 'dart format {arquivo}',
      prepare: flutter ? 'flutter pub get' : 'dart pub get',
      evidence: const ['pubspec.yaml'],
    );
  }
  if (has('package.json')) {
    final pkg = File('$path/package.json').readAsStringSync();
    final pm = has('pnpm-lock.yaml')
        ? 'pnpm'
        : has('yarn.lock')
        ? 'yarn'
        : 'npm';
    final hasLint = pkg.contains('"lint"');
    final hasPrettier =
        pkg.contains('"prettier"') ||
        has('.prettierrc') ||
        has('prettier.config.js');
    return StackDetection(
      name: 'Node.js',
      tests: '$pm test',
      lint: hasLint ? '$pm run lint' : null,
      format: hasPrettier ? 'npx prettier --write {arquivo}' : null,
      prepare: '$pm install',
      evidence: ['package.json', if (pm != 'npm') '$pm lock'],
    );
  }
  if (has('pyproject.toml') || has('requirements.txt') || has('setup.py')) {
    final py = has('pyproject.toml')
        ? File('$path/pyproject.toml').readAsStringSync()
        : '';
    final ruff = py.contains('ruff') || has('ruff.toml');
    final black = py.contains('black');
    return StackDetection(
      name: 'Python',
      tests: 'pytest',
      lint: ruff ? 'ruff check .' : null,
      format: ruff
          ? 'ruff format {arquivo}'
          : black
          ? 'black {arquivo}'
          : null,
      prepare: has('pyproject.toml') && py.contains('[tool.poetry]')
          ? 'poetry install'
          : has('requirements.txt')
          ? 'pip install -r requirements.txt'
          : null,
      evidence: [
        if (has('pyproject.toml')) 'pyproject.toml',
        if (has('requirements.txt')) 'requirements.txt',
        if (has('setup.py')) 'setup.py',
      ],
    );
  }
  if (has('Cargo.toml')) {
    return const StackDetection(
      name: 'Rust',
      tests: 'cargo test',
      lint: 'cargo clippy',
      format: 'rustfmt {arquivo}',
      evidence: ['Cargo.toml'],
    );
  }
  if (has('go.mod')) {
    return const StackDetection(
      name: 'Go',
      tests: 'go test ./...',
      lint: 'go vet ./...',
      format: 'gofmt -w {arquivo}',
      evidence: ['go.mod'],
    );
  }
  if (has('Makefile')) {
    final mk = File('$path/Makefile').readAsStringSync();
    return StackDetection(
      name: 'Makefile',
      tests: RegExp(r'^test:', multiLine: true).hasMatch(mk)
          ? 'make test'
          : null,
      lint: RegExp(r'^lint:', multiLine: true).hasMatch(mk)
          ? 'make lint'
          : null,
      evidence: const ['Makefile'],
    );
  }
  return const StackDetection(name: 'Desconhecida');
}

/// Fills the empty commands of [config] with the detection (never
/// overwrites what the user wrote). Returns the new config and whether
/// anything changed.
(ProjectConfig, bool) applyDetection(ProjectConfig config, StackDetection d) {
  var out = config;
  var changed = false;
  if (config.testCommand == null && d.tests != null) {
    out = out.copyWith(testCommand: () => d.tests);
    changed = true;
  }
  if (config.lintCommand == null && d.lint != null) {
    out = out.copyWith(lintCommand: () => d.lint);
    changed = true;
  }
  if (config.formatCommand == null && d.format != null) {
    out = out.copyWith(formatCommand: () => d.format);
    changed = true;
  }
  if (config.worktree.prepare == null && d.prepare != null) {
    out = out.copyWith(
      worktree: WorktreeConfig(
        copy: config.worktree.copy,
        prepare: d.prepare,
        basePort: config.worktree.basePort,
      ),
    );
    changed = true;
  }
  return (out, changed);
}

/// Applies the detection to the workspace: config (empty fields only) and
/// a memory line. Returns whether the config changed.
Future<bool> applyDetectionToWorkspace(
  String path,
  StackDetection d, {
  DateTime? now,
}) async {
  final (config, changed) = applyDetection(ProjectConfig.loadSync(path), d);
  if (changed) await ProjectConfig.save(path, config);
  await ProjectMemory.record(
    path,
    MemoryEntry(
      text: 'Stack detectada: ${d.summary}',
      origin: 'análise',
      date: now ?? DateTime.now(),
    ),
    replacing: (e) => e.text.startsWith('Stack detectada:'),
  );
  return changed;
}
