import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'codex_mcp_cli.dart';
import 'mcp_config.dart';

/// "Copiar para o Codex" (SPEC-105 R6): the translation of one Claude Code
/// server into `codex mcp add`. A one-time copy: nothing stays linked.

/// What the Claude Code entry has, as in its file. Read only when the copy
/// dialog opens; env / header values live only in the dialog and are
/// never stored by the app.
@immutable
class ClaudeMcpRawEntry {
  const ClaudeMcpRawEntry({
    this.command,
    this.args = const [],
    this.url,
    this.env = const {},
    this.headers = const {},
  });

  final String? command;
  final List<String> args;
  final String? url;
  final Map<String, String> env;
  final Map<String, String> headers;

  static ClaudeMcpRawEntry fromJson(Object? raw) {
    if (raw is! Map) return const ClaudeMcpRawEntry();
    Map<String, String> strings(Object? m) => m is Map
        ? {for (final e in m.entries) '${e.key}': '${e.value}'}
        : const {};
    return ClaudeMcpRawEntry(
      command: raw['command'] is String ? raw['command'] as String : null,
      args: raw['args'] is List
          ? [for (final a in raw['args'] as List) '$a']
          : const [],
      url: raw['url'] is String ? raw['url'] as String : null,
      env: strings(raw['env']),
      headers: strings(raw['headers']),
    );
  }
}

/// Reads the entry of [c] from its file (`~/.claude.json` for user /
/// local, `.mcp.json` for project). Never writes. Null when it is gone.
Future<ClaudeMcpRawEntry?> readClaudeMcpRaw(
  McpServerConfig c, {
  String? workspacePath,
}) async {
  try {
    final f = File(c.sourcePath);
    if (!await f.exists()) return null;
    final j = jsonDecode(await f.readAsString());
    if (j is! Map) return null;
    final Object? servers = switch (c.scope) {
      McpScope.local =>
        workspacePath == null
            ? null
            : ((j['projects'] as Map?)?[workspacePath] as Map?)?['mcpServers'],
      McpScope.user || McpScope.project => j['mcpServers'],
    };
    if (servers is! Map || !servers.containsKey(c.name)) return null;
    return ClaudeMcpRawEntry.fromJson(servers[c.name]);
  } catch (_) {
    return null;
  }
}

final _bearer = RegExp(r'^Bearer\s+\S+', caseSensitive: false);

/// What can be translated, and what differs (R6).
@immutable
class CodexCopyPlan {
  const CodexCopyPlan({
    required this.source,
    this.blocker,
    this.envKeys = const [],
    this.bearerHeader = false,
  });

  final McpServerConfig source;

  /// "Sem equivalente no Codex: transporte sse" — disables the copy.
  final String? blocker;
  final List<String> envKeys;

  /// http with `Authorization: Bearer …`: offered as
  /// `--bearer-token-env-var` instead of the value.
  final bool bearerHeader;

  bool get stdio => source.transport == McpTransport.stdio;

  /// Local / project servers become global in the Codex (P2).
  bool get scopeWarning => source.scope != McpScope.user;

  /// Default name of the token variable: `GITHUB_TOKEN` for `github`.
  String get defaultTokenVar =>
      '${source.name.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '_')}_TOKEN';
}

/// Plans the copy of [c]. [raw] is the entry as in its file (headers are
/// checked by value: only `Authorization: Bearer …` has an equivalent).
CodexCopyPlan planCodexCopy(McpServerConfig c, ClaudeMcpRawEntry? raw) {
  String? blocker;
  var bearer = false;
  switch (c.transport) {
    case McpTransport.stdio:
      if ((raw?.command ?? c.command) == null) {
        blocker = 'Sem equivalente no Codex: servidor sem comando';
      }
    case McpTransport.http:
      final other = <String>[];
      for (final k in c.headerKeys) {
        final v = raw?.headers[k];
        if (k.toLowerCase() == 'authorization' &&
            (v == null || _bearer.hasMatch(v))) {
          bearer = true;
        } else {
          other.add(k);
        }
      }
      if (other.isNotEmpty) {
        blocker =
            'Sem equivalente no Codex: '
            '${other.length == 1 ? 'cabeçalho' : 'cabeçalhos'} '
            '${other.join(', ')}. O codex mcp add só aceita o token por '
            'variável (--bearer-token-env-var).';
      }
    case McpTransport.sse || McpTransport.ws || McpTransport.unknown:
      blocker =
          'Sem equivalente no Codex: transporte ${c.transport.label}. O '
          'codex mcp add aceita stdio e http.';
  }
  return CodexCopyPlan(
    source: c,
    blocker: blocker,
    envKeys: c.transport == McpTransport.stdio ? c.envKeys : const [],
    bearerHeader: bearer,
  );
}

/// The `codex mcp add` of the copy. [envValues]: only non-empty values go
/// (an empty field = the value is not copied); [tokenVar]: the variable of
/// the bearer token (http). Throws [McpException] via the builder.
CodexMcpAddRequest codexCopyRequest(
  CodexCopyPlan plan,
  ClaudeMcpRawEntry? raw, {
  Map<String, String> envValues = const {},
  String? tokenVar,
}) {
  final c = plan.source;
  if (plan.stdio) {
    return CodexMcpAddRequest(
      name: c.name,
      transport: McpTransport.stdio,
      command: raw?.command ?? c.command,
      // The real arguments: the masked ones are only for display.
      args: raw?.args ?? c.args,
      env: {
        for (final k in plan.envKeys)
          if ((envValues[k] ?? '').isNotEmpty) k: envValues[k]!,
      },
    );
  }
  final v = tokenVar?.trim();
  return CodexMcpAddRequest(
    name: c.name,
    transport: McpTransport.http,
    url: raw?.url ?? c.url,
    bearerTokenEnvVar: plan.bearerHeader && v != null && v.isNotEmpty
        ? v
        : null,
  );
}

/// One line of the "nome repetido" diff: (campo, no Codex hoje, vindo do
/// Claude).
typedef CodexCopyDiff = (String field, String current, String incoming);

/// What changes in the Codex when the copy replaces [current] (P3).
List<CodexCopyDiff> codexCopyDiff(
  CodexMcpServer current,
  CodexMcpAddRequest incoming,
) {
  final out = <CodexCopyDiff>[];
  void add(String f, String a, String b) {
    if (a != b) out.add((f, a, b));
  }

  String transport(McpTransport t) => t == McpTransport.http ? 'http' : t.label;
  add(
    'Transporte',
    transport(current.transport),
    transport(incoming.transport),
  );
  if (incoming.stdio) {
    add(
      'Comando',
      current.target,
      [incoming.command ?? '', ...maskArgs(incoming.args)].join(' ').trim(),
    );
    add('Variáveis', current.envKeys.join(', '), incoming.env.keys.join(', '));
  } else {
    add('URL', current.url ?? '', maskUrl(incoming.url ?? ''));
    add(
      'Token',
      current.bearerTokenEnvVar ??
          (current.auth == CodexMcpAuth.oAuth ? 'OAuth' : '—'),
      incoming.bearerTokenEnvVar ?? 'OAuth',
    );
  }
  return out;
}
