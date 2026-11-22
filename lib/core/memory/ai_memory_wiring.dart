import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'ai_memory_cli.dart';
import 'ai_memory_state.dart';

/// State of one piece (hooks or MCP) of ai-memory in one agent (R3).
enum AiMemoryLink {
  on('ligado'),
  missing('ausente'),
  outdated('desatualizado'),
  awaitingTrust('aguardando confiança'),
  unknown('não verificado');

  const AiMemoryLink(this.label);
  final String label;
}

/// The agents the app wires (out of scope: the others ai-memory supports).
enum AiMemoryAgent {
  claude('claude-code', 'Claude Code', 'claude'),
  codex('codex', 'Codex', 'codex');

  const AiMemoryAgent(this.cliName, this.label, this.providerId);

  /// `--agent` / `--client` value of ai-memory.
  final String cliName;
  final String label;

  /// Id of the app's provider (for the chip).
  final String providerId;

  /// Commands "Ligar" runs, after the preview (R4). Never `setup` nor
  /// `install-instructions`, which would touch CLAUDE.md/AGENTS.md or
  /// other agents.
  List<List<String>> get installCommands => [
    ['install-hooks', '--agent', cliName, '--apply'],
    ['install-mcp', '--client', cliName, '--apply'],
  ];
}

/// ai-memory 3.5.1 has no per-agent uninstall: `uninstall --only <part>`
/// removes that part from every agent (P5). The app shows these to copy and
/// never runs them.
const aiMemoryUninstallCommands = [
  'ai-memory uninstall --only hooks --apply',
  'ai-memory uninstall --only mcp --apply',
];

/// ai-memory's state in one agent.
@immutable
class AiMemoryAgentWiring {
  const AiMemoryAgentWiring({
    required this.agent,
    this.hooks = AiMemoryLink.unknown,
    this.mcp = AiMemoryLink.unknown,
    this.plugin = false,
    this.found,
    this.trustSkipped = const [],
  });

  final AiMemoryAgent agent;
  final AiMemoryLink hooks;
  final AiMemoryLink mcp;

  /// Wired by ai-memory's marketplace plugin (hooks and MCP inside it).
  final bool plugin;

  /// Why setup detected the agent ("found its session store at …").
  final String? found;

  /// Codex hook events it skips, with Codex's reason.
  final List<String> trustSkipped;

  bool get fullyOn => hooks == AiMemoryLink.on && mcp == AiMemoryLink.on;
  bool get anyOn =>
      hooks == AiMemoryLink.on ||
      hooks == AiMemoryLink.awaitingTrust ||
      mcp == AiMemoryLink.on;
  bool get needsLink =>
      hooks == AiMemoryLink.missing ||
      hooks == AiMemoryLink.outdated ||
      mcp == AiMemoryLink.missing ||
      mcp == AiMemoryLink.outdated;
}

/// ai-memory in both agents, plus what the "Desligar" dialog shows.
@immutable
class AiMemoryWiring {
  const AiMemoryWiring({
    required this.claude,
    required this.codex,
    this.dataDir,
    this.removal = const [],
    this.planReadable = true,
  });

  final AiMemoryAgentWiring claude;
  final AiMemoryAgentWiring codex;

  /// ai-memory's data dir (`setup --plan`), where the hook scripts go.
  final String? dataDir;

  /// Lines of the uninstall dry-run: what "Desligar" would remove.
  final List<String> removal;

  /// `setup --plan --json` answered in a known layout (format 1).
  final bool planReadable;

  AiMemoryAgentWiring of(AiMemoryAgent a) =>
      a == AiMemoryAgent.claude ? claude : codex;

  /// Codex runs in the app carry the hooks only once Codex trusts them
  /// (R7). Null when they do.
  String? get codexAppWithoutMemory => switch (codex.hooks) {
    AiMemoryLink.awaitingTrust =>
      'os hooks do ai-memory aguardam confiança no Codex: abra o Codex uma '
          'vez e confie neles em /hooks.',
    AiMemoryLink.missing =>
      'os hooks do ai-memory não estão no Codex: ligue no Codex.',
    _ => null,
  };
}

