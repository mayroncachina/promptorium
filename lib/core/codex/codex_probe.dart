import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../claude/claude_process.dart' show ProcessStarter;
import '../process/process_runner.dart';
import 'codex_rpc.dart';

/// Lowest Codex CLI the app accepts (épico #332, decisão 10).
const codexMinVersion = '0.170.0';

/// Last version probed by SPEC-093; newer ones work with a warning.
const codexTestedVersion = '0.170';

/// App Server methods the adapter uses (SPEC-093 R2, `ADAPTADOR`).
const codexAdapterMethods = [
  'initialize',
  'account/read',
  'model/list',
  'thread/start',
  'thread/resume',
  'thread/fork',
  'turn/start',
  'turn/interrupt',
  'turn/steer',
  'item/commandExecution/requestApproval',
  'item/fileChange/requestApproval',
  'item/tool/requestUserInput',
  'thread/tokenUsage/updated',
  'turn/completed',
  'turn/started',
  'item/started',
  'item/completed',
  'item/agentMessage/delta',
  'serverRequest/resolved',
  'error',
  'account/rateLimits/read',
  'thread/compact/start',
];

/// Compares two `x.y.z` versions (missing parts = 0).
int compareVersions(String a, String b) {
  List<int> parts(String v) => [
    for (final p in v.split('.')) int.tryParse(p) ?? 0,
  ];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// Whether [version] is newer than the tested minor ([codexTestedVersion]).
bool codexNewerThanTested(String version) =>
    compareVersions(version, '$codexTestedVersion.999999') > 0;

/// Methods of [codexAdapterMethods] missing from the protocol of the
/// installed CLI: `codex app-server generate-json-schema` (0,05 s, no
/// model turn, P3) into a temporary folder, read and deleted.
Future<List<String>> codexMissingMethods(
  String executable,
  ProcessRunner run,
) async {
  final dir = await Directory.systemTemp.createTemp('promptorium-codex-');
  try {
    final r = await run(executable, [
      'app-server',
      'generate-json-schema',
      '--out',
      dir.path,
    ]);
    if (r.exitCode != 0) {
      throw StateError('generate-json-schema saiu com ${r.exitCode}');
    }
    return await missingMethodsIn(dir.path);
  } finally {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}

/// [codexAdapterMethods] absent from the schema files in [dir].
Future<List<String>> missingMethodsIn(String dir) async {
  final found = <String>{};
  for (final name in [
    'ClientRequest.json',
    'ServerRequest.json',
    'ServerNotification.json',
  ]) {
    final f = File('$dir/$name');
    if (!f.existsSync()) continue;
    final j = jsonDecode(await f.readAsString());
    for (final v in (j is Map ? j['oneOf'] : null) as List? ?? const []) {
      final e = ((v as Map)['properties'] as Map?)?['method']?['enum'];
      if (e is List && e.isNotEmpty) found.add('${e.first}');
    }
  }
  if (found.isEmpty) throw StateError('schema sem métodos');
  return [
    for (final m in codexAdapterMethods)
      if (!found.contains(m)) m,
  ];
}

/// One model of `model/list`.
class CodexModelInfo {
  const CodexModelInfo(this.id, this.efforts, this.modalities);

  factory CodexModelInfo.fromJson(Map<String, dynamic> j) => CodexModelInfo(
    '${j['id']}',
    [for (final e in j['efforts'] as List? ?? const []) '$e'],
    [
      for (final e in j['modalities'] as List? ?? const ['text']) '$e',
    ],
  );

  final String id;
  final List<String> efforts;
  final List<String> modalities;

  Map<String, dynamic> toJson() => {
    'id': id,
    'efforts': efforts,
    'modalities': modalities,
  };
}

/// What the App Server says at handshake, without a model turn: the model
/// catalog and the sandbox (SPEC-094 R7a, R8).
class CodexHandshake {
  const CodexHandshake({required this.models, this.sandboxWarning});

  final List<CodexModelInfo> models;

  /// `configWarning` / failed `command/exec` in `readOnly`: null = sandbox
  /// works on this machine.
  final String? sandboxWarning;

  bool get sandboxAvailable => sandboxWarning == null;
}

/// Starts `codex app-server`, reads `model/list` (paginated) and checks the
/// sandbox with `command/exec ["true"]` in `readOnly` (SPEC-093 achado 2).
/// No thread, no turn, no quota spent. Never changes the system.
Future<CodexHandshake> codexHandshake({
  required String executable,
  ProcessStarter? starter,
  String? workingDirectory,
  String clientVersion = '0.0.0',
  Duration timeout = const Duration(seconds: 15),
}) async {
  final Process process;
  try {
    process = await (starter ?? _start)(
      executable,
      const ['app-server'],
      workingDirectory: workingDirectory,
      environment: null,
    );
  } on ProcessException {
    throw StateError('Codex CLI não encontrado.');
  }
  final rpc = CodexRpc(process, timeout: timeout);
  String? warning;
  final sub = rpc.messages.stream.listen((m) {
    if (m['method'] == 'configWarning') {
      final p = m['params'];
      warning ??= p is Map ? '${p['summary'] ?? 'aviso do sandbox'}' : '';
    }
  });
  try {
    await rpc.request('initialize', {
      'clientInfo': {
        'name': 'promptorium',
        'title': 'Promptorium',
        'version': clientVersion,
      },
    });
    await rpc.write({'method': 'initialized', 'params': <String, dynamic>{}});
    final models = <CodexModelInfo>[];
    String? cursor;
    final seen = <String>{};
    do {
      final page = await rpc.request('model/list', {
        'limit': 100,
        'cursor': ?cursor,
      });
      for (final m in page['data'] as List? ?? const []) {
        if (m is! Map) continue;
        models.add(
          CodexModelInfo(
            '${m['id']}',
            [
              for (final e
                  in m['supportedReasoningEfforts'] as List? ?? const [])
                if (e is Map && e['reasoningEffort'] is String)
                  e['reasoningEffort'] as String,
            ],
            [
              for (final v in m['inputModalities'] as List? ?? const ['text'])
                '$v',
            ],
          ),
        );
      }
      cursor = page['nextCursor'] as String?;
      if (cursor != null && !seen.add(cursor)) break;
    } while (cursor != null);
    if (warning == null) {
      try {
        final exec = await rpc.request('command/exec', {
          'command': ['true'],
          'sandboxPolicy': {'type': 'readOnly'},
          'timeoutMs': 10000,
          'cwd': ?workingDirectory,
        });
        if (exec['exitCode'] != 0) {
          final err = '${exec['stderr'] ?? ''}'.trim();
          warning = err.isEmpty ? 'o sandbox não executou comandos' : err;
        }
      } catch (_) {
        // An older server without command/exec: rely on configWarning.
      }
    }
    return CodexHandshake(models: models, sandboxWarning: warning);
  } finally {
    await sub.cancel();
    await rpc.stop(timeout: const Duration(seconds: 2));
  }
}

Future<Process> _start(
  String exe,
  List<String> args, {
  String? workingDirectory,
  Map<String, String>? environment,
}) => Process.start(exe, args, workingDirectory: workingDirectory);

/// SPEC-096 R10a: without the sandbox the Codex never runs outside a
/// worktree (Prompt, sessions in the project root) nor without full access.
String codexNoSandboxMessage() =>
    'Codex · Sandbox do Codex indisponível nesta máquina: ele só roda em '
    'worktree com acesso total (YOLO). Para liberar: $codexSandboxFixCommand';

/// How to unblock the sandbox on Ubuntu 24.04 (the app never runs it).
const codexSandboxFixCommand =
    'sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0';
