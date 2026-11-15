import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// UTF-8 that replaces invalid bytes with U+FFFD instead of throwing: process
/// output may carry Latin-1 file names or contents (SPEC-071 R12).
const lenientUtf8 = Utf8Codec(allowMalformed: true);

/// Runs a short-lived process and returns its result (`Process.run` signature
/// subset). Injected so tests can fake executables.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// The real runner ([processRunnerProvider]'s default).
Future<ProcessResult> defaultProcessRunner(
  String executable,
  List<String> args,
) => Process.run(
  executable,
  args,
  stdoutEncoding: lenientUtf8,
  stderrEncoding: lenientUtf8,
);

final processRunnerProvider = Provider<ProcessRunner>(
  (ref) => defaultProcessRunner,
);

/// `Process.run` with a time limit that also ends the process: past
/// [timeout] it gets SIGTERM, then SIGKILL after [killGrace], and this waits
/// for it to exit before throwing [TimeoutException]. `Future.timeout` on
/// `Process.run` only abandons the future and leaves the process running
/// (SPEC-071 R16).
///
/// The process leads its own group (`setsid`, when available), so the
/// signals also reach what it started (MCP servers, hooks).
Future<ProcessResult> runKillingOnTimeout(
  String executable,
  List<String> args, {
  required Duration timeout,
  Duration killGrace = const Duration(seconds: 2),
}) async {
  Process p;
  var group = true;
  try {
    p = await Process.start('setsid', [executable, ...args]);
  } on ProcessException {
    group = false;
    p = await Process.start(executable, args);
  }
  final out = p.stdout.transform(lenientUtf8.decoder).join();
  final err = p.stderr.transform(lenientUtf8.decoder).join();
  // A child that inherited the pipes may keep them open after the exit.
  Future<String> drained(Future<String> f) =>
      f.timeout(killGrace, onTimeout: () => '');
  try {
    final code = await p.exitCode.timeout(timeout);
    return ProcessResult(p.pid, code, await drained(out), await drained(err));
  } on TimeoutException {
    Future<void> signal(ProcessSignal s) async {
      if (group) {
        try {
          await Process.run('kill', [
            '-${s.name.substring(3)}',
            '--',
            '-${p.pid}',
          ]);
        } catch (_) {}
      }
      p.kill(s);
    }

    await signal(ProcessSignal.sigterm);
    try {
      await p.exitCode.timeout(killGrace);
    } on TimeoutException {
      await signal(ProcessSignal.sigkill);
      await p.exitCode.timeout(killGrace, onTimeout: () => -1);
    }
    unawaited(out.catchError((_) => '').then((_) {}));
    unawaited(err.catchError((_) => '').then((_) {}));
    throw TimeoutException(
      '$executable não terminou em ${timeout.inSeconds} s',
      timeout,
    );
  }
}