/// Which agent a config path belongs to, for the uninstall dry-run lines.
AiMemoryAgent? agentOfPath(String path, Map<String, String> env) {
  final claudeDir = env['CLAUDE_CONFIG_DIR'];
  final codexHome = env['CODEX_HOME'];
  if (claudeDir != null && claudeDir.isNotEmpty) {
    if (p.equals(path, claudeDir) || p.isWithin(claudeDir, path)) {
      return AiMemoryAgent.claude;
    }
  }
  if (codexHome != null && codexHome.isNotEmpty) {
    if (p.equals(path, codexHome) || p.isWithin(codexHome, path)) {
      return AiMemoryAgent.codex;
    }
  }
  if (path.contains('/.claude/') ||
      path.endsWith('/.claude.json') ||
      path.endsWith('/.claude') ||
      path.contains('/hooks/claude-code')) {
    return AiMemoryAgent.claude;
  }
  if (path.contains('/.codex/') ||
      path.endsWith('/.codex') ||
      path.contains('/hooks/codex')) {
    return AiMemoryAgent.codex;
  }
  return null;
}

/// Agents that hold ai-memory entries, from the lines of
/// `uninstall --only <part>` without `--apply` ("would remove … from /home/u/.claude/…").
/// Only absolute paths count: the closing note names a relative
/// `.claude/settings.local.json` of other checkouts.
Set<AiMemoryAgent> agentsInRemovalPlan(String out, Map<String, String> env) {
  final found = <AiMemoryAgent>{};
  for (final line in out.split('\n')) {
    for (final m in RegExp(
      r'''(?:^|[\s(])((?:/|~/)[^\s,'"`)]+)''',
    ).allMatches(line)) {
      var path = m[1]!;
      if (path.startsWith('~/') && env['HOME'] != null) {
        path = p.join(env['HOME']!, path.substring(2));
      }
      final a = agentOfPath(path, env);
      if (a != null) found.add(a);
    }
  }
  return found;
}

/// Lines of the dry-run that name an agent's file (for the dialog).
List<String> removalLines(String out, Map<String, String> env) => [
  for (final line in out.split('\n'))
    if (line.trim().isNotEmpty && agentsInRemovalPlan(line, env).isNotEmpty)
      line.trim(),
];

/// Builds the wiring from what ai-memory itself reports (R3): `setup --plan
/// --json` (detection and plugin wiring), the uninstall dry-runs (which
/// entries exist) and `doctor --json` (whether Codex trusts the hooks).
AiMemoryWiring buildAiMemoryWiring({
  required Map<String, Object?>? plan,
  required String? hooksPlan,
  required String? mcpPlan,
  required Map<String, Object?>? doctor,
  required Map<String, String> env,
}) {
  final planOk = plan != null && plan['format'] == 1;
  final planAgents = <String, Map<String, Object?>>{
    if (plan?['agents'] case final List list)
      for (final a in list)
        if (a is Map && a['agent'] is String)
          a['agent'] as String: a.cast<String, Object?>(),
  };
  final withHooks = hooksPlan == null
      ? null
      : agentsInRemovalPlan(hooksPlan, env);
  final withMcp = mcpPlan == null ? null : agentsInRemovalPlan(mcpPlan, env);
  final trust = doctor?['codex_hooks'];
  final skipped = <String>[
    if (trust is Map && trust['skipped'] is List)
      for (final s in trust['skipped'] as List)
        if (s is List && s.isNotEmpty)
          s.length > 1 ? '${s[0]} (${s[1]})' : '${s[0]}'
        else if (s is String)
          s,
  ];

  AiMemoryAgentWiring agent(AiMemoryAgent a) {
    final entry = planAgents[a.cliName];
    final plugin = entry?['wiring'] == 'plugin';
    AiMemoryLink link(Set<AiMemoryAgent>? present, String part) {
      // A future plan layout may say it outright.
      final stated = entry?[part];
      if (stated is String) {
        switch (stated) {
          case 'installed' || 'on' || 'up_to_date':
            return AiMemoryLink.on;
          case 'missing' || 'absent':
            return AiMemoryLink.missing;
          case 'outdated' || 'stale':
            return AiMemoryLink.outdated;
        }
      }
      if (plugin) return AiMemoryLink.on;
      if (present == null) return AiMemoryLink.unknown;
      return present.contains(a) ? AiMemoryLink.on : AiMemoryLink.missing;
    }

    var hooks = link(withHooks, 'hooks');
    if (a == AiMemoryAgent.codex &&
        hooks == AiMemoryLink.on &&
        skipped.isNotEmpty) {
      hooks = AiMemoryLink.awaitingTrust;
    }
    final found = entry?['found'];
    return AiMemoryAgentWiring(
      agent: a,
      hooks: hooks,
      mcp: link(withMcp, 'mcp'),
      plugin: plugin,
      found: found is Map && found['path'] is String
          ? '${found['kind']}: ${found['path']}'
          : null,
      trustSkipped: a == AiMemoryAgent.codex ? skipped : const [],
    );
  }

  return AiMemoryWiring(
    claude: agent(AiMemoryAgent.claude),
    codex: agent(AiMemoryAgent.codex),
    dataDir: plan?['data_dir'] is String ? plan!['data_dir'] as String : null,
    removal: [
      ...removalLines(hooksPlan ?? '', env),
      ...removalLines(mcpPlan ?? '', env),
    ],
    planReadable: planOk,
  );
}

