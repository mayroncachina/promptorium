import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_cli.dart' show claudeExecutableProvider;
import 'mcp_config.dart';

/// Connection state of a server (from `claude mcp list/get` or
/// `system/init.mcp_servers[].status`).
enum McpConnState {
  connected('Conectado'),
  failed('Falhou'),
  pending('Aguardando aprovação'),
  needsAuth('Precisa autenticar'),
  disabled('Desligado'),
  checking('Verificando…'),
  unknown('Desconhecido');

  const McpConnState(this.label);

  final String label;

  /// `system/init` status strings (`connected`, `failed`, `pending`,
  /// `needs-auth`, `disabled`).
  static McpConnState fromInit(String s) => switch (s) {
    'connected' => connected,
    'failed' => failed,
    'pending' => pending,
    'needs-auth' => needsAuth,
    'disabled' => disabled,
    _ => unknown,
  };

  /// Text after the symbol in `claude mcp list/get` (`Connected`,
  /// `Failed to connect`, `Pending approval (run …)`).
  static McpConnState fromText(String s) {
    final t = s.toLowerCase();
    if (t.startsWith('connected')) return connected;
    if (t.contains('failed')) return failed;
    if (t.contains('pending')) return pending;
    if (t.contains('auth')) return needsAuth;
    if (t.contains('disabled')) return disabled;
    return unknown;
  }
}

/// One server line of `claude mcp list`.
@immutable
class McpListEntry {
  const McpListEntry({
    required this.name,
    required this.target,
    required this.state,
    required this.statusText,
    this.detail,
    this.isHttp = false,
  });

  final String name;

  /// Command line or URL as printed (without the ` (HTTP)` suffix).
  final String target;
  final McpConnState state;

  /// e.g. `Failed to connect`.
  final String statusText;

  /// e.g. `CONNECTION_CLOSED: Connection closed`.
  final String? detail;
  final bool isHttp;
}

/// Status of one server from `claude mcp get <name>` (only the `Status:`,
/// `Issue:` and `Scope:` lines are kept: the output also prints env and
/// header **values**, which are never read).
@immutable
class McpGetStatus {
  const McpGetStatus({
    required this.state,
    this.statusText,
    this.issue,
    this.scope,
  });

  final McpConnState state;
  final String? statusText;
  final String? issue;
  final String? scope;
}

/// Parses the output of `claude mcp list` (CLI 2.1.300, plano Fase 11):
///
/// ```
/// Checking MCP server health…
///
/// usr-fake: /bin/false  - ✘ Failed to connect — CONNECTION_CLOSED: Connection closed
/// fake-ok: python3 -I /x/fake_mcp.py - ✔ Connected
/// web-bad: http://127.0.0.1:9/mcp (HTTP) - ✘ Failed to connect — ECONNREFUSED: …
/// eco: /bin/true  - ⏸ Pending approval (run `claude` to approve)
///
/// MCP config diagnostics ⚠
/// …
/// ```
/// Lines before the first entry are skipped; parsing stops at the first
/// blank line after the entries (the diagnostics block). Never throws.
List<McpListEntry> parseMcpList(String stdout) {
  // Greedy target: the status is after the LAST " - <symbol> ".
  final line = RegExp(r'^([^:\s][^:]*?): (.*)\s- (\S) (.+)$');
  final out = <McpListEntry>[];
  var started = false;
  for (final raw in const LineSplitter().convert(stdout)) {
    final l = raw.trimRight();
    if (l.trim().isEmpty) {
      if (started) break;
      continue;
    }
    final m = line.firstMatch(l);
    if (m == null) continue;
    started = true;
    var target = m[2]!.trim();
    final isHttp = target.endsWith('(HTTP)') || target.endsWith('(SSE)');
    if (isHttp) target = target.substring(0, target.lastIndexOf('(')).trim();
    final rest = m[4]!.trim();
    final dash = rest.indexOf(' — ');
    final status = dash < 0 ? rest : rest.substring(0, dash).trim();
    final detail = dash < 0 ? null : rest.substring(dash + 3).trim();
    out.add(
      McpListEntry(
        name: m[1]!.trim(),
        target: target,
        state: McpConnState.fromText(status),
        statusText: status,
        detail: detail,
        isHttp: isHttp,
      ),
    );
  }
  return out;
}

