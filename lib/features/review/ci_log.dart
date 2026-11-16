import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The excerpt of one failed job (SPEC-073 R3).
@immutable
class CiJobExcerpt {
  const CiJobExcerpt({
    required this.job,
    required this.step,
    required this.lines,
    this.alsoIn = const [],
    this.runId,
  });

  final String job;

  /// The step that failed (the last one in the job's log).
  final String step;

  /// The lines kept, with a line for every cut (see [ciCutLine]).
  final List<String> lines;

  /// Other jobs of a matrix with the same excerpt ("mesmo erro em …").
  final List<String> alsoIn;

  /// Run the job belongs to (for the full-log command), when known.
  final int? runId;

  /// The first line that looks like an error (the row of the Review).
  String? get firstError => lines
      .where((l) => !isCiCutLine(l) && ciErrorLine.hasMatch(l))
      .firstOrNull;

  CiJobExcerpt copyWith({List<String>? lines, List<String>? alsoIn}) =>
      CiJobExcerpt(
        job: job,
        step: step,
        lines: lines ?? this.lines,
        alsoIn: alsoIn ?? this.alsoIn,
        runId: runId,
      );
}

/// What [ciLogExcerpt] gives: the jobs that fit in the ceiling, the ones
/// that did not (only by name) and whether the log looks intermittent.
@immutable
class CiLogExcerpt {
  const CiLogExcerpt({
    this.jobs = const [],
    this.omittedJobs = const [],
    this.flaky,
    this.totalLines = 0,
  });

  final List<CiJobExcerpt> jobs;

  /// Jobs past the ceiling: the message names them with the full-log
  /// command.
  final List<String> omittedJobs;

  /// Why the failure looks intermittent (R8); null = it does not.
  final String? flaky;

  /// Lines of the raw log.
  final int totalLines;

  bool get isEmpty => jobs.isEmpty && omittedJobs.isEmpty;

  /// Lines kept, every job together.
  int get keptLines => jobs.fold(0, (n, j) => n + j.lines.length);
}

/// A line that looks like an error (kept with its context).
final ciErrorLine = RegExp(
  r'\berror\b|error:|##\[error\]|FAILED|\bfailed\b|Expected|exit code|'
  r'Exception|\[E\]',
  caseSensitive: false,
);

final _ansi = RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]');
final _stamp = RegExp(r'^\uFEFF?\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?Z ?');

