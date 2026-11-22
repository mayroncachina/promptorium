import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../process/process_runner.dart';

/// Optional integration with ai-memory (SPEC-098, decision 13 of #332):
/// the app finds it, wires its hooks and MCP through ai-memory's own
/// installers after a preview, and shows the project's handoffs. It never
/// installs, upgrades or starts ai-memory, and never reads its token: reads
/// go through `ai-memory call`, which authenticates by itself (P2, R13).

/// First version with the local history of the previous session in
/// `ai-memory run`, which SPEC-099 uses (P7). Below it: "versão antiga".
const aiMemoryMinVersion = '3.1.0';

/// Default server address (`AI_MEMORY_SERVER_URL` overrides it).
const aiMemoryDefaultServer = 'http://127.0.0.1:49374';

/// The project page, for the "não encontrado" card.
const aiMemoryRepoUrl = 'https://github.com/akitaonrails/ai-memory';

/// Limit of each read (R14).
const aiMemoryCallTimeout = Duration(seconds: 5);

/// Limit of the installers and of `doctor` (it asks Codex for the hooks'
/// trust, up to 15 s by itself).
const aiMemoryLongTimeout = Duration(seconds: 30);

/// Commands shown for each bad state (R1): the app only shows them.
const aiMemoryInstallCommand =
    'curl -fsSL https://github.com/akitaonrails/ai-memory/releases/latest/'
    'download/install.sh | sh\nai-memory setup --agent claude-code';
const aiMemoryStartCommand = 'systemctl --user start ai-memory';
const aiMemoryUpgradeCommand = 'ai-memory upgrade';

/// Runs ai-memory with a time limit, in [workingDirectory] (the CLI
/// resolves the project from it). Injected so tests fake the binary.
typedef AiMemoryRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  required Duration timeout,
});

/// The real runner: ends the process (and what it started) past the limit.
Future<ProcessResult> defaultAiMemoryRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  required Duration timeout,
}) => runKillingOnTimeout(
  executable,
  arguments,
  timeout: timeout,
  workingDirectory: workingDirectory,
);

/// HTTP status of a GET (null when nothing answered in [timeout]). Only for
/// `/healthz` and the web UI probe, which need no token (P2).
typedef AiMemoryHttpProbe = Future<int?> Function(Uri url, Duration timeout);

Future<int?> defaultAiMemoryHttpProbe(Uri url, Duration timeout) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final req = await client.getUrl(url).timeout(timeout);
    req.followRedirects = false;
    final res = await req.close().timeout(timeout);
    await res.drain<void>().timeout(timeout, onTimeout: () {});
    return res.statusCode;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Where ai-memory is: the first executable `ai-memory` in `PATH`, then in
/// `~/.local/bin` (where its installer puts it). Only looks at the disk: no
/// process runs (R2).
String? findAiMemory(Map<String, String> env) {
  final dirs = <String>[
    ...(env['PATH'] ?? '').split(':').where((d) => d.isNotEmpty),
    if (env['HOME'] case final home?) p.join(home, '.local', 'bin'),
  ];
  for (final dir in dirs) {
    final file = File(p.join(dir, 'ai-memory'));
    try {
      final stat = file.statSync();
      if (stat.type == FileSystemEntityType.notFound) continue;
      if (stat.type == FileSystemEntityType.directory) continue;
      // Any execute bit.
      if (stat.mode & 0x49 == 0) continue;
      return file.path;
    } catch (_) {
      continue;
    }
  }
  return null;
}

/// `x.y.z` of `ai-memory --version` ("ai-memory 3.5.1").
String? parseAiMemoryVersion(String out) =>
    RegExp(r'\d+\.\d+\.\d+').firstMatch(out)?.group(0);