/// Parses `claude mcp get <name>`; only `Status:` / `Issue:` / `Scope:`.
McpGetStatus parseMcpGet(String stdout) {
  String? status, issue, scope;
  for (final raw in const LineSplitter().convert(stdout)) {
    final l = raw.trim();
    if (l.startsWith('Status:')) {
      status = l.substring(7).trim();
      // Drop the symbol (✔ ✘ ⏸ …).
      final sp = status.indexOf(' ');
      if (sp > 0 && sp <= 2) status = status.substring(sp + 1).trim();
    } else if (l.startsWith('Issue:')) {
      issue = l.substring(6).trim();
    } else if (l.startsWith('Scope:')) {
      scope = l.substring(6).trim();
    }
  }
  return McpGetStatus(
    state: status == null
        ? McpConnState.unknown
        : McpConnState.fromText(status),
    statusText: status,
    issue: issue,
    scope: scope,
  );
}

/// Input of `claude mcp add`.
@immutable
class McpAddRequest {
  const McpAddRequest({
    required this.name,
    required this.scope,
    required this.transport,
    this.command,
    this.args = const [],
    this.url,
    this.env = const {},
    this.headers = const {},
  });

  final String name;
  final McpScope scope;

  /// stdio, http or sse (`-t/--transport` of `claude mcp add --help`).
  final McpTransport transport;
  final String? command;
  final List<String> args;
  final String? url;
  final Map<String, String> env;
  final Map<String, String> headers;

  /// Values that must never appear in messages shown to the user.
  Iterable<String> get secretValues =>
      [...env.values, ...headers.values].where((v) => v.length >= 3);
}

