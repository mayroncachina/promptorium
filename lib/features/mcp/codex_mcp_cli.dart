import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_process.dart' show ProcessStarter;
import '../../core/codex/codex_cli.dart'
    show codexExecutableProvider, codexProcessStarterProvider;
import '../../core/codex/codex_rpc.dart';
import '../../core/providers/agent_provider.dart' show AgentUnavailable;
import 'mcp_cli.dart';
import 'mcp_config.dart';

/// `auth_status` of `codex mcp list --json` / `authStatus` of
/// `mcpServerStatus/list` (SPEC-105 R2).
enum CodexMcpAuth {
  unsupported('—'),
  bearerToken('Token por variável'),
  notLoggedIn('Precisa entrar'),
  oAuth('OAuth · conectado'),
  unknown('Desconhecida');

  const CodexMcpAuth(this.label);

  final String label;

  /// Both spellings: `not_logged_in` (CLI) and `notLoggedIn` (App Server).
  static CodexMcpAuth parse(Object? v) =>
      switch ('$v'.replaceAll('_', '').toLowerCase()) {
        'unsupported' => unsupported,
        'bearertoken' => bearerToken,
        'notloggedin' => notLoggedIn,
        'oauth' => oAuth,
        _ => unknown,
      };
}

/// One server of `codex mcp list --json` (0.170, SPEC-105 sondagem).
///
/// **No secret values**: the CLI prints `env` values in clear text; only the
/// key names survive the parse ([envKeys]). The bearer token is never read
/// (only the variable name, [bearerTokenEnvVar]).
@immutable
class CodexMcpServer {
  const CodexMcpServer({
    required this.name,
    required this.transport,
    this.enabled = true,
    this.disabledReason,
    this.command,
    this.args = const [],
    this.url,
    this.envKeys = const [],
    this.envVars = const [],
    this.headerKeys = const [],
    this.bearerTokenEnvVar,
    this.auth = CodexMcpAuth.unknown,
    this.enabledTools,
    this.disabledTools,
  });

  final String name;

  /// stdio or http (`streamable_http`); anything else = unknown.
  final McpTransport transport;
  final bool enabled;
  final String? disabledReason;
  final String? command;

  /// Masked ([maskArgs]).
  final List<String> args;

  /// Masked ([maskUrl]).
  final String? url;
  final List<String> envKeys;

  /// `env_vars`: variables passed through from the parent environment.
  final List<String> envVars;

  /// Keys of `http_headers` and `env_http_headers`.
  final List<String> headerKeys;
  final String? bearerTokenEnvVar;
  final CodexMcpAuth auth;

  /// Of `codex mcp get --json` only (the list does not have them).
  final List<String>? enabledTools;
  final List<String>? disabledTools;

  String get target => transport == McpTransport.stdio
      ? [command ?? '', ...args].where((s) => s.isNotEmpty).join(' ')
      : url ?? '';

  /// `[mcp_servers.<name>]` as it is in `config.toml`, values masked.
  String maskedToml() {
    String q(String s) => jsonEncode(s);
    String list(List<String> l) => '[${l.map(q).join(', ')}]';
    final b = StringBuffer('[mcp_servers.$name]\n');
    if (command != null) b.writeln('command = ${q(command!)}');
    if (args.isNotEmpty) b.writeln('args = ${list(args)}');
    if (url != null) b.writeln('url = ${q(url!)}');
    if (bearerTokenEnvVar != null) {
      b.writeln('bearer_token_env_var = ${q(bearerTokenEnvVar!)}');
    }
    if (!enabled) b.writeln('enabled = false');
    if (enabledTools != null) {
      b.writeln('enabled_tools = ${list(enabledTools!)}');
    }
    if (disabledTools != null) {
      b.writeln('disabled_tools = ${list(disabledTools!)}');
    }
    if (envVars.isNotEmpty) b.writeln('env_vars = ${list(envVars)}');
    if (envKeys.isNotEmpty) {
      b.writeln('\n[mcp_servers.$name.env]');
      for (final k in envKeys) {
        b.writeln('$k = ${q(mcpMask)}');
      }
    }
    if (headerKeys.isNotEmpty) {
      b.writeln('\n[mcp_servers.$name.http_headers]');
      for (final k in headerKeys) {
        b.writeln('$k = ${q(mcpMask)}');
      }
    }
    return b.toString().trimRight();
  }