/// Reads the wiring through the CLI (all read-only commands).
Future<AiMemoryWiring> loadAiMemoryWiring(
  AiMemoryCli cli, {
  required Map<String, String> env,
}) async {
  final results = await Future.wait<Object?>([
    cli.setupPlan([for (final a in AiMemoryAgent.values) a.cliName]),
    cli.removalPlan('hooks'),
    cli.removalPlan('mcp'),
  ]);
  final hooksPlan = results[1] as String?;
  // `doctor` asks Codex itself for the hooks' trust: only worth it when
  // ai-memory's Codex hooks are there.
  final codexHooks =
      hooksPlan != null &&
      agentsInRemovalPlan(hooksPlan, env).contains(AiMemoryAgent.codex);
  return buildAiMemoryWiring(
    plan: results[0] as Map<String, Object?>?,
    hooksPlan: hooksPlan,
    mcpPlan: results[2] as String?,
    doctor: codexHooks ? await cli.doctor() : null,
    env: env,
  );
}

/// The wiring, read when Configurações → Memória opens (and after Ligar);
/// null without the binary.
final aiMemoryWiringProvider = FutureProvider<AiMemoryWiring?>((ref) async {
  final cli = await ref.watch(aiMemoryCliProvider.future);
  if (cli == null) return null;
  return loadAiMemoryWiring(cli, env: ref.watch(aiMemoryEnvironmentProvider));
});

/// Files ai-memory's installers change for [agent] (shown in the preview,
/// never opened by the app), with what each holds.
List<(String, String)> aiMemoryFilesFor(
  AiMemoryAgent agent, {
  required Map<String, String> env,
  String? dataDir,
}) {
  final home = env['HOME'] ?? '~';
  String tilde(String path) =>
      path.startsWith('$home/') ? '~${path.substring(home.length)}' : path;
  final data = dataDir ?? p.join(home, '.local', 'share', 'ai-memory');
  switch (agent) {
    case AiMemoryAgent.claude:
      final dir = env['CLAUDE_CONFIG_DIR'];
      return [
        (
          tilde(p.join(dir ?? p.join(home, '.claude'), 'settings.json')),
          'hooks de ciclo de vida',
        ),
        (
          tilde(
            dir == null
                ? p.join(home, '.claude.json')
                : p.join(dir, '.claude.json'),
          ),
          'MCP ai-memory',
        ),
        (
          '${tilde(p.join(data, 'hooks', 'claude-code'))}/',
          'scripts dos hooks',
        ),
      ];
    case AiMemoryAgent.codex:
      final dir = env['CODEX_HOME'] ?? p.join(home, '.codex');
      return [
        (tilde(p.join(dir, 'config.toml')), 'MCP ai-memory · hooks'),
        ('${tilde(p.join(data, 'hooks', 'codex'))}/', 'scripts dos hooks'),
      ];
  }
}