class McpException implements Exception {
  const McpException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Server names accepted by the CLI ("Names can only contain letters,
/// numbers, hyphens, and underscores" — 2.1.300).
final mcpNamePattern = RegExp(r'^[A-Za-z0-9_-]+$');
final _envKey = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
final _headerKey = RegExp(r"^[A-Za-z0-9!#$%&'*+.^_`|~-]+$");

/// Arguments of `claude mcp add` (flags from `claude mcp add --help`,
/// 2.1.300):
/// `mcp add -s <scope> -t <transport> [-e K=V]… [-H "K: V"]… -- <name> <commandOrUrl> [args…]`.
///
/// `-e`/`-H` are variadic (`<env...>`), so every operand goes after `--`
/// (otherwise the name would be eaten as another env value). Verified with
/// a temporary `CLAUDE_CONFIG_DIR` (plano Fase 11). Throws [McpException].
List<String> buildMcpAddArgs(McpAddRequest r) {
  if (!mcpNamePattern.hasMatch(r.name)) {
    throw const McpException(
      'Nome inválido: use letras, números, hífens e sublinhados.',
    );
  }
  final stdio = r.transport == McpTransport.stdio;
  if (!stdio &&
      r.transport != McpTransport.http &&
      r.transport != McpTransport.sse) {
    throw const McpException('Tipo inválido: use stdio, http ou sse.');
  }
  final target = stdio ? r.command?.trim() : r.url?.trim();
  if (target == null || target.isEmpty) {
    throw McpException(stdio ? 'Informe o comando.' : 'Informe a URL.');
  }
  if (!stdio) {
    final u = Uri.tryParse(target);
    if (u == null || !(u.scheme == 'http' || u.scheme == 'https')) {
      throw const McpException('URL inválida (use http:// ou https://).');
    }
  }
  for (final k in r.env.keys) {
    if (!_envKey.hasMatch(k)) throw McpException('Variável inválida: $k');
  }
  for (final k in r.headers.keys) {
    if (!_headerKey.hasMatch(k)) throw McpException('Header inválido: $k');
  }
  if (stdio && r.headers.isNotEmpty) {
    throw const McpException('Headers só valem para http/sse.');
  }
  if (!stdio && r.env.isNotEmpty) {
    throw const McpException('Variáveis de ambiente só valem para stdio.');
  }
  return [
    'mcp',
    'add',
    '-s',
    r.scope.cliValue,
    '-t',
    r.transport.name,
    for (final MapEntry(:key, :value) in r.env.entries) ...[
      '-e',
      '$key=$value',
    ],
    for (final MapEntry(:key, :value) in r.headers.entries) ...[
      '-H',
      '$key: $value',
    ],
    '--',
    r.name,
    target,
    if (stdio) ...r.args,
  ];
}

/// `claude mcp remove <name> -s <scope>`.
List<String> buildMcpRemoveArgs(String name, McpScope scope) => [
  'mcp',
  'remove',
  name,
  '-s',
  scope.cliValue,
];

/// `KEY=value` per line (blank lines and `#` comments ignored). For headers
/// `Key: value` is accepted too. Throws [McpException] on a line without
/// separator.
Map<String, String> parseKeyValues(String text, {bool header = false}) {
  final out = <String, String>{};
  for (final raw in const LineSplitter().convert(text)) {
    final l = raw.trim();
    if (l.isEmpty || l.startsWith('#')) continue;
    var i = l.indexOf('=');
    if (header) {
      final c = l.indexOf(':');
      if (c > 0 && (i < 0 || c < i)) i = c;
    }
    if (i <= 0) {
      throw McpException(
        'Linha sem "=": ${l.length > 20 ? '${l.substring(0, 20)}…' : l}',
      );
    }
    out[l.substring(0, i).trim()] = l.substring(i + 1).trim();
  }
  return out;
}

/// Splits a command line (`npx -y "my pkg"`) into words: whitespace
/// separates, single / double quotes group, backslash escapes.
List<String> splitCommandLine(String text) {
  final out = <String>[];
  final cur = StringBuffer();
  var inWord = false;
  String? quote;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quote != null) {
      if (ch == quote) {
        quote = null;
      } else if (ch == r'\' && quote == '"' && i + 1 < text.length) {
        cur.write(text[++i]);
      } else {
        cur.write(ch);
      }
    } else if (ch == '"' || ch == "'") {
      quote = ch;
      inWord = true;
    } else if (ch == r'\' && i + 1 < text.length) {
      cur.write(text[++i]);
      inWord = true;
    } else if (ch.trim().isEmpty) {
      if (inWord) {
        out.add(cur.toString());
        cur.clear();
        inWord = false;
      }
    } else {
      cur.write(ch);
      inWord = true;
    }
  }
  if (quote != null) throw const McpException('Aspas sem fechar no comando.');
  if (inWord) out.add(cur.toString());
  return out;
}

/// Replaces every secret value in [text] with [mcpMask].
String redact(String text, Iterable<String> secrets) {
  var out = text;
  for (final s in secrets) {
    out = out.replaceAll(s, mcpMask);
  }
  return out;
}

/// Runs a process with a working directory and a [timeout] (injected in
/// tests). On timeout the process must be killed and a [TimeoutException]
/// thrown.
typedef McpRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Duration? timeout,
});

Future<ProcessResult> _defaultRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Duration? timeout,
}) async {
  // Safety net: `flutter test` sets FLUTTER_TEST. Tests must inject a fake
  // runner — a real `claude mcp …` would touch the user's ~/.claude.json.
  if (Platform.environment['FLUTTER_TEST'] == 'true') {
    throw const ProcessException(
      'claude',
      [],
      'mcpRunnerProvider sem fake em teste',
    );
  }
  final p = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  final out = p.stdout.transform(utf8.decoder).join();
  final err = p.stderr.transform(utf8.decoder).join();
  final int code;
  try {
    code = timeout == null
        ? await p.exitCode
        : await p.exitCode.timeout(timeout);
  } on TimeoutException {
    // `claude mcp list` health-checks every server and may hang (DT-46):
    // never leave it running.
    p.kill();
    unawaited(
      p.exitCode.timeout(const Duration(seconds: 3)).catchError((_) {
        p.kill(ProcessSignal.sigkill);
        return -1;
      }),
    );
    unawaited(out.catchError((_) => ''));
    unawaited(err.catchError((_) => ''));
    rethrow;
  }
  return ProcessResult(p.pid, code, await out, await err);
}

