import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/review/ci_log.dart';

/// A line of `gh run view --log-failed`.
String row(String job, String step, String text) =>
    '$job\t$step\t2026-11-15T10:00:00.1234567Z $text';

void main() {
  test('a 5.000-line log fits in the ceiling and says what it cut', () {
    final raw = [
      for (var i = 1; i <= 5000; i++)
        row(
          'test (ubuntu)',
          'Run flutter test',
          i == 1500
              ? '\x1B[31mExpected: <90.0>\x1B[0m'
              : 'linha $i de saída comum',
        ),
    ].join('\n');
    final e = ciLogExcerpt(raw);
    expect(e.totalLines, 5000);
    expect(e.keptLines, lessThanOrEqualTo(200));
    final text = e.jobs.single.lines.join('\n');
    expect(text.length, lessThanOrEqualTo(16000));
    // ANSI and the time are gone; the error keeps 5 lines around it.
    expect(text, contains('Expected: <90.0>'));
    expect(text, isNot(contains('\x1B')));
    expect(text, isNot(contains('2026-11-15T')));
    expect(text, contains('linha 1495 de saída comum'));
    expect(text, contains('linha 1505 de saída comum'));
    expect(text, isNot(contains('linha 1506 de saída comum')));
    // The 30 last lines, and every cut said.
    expect(text, contains('linha 4971 de saída comum'));
    expect(text, contains('linha 5000 de saída comum'));
    expect(
      e.jobs.single.lines.first,
      '… 1.494 linhas cortadas (linhas 1–1.494 de "Run flutter test") …',
    );
    expect(
      e.jobs.single.lines,
      contains(
        '… 3.465 linhas cortadas (linhas 1.506–4.970 de "Run flutter test") …',
      ),
    );
    expect(e.jobs.single.step, 'Run flutter test');
    expect(e.jobs.single.firstError, contains('Expected'));
    expect(e.flaky, isNull);
  });

  test('several jobs and steps; matrix jobs with the same error once', () {
    String job(String name) => [
      row(name, 'Set up job', 'Preparando'),
      row(name, 'Run flutter test', 'test/a_test.dart: soma [E]'),
      row(
        name,
        'Run flutter test',
        '##[error]Process completed with exit code 1.',
      ),
    ].join('\n');
    final raw = [
      job('test (ubuntu)'),
      job('test (macos)'),
      row(
        'lint',
        'Run flutter analyze',
        "error • The getter 'total' isn't defined",
      ),
    ].join('\n');
    final e = ciLogExcerpt(raw, runOf: (j) => j == 'lint' ? 2 : 1);
    expect(e.jobs.map((j) => j.job), ['test (ubuntu)', 'lint']);
    expect(e.jobs.first.alsoIn, ['test (macos)']);
    expect(e.jobs.first.step, 'Run flutter test');
    expect(e.jobs.first.runId, 1);
    expect(e.jobs.last.runId, 2);
    expect(e.jobs.last.lines.single, contains("getter 'total'"));
  });

  test('past the ceiling the jobs left appear only by name', () {
    String job(String name, int n) =>
        [for (var i = 0; i < n; i++) row(name, 'Run', 'erro $name $i: error')]
            .join('\n');
    final raw = [job('a', 150), job('b', 150), job('c', 10)].join('\n');
    final e = ciLogExcerpt(raw);
    expect(e.jobs.map((j) => j.job), ['a', 'c']);
    expect(e.omittedJobs, ['b']);
    expect(e.keptLines, lessThanOrEqualTo(200));
  });

  test('one huge job alone keeps its last lines within the ceiling', () {
    final raw = [for (var i = 0; i < 400; i++) row('a', 'Run', 'error $i')]
        .join('\n');
    final e = ciLogExcerpt(raw);
    final lines = e.jobs.single.lines;
    expect(lines.length, lessThanOrEqualTo(200));
    expect(lines.first, startsWith('… '));
    expect(lines.first, contains('teto de 200 linhas'));
    expect(lines.last, 'error 399');
  });

  test('intermittent: timeouts, resets, DNS, 5xx, rate limit, runner', () {
    expect(
      ciFlakyReason('curl: (6) Could not resolve host: pub.dev'),
      'host não resolvido',
    );
    expect(ciFlakyReason('read ECONNRESET'), 'conexão reiniciada (ECONNRESET)');
    expect(
      ciFlakyReason('API rate limit exceeded for 1.2.3.4'),
      'limite de requisições',
    );
    expect(ciFlakyReason('502 Bad Gateway'), 'erro 5xx do servidor');
    expect(
      ciFlakyReason('The runner has received a shutdown signal.'),
      'runner desligado',
    );
    expect(ciFlakyReason('Test timed out after 30 seconds'), 'tempo esgotado');
    expect(ciFlakyReason('Expected: <90.0> Actual: <100.0>'), isNull);
    expect(
      ciLogExcerpt(row('a', 'Run', 'npm ERR! ETIMEDOUT')).flaky,
      'tempo esgotado',
    );
  });

  test('cut lines in pt-BR', () {
    expect(ciCount(1204), '1.204');
    expect(ciCount(12), '12');
    expect(ciCutLine(3, 3, 'Run'), '… 1 linha cortada (linha 3 de "Run") …');
  });
}
