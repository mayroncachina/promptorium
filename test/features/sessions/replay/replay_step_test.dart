import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_neutral.dart';
import 'package:promptorium/features/sessions/replay/replay_step.dart';
import 'package:promptorium/features/sessions/replay/widgets/replay_style.dart';
import 'package:promptorium/features/sessions/timeline.dart';

import 'replay_fixtures.dart';

void main() {
  group('replaySteps (SPEC-082 R2)', () {
    test('each tool gets its kind and lane', () {
      final b = TimelineBuilder();
      const kinds = {
        'Read': ReplayKind.read,
        'Grep': ReplayKind.read,
        'Glob': ReplayKind.read,
        'LS': ReplayKind.read,
        'Edit': ReplayKind.edit,
        'MultiEdit': ReplayKind.edit,
        'Write': ReplayKind.edit,
        'NotebookEdit': ReplayKind.edit,
        'Bash': ReplayKind.run,
        'WebFetch': ReplayKind.web,
        'WebSearch': ReplayKind.web,
        'Task': ReplayKind.subagent,
        'Agent': ReplayKind.subagent,
        'TodoWrite': ReplayKind.plan,
        'ExitPlanMode': ReplayKind.plan,
        'mcp__github__get_me': ReplayKind.other,
      };
      for (final name in kinds.keys) {
        b.tool(name, {'file_path': '/w/a.dart'});
      }
      final steps = replaySteps(b.items);
      expect([for (final s in steps) s.kind], kinds.values.toList());
      expect(steps.first.lane, ReplayLane.read);
      expect(steps[4].lane, ReplayLane.edit);
      expect(steps[8].lane, ReplayLane.run);
      expect(steps[13].lane, ReplayLane.talk);
    });

    test('conversation steps, targets relative to the root, turns', () {
      final b = TimelineBuilder();
      b.note('Sessão iniciada');
      b.user('Implemente a R2\ncom cuidado');
      b.think('vou ler primeiro');
      b.read('/w/lib/a.dart');
      b.say('Pronto.');
      b.user('o gate reprovou: o CI fica verde');
      b.bash('flutter test');
      final steps = replaySteps(b.items, root: '/w');
      expect(
        [for (final s in steps) s.kind],
        [
          ReplayKind.mark,
          ReplayKind.user,
          ReplayKind.thinking,
          ReplayKind.read,
          ReplayKind.assistant,
          ReplayKind.user,
          ReplayKind.run,
        ],
      );
      expect([for (final s in steps) s.turn], [1, 1, 1, 1, 1, 2, 2]);
      expect(steps[1].target, 'Implemente a R2');
      expect(steps[3].target, 'lib/a.dart');
      expect(steps[6].target, 'flutter test');
      final starts = turnStarts(steps);
      expect(starts[2]!.target, 'o gate reprovou: o CI fica verde');
    });

    test('duration until the result or the next step; outcomes', () {
      final b = TimelineBuilder();
      b.bash('flutter test', took: const Duration(seconds: 48), error: true);
      b.say('falhou');
      final denied = b.tool('Edit', {
        'file_path': '/w/pubspec.yaml',
        'old_string': 'a',
        'new_string': 'b',
      }, result: null);
      b.denied(denied);
      b.tool('Bash', {'command': 'sleep 1'}, result: null);
      final steps = replaySteps(b.items);
      expect(steps[0].duration, const Duration(seconds: 48));
      expect(steps[0].outcome, ReplayOutcome.error);
      expect(steps[0].isProblem, isTrue);
      expect(steps[1].duration, const Duration(seconds: 1));
      expect(steps[2].outcome, ReplayOutcome.denied);
      expect(steps[2].isProblem, isTrue);
      expect(steps[3].outcome, ReplayOutcome.pending);
    });

    test('edit stats', () {
      final b = TimelineBuilder();
      b.edit('/w/a.dart', 'x\ny', 'a\nb\nc\nd\ne\nf');
      final s = replaySteps(b.items).single;
      expect((s.added, s.removed), (6, 2));
      expect(s.statsLabel, '+6 −2');
    });

    test('app marks: gate, compaction, resume, error', () {
      final b = TimelineBuilder();
      b.note('Verificação aprovada: ✓ commit');
      b.note('Verificação falhou: ✗ testes (12 s)', error: true);
      b.compact();
      b.note('Sessão retomada (--resume)');
      b.note('Falha ao iniciar claude: x', error: true);
      final steps = replaySteps(b.items);
      expect(
        [for (final s in steps) s.mark],
        [
          ReplayMarkKind.gatePassed,
          ReplayMarkKind.gateFailed,
          ReplayMarkKind.compaction,
          ReplayMarkKind.resume,
          ReplayMarkKind.error,
        ],
      );
      expect(steps[1].isProblem, isTrue);
      expect(steps[4].isProblem, isTrue);
      expect(steps[0].isProblem, isFalse);
      expect(steps[2].mark!.isFlag, isTrue);
      expect(steps.every((s) => s.lane == null), isTrue);
    });

    test('a subagent is one step with its own steps (P7)', () {
      final b = TimelineBuilder();
      final task = b.tool('Task', {
        'description': 'ache onde o CI é lido',
        'prompt': 'procure',
      }, result: null);
      b.tool('Grep', {'pattern': 'ciFixer'}, parent: task);
      b.read('/w/a.dart');
      final steps = replaySteps(b.items);
      expect(steps, hasLength(2));
      expect(steps[0].kind, ReplayKind.subagent);
      expect(steps[0].children, hasLength(1));
      expect(steps[0].children.single.parent, same(steps[0]));
      expect(steps[0].children.single.kind, ReplayKind.read);
      expect(flattenSteps(steps).length, 3);
    });

    test('long pauses are cut (P4)', () {
      final b = TimelineBuilder();
      b.read('/w/a.dart');
      b.pause(const Duration(hours: 2));
      b.read('/w/b.dart');
      final steps = replaySteps(b.items);
      final pauses = longPauses(steps);
      expect(pauses.keys, [1]);
      expect(shortDuration(pauses[1]!), '2 h');
    });

    test('the compaction notice is in the Timeline', () {
      final b = TimelineBuilder();
      b.compact();
      expect((b.items.single as NoticeItem).text, Timeline.compactionNotice);
    });
  });

  group('SPEC-110 R1 · passos do Codex', () {
    ReplayStep only(List<ReplayStep> steps, ReplayKind k) =>
        steps.singleWhere((s) => s.kind == k);

    test('leituras por comando viram Ler, com o alvo e a origem', () {
      final b = TimelineBuilder()..user('corrija');
      b.turn('t-1');
      b.command('c1', "/usr/bin/zsh -lc 'rg calcularFrete lib/'", [
        {
          'type': 'search',
          'command': 'rg calcularFrete lib/',
          'query': 'calcularFrete',
          'path': 'lib',
        },
      ]);
      b.command('c2', 'sed -n 1,80p lib/frete/tabela.dart', [
        readAction(
          '/w/lib/frete/tabela.dart',
          command: 'sed -n 1,80p lib/frete/tabela.dart',
        ),
      ]);
      b.command('c3', 'ls', [
        {'type': 'listFiles', 'command': 'ls', 'path': null},
      ]);
      final steps = replaySteps(b.items, root: '/w', agent: 'Codex');
      final reads = steps.where((s) => s.kind == ReplayKind.read).toList();
      expect(reads, hasLength(3));
      expect(reads.every((s) => s.lane == ReplayLane.read), isTrue);
      expect(replayStepLabel(reads[0]), 'Buscar "calcularFrete" lib');
      expect(reads[0].via, 'rg');
      expect(replayStepLabel(reads[1]), 'Ler tabela.dart 1–80');
      expect(reads[1].via, 'sed -n');
      expect(reads[1].filePath, '/w/lib/frete/tabela.dart');
      expect(replayStepLabel(reads[2]), startsWith('Listar'));
      // R11: de que comando a leitura veio.
      expect(
        replaySemanticValue(reads[1], 3),
        contains('Ler tabela.dart 1–80, pelo comando sed'),
      );
    });

    test('ação desconhecida ou misturada vira Rodar, com as leituras', () {
      final b = TimelineBuilder()..user('x');
      b.turn('t-1');
      b.command('c1', 'dart test', [
        {'type': 'unknown', 'command': 'dart test'},
      ]);
      b.command('c2', 'cat a.dart && dart test', [
        readAction('/w/a.dart'),
        {'type': 'unknown', 'command': 'dart test'},
      ], exit: 1);
      final runs = replaySteps(
        b.items,
        root: '/w',
      ).where((s) => s.kind == ReplayKind.run).toList();
      expect(runs, hasLength(2));
      expect(runs[0].reads, isEmpty);
      expect(replayStepLabel(runs[0]), 'Rodar dart test');
      expect(runs[1].reads.single.path, '/w/a.dart');
      expect(runs[1].outcome, ReplayOutcome.error);
    });

    test('um Editar por arquivo do fileChange, com o tipo e o +/−', () {
      final b = TimelineBuilder()..user('x');
      b.turn('t-1');
      b.patch('p1', [
        update('/w/a.dart', '@@ -1,2 +1,3 @@\n a\n-b\n+c\n+d\n'),
        {
          'path': '/w/n.dart',
          'kind': {'type': 'add'},
          'diff': 'x\ny\n',
        },
        {
          'path': '/w/v.dart',
          'kind': {'type': 'delete'},
          'diff': 'z\n',
        },
        update('/w/o.dart', '@@ -1 +1 @@\n-a\n+b\n', move: '/w/m.dart'),
      ]);
      final edits = replaySteps(
        b.items,
        root: '/w',
      ).where((s) => s.kind == ReplayKind.edit).toList();
      expect(edits.map((s) => s.changeLabel), [
        'alterado',
        'criado',
        'apagado',
        'movido',
      ]);
      expect(edits.map((s) => s.statsLabel), [
        '+2 −1',
        '+2 −0',
        '+0 −1',
        '+1 −1',
      ]);
      expect(replayStepLabel(edits[0]), 'Editar a.dart +2 −1');
      expect(replayStepLabel(edits[3]), 'Editar m.dart +1 −1 · movido');
    });

    test('MCP, busca na web, subagente, plano, raciocínio e turnos', () {
      final b = TimelineBuilder()..user('um');
      b.turn('t-1');
      b.tool('mcp__github__get_issue', {'n': 1});
      b.tool('WebSearch', {'query': 'frete'});
      b.tool('Agent', {'prompt': 'veja'});
      b.codexEvent(codexOtherItem({'id': 'pl', 'type': 'plan', 'text': '# P'}));
      b.codexEvent(
        codexTurnPlan({
          'turnId': 't-1',
          'plan': [
            {'step': 'ler', 'status': 'completed'},
            {'step': 'editar', 'status': 'pending'},
          ],
        })!,
      );
      b.think('vou ler antes');
      b.say('feito');
      b.endTurn();
      // Uma mensagem no meio do turno 2 não abre outro turno.
      b.user('dois');
      b.turn('t-2');
      b.user('e mais isto');
      b.command('c1', 'ls', [
        {'type': 'listFiles', 'command': 'ls'},
      ]);
      b.endTurn(status: 'interrupted');
      final steps = replaySteps(b.items, agent: 'Codex');
      expect(only(steps, ReplayKind.other).target, isNotEmpty);
      expect(only(steps, ReplayKind.web), isNotNull);
      expect(only(steps, ReplayKind.subagent), isNotNull);
      final plans = steps.where((s) => s.kind == ReplayKind.plan).toList();
      expect(plans, hasLength(2));
      expect(plans[1].tool!.other!.text, '✓ ler\n○ editar');
      expect(only(steps, ReplayKind.thinking).target, 'vou ler antes');
      expect(only(steps, ReplayKind.assistant).verb, 'Codex');
      final users = steps.where((s) => s.kind == ReplayKind.user).toList();
      expect(users.map((s) => s.turn), [1, 2, 2]);
      expect(users.map((s) => s.agentTurnId), ['t-1', 't-2', 't-2']);
      expect(only(steps, ReplayKind.read).agentTurnId, 't-2');
      final marks = steps
          .where((s) => s.mark == ReplayMarkKind.interrupted)
          .toList();
      expect(marks.single.mark!.isFlag, isTrue);
    });

    test('mensagem cujo processo morreu antes do turno fica sem turno', () {
      final b = TimelineBuilder()
        ..user('morreu')
        ..user('de novo');
      b.turn('t-9');
      final users = replaySteps(b.items)
          .where((s) => s.kind == ReplayKind.user)
          .toList();
      expect(users.map((s) => s.agentTurnId), [null, 't-9']);
      expect(users.map((s) => s.turn), [1, 2]);
    });

    test('turno que falhou e aprovação negada são marcas', () {
      final b = TimelineBuilder()..user('x');
      b.turn('t-1');
      b.patch('p1', [
        update('/w/a.dart', '@@ -1 +1 @@\n-a\n+b\n'),
      ], status: 'declined');
      b.endTurn(status: 'error_during_execution');
      final steps = replaySteps(b.items);
      expect(only(steps, ReplayKind.edit).outcome, ReplayOutcome.denied);
      expect(only(steps, ReplayKind.edit).isProblem, isTrue);
      expect(steps.last.mark, ReplayMarkKind.error);
    });

    test('a fixture da 0.170: as leituras e as edições gravadas', () {
      final b = TimelineBuilder()..user('edite');
      final lines = File('test/fixtures/codex/0.170/edicao-turno.jsonl')
          .readAsLinesSync()
          .where((l) => l.trim().isNotEmpty);
      for (final l in lines) {
        final msg = (jsonDecode(l) as Map)['msg'] as Map;
        final params = msg['params'];
        if (params is! Map) continue;
        if (msg['method'] == 'turn/started') {
          b.turn('${(params['turn'] as Map)['id']}');
        }
        if (msg['method'] != 'item/completed') continue;
        final item = (params['item'] as Map).cast<String, dynamic>();
        if (item['type'] == 'commandExecution') {
          b.codexEvent(codexCommand(item));
        } else if (item['type'] == 'fileChange') {
          b.patch('${item['id']}', [
            for (final c in item['changes'] as List)
              (c as Map).cast<String, dynamic>(),
          ]);
        }
      }
      final steps = replaySteps(b.items);
      final reads = steps.where((s) => s.kind == ReplayKind.read).toList();
      expect(reads, isNotEmpty);
      expect(
        reads.expand((s) => s.reads).map((r) => r.program).toSet(),
        containsAll(['sed', 'ls']),
      );
      expect(steps.where((s) => s.kind == ReplayKind.edit), isNotEmpty);
      expect(steps.map((s) => s.agentTurnId).toSet(), hasLength(1));
      expect(steps.first.agentTurnId, isNotNull);
    });
  });
}