final mcpRunnerProvider = Provider<McpRunner>((ref) => _defaultRunner);

/// `claude mcp …` commands. Every command runs with cwd = workspace (the
/// CLI resolves project / local scope from the cwd). Output of `get` is
/// parsed and dropped (it prints env / header values).
class McpCli {
  McpCli({required this.executable, required this.run});

  final String executable;
  final McpRunner run;

  static const listTimeout = Duration(seconds: 90);
  static const commandTimeout = Duration(seconds: 30);

  Future<ProcessResult> _run(
    List<String> args,
    String? cwd,
    Duration timeout,
  ) async {
    try {
      // The runner kills the process on [timeout]; the outer timeout is a
      // backstop for runners that ignore it.
      return await run(
        executable,
        args,
        workingDirectory: cwd,
        timeout: timeout,
      ).timeout(timeout + const Duration(seconds: 5));
    } on TimeoutException {
      throw McpException(
        'claude ${args.take(2).join(' ')} não respondeu em '
        '${timeout.inSeconds} s.',
      );
    } on ProcessException catch (e) {
      throw McpException('Falha ao executar o Claude Code: ${e.message}');
    }
  }

  /// `claude mcp list` (health-checks every server).
  Future<List<McpListEntry>> list(String? cwd) async {
    final r = await _run(const ['mcp', 'list'], cwd, listTimeout);
    if (r.exitCode != 0) {
      throw McpException(_message(r, 'claude mcp list falhou'));
    }
    return parseMcpList('${r.stdout}');
  }

  /// `claude mcp get <name>` (health-checks one server).
  Future<McpGetStatus> get(String name, String? cwd) async {
    final r = await _run(['mcp', 'get', name], cwd, commandTimeout);
    if (r.exitCode != 0) {
      // Only the known "No MCP server named …" line is shown: any other
      // output of `get` may carry env / header values.
      final l = _firstLine(r);
      throw McpException(
        l != null && l.startsWith('No MCP server')
            ? l
            : 'claude mcp get $name falhou (código ${r.exitCode}).',
      );
    }
    return parseMcpGet('${r.stdout}');
  }

  /// `claude mcp add …`. Returns the CLI's message (secrets redacted).
  Future<String> add(McpAddRequest req, String? cwd) async {
    final args = buildMcpAddArgs(req);
    if (req.scope != McpScope.user && cwd == null) {
      throw const McpException(
        'Selecione um workspace para os escopos Projeto e Local.',
      );
    }
    final r = await _run(args, cwd, commandTimeout);
    // The CLI may echo the command: env / header values and the masked
    // arguments never reach the message (F12).
    final masked = maskArgs(req.args);
    final msg = redact(_message(r, ''), [
      ...req.secretValues,
      for (final (i, a) in req.args.indexed)
        if (masked[i] == mcpMask && a.length >= 3) a,
    ]);
    if (r.exitCode != 0) {
      throw McpException(msg.isEmpty ? 'claude mcp add falhou.' : msg);
    }
    return msg;
  }

  /// `claude mcp remove <name> -s <scope>`.
  Future<String> remove(String name, McpScope scope, String? cwd) async {
    final r = await _run(buildMcpRemoveArgs(name, scope), cwd, commandTimeout);
    final msg = _message(r, '');
    if (r.exitCode != 0) {
      throw McpException(msg.isEmpty ? 'claude mcp remove falhou.' : msg);
    }
    return msg;
  }

  static String? _firstLine(ProcessResult r) {
    for (final s in ['${r.stderr}', '${r.stdout}']) {
      final l = s.trim().split('\n').first.trim();
      if (l.isNotEmpty) return l;
    }
    return null;
  }

  static String _message(ProcessResult r, String fallback) {
    final parts = [
      '${r.stdout}'.trim(),
      '${r.stderr}'.trim(),
    ].where((s) => s.isNotEmpty);
    return parts.isEmpty ? fallback : parts.join('\n');
  }
}

final mcpCliProvider = Provider<McpCli>(
  (ref) => McpCli(
    executable: ref.watch(claudeExecutableProvider),
    run: ref.watch(mcpRunnerProvider),
  ),
);
