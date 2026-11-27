import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_provider.dart';
import 'package:promptorium/core/providers/agent_provider.dart';
import 'package:promptorium/core/providers/claude_code_provider.dart';
import 'package:promptorium/core/providers/structured_run.dart';
import 'package:promptorium/core/providers/workspace_assets.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/instructions/unify_service.dart';

import '../../core/codex/fake_codex.dart';
import '../../helpers/test_db.dart';
import '../project/project_planner_test.dart' show resultLine;
import '../sessions/session_test_utils.dart';

/// The project of the mock `3-unificar.png`.
const vitrineClaude = '''# vitrine

## Comandos
- Testes: `flutter test test/<area>`; a suíte inteira só no CI.
- Antes de commitar: `flutter analyze`.

## Regras
- Textos para o usuário em português do Brasil.
- Nunca use `print`; use o logger.

## Só para o Claude Code
- Use o subagente `tester` depois de mudar `packages/api`.
''';

const vitrineAgents = '''# vitrine

## Comandos
- Testes: `flutter test`.
- Antes de commitar: `flutter analyze`.

## Regras
- Textos para o usuário em português do Brasil.
''';

void main() {
  group('canUnify (R3)', () {
    test('only CLAUDE.md, two sources and a generated AGENTS.md; never the '
        'single source nor without CLAUDE.md', () {
      expect(canUnifyTexts(claude: vitrineClaude), isTrue);
      expect(
        canUnifyTexts(claude: vitrineClaude, agents: vitrineAgents),
        isTrue,
      );
      expect(
        canUnifyTexts(
          claude: vitrineClaude,
          agents: generatedAgentsMd(vitrineClaude),
        ),
        isTrue,
      );
      expect(
        canUnifyTexts(
          claude: '## Novo\n',
          agents: generatedAgentsMd('## Velho\n'),
        ),
        isTrue,
        reason: 'stale',
      );
      expect(
        canUnifyTexts(claude: '@AGENTS.md\n', agents: vitrineAgents),
        isFalse,
      );
      expect(canUnifyTexts(agents: vitrineAgents), isFalse);
      expect(canUnifyTexts(), isFalse);
      expect(
        canUnify(
          const InstructionsInventory(root: '/w', claudeText: vitrineClaude),
        ),
        isTrue,
      );
    });

    test('opening an old project writes nothing and warns nothing; the '
        'Codex override of SPEC-104 stays', () async {
      final dir = Directory.systemTemp.createTempSync('promptorium-unify-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final claude = File('${dir.path}/CLAUDE.md')
        ..writeAsStringSync(vitrineClaude);
      final before = claude.statSync().modified;

      final inv = await scanInstructions(dir.path);
      expect(inv.agentsState, AgentsMdState.absent);
      expect(canUnify(inv), isTrue, reason: 'offered, never done by itself');
      // Building the comparison does not touch the disk either.
      buildUnifyPlan(claude: inv.claudeText, agents: inv.agentsText);
      expect(dir.listSync().map((e) => e.path.split('/').last).toList(), [
        'CLAUDE.md',
      ]);
      expect(claude.readAsStringSync(), vitrineClaude);
      expect(claude.statSync().modified, before);

      // Without AGENTS.md the Codex still gets the CLAUDE.md by the override.
      final fake = FakeCodex();
      final run =
          await CodexProvider(
            starter: (exe, args, {workingDirectory, environment}) async {
              expect(args, ['app-server', '-c', codexInstructionsOverride]);
              expect(workingDirectory, dir.path);
              return fake;
            },
          ).start(
            AgentStartOptions(
              workingDirectory: dir.path,
              mode: PromptMode.edit,
            ),
          );
      run.events.listen((_) {});
      addTearDown(run.stop);
      expect(dir.listSync(), hasLength(1));
    });
  });

  group('parse', () {
    test('sections by heading, list items with continuation, paragraphs and '
        'code blocks as one item', () {
      final s = parseMdSections('''Intro do arquivo
em duas linhas.

# Título

## Regras
- um
  continua
- dois

Um parágrafo.

```sh
## não é título

- nem item
```
''');
      expect(s.map((x) => x.title), ['', 'Título', 'Regras']);
      expect(s[0].items.single.text, 'Intro do arquivo\nem duas linhas.');
      expect(s[1].items, isEmpty);
      expect(s[2].items.map((i) => i.text), [
        '- um\n  continua',
        '- dois',
        'Um parágrafo.',
        '```sh\n## não é título\n\n- nem item\n```',
      ]);
      expect(s[2].items.first.isList, isTrue);
      expect(s[2].key, 'regras');
    });

    test('render gives back a normalized document', () {
      expect(renderMdSections(parseMdSections(vitrineAgents)), vitrineAgents);
      expect(renderMdSections(const []), '');
    });

    test('a blank line after the heading is kept, as written', () {
      const spaced = '# vitrine\n\n- Rode o analyze.\n- Textos em português.\n';
      expect(renderMdSections(parseMdSections(spaced)), spaced);
      final r = composeUnify(
        buildUnifyPlan(
          claude: '$spaced- Nunca use print.\n',
          agents: '$spaced- Rotas em lib/router.dart.\n',
        ),
      );
      expect(r.agents, startsWith('# vitrine\n\n- Rode o analyze.\n'));
    });
  });

  group('diffs (R4)', () {
    test('by section and item: changed, only in CLAUDE.md and a whole '
        'section only of the Claude', () {
      final plan = buildUnifyPlan(claude: vitrineClaude, agents: vitrineAgents);
      expect(plan.hadAgents, isTrue);
      expect(plan.diffs, hasLength(3));
      final [test, print, tester] = plan.diffs;
      expect(test.kind, UnifyDiffKind.changed);
      expect(test.section, 'Comandos');
      expect(test.title, 'Testes');
      expect(test.claudeText, contains('test/<area>'));
      expect(test.agentsText, '- Testes: `flutter test`.');
      expect(test.defaultTarget, UnifyTarget.claudeVersion);

      expect(print.kind, UnifyDiffKind.onlyClaude);
      expect(print.wholeSection, isFalse);
      expect(print.section, 'Regras');
      expect(print.defaultTarget, UnifyTarget.agents);

      expect(tester.kind, UnifyDiffKind.onlyClaude);
      expect(tester.wholeSection, isTrue);
      expect(tester.title, 'Só para o Claude Code');
      expect(tester.claudeSpecific, isTrue);
      expect(tester.defaultTarget, UnifyTarget.claudeOnly);
    });

    test('equal files have no difference; the import line is not one', () {
      final plan = buildUnifyPlan(
        claude: '@AGENTS.md\n\n$vitrineAgents',
        agents: vitrineAgents,
      );
      expect(plan.diffs, isEmpty);
      expect(composeUnify(plan).agents, vitrineAgents);
      expect(composeUnify(plan).claude, '@AGENTS.md\n');
    });

    test('an item only in AGENTS.md and a section only in AGENTS.md', () {
      final plan = buildUnifyPlan(
        claude: '## Regras\n- a\n',
        agents: '## Regras\n- a\n- só do codex\n\n## Deploy\n- fly deploy\n',
      );
      expect(plan.diffs.map((d) => (d.kind, d.wholeSection)), [
        (UnifyDiffKind.onlyAgents, false),
        (UnifyDiffKind.onlyAgents, true),
      ]);
      expect(composeUnify(plan).agents, contains('- só do codex'));
      expect(composeUnify(plan).agents, contains('## Deploy\n- fly deploy'));
    });

    test('a generated AGENTS.md is a copy: its text is not a source', () {
      final stale = generatedAgentsMd('## Velho\n- texto antigo\n');
      final plan = buildUnifyPlan(claude: vitrineClaude, agents: stale);
      expect(plan.agentsGenerated, isTrue);
      expect(plan.hadAgents, isFalse);
      expect(
        plan.diffs.every((d) => d.kind == UnifyDiffKind.onlyClaude),
        isTrue,
      );
      expect(plan.diffs.map((d) => d.title), [
        'Comandos',
        'Regras',
        'Só para o Claude Code',
      ]);
      final r = composeUnify(plan);
      expect(r.agents, isNot(contains('texto antigo')));
      expect(r.agents, startsWith('# vitrine\n\n## Comandos'));
      expect(r.agents, isNot(contains('subagente')));
      expect(r.claude, startsWith('@AGENTS.md\n\n## Só para o Claude Code'));
    });

    test('only CLAUDE.md: every section goes to AGENTS.md by default', () {
      final plan = buildUnifyPlan(
        claude: '# app\n\n## Regras\n- pt-BR\n',
        agents: null,
      );
      expect(plan.diffs.single.defaultTarget, UnifyTarget.agents);
      final r = composeUnify(plan);
      expect(r.agents, '# app\n\n## Regras\n- pt-BR\n');
      expect(r.claude, '@AGENTS.md\n');
    });
  });

  group('result (R4)', () {
    test('defaults give the mock: AGENTS.md full, CLAUDE.md = import + '
        'Claude-only part', () {
      final r = composeUnify(
        buildUnifyPlan(claude: vitrineClaude, agents: vitrineAgents),
      );
      expect(r.agents, '''# vitrine

## Comandos
- Testes: `flutter test test/<area>`; a suíte inteira só no CI.
- Antes de commitar: `flutter analyze`.

## Regras
- Textos para o usuário em português do Brasil.
- Nunca use `print`; use o logger.
''');
      expect(r.claude, '''@AGENTS.md

## Só para o Claude Code
- Use o subagente `tester` depois de mudar `packages/api`.
''');
      expect(hasAgentsImport(r.claude), isTrue);
      expect(
        agentsMdState(claude: r.claude, agents: r.agents),
        AgentsMdState.singleSource,
      );
    });

    test('the three destinations: AGENTS.md, Claude-only and a version '
        '(or another text)', () {
      final plan = buildUnifyPlan(claude: vitrineClaude, agents: vitrineAgents);
      final [test, print, tester] = plan.diffs;
      var r = composeUnify(
        plan,
        choices: {
          test.id: UnifyTarget.agentsVersion,
          print.id: UnifyTarget.claudeOnly,
          tester.id: UnifyTarget.agents,
        },
      );
      expect(r.agents, contains('- Testes: `flutter test`.'));
      expect(r.agents, isNot(contains('print')));
      expect(r.agents, contains('## Só para o Claude Code'));
      expect(r.claude, contains('## Regras\n- Nunca use `print`'));
      expect(r.claude, isNot(contains('tester')));

      r = composeUnify(
        plan,
        choices: {test.id: UnifyTarget.custom},
        custom: {test.id: '- Testes: `make test`.'},
      );
      expect(r.agents, contains('- Testes: `make test`.'));
      expect(r.agents, isNot(contains('flutter test`')));

      // A destination the difference does not accept falls to the default.
      r = composeUnify(plan, choices: {print.id: UnifyTarget.agentsVersion});
      expect(r.agents, contains('Nunca use `print`'));
    });
  });

  group('Pedir ajuda da IA (R4)', () {
    test('parse keeps known ids and accepted destinations only', () {
      final plan = buildUnifyPlan(claude: vitrineClaude, agents: vitrineAgents);
      final s = parseUnifySuggestions({
        'suggestions': [
          {'id': 'd1', 'target': 'claudeVersion', 'reason': 'mais atual'},
          {'id': 'd2', 'target': 'claudeVersion', 'reason': 'não aceita'},
          {'id': 'd9', 'target': 'agents', 'reason': 'não existe'},
          {'id': 'd3', 'target': 'claudeOnly', 'reason': 'só do Claude'},
        ],
      }, plan);
      expect(s.keys, ['d1', 'd3']);
      expect(s['d1']!.target, UnifyTarget.claudeVersion);
      expect(s['d3']!.reason, 'só do Claude');
      expect(() => parseUnifySuggestions('x', plan), throwsA(anything));
      expect(codexSchemaProblems(unifySuggestionSchema), isEmpty);
    });

    test('suggests on the planner provider, read-only, with the schema; '
        'nothing is decided nor written', () async {
      final dir = Directory.systemTemp.createTempSync('promptorium-unify-ai-');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/CLAUDE.md').writeAsStringSync(vitrineClaude);
      File('${dir.path}/AGENTS.md').writeAsStringSync(vitrineAgents);
      final cli = FakeCli();
      final c = ProviderContainer(
        overrides: sessionOverrides(
          db: memoryDatabase(),
          cli: cli,
          notifier: FakeNotifier(),
        ),
      );
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.notifier).load();
      final plan = buildUnifyPlan(claude: vitrineClaude, agents: vitrineAgents);

      final f = c.read(unifySuggesterProvider)(plan, cwd: dir.path);
      await settle();
      final args = cli.args.last;
      expect(
        jsonDecode(args[args.indexOf('--json-schema') + 1]),
        unifySuggestionSchema,
      );
      expect(
        args.sublist(args.indexOf('--disallowedTools') + 1),
        ClaudeCodeProvider.readOnlyDisallowedTools,
      );
      expect(cli.cwds.last, dir.path);
      final sent = '${cli.last.writtenJson.single['message']['content']}';
      expect(sent, contains('d1 · changed'));
      expect(sent, contains('test/<area>'));
      cli.last.emit(
        resultLine({
          'suggestions': [
            {'id': 'd2', 'target': 'claudeOnly', 'reason': 'regra do Claude'},
          ],
        }),
      );
      final s = await f;
      expect(s['d2']!.target, UnifyTarget.claudeOnly);
      expect(File('${dir.path}/CLAUDE.md').readAsStringSync(), vitrineClaude);
      expect(File('${dir.path}/AGENTS.md').readAsStringSync(), vitrineAgents);
    });
  });
}