/// `1204` → `1.204` (pt-BR).
String ciCount(int n) {
  final s = '$n';
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// The line that stands for a cut: `… 1.204 linhas cortadas (linhas
/// 12–1.215 de "Run flutter test") …`.
String ciCutLine(int from, int to, String step) {
  final n = to - from + 1;
  return '… ${ciCount(n)} ${n == 1 ? 'linha cortada' : 'linhas cortadas'} '
      '(${n == 1 ? 'linha ${ciCount(from)}' : 'linhas ${ciCount(from)}–${ciCount(to)}'} '
      'de "$step") …';
}

bool isCiCutLine(String l) => l.startsWith('… ') && l.endsWith(' …');

/// Reasons a log looks intermittent (R8), the first match wins.
const _flaky = <(String, String)>[
  (
    r'Could not resolve host|getaddrinfo|EAI_AGAIN|Temporary failure in name resolution',
    'host não resolvido',
  ),
  (r'ECONNRESET|connection reset', 'conexão reiniciada (ECONNRESET)'),
  (
    r'API rate limit|rate limit exceeded|429 Too Many Requests|secondary rate limit',
    'limite de requisições',
  ),
  (
    r'runner has received a shutdown signal|lost communication with the server|The hosted runner encountered an error',
    'runner desligado',
  ),
  (
    r'\bHTTP[/ 0-9.]* 5\d\d\b|\b50[234] (Bad Gateway|Service Unavailable|Gateway Time-?out)|status code 5\d\d|returned error: 5\d\d',
    'erro 5xx do servidor',
  ),
  (r'timed out|ETIMEDOUT|\btimeout\b', 'tempo esgotado'),
];

/// Why [log] looks like an intermittent failure (null = it does not).
String? ciFlakyReason(String log) {
  for (final (pattern, reason) in _flaky) {
    if (RegExp(pattern, caseSensitive: false).hasMatch(log)) return reason;
  }
  return null;
}

/// Cuts the output of `gh run view <run> --log-failed` (lines
/// `job<TAB>step<TAB>time text`) into what goes to the agent (SPEC-073 R3): per job and
/// step, without ANSI colours and the time at the start of the lines; in
/// each step the lines that look like errors with [context] lines around
/// them plus the [tail] last ones; every cut said in a line; matrix jobs
/// with the same excerpt once; at most [maxLines] lines and [maxChars]
/// characters, the jobs past it only by name. [runOf] gives the run of a
/// job, when the log of several runs was joined.
CiLogExcerpt ciLogExcerpt(
  String raw, {
  int maxLines = 200,
  int maxChars = 16000,
  int context = 5,
  int tail = 30,
  int? Function(String job)? runOf,
}) {
  // job → step → lines, in the order they appear.
  final jobs = <String, Map<String, List<String>>>{};
  var total = 0;
  for (final line in const LineSplitter().convert(raw)) {
    total++;
    final parts = line.split('\t');
    final String job, step, text;
    if (parts.length >= 3) {
      job = parts[0].trim();
      step = parts[1].trim();
      text = parts.skip(2).join('\t');
    } else {
      job = '';
      step = '';
      text = line;
    }
    final clean = text
        .replaceAll(_ansi, '')
        .replaceFirst(_stamp, '')
        .trimRight();
    jobs.putIfAbsent(job, () => {}).putIfAbsent(step, () => []).add(clean);
  }
  final flaky = ciFlakyReason(raw);

  final excerpts = <CiJobExcerpt>[];
  for (final MapEntry(key: job, value: steps) in jobs.entries) {
    final out = <String>[];
    for (final MapEntry(key: step, value: lines) in steps.entries) {
      final keep = List<bool>.filled(lines.length, false);
      for (var i = 0; i < lines.length; i++) {
        if (i >= lines.length - tail) keep[i] = true;
        if (ciErrorLine.hasMatch(lines[i])) {
          for (var k = i - context; k <= i + context; k++) {
            if (k >= 0 && k < lines.length) keep[k] = true;
          }
        }
      }
      var i = 0;
      while (i < lines.length) {
        if (keep[i]) {
          if (lines[i].trim().isNotEmpty || out.isNotEmpty) out.add(lines[i]);
          i++;
          continue;
        }
        final from = i;
        while (i < lines.length && !keep[i]) {
          i++;
        }
        out.add(ciCutLine(from + 1, i, step.isEmpty ? job : step));
      }
    }
    excerpts.add(
      CiJobExcerpt(
        job: job.isEmpty ? 'log' : job,
        step: steps.keys.lastOrNull ?? '',
        lines: out,
        runId: runOf?.call(job),
      ),
    );
  }

  // Matrix jobs with the same excerpt appear once.
  final merged = <CiJobExcerpt>[];
  String body(CiJobExcerpt e) =>
      e.lines.where((l) => !isCiCutLine(l)).join('\n');
  for (final e in excerpts) {
    final i = merged.indexWhere((m) => body(m) == body(e));
    if (i < 0) {
      merged.add(e);
    } else {
      merged[i] = merged[i].copyWith(alsoIn: [...merged[i].alsoIn, e.job]);
    }
  }

  // The ceiling: whole jobs while they fit; the first one, alone past it,
  // keeps its last lines.
  final kept = <CiJobExcerpt>[];
  final omitted = <String>[];
  var lines = 0, chars = 0;
  int size(List<String> l) => l.fold(0, (n, x) => n + x.length + 1);
  for (final e in merged) {
    final n = e.lines.length, c = size(e.lines);
    if (lines + n <= maxLines && chars + c <= maxChars) {
      kept.add(e);
      lines += n;
      chars += c;
      continue;
    }
    if (kept.isEmpty) {
      final room = <String>[];
      var roomChars = 0;
      for (final l in e.lines.reversed) {
        if (room.length + 1 >= maxLines ||
            roomChars + l.length + 1 > maxChars - 80) {
          break;
        }
        room.insert(0, l);
        roomChars += l.length + 1;
      }
      final cut = n - room.length;
      kept.add(
        e.copyWith(
          lines: [
            '… ${ciCount(cut)} ${cut == 1 ? 'linha cortada' : 'linhas cortadas'} '
                '(teto de ${ciCount(maxLines)} linhas e ${ciCount(maxChars)} '
                'caracteres; começo de "${e.step}") …',
            ...room,
          ],
        ),
      );
      lines = maxLines;
      chars = maxChars;
      continue;
    }
    omitted
      ..add(e.job)
      ..addAll(e.alsoIn);
  }
  return CiLogExcerpt(
    jobs: kept,
    omittedJobs: omitted,
    flaky: flaky,
    totalLines: total,
  );
}
