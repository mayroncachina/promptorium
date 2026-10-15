import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../agents/agent_repository.dart' show agentHomeProvider;

/// Where an MCP server is configured (`claude mcp add -s <scope>`).
enum McpScope {
  /// `projects["<workspace>"].mcpServers` of `~/.claude.json` (private).
  local('local', 'Local', 'privado neste projeto'),

  /// `<workspace>/.mcp.json` (shared with the repository).
  project('project', 'Projeto', 'compartilhado via .mcp.json'),

  /// `mcpServers` of `~/.claude.json` (every project).
  user('user', 'Global', 'todos os workspaces');

  const McpScope(this.cliValue, this.label, this.hint);

  /// Value of `-s/--scope` (`claude mcp add/remove --help`, 2.1.300).
  final String cliValue;
  final String label;
  final String hint;

  /// Precedence of the CLI (docs mcp): local > project > user.
  int get precedence => switch (this) {
    local => 3,
    project => 2,
    user => 1,
  };
}

/// `type` of a server entry. Missing `type` with a `command` = stdio.
enum McpTransport {
  stdio('stdio'),
  http('http'),
  sse('sse'),
  ws('ws'),
  unknown('?');

  const McpTransport(this.label);

  final String label;

  static McpTransport parse(Object? type, {required bool hasCommand}) {
    final t = type is String ? type.toLowerCase() : null;
    return switch (t) {
      'stdio' => stdio,
      'http' || 'streamable-http' => http,
      'sse' => sse,
      'ws' || 'websocket' => ws,
      null => hasCommand ? stdio : unknown,
      _ => unknown,
    };
  }
}

/// Masked value shown instead of env / header values (never kept).
const mcpMask = '••••';

/// One server entry as exposed to the UI.
///
/// **No secret values**: env and header *values* are never read into this
/// model — only their key names ([envKeys], [headerKeys]). URL query values,
/// URL passwords and arguments that follow a secret-looking flag are masked
/// ([maskUrl], [maskArgs]).
@immutable
class McpServerConfig {
  const McpServerConfig({
    required this.name,
    required this.scope,
    required this.transport,
    required this.sourcePath,
    this.command,
    this.args = const [],
    this.url,
    this.envKeys = const [],
    this.headerKeys = const [],
    this.active = true,
  });

  final String name;
  final McpScope scope;
  final McpTransport transport;

  /// File holding the entry (`~/.claude.json` or `.mcp.json`).
  final String sourcePath;
  final String? command;

  /// Masked arguments ([maskArgs]).
  final List<String> args;

  /// Masked URL ([maskUrl]).
  final String? url;
  final List<String> envKeys;
  final List<String> headerKeys;

  /// false = another scope with the same name wins (local > project > user).
  final bool active;

  /// `npx -y pkg` or the URL.
  String get target => transport == McpTransport.stdio || command != null
      ? [command ?? '', ...args].where((s) => s.isNotEmpty).join(' ')
      : url ?? '';

  McpServerConfig withActive(bool value) => McpServerConfig(
    name: name,
    scope: scope,
    transport: transport,
    sourcePath: sourcePath,
    command: command,
    args: args,
    url: url,
    envKeys: envKeys,
    headerKeys: headerKeys,
    active: value,
  );

  /// JSON shown in the "Configuração" card: same shape as the file, values
  /// of env / headers replaced by [mcpMask].
  String maskedJson() {
    final m = <String, Object?>{
      if (transport != McpTransport.unknown) 'type': transport.name,
      'command': ?command,
      if (args.isNotEmpty) 'args': args,
      'url': ?url,
      if (envKeys.isNotEmpty) 'env': {for (final k in envKeys) k: mcpMask},
      if (headerKeys.isNotEmpty)
        'headers': {for (final k in headerKeys) k: mcpMask},
    };
    return const JsonEncoder.withIndent('  ').convert({name: m});
  }

  /// Builds an entry from one raw JSON value. Values of `env` / `headers`
  /// are dropped here — only the keys survive.
  static McpServerConfig? fromJson(
    String name,
    Object? raw,
    McpScope scope,
    String sourcePath,
  ) {
    if (raw is! Map) return null;
    final command = raw['command'] is String ? raw['command'] as String : null;
    final args = raw['args'] is List
        ? [for (final a in raw['args'] as List) '$a']
        : const <String>[];
    List<String> keys(Object? m) =>
        m is Map ? [for (final k in m.keys) '$k'] : const [];
    return McpServerConfig(
      name: name,
      scope: scope,
      transport: McpTransport.parse(raw['type'], hasCommand: command != null),
      sourcePath: sourcePath,
      command: command,
      args: maskArgs(args),
      url: raw['url'] is String ? maskUrl(raw['url'] as String) : null,
      envKeys: keys(raw['env']),
      headerKeys: keys(raw['headers']),
    );
  }
}

final _secretWord = RegExp(
  r'(token|secret|passw|api[-_]?key|apikey|auth|bearer|credential)',
  caseSensitive: false,
);