  /// One entry of `codex mcp list --json` / `codex mcp get --json`. Values
  /// of `env` and of the headers are dropped here.
  static CodexMcpServer? fromJson(Object? raw) {
    if (raw is! Map || raw['name'] is! String) return null;
    final t = raw['transport'] is Map ? raw['transport'] as Map : const {};
    List<String> keys(Object? m) =>
        m is Map ? [for (final k in m.keys) '$k'] : const [];
    List<String>? strings(Object? l) =>
        l is List ? [for (final v in l) '$v'] : null;
    final type = '${t['type']}';
    final transport = switch (type) {
      'stdio' => McpTransport.stdio,
      'streamable_http' || 'http' => McpTransport.http,
      _ => McpTransport.unknown,
    };
    return CodexMcpServer(
      name: raw['name'] as String,
      transport: transport,
      enabled: raw['enabled'] != false,
      disabledReason: raw['disabled_reason'] is String
          ? raw['disabled_reason'] as String
          : null,
      command: t['command'] is String ? t['command'] as String : null,
      args: maskArgs(strings(t['args']) ?? const []),
      url: t['url'] is String ? maskUrl(t['url'] as String) : null,
      envKeys: keys(t['env']),
      envVars: [
        for (final v in strings(t['env_vars']) ?? const <String>[])
          // `env_vars` may carry `{name, source}` objects in newer CLIs.
          if (!v.startsWith('{')) v,
      ],
      headerKeys: {
        ...keys(t['http_headers']),
        ...keys(t['env_http_headers']),
      }.toList(),
      bearerTokenEnvVar: t['bearer_token_env_var'] is String
          ? t['bearer_token_env_var'] as String
          : null,
      auth: CodexMcpAuth.parse(raw['auth_status']),
      enabledTools: strings(raw['enabled_tools']),
      disabledTools: strings(raw['disabled_tools']),
    );
  }
}

/// `codex mcp list --json` → servers sorted by name. Throws
/// [McpException] on output that is not the expected JSON list.
List<CodexMcpServer> parseCodexMcpList(String stdout) {
  final start = stdout.indexOf('[');
  if (start < 0) {
    throw const McpException('codex mcp list --json não devolveu uma lista.');
  }
  final Object? j;
  try {
    j = jsonDecode(stdout.substring(start));
  } on FormatException {
    throw const McpException('codex mcp list --json devolveu JSON inválido.');
  }
  if (j is! List) {
    throw const McpException('codex mcp list --json não devolveu uma lista.');
  }
  return [for (final e in j) ?CodexMcpServer.fromJson(e)]
    ..sort((a, b) => a.name.compareTo(b.name));
}

/// One tool of `mcpServerStatus/list`.
@immutable
class CodexMcpTool {
  const CodexMcpTool(this.name, [this.description]);

  final String name;
  final String? description;
}

/// One entry of `mcpServerStatus/list` (R2).
@immutable
class CodexMcpStatus {
  const CodexMcpStatus({
    required this.name,
    required this.state,
    this.auth = CodexMcpAuth.unknown,
    this.tools = const [],
    this.toolsError,
    this.pluginId,
  });

  final String name;
  final McpConnState state;
  final CodexMcpAuth auth;
  final List<CodexMcpTool> tools;
  final String? toolsError;

  /// Servers of a Codex plugin: read only on the screen (R3).
  final String? pluginId;

  /// `runtimeStatus` → the screen's state (`notStarted`/`starting` count as
  /// "verificando").
  static McpConnState stateOf(Object? runtime) => switch ('$runtime') {
    'connected' => McpConnState.connected,
    'failed' || 'cancelled' => McpConnState.failed,
    'authenticationRequired' => McpConnState.needsAuth,
    'disabled' => McpConnState.disabled,
    'starting' || 'notStarted' => McpConnState.checking,
    _ => McpConnState.unknown,
  };

