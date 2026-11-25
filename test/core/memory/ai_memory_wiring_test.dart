import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/memory/ai_memory_cli.dart';
import 'package:promptorium/core/memory/ai_memory_wiring.dart';

import 'fake_ai_memory.dart';

/// SPEC-098 T3 (R3, R4, R5): the state of hooks and MCP per agent comes
/// from ai-memory itself, and the app never writes the agents' files.
///
/// The outputs below follow ai-memory 3.5.1's source (`setup --plan
/// --json` PlanDocument format 1, `uninstall` dry-run lines, `doctor
/// --json` codex_hooks): the binary was not installed on this machine.
void main() {
  const env = {'HOME': '/home/u'};

  final plan = {
    'format': 1,
    'data_dir': '/home/u/.local/share/ai-memory',
    'config_path': '/home/u/.config/ai-memory/config.toml',
    'fresh': false,
    'service': {'action': 'skip', 'reason': 'already running'},
    'agents': [
      {
        'agent': 'claude-code',
        'found': {'kind': 'session_store', 'path': '/home/u/.claude/projects'},
        'wiring': 'mcp+hooks+skills',
      },
      {'agent': 'codex', 'found': null, 'wiring': 'mcp+hooks+skills'},
    ],
    'other_agents': ['cursor'],
    'checks': ['healthz', 'memory_status', 'doctor'],
    'first_question': 'What do you remember about this project?',
  };
  const hooksPlan =
      'would remove SessionStart, SessionEnd, Stop from '
      '/home/u/.claude/settings.json\n'
      'would remove SessionStart, Stop from /home/u/.codex/hooks.json\n'
      'note: run `ai-memory uninstall --only hooks --apply` inside every other '
      'checkout that used `install-hooks --scope project`; their '
      '.claude/settings.local.json keeps calling this binary and data dir.\n'
      '(dry-run; pass --apply to remove)\n';
  const mcpPlan =
      'would remove ai-memory from /home/u/.claude.json\n'
      'would remove ai-memory from /home/u/.codex/config.toml\n'
      '(dry-run; pass --apply to remove)\n';
  final doctor = {
    'codex_hooks': {
      'trusted': <String>[],
      'skipped': [
        ['sessionStart', 'untrusted'],
        ['stop', 'untrusted'],
      ],
    },
  };

  test('R3: hooks and MCP on in both; Codex hooks "aguardando confiança" '
      'while Codex skips them', () {
    final w = buildAiMemoryWiring(
      plan: plan,
      hooksPlan: hooksPlan,
      mcpPlan: mcpPlan,
      doctor: doctor,
      env: env,
    );
    expect(w.planReadable, isTrue);
    expect(w.claude.hooks, AiMemoryLink.on);
    expect(w.claude.mcp, AiMemoryLink.on);
    expect(w.claude.found, contains('/home/u/.claude/projects'));
    expect(w.codex.hooks, AiMemoryLink.awaitingTrust);
    expect(w.codex.mcp, AiMemoryLink.on);
    expect(w.codex.trustSkipped, [
      'sessionStart (untrusted)',
      'stop (untrusted)',
    ]);
    expect(w.codexAppWithoutMemory, contains('aguardam confiança'));
    expect(w.dataDir, '/home/u/.local/share/ai-memory');
    // The relative path of the closing note never counts.
    expect(w.removal, hasLength(4));
    expect(w.removal.where((l) => l.startsWith('note')), isEmpty);
  });

  test('R3: absent when the dry-run says nothing; trusted Codex hooks are '
      'ligado; the marketplace plugin counts as on', () {
    var w = buildAiMemoryWiring(
      plan: plan,
      hooksPlan: 'Nothing to remove. ai-memory wiring not found.\n',
      mcpPlan: 'would remove ai-memory from /home/u/.claude.json\n',
      doctor: null,
      env: env,
    );
    expect(w.claude.hooks, AiMemoryLink.missing);
    expect(w.claude.mcp, AiMemoryLink.on);
    expect(w.codex.hooks, AiMemoryLink.missing);
    expect(w.codex.needsLink, isTrue);

    w = buildAiMemoryWiring(
      plan: plan,
      hooksPlan: hooksPlan,
      mcpPlan: mcpPlan,
      doctor: {
        'codex_hooks': {
          'trusted': ['sessionStart'],
          'skipped': <Object>[],
        },
      },
      env: env,
    );
    expect(w.codex.hooks, AiMemoryLink.on);
    expect(w.codexAppWithoutMemory, isNull);

    final withPlugin = jsonDecode(jsonEncode(plan)) as Map<String, Object?>;
    ((withPlugin['agents']! as List)[1] as Map)['wiring'] = 'plugin';
    w = buildAiMemoryWiring(
      plan: withPlugin,
      hooksPlan: '',
      mcpPlan: '',
      doctor: null,
      env: env,
    );
    expect(w.codex.plugin, isTrue);
    expect(w.codex.fullyOn, isTrue);
  });

  test('CLAUDE_CONFIG_DIR and CODEX_HOME are honored', () {
    const custom = {
      'HOME': '/home/u',
      'CLAUDE_CONFIG_DIR': '/cfg/claude',
      'CODEX_HOME': '/cfg/codex',
    };
    expect(
      agentOfPath('/cfg/claude/settings.json', custom),
      AiMemoryAgent.claude,
    );
    expect(agentOfPath('/cfg/codex/config.toml', custom), AiMemoryAgent.codex);
    expect(
      aiMemoryFilesFor(AiMemoryAgent.codex, env: custom).first.$1,
      '/cfg/codex/config.toml',
    );
  });

  test('R4: the preview lists the files ai-memory changes', () {
    expect(aiMemoryFilesFor(AiMemoryAgent.claude, env: env), [
      ('~/.claude/settings.json', 'hooks de ciclo de vida'),
      ('~/.claude.json', 'MCP ai-memory'),
      ('~/.local/share/ai-memory/hooks/claude-code/', 'scripts dos hooks'),
    ]);
    expect(aiMemoryFilesFor(AiMemoryAgent.codex, env: env), [
      ('~/.codex/config.toml', 'MCP ai-memory · hooks'),
      ('~/.local/share/ai-memory/hooks/codex/', 'scripts dos hooks'),
    ]);
    expect(AiMemoryAgent.codex.installCommands, [
      ['install-hooks', '--agent', 'codex', '--apply'],
      ['install-mcp', '--client', 'codex', '--apply'],
    ]);
  });

  test('R3: reading the state runs only read-only commands (setup --plan, '
      'uninstall without --apply, doctor)', () async {
    final fake = await FakeAiMemory.create(
      replies: {
        'setup': jsonEncode(plan),
        'uninstall hooks': hooksPlan,
        'uninstall mcp': mcpPlan,
        'doctor': jsonEncode(doctor),
      },
    );
    addTearDown(fake.dispose);
    final w = await loadAiMemoryWiring(
      AiMemoryCli(executable: fake.executable, log: (_) {}),
      env: env,
    );
    expect(w.codex.hooks, AiMemoryLink.awaitingTrust);
    final calls = fake.calls.map((c) => c.split('\t').first).toList();
    expect(calls.toSet(), {
      'setup --plan --json --agent claude-code --agent codex',
      'uninstall --only hooks',
      'uninstall --only mcp',
      'doctor --json',
    });
    expect(calls.where((c) => c.contains('--apply')), isEmpty);
  });

  test('R4/R5: the app never opens an agent file for writing (code '
      'inspection of the integration)', () {
    final files = [
      ...Directory('lib/core/memory').listSync().whereType<File>(),
      File('lib/features/settings/ai_memory_view.dart'),
      File('lib/features/settings/ai_memory_links.dart'),
    ];
    for (final f in files) {
      final src = f.readAsStringSync();
      for (final w in [
        'writeAsString',
        'writeAsBytes',
        'openWrite',
        'copySync',
        'renameSync',
        'deleteSync',
        '.create(',
      ]) {
        expect(src.contains(w), isFalse, reason: '${f.path} usa $w');
      }
    }
  });
}
