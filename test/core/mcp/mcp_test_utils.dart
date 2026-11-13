import 'dart:convert';
import 'dart:io';

import 'package:promptorium/core/mcp/app_mcp_server.dart';
import 'package:promptorium/core/mcp/app_mcp_tools.dart';

/// Answer of one HTTP request to the server.
typedef McpHttp = ({int status, Object? body});

/// POSTs [body] (JSON-RPC) to `127.0.0.1:<port>/mcp` with [token].
Future<McpHttp> mcpPost(
  int port,
  Object? body, {
  String? token,
  String method = 'POST',
  String host = '127.0.0.1',
}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:$port/mcp'),
    );
    req.headers.host = host;
    req.headers.port = port;
    if (token != null) req.headers.set('Authorization', 'Bearer $token');
    req.headers.contentType = ContentType.json;
    if (body != null) req.write(jsonEncode(body));
    final res = await req.close();
    final text = await utf8.decoder.bind(res).join();
    return (
      status: res.statusCode,
      body: text.isEmpty ? null : jsonDecode(text),
    );
  } finally {
    client.close(force: true);
  }
}

/// `tools/call` of [tool]; returns the JSON-RPC `result`.
Future<Map<String, dynamic>> mcpCall(
  int port,
  String token,
  String tool, [
  Map<String, Object?> args = const {},
]) async {
  final r = await mcpPost(port, {
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'tools/call',
    'params': {'name': tool, 'arguments': args},
  }, token: token);
  return ((r.body as Map)['result'] as Map).cast<String, dynamic>();
}

/// Names of `tools/list` for [token].
Future<List<String>> mcpToolNames(int port, String token) async {
  final r = await mcpPost(port, {
    'jsonrpc': '2.0',
    'id': 1,
    'method': 'tools/list',
  }, token: token);
  return [
    for (final t in ((r.body as Map)['result'] as Map)['tools'] as List)
      '${(t as Map)['name']}',
  ];
}

/// Toolbox that records each call and answers with the grant it saw.
class RecordingToolbox implements McpToolbox {
  final calls = <(McpGrant, String, Map<String, Object?>)>[];

  @override
  List<McpToolDef> get catalog => appMcpCatalog;

  @override
  Future<McpToolOutcome> call(
    McpGrant grant,
    String tool,
    Map<String, Object?> args,
  ) async {
    calls.add((grant, tool, args));
    return McpToolOutcome('$tool @ workspace ${grant.workspaceId}');
  }
}