  static CodexMcpStatus? fromJson(Object? raw) {
    if (raw is! Map || raw['name'] is! String) return null;
    final tools = <CodexMcpTool>[];
    final t = raw['tools'];
    if (t is Map) {
      for (final MapEntry(:key, :value) in t.entries) {
        final d = value is Map ? value['description'] : null;
        tools.add(CodexMcpTool('$key', d is String ? d : null));
      }
    }
    tools.sort((a, b) => a.name.compareTo(b.name));
    final err = raw['toolsError'];
    var state = stateOf(raw['runtimeStatus']);
    // Without a runtime state, an error listing the tools is a failure and
    // a tool list is a connection.
    if (state == McpConnState.unknown) {
      state = err is String
          ? McpConnState.failed
          : tools.isNotEmpty
          ? McpConnState.connected
          : state;
    }
    return CodexMcpStatus(
      name: raw['name'] as String,
      state: state,
      auth: CodexMcpAuth.parse(raw['authStatus']),
      tools: tools,
      toolsError: err is String ? CodexRpc.redact(err) : null,
      pluginId: raw['pluginId'] is String ? raw['pluginId'] as String : null,
    );
  }
}

/// `mcpServerStatus/list` result → entries.
List<CodexMcpStatus> parseCodexMcpStatus(Map<String, dynamic> result) => [
  for (final e in result['data'] as List? ?? const [])
    ?CodexMcpStatus.fromJson(e),
];

// --- add / remove ----------------------------------------------------------------

/// Input of `codex mcp add` (R4): stdio (command + env) or http (url +
/// optional bearer token variable).
@immutable
class CodexMcpAddRequest {
  const CodexMcpAddRequest({
    required this.name,
    required this.transport,
    this.command,
    this.args = const [],
    this.env = const {},
    this.url,
    this.bearerTokenEnvVar,
  });

  final String name;
  final McpTransport transport;
  final String? command;
  final List<String> args;
  final Map<String, String> env;
  final String? url;
  final String? bearerTokenEnvVar;

  bool get stdio => transport == McpTransport.stdio;

  /// http without a token variable: `codex mcp add` starts the OAuth flow
  /// right after writing the entry (SPEC-105 sondagem).
  bool get startsOauth => !stdio && bearerTokenEnvVar == null;

  Iterable<String> get secretValues => env.values.where((v) => v.length >= 3);
}

final _envKey = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// Arguments of `codex mcp add` (0.170 `--help`):
/// `mcp add <name> [--env K=V]… -- <command> [args…]` or
/// `mcp add <name> --url <url> [--bearer-token-env-var VAR]`.
/// Throws [McpException].
List<String> buildCodexMcpAddArgs(CodexMcpAddRequest r) {
  if (!mcpNamePattern.hasMatch(r.name)) {
    throw const McpException(
      'Nome inválido: use letras, números, hífens e sublinhados.',
    );
  }
  if (r.transport != McpTransport.stdio && r.transport != McpTransport.http) {
    throw McpException(
      'Sem equivalente no Codex: transporte ${r.transport.label}. '
      'O codex mcp add aceita stdio e http.',
    );
  }
  if (r.stdio) {
    final cmd = r.command?.trim() ?? '';
    if (cmd.isEmpty) throw const McpException('Informe o comando.');
    for (final k in r.env.keys) {
      if (!_envKey.hasMatch(k)) throw McpException('Variável inválida: $k');
    }
    if (r.bearerTokenEnvVar != null) {
      throw const McpException('Token por variável só vale para http.');
    }
    return [
      'mcp',
      'add',
      r.name,
      for (final MapEntry(:key, :value) in r.env.entries) ...[
        '--env',
        '$key=$value',
      ],
      '--',
      cmd,
      ...r.args,
    ];
  }
  final url = r.url?.trim() ?? '';
  final u = Uri.tryParse(url);
  if (url.isEmpty) throw const McpException('Informe a URL.');
  if (u == null || !(u.scheme == 'http' || u.scheme == 'https')) {
    throw const McpException('URL inválida (use http:// ou https://).');
  }
  if (r.env.isNotEmpty) {
    throw const McpException('Variáveis de ambiente só valem para stdio.');
  }
  final v = r.bearerTokenEnvVar;
  if (v != null && !_envKey.hasMatch(v)) {
    throw McpException('Variável do token inválida: $v');
  }
  return [
    'mcp',
    'add',
    r.name,
    '--url',
    url,
    if (v != null) ...['--bearer-token-env-var', v],
  ];
}

