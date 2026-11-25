import 'dart:async';
import 'dart:io';

import '../claude/claude_process.dart' show ProcessStarter;
import '../providers/agent_provider.dart' show AgentUnavailable;
import 'codex_mcp_overrides.dart';
import 'codex_provider.dart' show codexThreadApproval, codexThreadSandbox;
import 'codex_rpc.dart';

/// Thread operations of the App Server that never start a turn (SPEC-110):
/// no model call, no quota. Shapes of the 0.170 schema (`codex app-server
/// generate-json-schema`), checked against the real binary with a local
/// model provider:
///
/// - `thread/revert` needs the thread loaded in that connection and a
///   `paginated` thread (the default since 0.170);
/// - a thread has one writer at a time: while the session's process is
///   alive, only its connection can revert it;
/// - a fork keeps the ids of the turns, and the copy stays whole after the
///   original is reverted.
///
/// The files of `~/.codex/sessions` are never read nor written (R4).
class CodexThreadOps {
  CodexThreadOps(this._request, {this.timeout = const Duration(seconds: 10)});

  /// Over a connection that finished `initialize`.
  factory CodexThreadOps.of(
    CodexRpc rpc, {
    Duration timeout = const Duration(seconds: 10),
  }) => CodexThreadOps(rpc.request, timeout: timeout);

  final Future<Map<String, dynamic>> Function(
    String method,
    Map<String, dynamic> params,
  )
  _request;

  /// Limit of each request.
  final Duration timeout;

  Future<Map<String, dynamic>> _call(
    String method,
    Map<String, dynamic> params,
  ) => _request(method, params).timeout(
    timeout,
    onTimeout: () => throw AgentUnavailable(
      'o App Server não respondeu em ${timeout.inSeconds} s ($method)',
    ),
  );

  /// Same policy as every thread the app opens (SPEC-093 D1): `read-only`
  /// never saves trust in `~/.codex/config.toml`.
  Map<String, dynamic> _open(String threadId, String? cwd) => {
    'threadId': threadId,
    'excludeTurns': true,
    'cwd': ?cwd,
    'sandbox': codexThreadSandbox,
    'approvalPolicy': codexThreadApproval,
  };

  /// Loads the thread in this connection, without a turn.
  Future<void> resume(String threadId, {String? cwd}) async {
    final r = await _call('thread/resume', _open(threadId, cwd));
    final id = (r['thread'] as Map?)?['id'];
    if (id != threadId) {
      throw const AgentUnavailable('o Codex não retomou a thread da sessão');
    }
  }

  /// A copy of the whole conversation (`thread/fork`, not ephemeral): its
  /// id.
  Future<String> fork(String threadId, {String? cwd}) async {
    final r = await _call('thread/fork', {
      ..._open(threadId, cwd),
      'ephemeral': false,
    });
    final id = (r['thread'] as Map?)?['id'];
    if (id is! String || id.isEmpty || id == threadId) {
      throw const AgentUnavailable('o Codex não devolveu a cópia da conversa');
    }
    return id;
  }

  /// Drops the turn [beforeTurnId] and every later one from the history of
  /// the thread (`thread/revert`). The thread must be loaded here.
  Future<void> revert(String threadId, String beforeTurnId) async {
    final r = await _call('thread/revert', {
      'threadId': threadId,
      'beforeTurnId': beforeTurnId,
    });
    if (r['thread'] is! Map) {
      throw const AgentUnavailable('o Codex não confirmou a volta da conversa');
    }
  }

  /// Fails when the thread does not exist (any more).
  Future<void> check(String threadId) async {
    final r = await _call('thread/read', {
      'threadId': threadId,
      'includeTurns': false,
    });
    if ((r['thread'] as Map?)?['id'] != threadId) {
      throw const AgentUnavailable('o Codex não achou a cópia da conversa');
    }
  }

  Future<void> archive(String threadId) async {
    await _call('thread/archive', {'threadId': threadId});
  }

  /// The saved output of one item of a turn (`thread/items/list`); null
  /// when the thread has no such item (or it has no output).
  Future<String?> itemOutput(
    String threadId,
    String turnId,
    String itemId,
  ) async {
    String? cursor;
    final seen = <String>{};
    do {
      final r = await _call('thread/items/list', {
        'threadId': threadId,
        'turnId': turnId,
        'limit': 100,
        'cursor': ?cursor,
      });
      for (final e in r['data'] as List? ?? const []) {
        final item = e is Map ? e['item'] : null;
        if (item is! Map || item['id'] != itemId) continue;
        final out = item['aggregatedOutput'];
        return out is String ? CodexRpc.redact(out) : null;
      }
      cursor = r['nextCursor'] as String?;
      if (cursor != null && !seen.add(cursor)) return null;
    } while (cursor != null);
    return null;
  }
}

/// Runs [job] over a short-lived `codex app-server` (no turn): started,
/// initialized, closed. [loadsThread] = the job resumes or forks a thread,
/// which starts the MCP servers of the person's configuration: they are
/// turned off for this process (when they can be listed).
Future<T> withCodexThreadOps<T>(
  Future<T> Function(CodexThreadOps ops) job, {
  required String executable,
  ProcessStarter? starter,
  CodexMcpLister? mcpLister,
  String? cwd,
  String clientVersion = '0.0.0',
  bool loadsThread = false,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final dir = cwd != null && Directory(cwd).existsSync()
      ? cwd
      : Directory.systemTemp.path;
  final args = ['app-server'];
  if (loadsThread) {
    try {
      final servers = await (mcpLister ?? defaultCodexMcpLister)(
        executable,
        dir,
      );
      args.addAll(codexMcpOverrides(servers: servers, readOnly: true));
    } catch (_) {
      // Not listed: they start, and nobody calls them (there is no turn).
    }
  }
  final Process process;
  try {
    process = await (starter ?? _start)(
      executable,
      args,
      workingDirectory: dir,
      environment: null,
    );
  } on ProcessException {
    throw const AgentUnavailable('Codex CLI não encontrado');
  }
  final rpc = CodexRpc(process, timeout: timeout, ephemeral: true);
  final sub = rpc.messages.stream.listen((_) {});
  try {
    final ops = CodexThreadOps.of(rpc, timeout: timeout);
    await ops._call('initialize', {
      'clientInfo': {
        'name': 'promptorium',
        'title': 'Promptorium',
        'version': clientVersion,
      },
    });
    await rpc.write({'method': 'initialized', 'params': <String, dynamic>{}});
    return await job(ops);
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

/// Why a thread operation failed, in words for the timeline (R8): without
/// the class name or the JSON of the RPC error.
String codexThreadFailure(Object e) {
  var text = '$e'.trim();
  final m = RegExp(r'message: ([^,}]+)').firstMatch(text);
  if (m != null) text = m.group(1)!.trim();
  text = text.replaceFirst(RegExp(r'^Codex:\s*'), '').trim();
  final low = text.toLowerCase();
  if (low.contains('active writer')) {
    return 'outro processo do Codex está com esta conversa aberta';
  }
  if (low.contains('turn not found')) {
    return 'o turno não está mais na conversa do Codex';
  }
  if (low.contains('thread not found') || low.contains('no rollout found')) {
    return 'o Codex não achou a conversa desta sessão';
  }
  if (low.contains('does not use paginated history') ||
      low.contains('not paginated')) {
    return 'esta conversa é de uma versão antiga do Codex e não volta';
  }
  if (low.contains('is archived')) return 'a conversa foi arquivada';
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return text.isEmpty ? 'erro do App Server' : text;
}
