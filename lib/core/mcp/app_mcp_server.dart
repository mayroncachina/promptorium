import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// What a run of the app may do with the Promptorium MCP (SPEC-052 R8):
/// "Perguntar" only reads; "Planejar", "Editar" and the sessions also
/// write (always through the approval, except in "sem perguntar").
enum McpAccess { read, write }

/// One run of the app (session or Prompt conversation) linked to the
/// server: who calls, where and with what access (SPEC-052 R2). Immutable;
/// the server swaps it when [created] changes.
@immutable
class McpGrant {
  const McpGrant({
    required this.token,
    required this.workspaceId,
    required this.sessionId,
    required this.access,
    this.conversationId,
    this.specId,
    this.steps,
    this.title,
    this.skipApproval = false,
    this.limit = defaultCreationLimit,
    this.created = 0,
  });

  /// R9 default (P5).
  static const defaultCreationLimit = 10;

  /// Bearer token of the run's `--mcp-config` file.
  final String token;
  final int workspaceId;

  /// Session id (sessions) or the Claude session of the conversation.
  final String sessionId;

  /// Prompt conversation (null for sessions).
  final int? conversationId;

  /// Spec and steps the session works on when the run started (the tools
  /// read the live ones from the session row).
  final int? specId;
  final String? steps;

  /// Name of the run (status in Configurações).
  final String? title;
  final McpAccess access;

  /// Started with `--dangerously-skip-permissions`: writes run without the
  /// approval card (R8, P4); the timeline marks them.
  final bool skipApproval;

  /// Specs the run may still create in total (R9).
  final int limit;

  /// Specs created so far.
  final int created;

  bool get canWrite => access == McpAccess.write;

  McpGrant withCreated(int n) => McpGrant(
    token: token,
    workspaceId: workspaceId,
    sessionId: sessionId,
    access: access,
    conversationId: conversationId,
    specId: specId,
    steps: steps,
    title: title,
    skipApproval: skipApproval,
    limit: limit,
    created: n,
  );
}

/// A tool of the server (`tools/list`).
@immutable
class McpToolDef {
  const McpToolDef({
    required this.name,
    required this.description,
    required this.summary,
    required this.inputSchema,
    this.write = false,
  });

  final String name;

  /// What the agent reads in `tools/list`.
  final String description;

  /// One line for the Configurações table.
  final String summary;
  final Map<String, Object?> inputSchema;

  /// Writes (R4): left out of read-only grants and never auto-approved.
  final bool write;

  /// `readOnlyHint` matters: without it, `--permission-mode plan` asks for
  /// every read even when it is in `--allowedTools`
  /// (docs/pesquisa/mcp-do-app.md, pergunta 10).
  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'inputSchema': inputSchema,
    'annotations': {
      'readOnlyHint': !write,
      'destructiveHint': false,
      'idempotentHint': !write,
      'openWorldHint': false,
    },
  };
}

/// What a tool call returns to the agent.
@immutable
class McpToolOutcome {
  const McpToolOutcome(this.text, {this.error = false, this.data});

  const McpToolOutcome.error(this.text) : error = true, data = null;

  final String text;

  /// `isError`: the agent reads [text] as the reason.
  final bool error;

  /// `structuredContent` (optional).
  final Map<String, Object?>? data;

  Map<String, Object?> toJson() => {
    'content': [
      {'type': 'text', 'text': text},
    ],
    'structuredContent': ?data,
    if (error) 'isError': true,
  };
}

/// The tools the server serves (`app_mcp_tools.dart`).
abstract interface class McpToolbox {
  List<McpToolDef> get catalog;

  /// Runs [tool] for [grant]. Only tools of [toolsFor] reach it.
  Future<McpToolOutcome> call(
    McpGrant grant,
    String tool,
    Map<String, Object?> args,
  );
}

/// Tools [grant] sees (R8): reads always, writes only with write access.
List<McpToolDef> toolsFor(McpToolbox box, McpGrant grant) => [
  for (final t in box.catalog)
    if (!t.write || grant.canWrite) t,
];

/// Calls a run made so far (status in Configurações and in the session).
@immutable
class McpCallCount {
  const McpCallCount({this.reads = 0, this.writes = 0});

