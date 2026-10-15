import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs a short-lived process and returns its result (`Process.run` signature
/// subset). Injected so tests can fake executables.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

Future<ProcessResult> _defaultRunner(String executable, List<String> args) =>
    Process.run(executable, args);

final processRunnerProvider = Provider<ProcessRunner>((ref) => _defaultRunner);
