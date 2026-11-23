import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_agent_mapping.dart';
import 'package:promptorium/core/codex/codex_probe.dart';
import 'package:promptorium/core/providers/agent_provider.dart';
import 'package:promptorium/features/agents/agent_file.dart';

import 'fake_codex.dart';

/// SPEC-106 T1: the translation of every field of an agent, by mode, with
/// the table empty or full and models without the effort asked for.
void main() {
  // The catalog of the 0.170 probe (handshake.jsonl).
  final catalog = [
    for (final l in readCodexTranscript(
      'test/fixtures/codex/0.170/handshake.jsonl',
    ))
      if (l.dir == 'recv' && l.msg['id'] == 3)
        for (final m in (l.msg['result'] as Map)['data'] as List)
          CodexModelInfo(
            '${m['id']}',
            [
              for (final e in m['supportedReasoningEfforts'] as List)
                '${e['reasoningEffort']}',
            ],
            [for (final v in m['inputModalities'] as List) '$v'],
          ),
  ];

  AgentFile agent(String frontmatter, [String body = '']) =>
      AgentFile.parse('---\n$frontmatter\n---\n$body');

  final flutterDev = agent(
    'name: flutter-dev\n'
        'description: Dev Flutter\n'
        'model: sonnet\n'
        'effort: high\n'
        'tools: Read, Edit, Write, Bash, Grep, Glob\n'
        'maxTurns: 40\n'
        'mcpServers:\n  - github\n'
        'color: amber',
    'Você é um engenheiro Flutter.\nUse Riverpod.\n',
  );

  const full = CodexAgentTable(
    models: {'opus': 'gpt-6.2-sol', 'sonnet': 'gpt-6.1-terra'},
  );

  CodexAgentPlan plan(
    AgentFile a, {
    AgentAccess access = AgentAccess.edit,
    CodexAgentTable table = full,
    List<CodexModelInfo>? models,
    String runModel = 'gpt-6-sol',
    String? runEffort,
    bool sandbox = true,
  }) => codexAgentPlan(
    a,
    name: a.name ?? 'x',
    access: access,
    table: table,
    catalog: models ?? catalog,
    runModel: runModel,
    runEffort: runEffort,
    sandboxAvailable: sandbox,
  );

  CodexAgentField field(CodexAgentPlan p, String key) =>
      p.fields.firstWhere((f) => f.key == key);

  group('R1 instruções', () {
    test('the body goes with a header carrying the agent name', () {
      final p = plan(flutterDev);
      expect(p.instructions, startsWith('# Agente `flutter-dev`'));
      expect(p.instructions, contains('Use Riverpod.'));
      expect(field(p, 'prompt').state, CodexFieldState.applied);
      expect(field(p, 'prompt').value, '2 linhas');
    });

    test('the agent comes before the app instructions, separated', () {
      final s = codexAgentInstructions('# Agente `a`\n\nA', 'APP')!;
      expect(s.indexOf('A'), lessThan(s.indexOf('APP')));
      expect(s, contains('\n---\n'));
      expect(codexAgentInstructions(null, 'APP'), 'APP');
      expect(codexAgentInstructions('X', null), 'X');
    });

    test('an empty body sends no instructions', () {
      final p = plan(agent('name: a\ndescription: d'));
      expect(p.instructions, isNull);
      expect(p.fields.where((f) => f.key == 'prompt'), isEmpty);
    });
  });

  group('R2 modelo', () {
    test('an alias with an equivalent goes as the Codex model', () {
      final p = plan(flutterDev);
      expect(p.model, 'gpt-6.1-terra');
      expect(
        field(p, 'model'),
        const CodexAgentField(
          'model',
          'sonnet',
          'gpt-6.1-terra',
          CodexFieldState.adapted,
        ),
      );
    });

    test('without an equivalent, the model of the run kind', () {
      final p = plan(flutterDev, table: const CodexAgentTable());
      expect(p.model, 'gpt-6-sol');
      expect(field(p, 'model').target, 'padrão do Codex');
      final i = plan(
        agent('name: a\ndescription: d\nmodel: inherit'),
        table: const CodexAgentTable(),
      );
      expect(i.model, 'gpt-6-sol');
      expect(field(i, 'model').state, CodexFieldState.applied);
    });

    test('an id outside model/list is never sent', () {
      final stale = plan(
        flutterDev,
        table: const CodexAgentTable(models: {'sonnet': 'gpt-4-velho'}),
      );
      expect(stale.model, 'gpt-6-sol');
      expect(stale.warnings.single, contains('saiu do model/list'));
      final id = plan(agent('name: a\ndescription: d\nmodel: claude-x-1'));
      expect(id.model, 'gpt-6-sol');
      expect(field(id, 'model').target, 'padrão do Codex');
      // Catalog not read yet: nothing of the table goes.
      final unread = codexAgentPlan(
        flutterDev,
        name: 'flutter-dev',
        access: AgentAccess.edit,
        table: full,
        runModel: 'inherit',
      );
      expect(unread.model, 'inherit');
    });

    test('a Codex id the catalog has goes as is', () {
      final p = plan(agent('name: a\ndescription: d\nmodel: gpt-6-luna'));
      expect(p.model, 'gpt-6-luna');
      expect(field(p, 'model').state, CodexFieldState.applied);
    });
  });

  group('R3 esforço', () {
    test('the same name when the model offers it', () {
      final p = plan(flutterDev);
      expect(p.effort, 'high');
      expect(field(p, 'effort').state, CodexFieldState.applied);
    });

    test('P2: xhigh and max go to the highest effort of the model', () {
      final max = agent('name: a\ndescription: d\nmodel: opus\neffort: max');
      final sol = plan(max);
      expect(sol.effort, 'ultra');
      expect(sol.warnings, contains('ultra gasta mais cota.'));
      final luna = plan(
        max,
        table: const CodexAgentTable(models: {'opus': 'gpt-6-luna'}),
      );
      expect(luna.effort, 'max');
    });

    test('an effort the model lacks falls to the model default, with a '
        'warning; the effort sent is always in the list', () {
      final p = plan(
        agent('name: a\ndescription: d\nmodel: opus\neffort: high'),
        table: const CodexAgentTable(
          models: {'opus': 'gpt-6-luna'},
          efforts: {'high': 'ultra'},
        ),
      );
      expect(p.effort, isNull);
      expect(field(p, 'effort').target, 'padrão do modelo');
      expect(p.warnings.single, contains('indisponível em gpt-6-luna'));
      for (final level in codexAgentEffortLevels) {
        for (final m in catalog) {
          final q = plan(
            agent('name: a\ndescription: d\nmodel: opus\neffort: $level'),
            table: CodexAgentTable(models: {'opus': m.id}),
          );
          if (q.effort != null) expect(m.efforts, contains(q.effort));
        }
      }
    });

    test('the run effort is dropped when the new model does not have it', () {
      final p = plan(
        agent('name: a\ndescription: d\nmodel: haiku'),
        table: const CodexAgentTable(models: {'haiku': 'gpt-6-luna'}),
        runEffort: 'ultra',
      );
      expect(p.effort, isNull);
      expect(plan(flutterDev, runEffort: 'low').effort, 'high');
    });
  });

  group('R4 ferramentas', () {
    final reader = agent(
      'name: leitor\ndescription: d\ntools: Read, Grep, Glob',
    );

    test('a read-only agent runs read-only even in Editar', () {
      for (final a in [
        AgentAccess.edit,
        AgentAccess.refine,
        AgentAccess.yolo,
      ]) {
        final p = plan(reader, access: a);
        expect(p.sandbox, 'read-only', reason: '$a');
        expect(p.effectiveSandbox, 'read-only');
      }
      expect(field(plan(reader), 'tools').target, 'só leitura · read-only');
    });

    test('no agent raises the sandbox above the mode', () {
      for (final a in AgentAccess.values) {
        for (final f in [
          flutterDev,
          reader,
          agent('name: a\ndescription: d'),
        ]) {
          final p = plan(f, access: a);
          expect(p.sandbox, anyOf(isNull, 'read-only'));
          if (a.readOnly) expect(p.effectiveSandbox, 'read-only');
        }
      }
      expect(plan(flutterDev).effectiveSandbox, 'workspace-write');
      expect(
        field(plan(flutterDev), 'tools').target,
        'workspace-write · confirma edições',
      );
    });

    test('P5: Bash alone counts as writing', () {
      final p = plan(agent('name: a\ndescription: d\ntools: Read, Bash'));
      expect(p.sandbox, isNull);
      expect(p.effectiveSandbox, 'workspace-write');
    });

    test('disallowedTools without the write tools = read-only', () {
      final p = plan(
        agent(
          'name: a\ndescription: d\n'
          'disallowedTools: Edit, Write, MultiEdit, NotebookEdit, Bash',
        ),
      );
      expect(p.sandbox, 'read-only');
    });

    test('permissionMode plan restricts; others never widen', () {
      final p = plan(
        agent('name: a\ndescription: d\npermissionMode: plan\ntools: Edit'),
      );
      expect(p.sandbox, 'read-only');
      expect(field(p, 'permissionMode').state, CodexFieldState.adapted);
      final bypass = plan(
        agent('name: a\ndescription: d\npermissionMode: bypassPermissions'),
        access: AgentAccess.ask,
      );
      expect(bypass.effectiveSandbox, 'read-only');
      expect(field(bypass, 'permissionMode').state, CodexFieldState.ignored);
    });

    test('MCP tools in tools free nothing', () {
      final p = plan(
        agent('name: a\ndescription: d\ntools: Read, mcp__github__issues'),
      );
      expect(p.sandbox, 'read-only');
      expect(field(p, 'tools (MCP)').state, CodexFieldState.ignored);
    });

    test('decision 15: without the OS sandbox the read-only is said, not '
        'enforced, and the run still goes', () {
      final p = plan(reader, access: AgentAccess.yolo, sandbox: false);
      expect(p.sandbox, isNull);
      expect(p.effectiveSandbox, 'danger-full-access');
      expect(field(p, 'tools').state, CodexFieldState.ignored);
      expect(p.warnings.single, contains('não é imposto'));
    });
  });

  group('R5 ignorados', () {
    test('maxTurns, mcpServers, hooks, color and subagents are ignored', () {
      final p = plan(
        agent(
          'name: a\ndescription: d\nmaxTurns: 10\nmcpServers:\n  - github\n'
          'hooks:\n  Stop: []\ncolor: red\ntools: Read, Edit, Task',
        ),
      );
      expect(p.ignored, [
        'subagentes',
        'maxTurns',
        'mcpServers',
        'hooks',
        'color',
      ]);
    });

    test('summary and detail of flutter-dev (mock 3)', () {
      final p = plan(flutterDev);
      expect(p.summary, 'adaptado · 3 campos ignorados');
      expect(
        p.detail,
        'Instruções aplicadas · sonnet → gpt-6.1-terra · workspace-write · '
        'maxTurns, mcpServers e color ignorados no Codex',
      );
      expect(plan(agent('name: a\ndescription: d', 'x')).summary, 'aplicado');
    });
  });

  group('R11 registro', () {
    test('the record keeps name, model, effort, sandbox and ignored, and '
        'comes back without the .md', () {
      final p = plan(flutterDev);
      final rec = jsonDecode(jsonEncode(p.toRecord())) as Map;
      expect(rec['name'], 'flutter-dev');
      expect(rec['model'], 'gpt-6.1-terra');
      expect(rec['effort'], 'high');
      expect(rec['sandbox'], 'workspace-write');
      expect(rec['ignored'], ['maxTurns', 'mcpServers', 'color']);
      final back = CodexAgentPlan.fromRecord(rec)!;
      expect(back.label, 'flutter-dev · adaptado');
      expect(back.fields, p.fields);
      expect(CodexAgentPlan.fromRecord(null), isNull);
    });
  });

  group('R6 tabela', () {
    test('starts empty and reads app_settings', () {
      final t = CodexAgentTable.fromSettings(const {});
      expect(t.models, isEmpty);
      expect(t.effortFor('high'), 'high');
      expect(t.effortFor('max'), codexHighestEffort);
      final s = CodexAgentTable.fromSettings({
        codexAgentModelKey('opus'): 'gpt-6.2-sol',
        codexAgentModelKey('fable'): 'inherit',
        codexAgentEffortKey('low'): 'medium',
      });
      expect(s.models, {'opus': 'gpt-6.2-sol'});
      expect(s.effortFor('low'), 'medium');
    });

    test('P1: suggestion by position in model/list', () {
      expect(codexSuggestedModels(catalog), {
        'opus': 'gpt-6.2-sol',
        'sonnet': 'gpt-6-sol',
        'haiku': 'gpt-5.6-luna',
      });
      expect(codexSuggestedModels(const []), isEmpty);
      expect(codexHighestOf(['low', 'ultra', 'high']), 'ultra');
      expect(codexHighestOf(['a', 'b']), 'b');
    });
  });

  test('R12: withCodexAgent changes only the run options', () {
    final p = plan(agent('name: a\ndescription: d\ntools: Read', 'Leia.'));
    final o = withCodexAgent(
      const AgentStartOptions(
        workingDirectory: '/w',
        mode: PromptMode.edit,
        appendSystemPrompt: 'APP',
        extras: CodexExtras(
          writableRoots: ['/r'],
          compactLimit: '200k',
          mcpDisallowedTools: ['mcp__github__delete_branch'],
        ),
      ),
      p,
    );
    expect(o.model, 'gpt-6-sol');
    expect(o.appendSystemPrompt, startsWith('# Agente `a`'));
    expect(o.appendSystemPrompt, endsWith('APP'));
    expect(o.codex.sandbox, 'read-only');
    expect(o.codex.writableRoots, ['/r']);
    expect(o.codex.compactLimit, '200k');
    expect(o.codex.mcpDisallowedTools, ['mcp__github__delete_branch']);
  });
}