  final int reads;
  final int writes;
}

/// The Promptorium MCP server (SPEC-052 R1, R2): `HttpServer` on
/// `127.0.0.1:<free port>`, "Streamable HTTP" transport with JSON answers
/// only (POST of JSON-RPC; `GET` gets 405: no SSE stream). Every request
/// needs `Authorization: Bearer <token>` of a live [McpGrant]. Verified on
/// CLI 2.1.325 (docs/pesquisa/mcp-do-app.md).
class AppMcpServer extends ChangeNotifier {
  AppMcpServer(this.toolbox, {Random? random})
    : _random = random ?? Random.secure();

  final McpToolbox toolbox;
  final Random _random;

  /// Path of the endpoint in the `--mcp-config` URL.
  static const path = '/mcp';

  /// MCP revisions the server answers with (the client's when known).
  static const protocolVersions = [
    '2025-11-25',
    '2025-06-18',
    '2025-03-26',
    '2024-11-05',
  ];

  HttpServer? _server;
  Future<int>? _starting;
  final Map<String, McpGrant> _grants = {};
  final Map<String, McpCallCount> _calls = {};

  /// Writes run one at a time: the limit check and the creation of R9 must
  /// not race between two calls of the same run.
  Future<void> _writeTail = Future.value();

  /// Bound port, or null while stopped.
  int? get port => _server?.port;

  bool get running => _server != null;

  /// Live grants (runs connected).
  List<McpGrant> get grants => List.unmodifiable(_grants.values);

  McpGrant? grantOf(String token) => _grants[token];

  McpCallCount callsOf(String token) => _calls[token] ?? const McpCallCount();

  /// Binds the server (once); returns the port.
  Future<int> start() async {
    final s = _server;
    if (s != null) return s.port;
    return _starting ??= _bind().whenComplete(() => _starting = null);
  }