/// The command shown in the confirmation (R4, R6): env values and the
/// secret-looking arguments masked.
String codexMcpAddPreview(CodexMcpAddRequest r) {
  final args = buildCodexMcpAddArgs(r);
  final sep = args.indexOf('--');
  final out = <String>['codex'];
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (i > 0 && args[i - 1] == '--env') {
      final eq = a.indexOf('=');
      out.add('${a.substring(0, eq)}=$mcpMask');
    } else if (sep >= 0 && i > sep + 1) {
      out.add(maskArgs(args.sublist(sep + 2))[i - sep - 2]);
    } else if (i > 0 && args[i - 1] == '--url') {
      out.add(maskUrl(a));
    } else {
      out.add(a.contains(' ') ? jsonEncode(a) : a);
    }
  }
  return out.join(' ');
}

/// `codex mcp remove <name>`.
List<String> buildCodexMcpRemoveArgs(String name) => ['mcp', 'remove', name];

/// `codex mcp logout <name>`.
List<String> buildCodexMcpLogoutArgs(String name) => ['mcp', 'logout', name];

/// Result of [CodexMcpCli.add].
@immutable
class CodexMcpAddResult {
  const CodexMcpAddResult(this.message, {this.needsLogin = false});

  final String message;

  /// The server was written but its OAuth was left for "Entrar".
  final bool needsLogin;
}

/// `codex mcp …` (R2, R4, R5). Never edits `config.toml`: every change goes
/// through the CLI. Output of `list`/`get` carries env values in clear text;
/// it is parsed here and only key names survive.
class CodexMcpCli {
  CodexMcpCli({required this.executable, required this.run});

  final String executable;
  final McpRunner run;

  static const commandTimeout = Duration(seconds: 20);

  /// How long `add` waits for the OAuth flow it opens by itself before
  /// leaving the login for "Entrar".
  static const oauthGrace = Duration(seconds: 8);

  Future<ProcessResult> _run(
    List<String> args,
    String? cwd, {
    Duration timeout = commandTimeout,
  }) async {
    try {
      return await run(
        executable,
        args,
        workingDirectory: cwd,
        timeout: timeout,
      ).timeout(timeout + const Duration(seconds: 5));
    } on TimeoutException {
      rethrow;
    } on ProcessException catch (e) {
      throw McpException('Falha ao executar o Codex: ${e.message}');
    }
  }

  static String _clean(String s) => CodexRpc.redact(
    const LineSplitter()
        .convert(s)
        // The CLI warns about PATH aliases on every command.
        .where((l) => !l.startsWith('WARNING: proceeding'))
        .join('\n')
        .trim(),
  );

  Future<List<CodexMcpServer>> list(String? cwd) async {
    final ProcessResult r;
    try {
      r = await _run(const ['mcp', 'list', '--json'], cwd);
    } on TimeoutException {
      throw const McpException('codex mcp list não respondeu.');
    }
    if (r.exitCode != 0) {
      // Never echo stdout: it may carry env values.
      final err = _clean('${r.stderr}');
      throw McpException(
        err.isEmpty ? 'codex mcp list falhou (código ${r.exitCode}).' : err,
      );
    }
    return parseCodexMcpList('${r.stdout}');
  }

