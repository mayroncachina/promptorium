import 'package:flutter/foundation.dart';

/// Tests that passed and were skipped in one run of the `testes:` command
/// (SPEC-023 R1), compared by the gate against the spec's last approved one.
@immutable
class TestCount {
  const TestCount({required this.passed, this.skipped = 0});

  final int passed;
  final int skipped;

  /// Fewer passing or more skipped than [before] (SPEC-023 R2).
  bool droppedFrom(TestCount before) =>
      passed < before.passed || skipped > before.skipped;

  Map<String, Object?> toJson() => {'passaram': passed, 'pulados': skipped};

  static TestCount? fromJson(Object? j) {
    if (j is! Map) return null;
    final p = j['passaram'], s = j['pulados'];
    if (p is! num) return null;
    return TestCount(passed: p.toInt(), skipped: s is num ? s.toInt() : 0);
  }

  /// `751 passaram, 0 pulados`.
  @override
  String toString() => '$passed passaram, $skipped pulados';

  @override
  bool operator ==(Object other) =>
      other is TestCount && other.passed == passed && other.skipped == skipped;

  @override
  int get hashCode => Object.hash(passed, skipped);
}

final _ansi = RegExp(r'\x1B\[[0-9;?]*[A-Za-z]');

/// Count in the summary of a test run (the whole output: the gate keeps
/// only its tail). Recognised: `flutter test` / `dart test`
/// (`+751 ~2: All tests passed!`), pytest (`12 passed, 1 skipped in 0.30s`),
/// jest (`Tests: 1 skipped, 3 passed, 4 total`), vitest
/// (`Tests  3 passed | 1 skipped (4)`) and cargo (`test result: ok. 12
/// passed; 0 failed; 1 ignored`, summed over the crates). Null = no summary.
TestCount? parseTestCount(String output) {
  final text = output.replaceAll(_ansi, '').replaceAll('\r', '\n');
  int n(Match m, int group) => int.tryParse(m.group(group) ?? '') ?? 0;
  int field(String line, String word) {
    final m = RegExp('\\b(\\d+) $word\\b').firstMatch(line);
    return m == null ? 0 : n(m, 1);
  }

  // cargo: one "test result" per test binary (unit, integration, doc).
  final cargo = RegExp(
    r'test result: \w+\. (\d+) passed; \d+ failed; (\d+) ignored',
  ).allMatches(text).toList();
  if (cargo.isNotEmpty) {
    return TestCount(
      passed: cargo.fold(0, (a, m) => a + n(m, 1)),
      skipped: cargo.fold(0, (a, m) => a + n(m, 2)),
    );
  }
  // jest (`Tests:`) and vitest (`Tests  …`); not "Test Files" / "Test Suites".
  final js = RegExp(
    r'^\s*Tests:?\s+(.*\bpassed\b.*)$',
    multiLine: true,
  ).allMatches(text).lastOrNull;
  if (js != null) {
    final line = js.group(1)!;
    return TestCount(
      passed: field(line, 'passed'),
      skipped: field(line, 'skipped') + field(line, 'todo'),
    );
  }
  // flutter test / dart test: the last progress line.
  final dart = RegExp(r'\+(\d+)(?: ~(\d+))?(?: -\d+)?: All tests passed!')
      .allMatches(text)
      .lastOrNull;
  if (dart != null) return TestCount(passed: n(dart, 1), skipped: n(dart, 2));
  // pytest: `==== 12 passed, 1 skipped, 2 warnings in 0.30s ====` (or -q).
  final py = RegExp(
    r'^[=\s]*(.*\b\d+ passed\b.*\bin [\d.]+\s*s.*)$',
    multiLine: true,
  ).allMatches(text).lastOrNull;
  if (py != null) {
    final line = py.group(1)!;
    return TestCount(
      passed: field(line, 'passed'),
      skipped: field(line, 'skipped'),
    );
  }
  return null;
}
