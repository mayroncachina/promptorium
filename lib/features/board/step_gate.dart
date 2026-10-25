import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/git/git_service.dart';
import '../../core/process/shell_runner.dart';
import '../project/project_config.dart';
import 'test_count.dart';

/// One item of the step gate: the commit, the clean tree or a command.
@immutable
class GateCheck {
  const GateCheck({
    required this.name,
    required this.ok,
    this.output = '',
    this.duration = Duration.zero,
    this.command,
    this.count,
  });

  /// `commit`, `arvore`, `testes`, `contagem` (SPEC-023 R2), `lint`, `build`
  /// or `verificar` (criteria).
  final String name;
  final bool ok;
  final String output;
  final Duration duration;

  /// Shell command, for the command checks.
  final String? command;

  /// Passed / skipped tests of the `testes` check (null = no summary).
  final TestCount? count;

  String get label => switch (name) {
    'commit' => 'commit',
    'arvore' => 'árvore limpa',
    'contagem' => 'contagem de testes',
    _ => name,
  };

  GateCheck copyWith({bool? ok, String? output}) => GateCheck(
    name: name,
    ok: ok ?? this.ok,
    output: output ?? this.output,
    duration: duration,
    command: command,
    count: count,
  );

  Map<String, Object?> toJson() => {
    'nome': name,
    'ok': ok,
    'saida': output,
    'ms': duration.inMilliseconds,
    if (command != null) 'comando': command,
    if (count != null) 'contagem': count!.toJson(),
  };

  static GateCheck fromJson(Map<String, Object?> j) => GateCheck(
    name: '${j['nome'] ?? ''}',
    ok: j['ok'] == true,
    output: '${j['saida'] ?? ''}',
    duration: Duration(milliseconds: (j['ms'] as num?)?.toInt() ?? 0),
    command: j['comando'] as String?,
    count: TestCount.fromJson(j['contagem']),
  );
}

/// Result of [StepGate.run] (stored as JSON in `spec_steps.gate_report`).
@immutable
class GateReport {
  const GateReport({required this.checks, required this.at, this.attempt = 0});

  final List<GateCheck> checks;
  final DateTime at;

  /// Automatic resends already made when this report was taken.
  final int attempt;

  bool get ok => checks.every((c) => c.ok);

  List<GateCheck> get failures => [
    for (final c in checks)
      if (!c.ok) c,
  ];

  /// The only problem is uncommitted files ("Commitar o que sobrou").
  bool get onlyDirtyTree =>
      failures.isNotEmpty && failures.every((c) => c.name == 'arvore');

  /// The only problem is fewer tests than before ("Aceitar a redução",
  /// SPEC-023 R3).
  bool get onlyTestCount =>
      failures.isNotEmpty && failures.every((c) => c.name == 'contagem');

  /// Count of the `testes` check (null = not run or no summary).
  TestCount? get testCount =>
      checks.where((c) => c.name == 'testes').firstOrNull?.count;

  /// `testes, lint` / `ok`.
  String get summary => ok ? 'ok' : failures.map((c) => c.label).join(', ');

  String encode() => jsonEncode({
    'em': at.toIso8601String(),
    'tentativa': attempt,
    'checks': [for (final c in checks) c.toJson()],
  });

  static GateReport? decode(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    try {
      final j = jsonDecode(text);
      if (j is! Map) return null;
      return GateReport(
        at: DateTime.tryParse('${j['em']}') ?? DateTime(1970),
        attempt: (j['tentativa'] as num?)?.toInt() ?? 0,
        checks: [
          for (final c in (j['checks'] as List? ?? const []))
            if (c is Map) GateCheck.fromJson(c.cast<String, Object?>()),
        ],
      );
    } on FormatException {
      return null;
    }
  }
}

/// Last [lines] lines of [text] (the end of a test run has the summary).
String tailLines(String text, int lines) {
  final all = text.trimRight().split('\n');
  if (all.length <= lines) return all.join('\n');
  return '…\n${all.sublist(all.length - lines).join('\n')}';
}

/// Message sent to the session when the gate fails and attempts remain.
String gateRetryMessage(GateReport report, List<String> steps) {
  final b = StringBuffer()
    ..writeln(
      'A verificação do Promptorium falhou: ${report.summary}. '
      'A etapa ainda não foi aceita.',
    );
  for (final c in report.failures) {
    b
      ..writeln()
      ..writeln(
        c.command == null
            ? '### ${c.label}'
            : '### ${c.label} (`${c.command}`)',
      )
      ..writeln('```')
      ..writeln(tailLines(c.output, 40))
      ..writeln('```');
  }
  b
    ..writeln()
    ..writeln(
      'Corrija, faça commit e repita a linha exata: '
      'ETAPA CONCLUÍDA: ${steps.join(', ')}',
    );
  return b.toString().trimRight();
}