  /// `codex mcp get <name> --json` (adds `enabled_tools`/`disabled_tools`).
  /// Null when the server does not exist.
  Future<CodexMcpServer?> get(String name, String? cwd) async {
    final ProcessResult r;
    try {
      r = await _run(['mcp', 'get', name, '--json'], cwd);
    } on TimeoutException {
      throw McpException('codex mcp get $name não respondeu.');
    }
    if (r.exitCode != 0) {
      if ('${r.stderr}'.contains('No MCP server named')) return null;
      throw McpException('codex mcp get $name falhou (código ${r.exitCode}).');
    }
    final out = '${r.stdout}';
    final start = out.indexOf('{');
    if (start < 0) return null;
    try {
      return CodexMcpServer.fromJson(jsonDecode(out.substring(start)));
    } on FormatException {
      throw McpException('codex mcp get $name devolveu JSON inválido.');
    }
  }

  /// `codex mcp add …`. An http server without a token variable opens the
  /// OAuth flow and waits for the browser: after [oauthGrace] the process
  /// is ended, and the entry is confirmed by `get` (R5 does the login).
  Future<CodexMcpAddResult> add(CodexMcpAddRequest req, String? cwd) async {
    final args = buildCodexMcpAddArgs(req);
    final secrets = [
      ...req.secretValues,
      for (final (i, a) in req.args.indexed)
        if (maskArgs(req.args)[i] == mcpMask && a.length >= 3) a,
    ];
    ProcessResult r;
    try {
      r = await _run(
        args,
        cwd,
        timeout: req.startsOauth ? oauthGrace : commandTimeout,
      );
    } on TimeoutException {
      if (req.startsOauth && await get(req.name, cwd) != null) {
        return CodexMcpAddResult(
          '${req.name} adicionado. Use "Entrar" para autorizar no navegador.',
          needsLogin: true,
        );
      }
      throw const McpException('codex mcp add não respondeu.');
    }
    final msg = redact(
      _clean(
        [
          '${r.stdout}',
          '${r.stderr}',
        ].where((s) => s.trim().isNotEmpty).join('\n'),
      ),
      secrets,
    );
    if (r.exitCode != 0) {
      throw McpException(msg.isEmpty ? 'codex mcp add falhou.' : msg);
    }
    return CodexMcpAddResult(
      msg.isEmpty ? '${req.name} adicionado ao Codex.' : msg,
      needsLogin: req.startsOauth,
    );
  }

  Future<String> remove(String name, String? cwd) =>
      _simple(buildCodexMcpRemoveArgs(name), cwd, 'codex mcp remove');

  Future<String> logout(String name, String? cwd) =>
      _simple(buildCodexMcpLogoutArgs(name), cwd, 'codex mcp logout');

  Future<String> _simple(List<String> args, String? cwd, String what) async {
    final ProcessResult r;
    try {
      r = await _run(args, cwd);
    } on TimeoutException {
      throw McpException('$what não respondeu.');
    }
    final msg = _clean(
      ['${r.stdout}', '${r.stderr}'].where((s) => s.trim().isNotEmpty).join(),
    );
    if (r.exitCode != 0) {
      throw McpException(msg.isEmpty ? '$what falhou.' : msg);
    }
    return msg;
  }
}

final codexMcpCliProvider = Provider<CodexMcpCli>(
  (ref) => CodexMcpCli(
    executable: ref.watch(codexExecutableProvider),
    run: ref.watch(mcpRunnerProvider),
  ),
);

// --- App Server (status and OAuth) ----------------------------------------------

