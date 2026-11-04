import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/readonly_run.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/board/step_decision.dart';
import 'package:promptorium/features/board/step_gate.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/features/specs/spec_service.dart';

import '../../helpers/test_db.dart';
import '../project/project_planner_test.dart' show resultLine;
import '../sessions/session_test_utils.dart';
import '../specs/spec_file_test.dart' show newFormatSpec;

Map<String, Object?> option(
  String title, {
  String kind = 'answer',
  String consequence = 'Segue.',
  String change = '',
  List<Object?> split = const [],
  bool suggested = false,
}) => {
  'title': title,
  'kind': kind,
  'consequence': consequence,
  'change': change,
  'split': split,
  'suggested': suggested,
};

Map<String, Object?> output({
  String summary = 'O agente perguntou qual tabela usar.',
  List<Map<String, Object?>>? options,
}) => {
  'summary': summary,
  'decisions': [
    {
      'question': 'Qual tabela?',
      'options': options ?? [option('Usar a nova'), option('Usar a antiga')],
    },
  ],
};

GateReport failedGate({int lines = 60}) => GateReport(
  at: DateTime(2026, 11, 4),
  attempt: 2,
  checks: [
    const GateCheck(name: 'commit', ok: true),
    GateCheck(
      name: 'testes',
      ok: false,
      command: 'flutter test test/a_test.dart',
      output: [for (var i = 1; i <= lines; i++) 'linha $i'].join('\n'),
    ),
  ],
);