/// Masks the value after a secret-looking flag (`--api-key X`,
/// `--token=X`) — tokens are sometimes passed as arguments.
List<String> maskArgs(List<String> args) {
  final out = <String>[];
  var maskNext = false;
  for (final a in args) {
    if (maskNext) {
      out.add(mcpMask);
      maskNext = false;
      continue;
    }
    final eq = a.indexOf('=');
    if (a.startsWith('-') &&
        eq > 0 &&
        _secretWord.hasMatch(a.substring(0, eq))) {
      out.add('${a.substring(0, eq)}=$mcpMask');
    } else {
      out.add(a);
      maskNext = a.startsWith('-') && eq < 0 && _secretWord.hasMatch(a);
    }
  }
  return out;
}

/// Masks query values and the password of a URL.
String maskUrl(String url) => url
    .replaceAllMapped(
      RegExp(r'([?&][^=&#]+)=([^&#]*)'),
      (m) => '${m[1]}=$mcpMask',
    )
    .replaceAllMapped(
      RegExp(r'(//[^/:@]+):[^@/]*@'),
      (m) => '${m[1]}:$mcpMask@',
    );

/// Servers of the three scopes, sorted by scope then name.
@immutable
class McpRegistrySnapshot {
  const McpRegistrySnapshot(this.servers, {this.errors = const []});

  final List<McpServerConfig> servers;

  /// Unreadable files (path: message).
  final List<String> errors;

  List<McpServerConfig> ofScope(McpScope s) => [
    for (final c in servers)
      if (c.scope == s) c,
  ];

  /// The entry the CLI uses for [name] (highest precedence).
  McpServerConfig? effective(String name) {
    McpServerConfig? best;
    for (final c in servers) {
      if (c.name != name) continue;
      if (best == null || c.scope.precedence > best.scope.precedence) best = c;
    }
    return best;
  }
}

/// Reads (never writes — anti-padrão 0.5) the MCP configuration of the
/// three scopes: user (`<claudeJson>.mcpServers`), local
/// (`<claudeJson>.projects[<workspace>].mcpServers`) and project
/// (`<workspace>/.mcp.json`). Marks which entry wins for each name
/// (local > project > user).
class McpRegistry {
  McpRegistry({required this.claudeJsonPath, this.workspacePath});

  /// `~/.claude.json` (or `$CLAUDE_CONFIG_DIR/.claude.json`); null = none.
  final String? claudeJsonPath;
  final String? workspacePath;

  String? get projectJsonPath =>
      workspacePath == null ? null : '$workspacePath/.mcp.json';

  Future<McpRegistrySnapshot> read() async {
    final errors = <String>[];
    final all = <McpServerConfig>[];

    Future<Object?> readJson(String path) async {
      try {
        final f = File(path);
        if (!await f.exists()) return null;
        return jsonDecode(await f.readAsString());
      } catch (e) {
        errors.add('$path: ${e is FormatException ? 'JSON inválido' : e}');
        return null;
      }
    }

    void addAll(Object? servers, McpScope scope, String path) {
      if (servers is! Map) return;
      for (final MapEntry(:key, :value) in servers.entries) {
        final c = McpServerConfig.fromJson('$key', value, scope, path);
        if (c != null) all.add(c);
      }
    }

    if (claudeJsonPath != null) {
      final j = await readJson(claudeJsonPath!);
      if (j is Map) {
        addAll(j['mcpServers'], McpScope.user, claudeJsonPath!);
        final projects = j['projects'];
        if (workspacePath != null && projects is Map) {
          final p = projects[workspacePath];
          if (p is Map) {
            addAll(p['mcpServers'], McpScope.local, claudeJsonPath!);
          }
        }
      }
    }
    if (projectJsonPath != null) {
      final j = await readJson(projectJsonPath!);
      if (j is Map) addAll(j['mcpServers'], McpScope.project, projectJsonPath!);
    }

    final best = <String, McpScope>{};
    for (final c in all) {
      final b = best[c.name];
      if (b == null || c.scope.precedence > b.precedence) {
        best[c.name] = c.scope;
      }
    }
    final out = [for (final c in all) c.withActive(best[c.name] == c.scope)]
      ..sort((a, b) {
        final s = b.scope.precedence.compareTo(a.scope.precedence);
        return s != 0 ? s : a.name.compareTo(b.name);
      });
    return McpRegistrySnapshot(out, errors: errors);
  }
}

// --- providers -----------------------------------------------------------------

/// Path of the CLI's `.claude.json`: `$CLAUDE_CONFIG_DIR/.claude.json` when
/// the variable is set (verified on 2.1.300, plano Fase 11), else
/// `~/.claude.json`. Tests override it.
final claudeJsonPathProvider = Provider<String?>((ref) {
  final dir = Platform.environment['CLAUDE_CONFIG_DIR'];
  if (dir != null && dir.isNotEmpty) return '$dir/.claude.json';
  final home = ref.watch(agentHomeProvider);
  return home == null ? null : '$home/.claude.json';
});

/// Configured servers of a workspace (null = user scope only).
/// Invalidate after `claude mcp add/remove`.
final mcpRegistryProvider = FutureProvider.family<McpRegistrySnapshot, String?>(
  (ref, workspacePath) => McpRegistry(
    claudeJsonPath: ref.watch(claudeJsonPathProvider),
    workspacePath: workspacePath,
  ).read(),
);
