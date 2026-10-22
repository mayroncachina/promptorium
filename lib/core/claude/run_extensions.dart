import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';

/// Plugins and MCP servers of the user that the app's Claude runs leave out
/// (SPEC-017 R2): a `--settings` with `enabledPlugins: {id: false}` and
/// `deniedMcpServers`. Verified on CLI 2.1.308
/// (docs/pesquisa/plugins-mcp-desligados.md): the plugin, its MCP server,
/// its tools and its hooks go away; a denied server goes away and the
/// others stay. The Claude Code of the terminal does not change.
typedef RunExtensions = ({Set<String> plugins, Set<String> mcpServers});

/// `--settings` JSON turning [off] off; empty when nothing is.
Map<String, Object?> disabledExtensionsJson(RunExtensions off) => {
  if (off.plugins.isNotEmpty)
    'enabledPlugins': {for (final p in off.plugins.toList()..sort()) p: false},
  if (off.mcpServers.isNotEmpty)
    'deniedMcpServers': [
      for (final s in off.mcpServers.toList()..sort()) {'serverName': s},
    ],
};

/// A plugin seen in `system/init` (`source` = `nome@marketplace`).
@immutable
class KnownPlugin {
  const KnownPlugin({required this.id, this.version, this.tools = 0});

  final String id;
  final String? version;

  /// MCP tools it brings (`mcp__plugin_<nome>_…`).
  final int tools;

  String get name => id.split('@').first;

  Map<String, Object?> toJson() => {
    'id': id,
    'version': ?version,
    'tools': tools,
  };
}

/// An MCP server of the user, the project or claude.ai seen in
/// `system/init` (the plugins' follow their plugin).
@immutable
class KnownMcpServer {
  const KnownMcpServer({required this.name, required this.source});

  final String name;

  /// `user`, `project` or `claudeai`.
  final String source;

  Map<String, Object?> toJson() => {'name': name, 'source': source};
}

typedef KnownExtensions = ({
  List<KnownPlugin> plugins,
  List<KnownMcpServer> servers,
});

/// What the user can turn off, from a `system/init` (raw JSON): plugins but
/// the `@builtin` ones, MCP servers of `user` / `project` / `claudeai`.
KnownExtensions knownExtensionsFromInit(Map<String, dynamic> init) {
  final tools = [for (final t in init['tools'] as List? ?? const []) '$t'];
  return (
    plugins: [
      for (final p in init['plugins'] as List? ?? const [])
        if (p is Map && '${p['source'] ?? ''}'.contains('@'))
          if (!'${p['source']}'.endsWith('@builtin'))
            KnownPlugin(
              id: '${p['source']}',
              version: p['version'] as String?,
              tools: tools
                  .where(
                    (t) => t.startsWith(
                      'mcp__plugin_${'${p['source']}'.split('@').first}_',
                    ),
                  )
                  .length,
            ),
    ],
    servers: [
      for (final s in init['mcp_servers'] as List? ?? const [])
        if (s is Map &&
            const {'user', 'project', 'claudeai'}.contains(s['source']))
          KnownMcpServer(name: '${s['name']}', source: '${s['source']}'),
    ],
  );
}

String encodeKnownExtensions(KnownExtensions k) => jsonEncode({
  'plugins': [for (final p in k.plugins) p.toJson()],
  'servers': [for (final s in k.servers) s.toJson()],
});

KnownExtensions decodeKnownExtensions(String? raw) {
  const empty = (plugins: <KnownPlugin>[], servers: <KnownMcpServer>[]);
  if (raw == null || raw.isEmpty) return empty;
  try {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return (
      plugins: [
        for (final p in j['plugins'] as List? ?? const [])
          KnownPlugin(
            id: '${p['id']}',
            version: p['version'] as String?,
            tools: (p['tools'] as num?)?.toInt() ?? 0,
          ),
      ],
      servers: [
        for (final s in j['servers'] as List? ?? const [])
          KnownMcpServer(name: '${s['name']}', source: '${s['source']}'),
      ],
    );
  } catch (_) {
    return empty;
  }
}

Set<String> _set(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  try {
    return {for (final v in jsonDecode(raw) as List) '$v'};
  } catch (_) {
    return const {};
  }
}

/// What the user turned off (Configurações › Execução de specs).
final runExtensionsProvider = Provider<RunExtensions>((ref) {
  final s = ref.watch(appSettingsProvider);
  return (
    plugins: _set(s[AppSettingKeys.disabledPlugins]),
    mcpServers: _set(s[AppSettingKeys.disabledMcpServers]),
  );
});

/// Folder of the files the app passes in `--settings`.
final runSettingsDirProvider = Provider<String>(
  (ref) => '${Platform.environment['HOME'] ?? ''}/.promptorium/run',
);

/// Writes [json] to `<dir>/settings-<hash>.json` (same content, same file:
/// a run never sees the file change under it) and returns its path; null
/// when [json] is empty.
Future<String?> writeRunSettings(String dir, Map<String, Object?> json) async {
  if (json.isEmpty) return null;
  final text = jsonEncode(json);
  final hash = sha1.convert(utf8.encode(text)).toString().substring(0, 12);
  final f = File('$dir/settings-$hash.json');
  if (!await f.exists()) {
    await f.parent.create(recursive: true);
    await f.writeAsString(text);
  }
  return f.path;
}

/// `--settings` of a Claude run that has no hooks of its own (conversations,
/// read-only runs): the extensions turned off, or null.
Future<String?> runSettingsFile(Ref ref) => writeRunSettings(
  ref.read(runSettingsDirProvider),
  disabledExtensionsJson(ref.read(runExtensionsProvider)),
);

/// Records the plugins and servers of a `system/init` (raw JSON) for the
/// settings screen; ones turned off in the app do not show in the init,
/// so they are kept from the previous record.
Future<void> recordKnownExtensions(Ref ref, Map<String, dynamic> init) async {
  // Only Claude's init lists plugins (other providers have no such key).
  if (!init.containsKey('plugins')) return;
  final settings = ref.read(appSettingsProvider.notifier);
  final seen = knownExtensionsFromInit(init);
  final before = decodeKnownExtensions(
    settings.get(AppSettingKeys.knownExtensions),
  );
  final off = ref.read(runExtensionsProvider);
  final merged = (
    plugins: [
      ...seen.plugins,
      for (final p in before.plugins)
        if (off.plugins.contains(p.id) &&
            !seen.plugins.any((x) => x.id == p.id))
          p,
    ],
    servers: [
      ...seen.servers,
      for (final s in before.servers)
        if (off.mcpServers.contains(s.name) &&
            !seen.servers.any((x) => x.name == s.name))
          s,
    ],
  );
  await settings.set(
    AppSettingKeys.knownExtensions,
    encodeKnownExtensions(merged),
  );
}