  Future<int> _bind() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = s;
    s.listen(
      (req) => unawaited(_serve(req)),
      onError: (Object e) => debugPrint('servidor MCP: $e'),
    );
    notifyListeners();
    return s.port;
  }

  /// Closes the server and drops every grant.
  Future<void> stop() async {
    final s = _server;
    _server = null;
    _grants.clear();
    _calls.clear();
    await s?.close(force: true);
    notifyListeners();
  }

  /// A new random token (32 bytes, hex).
  String newToken() => [
    for (var i = 0; i < 32; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();

  /// Registers [grant] (R2).
  void issue(McpGrant grant) {
    _grants[grant.token] = grant;
    notifyListeners();
  }

  /// Forgets [token]: later calls get 401 (R2, end of the process).
  void revoke(String token) {
    if (_grants.remove(token) == null) return;
    _calls.remove(token);
    notifyListeners();
  }

  /// Runs [job] after the writes in flight.
  Future<T> serialWrite<T>(Future<T> Function() job) {
    final next = _writeTail.then((_) => job());
    _writeTail = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  /// Records a creation of [token] (R9).
  void addCreated(String token, int n) {
    final g = _grants[token];
    if (g == null) return;
    _grants[token] = g.withCreated(g.created + n);
    notifyListeners();
  }

  /// Specs [token] may still create (0 when unknown).
  int remaining(String token) {
    final g = _grants[token];
    return g == null ? 0 : max(0, g.limit - g.created);
  }

  // --- HTTP ------------------------------------------------------------------

  Future<void> _serve(HttpRequest req) async {
    final res = req.response;
    try {
      if (req.uri.path != path) return await _status(res, 404);
      // DNS rebinding: only loopback host names.
      final host = req.headers.host ?? '';
      if (!const {'127.0.0.1', 'localhost'}.contains(host)) {
        return await _status(res, 403);
      }
      final grant = _grantOf(
        req.headers.value(HttpHeaders.authorizationHeader),
      );
      if (grant == null) {
        res.headers.set(HttpHeaders.wwwAuthenticateHeader, 'Bearer');
        return await _status(res, 401);
      }
      if (req.method != 'POST') return await _status(res, 405);
      final body = await utf8.decoder.bind(req).join();
      Object? msg;
      try {
        msg = jsonDecode(body);
      } catch (_) {
        return await _json(res, _error(null, -32700, 'JSON inválido.'));
      }
      if (msg is List) {
        final out = [for (final m in msg) ?await _handle(grant.token, m)];
        if (out.isEmpty) return await _status(res, 202);
        return await _json(res, out);
      }
      final out = await _handle(grant.token, msg);
      if (out == null) return await _status(res, 202);
      await _json(res, out);
    } catch (e) {
      debugPrint('servidor MCP: requisição falhou — $e');
      try {
        await _status(res, 500);
      } catch (_) {}
    }
  }

  McpGrant? _grantOf(String? auth) {
    if (auth == null || !auth.startsWith('Bearer ')) return null;
    return _grants[auth.substring(7).trim()];
  }

  /// One JSON-RPC message; null for notifications.
  Future<Map<String, Object?>?> _handle(String token, Object? msg) async {
    if (msg is! Map) return _error(null, -32600, 'Requisição inválida.');
    final id = msg['id'];
    final method = msg['method'];
    final params = msg['params'] is Map
        ? Map<String, Object?>.from(msg['params'] as Map)
        : const <String, Object?>{};
    if (id == null) return null; // notification (or a response to us)
    if (method is! String) return _error(id, -32600, 'Requisição inválida.');
    // The grant may have been revoked or changed since the HTTP check.
    final grant = _grants[token];
    if (grant == null) return _error(id, -32001, 'Token revogado.');
    switch (method) {
      case 'initialize':
        final asked = params['protocolVersion'];
        return _result(id, {
          'protocolVersion': protocolVersions.contains(asked)
              ? asked
              : protocolVersions.first,
          'capabilities': {
            'tools': {'listChanged': false},
          },
          'serverInfo': {'name': 'promptorium', 'version': '1'},
          'instructions':
              'Quadro e specs do Promptorium deste workspace. As ferramentas '
              'de escrita criam rascunhos e notas; nada muda status, coluna '
              'ou etapas, e a pessoa aprova cada gravação.',
        });
      case 'ping':
        return _result(id, const {});
      case 'tools/list':
        return _result(id, {
          'tools': [for (final t in toolsFor(toolbox, grant)) t.toJson()],
        });
      case 'tools/call':
        return _result(id, (await _call(grant, params)).toJson());
      default:
        return _error(id, -32601, 'Método desconhecido: $method');
    }
  }

  Future<McpToolOutcome> _call(
    McpGrant grant,
    Map<String, Object?> params,
  ) async {
    final name = params['name'];
    final args = params['arguments'] is Map
        ? Map<String, Object?>.from(params['arguments'] as Map)
        : <String, Object?>{};
    final tool = toolsFor(
      toolbox,
      grant,
    ).where((t) => t.name == name).firstOrNull;
    if (tool == null) {
      return McpToolOutcome.error(
        'A ferramenta $name não existe ou não está liberada nesta execução.',
      );
    }
    final before = callsOf(grant.token);
    _calls[grant.token] = McpCallCount(
      reads: before.reads + (tool.write ? 0 : 1),
      writes: before.writes + (tool.write ? 1 : 0),
    );
    notifyListeners();
    try {
      if (!tool.write) return await toolbox.call(grant, tool.name, args);
      // Re-read the grant inside the queue: [created] may have changed.
      return await serialWrite(() async {
        final g = _grants[grant.token];
        if (g == null) return const McpToolOutcome.error('Token revogado.');
        return toolbox.call(g, tool.name, args);
      });
    } catch (e) {
      return McpToolOutcome.error('Falha em ${tool.name}: $e');
    }
  }

  static Map<String, Object?> _result(Object? id, Object? result) => {
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  };

  static Map<String, Object?> _error(Object? id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };

  static Future<void> _status(HttpResponse res, int code) async {
    res
      ..statusCode = code
      ..contentLength = 0;
    await res.close();
  }

  static Future<void> _json(HttpResponse res, Object? body) async {
    final bytes = utf8.encode(jsonEncode(body));
    res
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..contentLength = bytes.length
      ..add(bytes);
    await res.close();
  }
}