/// A short-lived `codex app-server`: `initialize` → `initialized` → [body]
/// → ends. Never `thread/start` nor `turn/start` (R2: no paid turn).
Future<T> withCodexAppServer<T>({
  required String executable,
  required Future<T> Function(CodexRpc rpc) body,
  ProcessStarter? starter,
  String? workingDirectory,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final Process process;
  try {
    process = await (starter ?? _start)(
      executable,
      const ['app-server'],
      workingDirectory: workingDirectory ?? Directory.systemTemp.path,
      environment: null,
    );
  } on ProcessException {
    throw const AgentUnavailable('Codex CLI não encontrado.');
  }
  final rpc = CodexRpc(process, timeout: timeout, ephemeral: true);
  try {
    await rpc.request('initialize', {
      'clientInfo': {
        'name': 'promptorium',
        'title': 'Promptorium',
        'version': '0.0.0',
      },
    });
    await rpc.write({'method': 'initialized', 'params': <String, dynamic>{}});
    return await body(rpc);
  } finally {
    await rpc.stop(timeout: const Duration(seconds: 2));
  }
}

Future<Process> _start(
  String exe,
  List<String> args, {
  String? workingDirectory,
  Map<String, String>? environment,
}) {
  if (Platform.environment['FLUTTER_TEST'] == 'true') {
    throw ProcessException(exe, args, 'codex app-server sem fake em teste');
  }
  return Process.start(exe, args, workingDirectory: workingDirectory);
}

/// `mcpServerStatus/list` (R2): `toolsAndAuthOnly` for the list, `full`
/// for one server ([serverName]). Follows `nextCursor`.
Future<List<CodexMcpStatus>> readCodexMcpStatus({
  required String executable,
  ProcessStarter? starter,
  String? workingDirectory,
  String? serverName,
  bool full = false,
}) => withCodexAppServer(
  executable: executable,
  starter: starter,
  workingDirectory: workingDirectory,
  // Starting every server may take a while (npx downloads, OAuth checks).
  timeout: const Duration(seconds: 60),
  body: (rpc) async {
    final sub = rpc.messages.stream.listen((_) {});
    try {
      final out = <CodexMcpStatus>[];
      String? cursor;
      do {
        final r = await rpc.request('mcpServerStatus/list', {
          'detail': full ? 'full' : 'toolsAndAuthOnly',
          'serverName': ?serverName,
          'cursor': ?cursor,
        });
        out.addAll(parseCodexMcpStatus(r));
        final next = r['nextCursor'];
        cursor = next is String && next.isNotEmpty && next != cursor
            ? next
            : null;
      } while (cursor != null);
      return out;
    } finally {
      await sub.cancel();
    }
  },
);

/// Outcome of an OAuth login (R5).
@immutable
class CodexMcpLoginResult {
  const CodexMcpLoginResult({required this.success, this.error});

  final bool success;
  final String? error;
}

/// `mcpServer/oauth/login` (R5): asks the App Server for the authorization
/// URL, hands it to [openUrl] (the browser) and waits for
/// `mcpServer/oauthLogin/completed` of [name].
Future<CodexMcpLoginResult> codexMcpOauthLogin({
  required String executable,
  required String name,
  required Future<void> Function(String url) openUrl,
  ProcessStarter? starter,
  String? workingDirectory,
  Duration wait = const Duration(minutes: 5),
}) => withCodexAppServer(
  executable: executable,
  starter: starter,
  workingDirectory: workingDirectory,
  body: (rpc) async {
    final done = Completer<CodexMcpLoginResult>();
    String? loginId;
    final sub = rpc.messages.stream.listen((m) {
      if (m['method'] != 'mcpServer/oauthLogin/completed') return;
      final p = m['params'];
      if (p is! Map || p['name'] != name) return;
      if (loginId != null && p['loginId'] != null && p['loginId'] != loginId) {
        return;
      }
      if (!done.isCompleted) {
        done.complete(
          CodexMcpLoginResult(
            success: p['success'] == true,
            error: p['error'] is String
                ? CodexRpc.redact(p['error'] as String)
                : null,
          ),
        );
      }
    });
    try {
      final r = await rpc.request('mcpServer/oauth/login', {
        'name': name,
        'timeoutSecs': wait.inSeconds,
      });
      loginId = r['loginId'] is String ? r['loginId'] as String : null;
      final url = r['authorizationUrl'];
      if (url is! String || url.isEmpty) {
        return const CodexMcpLoginResult(
          success: false,
          error: 'O Codex não devolveu a URL de autorização.',
        );
      }
      await openUrl(url);
      return await done.future.timeout(
        wait,
        onTimeout: () => const CodexMcpLoginResult(
          success: false,
          error: 'O login não terminou a tempo.',
        ),
      );
    } finally {
      await sub.cancel();
    }
  },
);

/// Starter of the short App Server connections (tests inject one).
final codexMcpStarterProvider = Provider<ProcessStarter?>(
  (ref) => ref.watch(codexProcessStarterProvider),
);
