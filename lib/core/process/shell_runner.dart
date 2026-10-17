import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Result of a project command (`testes:`, `lint:`, `preparar:`…).
@immutable
class ShellOutcome {
  const ShellOutcome({
    required this.exitCode,
    required this.output,
    required this.duration,
    this.timedOut = false,
  });

  /// -1 when it could not start or was killed by the timeout.
  final int exitCode;

  /// stdout + stderr interleaved, the last [shellMaxOutput] bytes.
  final String output;
  final Duration duration;
  final bool timedOut;

  bool get ok => exitCode == 0 && !timedOut;
}

/// Runs [command] with `bash -c` in [cwd]. [timeout] ends it with SIGTERM
/// on its whole process group, then SIGKILL.
typedef ShellRunner = Future<ShellOutcome> Function(
  String command, {
  required String cwd,
  required Duration timeout,
  Map<String, String>? environment,
});

/// Keeps the last [max] bytes of what was written (UTF-8, cut on a char).
class _Tail {
  _Tail(this.max);

  final int max;
  final _chunks = <List<int>>[];
  int _size = 0;
  bool cut = false;

  void add(List<int> data) {
    _chunks.add(data);
    _size += data.length;
    while (_size > max && _chunks.length > 1) {
      _size -= _chunks.removeAt(0).length;
      cut = true;
    }
  }

  String text() {
    var bytes = [for (final c in _chunks) ...c];
    if (bytes.length > max) {
      bytes = bytes.sublist(bytes.length - max);
      cut = true;
    }
    final s = utf8.decode(bytes, allowMalformed: true);
    return cut ? '…(início cortado)…\n$s' : s;
  }
}

const shellMaxOutput = 64 * 1024;

Future<ShellOutcome> runShell(
  String command, {
  required String cwd,
  required Duration timeout,
  Map<String, String>? environment,
}) async {
  final watch = Stopwatch()..start();
  Process p;
  try {
    // setsid: the command leads its own process group, so the timeout also
    // ends what it started (test runners, watchers).
    try {
      p = await Process.start(
        'setsid',
        ['bash', '-c', command],
        workingDirectory: cwd,
        environment: environment,
      );
    } on ProcessException {
      p = await Process.start(
        'bash',
        ['-c', command],
        workingDirectory: cwd,
        environment: environment,
      );
    }
  } on ProcessException catch (e) {
    return ShellOutcome(
      exitCode: -1,
      output: 'Não foi possível executar: ${e.message}',
      duration: watch.elapsed,
    );
  }
  final tail = _Tail(shellMaxOutput);
  final out = p.stdout.listen(tail.add).asFuture<void>();
  final err = p.stderr.listen(tail.add).asFuture<void>();
  var timedOut = false;
  int code;
  try {
    code = await p.exitCode.timeout(timeout);
  } on TimeoutException {
    timedOut = true;
    await _killGroup(p.pid, 'TERM');
    try {
      code = await p.exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      await _killGroup(p.pid, 'KILL');
      p.kill(ProcessSignal.sigkill);
      code = await p.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -1,
      );
    }
  }
  await Future.wait([out, err])
      .timeout(const Duration(seconds: 2), onTimeout: () => const []);
  watch.stop();
  var text = tail.text();
  if (timedOut) {
    text = '$text\n(encerrado após ${timeout.inSeconds} s sem terminar)';
  }
  return ShellOutcome(
    exitCode: timedOut ? -1 : code,
    output: text,
    duration: watch.elapsed,
    timedOut: timedOut,
  );
}

Future<void> _killGroup(int pid, String signal) async {
  try {
    await Process.run('kill', ['-$signal', '--', '-$pid']);
  } catch (_) {
    // already gone
  }
}

final shellRunnerProvider = Provider<ShellRunner>((ref) => runShell);
