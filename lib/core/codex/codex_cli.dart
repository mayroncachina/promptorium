import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../claude/claude_cli.dart'
    show ClaudeCliInfo, ClaudeCliNotFound, detectClaudeCli;
import '../claude/claude_process.dart' show ProcessStarter;
import '../process/process_runner.dart';

final codexExecutableCandidatesProvider = Provider<List<String>>((ref) {
  final home = Platform.environment['HOME'];
  return ['codex', if (home != null) '$home/.local/bin/codex'];
});

final codexCliInfoProvider = FutureProvider<ClaudeCliInfo?>((ref) async {
  try {
    return await detectClaudeCli(
      run: ref.watch(processRunnerProvider),
      candidates: ref.watch(codexExecutableCandidatesProvider),
    );
  } on ClaudeCliNotFound {
    // An absent optional CLI is a diagnostic, not a failed provider to retry.
    return null;
  }
});

final codexExecutableProvider = Provider<String>(
  (ref) =>
      ref.watch(codexCliInfoProvider).value?.executable ??
      ref.watch(codexExecutableCandidatesProvider).first,
);

final codexProcessStarterProvider = Provider<ProcessStarter?>((ref) => null);
