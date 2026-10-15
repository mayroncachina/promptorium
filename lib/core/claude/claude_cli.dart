import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../process/process_runner.dart';
import 'claude_process.dart' show ProcessStarter;

/// Result of locating the Claude Code CLI.
class ClaudeCliInfo {
  const ClaudeCliInfo({required this.executable, required this.version});

  /// Executable that answered `--version` (name on PATH or absolute path).
  final String executable;

  /// Semantic version, e.g. `2.1.300`.
  final String version;
}

class ClaudeCliNotFound implements Exception {
  const ClaudeCliNotFound(this.message, {this.details});

  final String message;
  final String? details;

  @override
  String toString() => details == null ? message : '$message ($details)';
}

/// Candidate executables, in order. Desktop launchers often lack
/// `~/.local/bin` on PATH, so the default install location is tried too.
final claudeExecutableCandidatesProvider = Provider<List<String>>((ref) {
  final home = Platform.environment['HOME'];
  return [
    'claude',
    if (home != null && home.isNotEmpty) '$home/.local/bin/claude',
  ];
});

/// Runs `claude --version` on each candidate until one answers.
Future<ClaudeCliInfo> detectClaudeCli({
  required ProcessRunner run,
  required List<String> candidates,
}) async {
  String? lastDetails;
  for (final exe in candidates) {
    try {
      final result = await run(exe, const ['--version']);
      if (result.exitCode != 0) {
        lastDetails = '$exe --version saiu com código ${result.exitCode}';
        continue;
      }
      final out = '${result.stdout}';
      final match = RegExp(r'\d+\.\d+\.\d+').firstMatch(out);
      if (match == null) {
        lastDetails = 'saída inesperada de $exe --version: ${out.trim()}';
        continue;
      }
      return ClaudeCliInfo(executable: exe, version: match.group(0)!);
    } on ProcessException catch (e) {
      lastDetails = e.message.isEmpty ? '$exe: não encontrado' : e.message;
    }
  }
  throw ClaudeCliNotFound(
    'Claude Code CLI não encontrado',
    details: lastDetails,
  );
}

/// CLI found by the startup check (`ClaudeCliStep`); null until it runs.
class ResolvedClaudeCli extends Notifier<ClaudeCliInfo?> {
  @override
  ClaudeCliInfo? build() => null;

  void set(ClaudeCliInfo? info) => state = info;
}

final resolvedClaudeCliProvider =
    NotifierProvider<ResolvedClaudeCli, ClaudeCliInfo?>(ResolvedClaudeCli.new);

/// Executable used to start sessions (`ClaudeProcess.start`): the one that
/// answered `--version` in the splash, else the first candidate.
final claudeExecutableProvider = Provider<String>(
  (ref) =>
      ref.watch(resolvedClaudeCliProvider)?.executable ??
      ref.watch(claudeExecutableCandidatesProvider).first,
);

/// `Process.start` replacement for `claude -p` processes (sessions and Prompt
/// conversations; tests feed fake CLI output). Null = real `Process.start`.
final claudeProcessStarterProvider = Provider<ProcessStarter?>((ref) => null);