int compareSemver(String a, String b) {
  List<int> parts(String v) => [
    for (final s in v.split('-').first.split('.')) int.tryParse(s) ?? 0,
  ];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// A failed ai-memory read: the panel shows [message] as one status line.
class AiMemoryException implements Exception {
  const AiMemoryException(this.message, {this.timedOut = false});
  final String message;
  final bool timedOut;

  @override
  String toString() => message;
}

/// Hides what looks like a credential in installer output before the app
/// shows it (R13: the token never appears on screen).
String redactAiMemoryOutput(String text) => text
    .replaceAllMapped(
      RegExp(
        r'((?:token|bearer|api[-_]?key|authorization|secret|ingest_key)'
        r'["\x27]?\s*[:=]?\s*["\x27]?)([A-Za-z0-9._\-]{12,})',
        caseSensitive: false,
      ),
      (m) => '${m[1]}•••',
    )
    .replaceAllMapped(
      RegExp(r'(Bearer\s+)\S+', caseSensitive: false),
      (m) => '${m[1]}•••',
    );

/// The ai-memory CLI. Every call has a limit; the log keeps only the
/// subcommand (or tool), the time and the exit code (R13).
class AiMemoryCli {
  AiMemoryCli({
    required this.executable,
    AiMemoryRunner? run,
    this.log = _debugLog,
  }) : _run = run ?? defaultAiMemoryRunner;

  final String executable;
  final AiMemoryRunner _run;
  final void Function(String line) log;

  static void _debugLog(String line) => debugPrint(line);

  Future<ProcessResult> _exec(
    List<String> args, {
    required String label,
    String? cwd,
    Duration timeout = aiMemoryCallTimeout,
  }) async {
    final watch = Stopwatch()..start();
    try {
      final r = await _run(
        executable,
        args,
        workingDirectory: cwd,
        timeout: timeout,
      );
      log(
        'ai-memory: $label · ${watch.elapsedMilliseconds} ms · '
        'saída ${r.exitCode}',
      );
      return r;
    } on TimeoutException {
      log('ai-memory: $label · tempo esgotado em ${timeout.inSeconds} s');
      throw AiMemoryException(
        'tempo esgotado em ${timeout.inSeconds} s',
        timedOut: true,
      );
    } on ProcessException {
      log('ai-memory: $label · não iniciou');
      throw const AiMemoryException('o ai-memory não iniciou');
    }
  }

  /// `ai-memory --version` → `x.y.z` (null when it did not answer).
  Future<String?> version() async {
    try {
      final r = await _exec(['--version'], label: '--version');
      if (r.exitCode != 0) return null;
      return parseAiMemoryVersion('${r.stdout}');
    } on AiMemoryException {
      return null;
    }
  }

  /// `ai-memory call <tool> '<json>'` in [cwd]: the CLI resolves the
  /// project (marker, git remote, worktrees) and the token by itself (P2).
  /// Returns the decoded JSON of the tool's answer.
  Future<Object?> call(
    String tool,
    Map<String, Object?> arguments, {
    required String cwd,
  }) async {
    final r = await _exec(
      ['call', tool, jsonEncode(arguments)],
      label: 'call $tool',
      cwd: cwd,
    );
    if (r.exitCode != 0) {
      throw AiMemoryException(
        'o ai-memory respondeu com erro (saída ${r.exitCode})',
      );
    }
    final out = '${r.stdout}'.trim();
    try {
      return jsonDecode(out);
    } on FormatException {
      // Some builds print a line before the JSON: take the first object.
      final start = out.indexOf('{');
      if (start >= 0) {
        try {
          return jsonDecode(out.substring(start));
        } on FormatException {
          // fall through
        }
      }
      throw const AiMemoryException('resposta do ai-memory não reconhecida');
    }
  }

  /// `ai-memory setup --plan --json --agent …`: what setup would wire and
  /// why each agent was detected. Changes nothing.
  Future<Map<String, Object?>?> setupPlan(List<String> agents) async {
    try {
      final r = await _exec(
        [
          'setup',
          '--plan',
          '--json',
          for (final a in agents) ...['--agent', a],
        ],
        label: 'setup --plan',
        timeout: const Duration(seconds: 10),
      );
      if (r.exitCode != 0) return null;
      final j = jsonDecode('${r.stdout}');
      return j is Map<String, Object?> ? j : null;
    } catch (_) {
      return null;
    }
  }

  /// `ai-memory uninstall --only <hooks|mcp>` without `--apply`: the
  /// dry-run that lists the ai-memory entries present in each agent's files.
  /// Read-only by contract ("without it, prints the removal plan").
  Future<String?> removalPlan(String only) async {
    try {
      final r = await _exec(
        ['uninstall', '--only', only],
        label: 'uninstall --only $only (prévia)',
        timeout: const Duration(seconds: 10),
      );
      if (r.exitCode != 0) return null;
      return '${r.stdout}';
    } catch (_) {
      return null;
    }
  }

  /// `ai-memory doctor --json` (read-only): whether Codex runs the hooks.
  Future<Map<String, Object?>?> doctor({String? cwd}) async {
    try {
      final r = await _exec(
        ['doctor', '--json'],
        label: 'doctor',
        cwd: cwd,
        timeout: aiMemoryLongTimeout,
      );
      if (r.exitCode != 0 && '${r.stdout}'.trim().isEmpty) return null;
      final j = jsonDecode('${r.stdout}');
      return j is Map<String, Object?> ? j : null;
    } catch (_) {
      return null;
    }
  }

  /// `ai-memory status --json`: the server's data dir (the wiki is in
  /// `<data_dir>/wiki/<workspace>/<project>`).
  Future<Map<String, Object?>?> status() async {
    try {
      final r = await _exec(['status', '--json'], label: 'status');
      if (r.exitCode != 0) return null;
      final j = jsonDecode('${r.stdout}');
      return j is Map<String, Object?> ? j : null;
    } catch (_) {
      return null;
    }
  }

  /// Runs one installer command the person confirmed (R4), returning the
  /// exit code and the output with credentials hidden.
  Future<({int exitCode, String output})> runConfirmed(
    List<String> args,
  ) async {
    try {
      final r = await _exec(
        args,
        label: args.take(2).join(' '),
        timeout: aiMemoryLongTimeout,
      );
      final out = [
        '${r.stdout}'.trim(),
        '${r.stderr}'.trim(),
      ].where((s) => s.isNotEmpty).join('\n');
      return (exitCode: r.exitCode, output: redactAiMemoryOutput(out));
    } on AiMemoryException catch (e) {
      return (exitCode: -1, output: e.message);
    }
  }
}