/// Checks a step before it is accepted, in its worktree and outside the
/// agent: commit of the step since [run]'s `startSha`, clean tree, then the
/// project's `testes:` / `lint:` / `build:` and the criteria's `verificar:`.
/// Commands stop at the first failure (the rest would only add noise).
/// With `contar-testes` on, the count of `testes:` is compared with
/// [run]'s `baseline` (SPEC-023 R2): a drop fails the `contagem` item, but
/// the other commands still run, so accepting the drop accepts nothing else.
class StepGate {
  StepGate({required this.git, required this.shell});

  final GitService git;
  final ShellRunner shell;

  Future<GateReport> run({
    required String specCode,
    required List<String> steps,
    required String? startSha,
    required ProjectConfig config,
    List<String> extraCommands = const [],
    Map<String, String>? environment,
    int attempt = 0,
    TestCount? baseline,
  }) async {
    final gate = config.gate;
    final checks = <GateCheck>[];
    if (gate.requireCommit) {
      checks.add(await _commit(specCode, steps, startSha));
    }
    if (gate.requireCleanTree) checks.add(await _tree());
    final commands = [
      if (config.testCommand case final c?) ('testes', c),
      if (config.lintCommand case final c?) ('lint', c),
      if (config.buildCommand case final c?) ('build', c),
      for (final c in extraCommands) ('verificar', c),
    ];
    for (final (name, cmd) in commands) {
      final r = await shell(
        cmd,
        cwd: git.repoRoot,
        timeout: gate.timeout,
        environment: environment,
      );
      // The summary is parsed before the output is cut to its tail.
      final count = name == 'testes' && r.ok ? parseTestCount(r.output) : null;
      checks.add(
        GateCheck(
          name: name,
          ok: r.ok,
          output: r.ok ? tailLines(r.output, 20) : r.output,
          duration: r.duration,
          command: cmd,
          count: count,
        ),
      );
      if (!r.ok) break;
      if (name == 'testes' && gate.countTests) {
        checks.add(countCheck(baseline, count, cmd));
      }
    }
    return GateReport(checks: checks, at: DateTime.now(), attempt: attempt);
  }

  /// `contagem` item: [after] against [before] (SPEC-023 R2); without one
  /// of them it passes, saying why it was not compared (R4).
  static GateCheck countCheck(
    TestCount? before,
    TestCount? after,
    String command,
  ) {
    if (after == null) {
      return GateCheck(
        name: 'contagem',
        ok: true,
        output:
            'contagem não conferida: a saída de `$command` não tem um '
            'resumo reconhecido.',
      );
    }
    if (before == null) {
      return GateCheck(
        name: 'contagem',
        ok: true,
        output:
            'contagem não conferida: a spec não tem gate aprovado anterior '
            'com contagem (agora: $after).',
      );
    }
    return GateCheck(
      name: 'contagem',
      ok: !after.droppedFrom(before),
      output: 'antes: $before · depois: $after',
    );
  }

  Future<GateCheck> _commit(
    String code,
    List<String> steps,
    String? startSha,
  ) async {
    if (startSha == null) {
      return const GateCheck(
        name: 'commit',
        ok: true,
        output: 'Início da etapa desconhecido: commit não conferido.',
      );
    }
    final List<String> subjects;
    try {
      subjects = await git.subjectsSince(startSha);
    } on GitException catch (e) {
      return GateCheck(name: 'commit', ok: false, output: '$e');
    }
    final mine = [
      for (final s in subjects)
        if (s.toUpperCase().startsWith(code.toUpperCase())) s,
    ];
    final missing = [
      for (final st in steps)
        if (!mine.any(
          (s) => RegExp('\\b$st\\b', caseSensitive: false).hasMatch(s),
        ))
          st,
    ];
    if (missing.isEmpty) {
      return GateCheck(name: 'commit', ok: true, output: mine.join('\n'));
    }
    final seen = subjects.isEmpty
        ? 'Nenhum commit desde o início da etapa.'
        : 'Commits desde o início da etapa:\n${subjects.join('\n')}';
    return GateCheck(
      name: 'commit',
      ok: false,
      output:
          'Falta um commit com a mensagem "$code ${missing.join(', ')}: …".\n'
          '$seen',
    );
  }

  Future<GateCheck> _tree() async {
    try {
      final st = await git.status();
      if (st.isEmpty) return const GateCheck(name: 'arvore', ok: true);
      final shown = st.take(30).map((e) => e.toString()).join('\n');
      final more = st.length > 30 ? '\n… e mais ${st.length - 30}' : '';
      return GateCheck(
        name: 'arvore',
        ok: false,
        output: 'Arquivos sem commit:\n$shown$more',
      );
    } on GitException catch (e) {
      return GateCheck(name: 'arvore', ok: false, output: '$e');
    }
  }
}