void main() {
  group('parseStepDecisions', () {
    List<StepDecisionOption> parse(List<Object?> options) =>
        parseStepDecisions({
          'summary': ' Parou. ',
          'decisions': [
            {'question': ' Qual? ', 'options': options},
          ],
        }).decisions.single.options;

    test('reads the summary, the question and every field', () {
      final r = parseStepDecisions(
        output(
          options: [
            option(
              ' Mudar o requisito ',
              kind: 'amend',
              consequence: ' O R1 muda. ',
              change: ' Usar a tabela nova. ',
            ),
            option('Separar', kind: 'split', split: [' Migrar ', 'Ler']),
            option('Depois', kind: 'defer'),
          ],
        ),
      );
      expect(r.error, isNull);
      expect(r.summary, 'O agente perguntou qual tabela usar.');
      expect(r.decisions.single.question, 'Qual tabela?');
      final [amend, split, defer] = r.decisions.single.options;
      expect(amend.title, 'Mudar o requisito');
      expect(amend.kind, StepDecisionKind.amend);
      expect(amend.consequence, 'O R1 muda.');
      expect(amend.change, 'Usar a tabela nova.');
      expect(split.kind, StepDecisionKind.split);
      expect(split.split, ['Migrar', 'Ler']);
      expect(defer.kind, StepDecisionKind.defer);
    });

    test('drops empty titles', () {
      final options = parse([
        option('  '),
        {'kind': 'answer'},
        'not an option',
        option('Fica'),
      ]);
      expect(options.map((o) => o.title), ['Fica']);
    });

    test('keeps at most 4 options', () {
      final options = parse([for (var i = 1; i <= 6; i++) option('O$i')]);
      expect(options.map((o) => o.title), ['O1', 'O2', 'O3', 'O4']);
    });

    test('keeps only the first suggested, and it comes first (R5)', () {
      final options = parse([
        option('A'),
        option('B', suggested: true),
        option('C', suggested: true),
      ]);
      expect(options.map((o) => o.title), ['B', 'A', 'C']);
      expect(options.map((o) => o.suggested), [true, false, false]);
    });

    test('the limit never cuts the suggested option', () {
      final options = parse([
        for (var i = 1; i <= 4; i++) option('O$i'),
        option('Quinta', suggested: true),
      ]);
      expect(options.map((o) => o.title), ['Quinta', 'O1', 'O2', 'O3']);
    });

    test('an empty title does not take the suggestion', () {
      final options = parse([
        option('', suggested: true),
        option('A'),
        option('B', suggested: true),
      ]);
      expect(options.map((o) => (o.title, o.suggested)), [
        ('B', true),
        ('A', false),
      ]);
    });

    test('a split has 2 to 4 sub-steps; other kinds carry none (R16)', () {
      final options = parse([
        option('Um só', kind: 'split', split: ['A', ' ']),
        option('Muitos', kind: 'split', split: ['A', 'B', 'C', 'D', 'E']),
        option('Responder', split: ['A', 'B'], change: 'Muda'),
      ]);
      expect(options.map((o) => o.title), ['Muitos', 'Responder']);
      expect(options.first.split, ['A', 'B', 'C', 'D']);
      expect(options.last.split, isEmpty);
      expect(options.last.change, isEmpty);
    });

    test('an unknown kind is dropped', () {
      expect(
        parse([option('Inventado', kind: 'other'), option('Fica')])
            .map((o) => o.title),
        ['Fica'],
      );
    });

    test('nothing usable is an error, not an empty modal', () {
      for (final data in [
        null,
        'texto',
        <String, Object?>{},
        {'summary': 'Parou.', 'decisions': <Object?>[]},
        output(options: [option(' ')]),
      ]) {
        final r = parseStepDecisions(data);
        expect(r.error, 'a IA não devolveu opções');
        expect(r.decisions, isEmpty);
      }
    });
  });

  group('cache key', () {
    test('session, step and last message each make a new key', () {
      final base = stepDecisionKey('s1', 'R1', 'Qual tabela?');
      expect(stepDecisionKey('s1', 'R1', 'Qual tabela?'), base);
      expect(stepDecisionKey('s2', 'R1', 'Qual tabela?'), isNot(base));
      expect(stepDecisionKey('s1', 'R2', 'Qual tabela?'), isNot(base));
      expect(stepDecisionKey('s1', 'R1', 'Outra?'), isNot(base));
      expect(base.$3, isNot(contains('Qual')));
    });
  });

  group('context', () {
    test('the last agent message ignores subagents and other items', () {
      expect(lastAgentMessage([UserItem('Oi')]), '');
      expect(
        lastAgentMessage([
          AssistantTextItem(' Qual tabela? '),
          AssistantTextItem('do subagente', parentToolUseId: 't1'),
          NoticeItem('Concluído'),
        ]),
        'Qual tabela?',
      );
    });

    test('keeps the last 12 thousand characters of the timeline', () {
      final context = stepDecisionContext([
        AssistantTextItem('começo${'x' * 20000}'),
        UserItem('fim da conversa'),
      ]);
      expect(context, isNot(contains('começo')));
      expect(context, contains('Pessoa: fim da conversa'));
      final body = context
          .replaceFirst('<sessao>\n', '')
          .replaceFirst('\n</sessao>', '');
      expect(body, hasLength(stepDecisionTimelineChars));
    });

    test('shows each kind of item; a long tool result keeps its end', () {
      final tool =
          ToolItem(
              id: 't1',
              name: 'Bash',
              input: const {'command': 'flutter test'},
            )
            ..result = '${'x' * 2000}\nSome tests failed.'
            ..isError = true;
      final context = stepDecisionContext([
        UserItem('Faça o R1'),
        ThinkingItem('pensando escondido'),
        tool,
        AssistantTextItem('Qual tabela?'),
        NoticeItem('Falhou · orçamento esgotado'),
      ]);
      expect(context, contains('Pessoa: Faça o R1'));
      expect(context, isNot(contains('pensando escondido')));
      expect(context, contains('Ferramenta: Bash flutter test (erro)'));
      expect(context, contains('Some tests failed.'));
      expect(context.length, lessThan(1000));
      expect(context, contains('Agente: Qual tabela?'));
      expect(context, contains('Aviso: Falhou · orçamento esgotado'));
    });

    test('a failed gate adds the command and the last 40 lines', () {
      final context = stepDecisionContext(const [], gate: failedGate());
      expect(context, contains('<verificacao>'));
      expect(context, contains('A verificação falhou: testes.'));
      expect(context, contains('testes (`flutter test test/a_test.dart`)'));
      expect(context, contains('linha 21\n'));
      expect(context, contains('linha 60'));
      expect(context, isNot(contains('linha 20\n')));
      expect(context, isNot(contains('commit')));
    });

    test('a gate that passed adds nothing', () {
      final ok = GateReport(
        at: DateTime(2026),
        checks: const [GateCheck(name: 'testes', ok: true, output: 'tudo')],
      );
      expect(
        stepDecisionContext(const [], gate: ok),
        isNot(contains('<verificacao>')),
      );
    });

    test('the input has the spec, the requirement and the session; the gate '
        'only when the step stopped on it', () {
      String input(StepStatus status, GateReport? gate) => stepDecisionInput(
        specText: '# Spec\n\n',
        step: StepView(id: 'R1', text: 'Agrupar', status: status, gate: gate),
        items: [AssistantTextItem('Qual tabela?')],
      );
      final stopped = input(StepStatus.needsInput, failedGate());
      expect(stopped, contains('<spec>\n# Spec\n</spec>'));
      expect(stopped, contains('Etapa R1: Agrupar'));
      expect(stopped, contains('Agente: Qual tabela?'));
      expect(stopped, contains('<verificacao>'));
      expect(
        input(StepStatus.needsInput, null),
        isNot(contains('<verificacao>')),
      );
      expect(
        input(StepStatus.done, failedGate()),
        isNot(contains('<verificacao>')),
      );
    });

    test('the prompt: split separates the work, a new behaviour is amend, '
        'and the options of an exhausted gate (R14, R16)', () {
      expect(stepDecisionPrompt, contains('Dividir separa o trabalho'));
      expect(stepDecisionPrompt, contains('de 2 a 4 subetapas'));
      expect(
        stepDecisionPrompt,
        contains('Mudar o comportamento pedido é Ajustar o requisito'),
      );
      expect(stepDecisionPrompt, contains('não proponha Dividir'));
      expect(stepDecisionPrompt, contains('"Corrigir o teste"'));
      expect(stepDecisionPrompt, contains('"Marcar o critério como manual"'));
      expect(stepDecisionPrompt, contains('do tipo\namend'));
    });
  });

  test('a failure reason is short and reads after the colon', () {
    expect(
      stepDecisionReason(
        const PlannerException('O planner não respondeu em 5 minutos.'),
      ),
      'o planner não respondeu em 5 minutos',
    );
    final long = stepDecisionReason(
      PlannerException('Falha ao iniciar claude: ${'x' * 500}\nstack'),
    );
    expect(long.length, lessThanOrEqualTo(121));
    expect(long, startsWith('falha ao iniciar claude'));
    expect(long, endsWith('…'));
    expect(
      stepDecisionReason(StateError('boom')),
      'erro inesperado ao preparar as opções',
    );
    expect(
      stepDecisionReason(const SpecException('Caminho de spec inválido: x')),
      'caminho de spec inválido: x',
    );
  });

  group('StepDecisionOptions', () {
    late FakeCli cli;
    late ProviderContainer c;
    late Directory tmp;
    late File file;
    late Workspace ws;
    late Spec spec;

    StepView step({
      String id = 'R1',
      String? session = 's1',
      GateReport? gate,
    }) => StepView(
      id: id,
      text: 'Agrupar',
      status: StepStatus.needsInput,
      sessionId: session,
      gate: gate,
    );

    StepDecisionOptions options() =>
        c.read(stepDecisionOptionsProvider.notifier);

    StepDecisionStatus status([String id = 'R1']) =>
        c.read(stepDecisionProvider((spec.id, id))).status;

    Future<void> say(String text, {String session = 's1'}) => c
        .read(sessionsRepoProvider)
        .appendEvent(
          session,
          type: 'assistant',
          json: jsonEncode({
            'type': 'assistant',
            'message': {
              'content': [
                {'type': 'text', 'text': text},
              ],
            },
          }),
        );

    Future<Session> addSession(String id) => c
        .read(sessionsRepoProvider)
        .insert(
          id: id,
          workspaceId: ws.id,
          worktreePath: tmp.path,
          branch: 'b',
          model: 'm',
          specId: spec.id,
        );

    String prompt(FakeProcess p) =>
        '${p.writtenJson.single['message']['content']}';

    String flag(List<String> args, String name) => args[args.indexOf(name) + 1];

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('promptorium-decision-');
      file = File('${tmp.path}/specs/SPEC-012-grupos.md')
        ..createSync(recursive: true)
        ..writeAsStringSync(newFormatSpec);
      cli = FakeCli();
      c = ProviderContainer(
        retry: (_, _) => null,
        overrides: sessionOverrides(
          db: memoryDatabase(),
          cli: cli,
          notifier: FakeNotifier(),
        ),
      );
      await c.read(appSettingsProvider.notifier).load();
      ws = await c.read(workspacesRepoProvider).add(path: tmp.path, name: 'w');
      spec = await c
          .read(specsRepoProvider)
          .insert(
            workspaceId: ws.id,
            code: 'SPEC-012',
            title: 'Grupos',
            path: 'specs/SPEC-012-grupos.md',
          );
      await addSession('s1');
      await say('Qual tabela?');
    });

    tearDown(() {
      c.dispose();
      tmp.deleteSync(recursive: true);
    });

    test('nothing runs until the modal asks; then a read-only run with '
        '--json-schema, loading until it answers', () async {
      await settle();
      expect(cli.args, isEmpty);

      final run = options().generate(spec, step());
      await settle();
      expect(status(), StepDecisionStatus.loading);
      final args = cli.args.single;
      expect(cli.cwds.single, tmp.path);
      expect(jsonDecode(flag(args, '--json-schema')), stepDecisionSchema);
      expect(flag(args, '--append-system-prompt'), stepDecisionPrompt);
      final tools = flag(args, '--tools').split(',');
      expect(tools, isNot(contains('Write')));
      expect(tools, isNot(contains('Edit')));
      expect(prompt(cli.last), contains(newFormatSpec.trimRight()));
      expect(prompt(cli.last), contains('Etapa R1: Agrupar'));
      expect(prompt(cli.last), contains('Agente: Qual tabela?'));
      expect(prompt(cli.last), isNot(contains('<verificacao>')));

      cli.last.emit(resultLine(output()));
      final r = await run;
      expect(r.summary, 'O agente perguntou qual tabela usar.');
      expect(status(), StepDecisionStatus.ready);
      final state = c.read(stepDecisionProvider((spec.id, 'R1')));
      expect(state.result!.decisions.single.options, hasLength(2));
    });

    test('the schema limits a decision to 4 options of the 4 kinds', () {
      final decisions =
          (stepDecisionSchema['properties']! as Map)['decisions'] as Map;
      final items = decisions['items'] as Map;
      final opts = (items['properties'] as Map)['options'] as Map;
      expect(opts['maxItems'], 4);
      expect(opts['minItems'], 2);
      final fields = (opts['items'] as Map)['properties'] as Map;
      expect((fields['kind'] as Map)['enum'], [
        'answer',
        'amend',
        'split',
        'defer',
      ]);
      expect(fields.keys, containsAll(['change', 'split', 'suggested']));
    });

    test(
      'with the gate exhausted, the prompt carries the GateReport',
      () async {
        final run = options().generate(spec, step(gate: failedGate()));
        await settle();
        final text = prompt(cli.last);
        expect(text, contains('<verificacao>'));
        expect(text, contains('`flutter test test/a_test.dart`'));
        expect(text, contains('linha 60'));
        expect(text, isNot(contains('linha 20\n')));
        cli.last.emit(resultLine(output()));
        await run;
      },
    );

    test('a step without a session still gets options', () async {
      final run = options().generate(spec, step(session: null));
      await settle();
      cli.last.emit(resultLine(output()));
      expect((await run).error, isNull);
    });

    test('runs in the worktree of the spec when it exists', () async {
      final wt = Directory('${tmp.path}/wt')..createSync();
      await c
          .read(specsRepoProvider)
          .setWorktree(spec.id, path: wt.path, branch: 'b');
      final withTree = (await c.read(specsRepoProvider).getById(spec.id))!;
      final run = options().generate(withTree, step());
      await settle();
      expect(cli.cwds.single, wt.path);
      cli.last.emit(resultLine(output()));
      await run;
    });

    group('cache', () {
      Future<void> answer(
        Future<StepDecisionResult> run,
        String summary,
      ) async {
        await settle();
        cli.last.emit(resultLine(output(summary: summary)));
        await run;
      }

      test('reopening the same stop does not generate again', () async {
        await answer(options().generate(spec, step()), 'Primeira');
        options().cancel(spec.id, 'R1');
        await settle();
        expect(c.read(stepDecisionOptionsProvider), isEmpty);

        final again = await options().generate(spec, step());
        await settle();
        expect(again.summary, 'Primeira');
        expect(status(), StepDecisionStatus.ready);
        expect(cli.args, hasLength(1));
      });

      test('a new last message generates again', () async {
        await answer(options().generate(spec, step()), 'Primeira');
        options().cancel(spec.id, 'R1');
        await say('E a coluna?');

        final run = options().generate(spec, step());
        await settle();
        expect(cli.args, hasLength(2));
        expect(status(), StepDecisionStatus.loading);
        expect(prompt(cli.last), contains('Agente: E a coluna?'));
        cli.last.emit(resultLine(output(summary: 'Segunda')));
        expect((await run).summary, 'Segunda');
      });

      test('another step of the same session has its own entry', () async {
        await answer(options().generate(spec, step()), 'Do R1');
        await answer(options().generate(spec, step(id: 'R2')), 'Do R2');
        expect(cli.args, hasLength(2));
        final r1 = c.read(stepDecisionProvider((spec.id, 'R1')));
        expect(r1.result!.summary, 'Do R1');
      });
    });

    group('one run per spec', () {
      test('asking twice for the same step joins the run', () async {
        final a = options().generate(spec, step());
        final b = options().generate(spec, step());
        await settle();
        final c2 = options().generate(spec, step());
        await settle();
        expect(cli.args, hasLength(1));
        cli.last.emit(resultLine(output()));
        expect((await b).summary, (await a).summary);
        expect((await c2).summary, (await a).summary);
      });

      test('another step of the spec stops the run and only starts once the '
          'process is gone', () async {
        final first = options().generate(spec, step());
        await settle();
        final old = cli.last..exitOnSigterm = false;

        final second = options().generate(spec, step(id: 'R2'));
        await settle();
        expect(old.signals, isNotEmpty);
        expect(cli.args, hasLength(1));

        await old.finish();
        expect((await first).error, 'geração cancelada');
        await settle();
        expect(cli.args, hasLength(2));
        cli.last.emit(resultLine(output(summary: 'Do R2')));
        expect((await second).summary, 'Do R2');
        expect(status('R2'), StepDecisionStatus.ready);
        // The stopped modal forgets its step when it is disposed.
        options().cancel(spec.id, 'R1');
        await settle();
        expect(c.read(stepDecisionOptionsProvider).keys, [(spec.id, 'R2')]);
      });

      test('different specs run at the same time', () async {
        final other = await c
            .read(specsRepoProvider)
            .insert(
              workspaceId: ws.id,
              code: 'SPEC-013',
              title: 'Outra',
              path: 'specs/SPEC-012-grupos.md',
            );
        final a = options().generate(spec, step());
        final b = options().generate(other, step());
        await settle();
        expect(cli.args, hasLength(2));
        for (final p in cli.processes) {
          p.emit(resultLine(output()));
        }
        await Future.wait([a, b]);
      });
    });

    group('cancel', () {
      test('closing the modal stops the process and forgets the run', () async {
        final run = options().generate(spec, step());
        await settle();
        options().cancel(spec.id, 'R1');
        expect((await run).error, 'geração cancelada');
        await settle();
        expect(cli.last.signals, isNotEmpty);
        expect(c.read(stepDecisionOptionsProvider), isEmpty);

        // Nothing was cached: the next visit generates.
        final next = options().generate(spec, step());
        await settle();
        expect(cli.args, hasLength(2));
        cli.last.emit(resultLine(output()));
        expect((await next).error, isNull);
      });

      test('cancelling before the run starts does not start it', () async {
        final run = options().generate(spec, step());
        options().cancel(spec.id, 'R1');
        expect((await run).error, 'geração cancelada');
        await settle();
        expect(cli.args, isEmpty);
      });

      test('a modal that is closing does not stop the one that replaced '
          'it', () async {
        final closing = options().generate(spec, step());
        await settle();
        final open = options().generate(spec, step());
        options().cancel(spec.id, 'R1');
        await settle();
        expect(cli.last.signals, isEmpty);
        cli.last.emit(resultLine(output()));
        await closing;
        await open;
        expect(status(), StepDecisionStatus.ready);

        options().cancel(spec.id, 'R1');
        await settle();
        expect(c.read(stepDecisionOptionsProvider), isEmpty);
      });

      test('cancelling another step leaves the run alone', () async {
        final run = options().generate(spec, step());
        await settle();
        options().cancel(spec.id, 'R2');
        await settle();
        expect(cli.last.signals, isEmpty);
        cli.last.emit(resultLine(output()));
        expect((await run).error, isNull);
      });

      test('disposing the container stops the run', () async {
        final run = options().generate(spec, step());
        await settle();
        final process = cli.last;
        c.dispose();
        expect((await run).error, 'geração cancelada');
        expect(process.signals, isNotEmpty);
      });
    });

    group('errors become a result', () {
      test('a run that cannot start; "Tentar de novo" generates', () async {
        cli.failStart = true;
        final r = await options().generate(spec, step());
        expect(r.error, startsWith('falha ao iniciar'));
        expect(status(), StepDecisionStatus.failed);
        expect(c.read(stepDecisionOptionsProvider), isA<Map<Object, Object>>());

        cli.failStart = false;
        final retry = options().retry(spec, step());
        expect(status(), StepDecisionStatus.loading);
        await settle();
        cli.last.emit(resultLine(output()));
        expect((await retry).error, isNull);
        expect(status(), StepDecisionStatus.ready);

        // "Tentar de novo" needs no extra cancel.
        options().cancel(spec.id, 'R1');
        await settle();
        expect(c.read(stepDecisionOptionsProvider), isEmpty);
      });

      test('a run that ends in error is not cached', () async {
        final run = options().generate(spec, step());
        await settle();
        cli.last.emit(
          jsonEncode({
            'type': 'result',
            'subtype': 'error_max_budget_usd',
            'is_error': true,
          }),
        );
        final r = await run;
        expect(r.error, 'o planner terminou com erro (error_max_budget_usd)');
        expect(status(), StepDecisionStatus.failed);

        final again = options().generate(spec, step());
        await settle();
        expect(cli.args, hasLength(2));
        cli.last.emit(resultLine(output()));
        await again;
      });

      test('an answer without options fails and is not cached', () async {
        final run = options().generate(spec, step());
        await settle();
        cli.last.emit(resultLine({'summary': 'Parou.', 'decisions': []}));
        expect((await run).error, 'a IA não devolveu opções');
        expect(status(), StepDecisionStatus.failed);

        final again = options().generate(spec, step());
        await settle();
        expect(cli.args, hasLength(2));
        cli.last.emit(resultLine(output()));
        await again;
      });

      test('a process that dies before answering', () async {
        final run = options().generate(spec, step());
        await settle();
        await cli.last.finish(1);
        expect((await run).error, contains('encerrou antes de responder'));
        expect(status(), StepDecisionStatus.failed);
      });

      test('a spec file that is gone starts no run', () async {
        file.deleteSync();
        final r = await options().generate(spec, step());
        expect(r.error, 'o arquivo da spec não existe mais');
        expect(cli.args, isEmpty);
      });
    });

    testWidgets('generate in initState and cancel in dispose do not write '
        'the provider while the tree builds', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: _Probe(spec: spec, step: step()),
        ),
      );
      await tester.runAsync(settle);
      expect(tester.takeException(), isNull);

      // The scope stays: Riverpod only checks writes while it is mounted.
      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const SizedBox()),
      );
      await tester.runAsync(settle);
      expect(tester.takeException(), isNull);
      expect(c.read(stepDecisionOptionsProvider), isEmpty);
    });
  });
}

/// The life cycle the modal will use.
class _Probe extends ConsumerStatefulWidget {
  const _Probe({required this.spec, required this.step});

  final Spec spec;
  final StepView step;

  @override
  ConsumerState<_Probe> createState() => _ProbeState();
}

class _ProbeState extends ConsumerState<_Probe> {
  late final StepDecisionOptions _options;

  @override
  void initState() {
    super.initState();
    _options = ref.read(stepDecisionOptionsProvider.notifier);
    _options.generate(widget.spec, widget.step);
  }

  @override
  void dispose() {
    _options.cancel(widget.spec.id, widget.step.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(stepDecisionProvider((widget.spec.id, widget.step.id)));
    return const SizedBox();
  }
}
