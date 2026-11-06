import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/claude_code_provider.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/specs/spec_draft.dart';
import 'package:promptorium/features/specs/spec_file.dart';
import 'package:promptorium/features/specs/spec_planner.dart';

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';

/// `result` line of a `--json-schema` run carrying [output].
String resultLine(Object output, {double cost = 0.01}) => jsonEncode({
  'type': 'result',
  'subtype': 'success',
  'is_error': false,
  'total_cost_usd': cost,
  'result': jsonEncode(output),
  'structured_output': output,
});

/// One answer of the planner.
Map<String, Object?> plannerOutput({
  String reply = 'Por qual canal sai o aviso?',
  String title = 'Lembretes de consulta',
  String objective = 'Avisar o paciente antes da consulta.',
  List<String> requirements = const [
    'Quando uma consulta for marcada, o sistema deve agendar um lembrete.',
  ],
  List<String> outOfScope = const [],
  List<String> dependsOn = const [],
  List<Map<String, String>> openQuestions = const [
    {'text': 'Por qual canal?', 'suggestion': ''},
  ],
  List<String> suggestions = const ['Só e-mail', 'Decidir depois'],
}) => {
  'reply': reply,
  'draft': {
    'title': title,
    'objective': objective,
    'requirements': requirements,
    'outOfScope': outOfScope,
    'dependsOn': dependsOn,
    'openQuestions': openQuestions,
  },
  'suggestions': suggestions,
};

void main() {
  late FakeCli cli;
  late ProviderContainer c;
  late Workspace ws;
  late Directory tmp;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-spec-planner-');
    cli = FakeCli();
    c = ProviderContainer(
      overrides: sessionOverrides(
        db: memoryDatabase(),
        cli: cli,
        notifier: FakeNotifier(),
      ),
    );
    c.listen(specPlannerProvider, (_, _) {});
    await c.read(appSettingsProvider.notifier).load();
    ws = await c.read(workspacesRepoProvider).add(path: tmp.path, name: 'r');
  });
  tearDown(() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  SpecPlanner planner() => c.read(specPlannerProvider.notifier);

  Future<(SpecDraft, SpecDraftData)> load() async {
    final row = (await c.read(specDraftsRepoProvider).get(ws.id))!;
    return (row, SpecDraftData.decode(row.data));
  }

  String option(List<String> args, String flag) => args[args.indexOf(flag) + 1];

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 5));

  /// Waits for the process number [n] and answers it.
  Future<void> answer(int n, String line) async {
    for (var i = 0; i < 200 && cli.processes.length < n; i++) {
      await settle();
    }
    cli.processes[n - 1].emit(line);
  }

  test('R4: read-only run with the schema; the first turn opens the session, '
      'the next resumes it; the draft and the messages are stored', () async {
    final first = planner().begin(ws, 'Quero avisar o paciente');
    await answer(1, resultLine(plannerOutput()));
    await first;
    var args = cli.args.single;
    expect(cli.cwds.single, tmp.path);
    expect(args, containsAllInOrder(['--permission-mode', 'default']));
    expect(jsonDecode(option(args, '--json-schema')), specPlannerSchema);
    expect(option(args, '--append-system-prompt'), specPlannerSystemPrompt);
    expect(option(args, '--max-budget-usd'), '0.5');
    expect(
      args.sublist(args.indexOf('--disallowedTools') + 1),
      ClaudeCodeProvider.readOnlyDisallowedTools,
    );
    final sid = option(args, '--session-id');
    var (row, data) = await load();
    expect(row.plannerSessionId, sid);
    expect(row.costUsd, closeTo(0.01, 1e-9));
    expect(data.title, 'Lembretes de consulta');
    expect(data.requirements, hasLength(1));
    expect(data.newRequirements, data.requirements);
    expect(data.openQuestions.single.text, 'Por qual canal?');
    expect(data.messages.last.suggestions, ['Só e-mail', 'Decidir depois']);
    expect(
      data.messages.last.note,
      'Rascunho atualizado · Título · Objetivo · Requisitos +1 · Perguntas 1',
    );

    final second = planner().send(ws, 'Só e-mail');
    await answer(
      2,
      resultLine(
        plannerOutput(
          requirements: [
            'Quando uma consulta for marcada, o sistema deve agendar um '
                'lembrete.',
            'Quando faltarem 24 h, o sistema deve enviar um e-mail.',
          ],
        ),
      ),
    );
    await second;
    args = cli.args.last;
    expect(option(args, '--resume'), sid);
    expect(args, isNot(contains('--session-id')));
    (row, data) = await load();
    // R5: "novo" only on what this answer added.
    expect(data.newRequirements, [
      'Quando faltarem 24 h, o sistema deve enviar um e-mail.',
    ]);
    expect(data.messages.last.note, 'Rascunho atualizado · Requisitos +1');
  });

  test('R4: what stays unanswered goes to Perguntas em aberto, and an answer '
      'that changes nothing has no note', () async {
    final first = planner().begin(ws, 'Ideia');
    await answer(1, resultLine(plannerOutput()));
    await first;
    final second = planner().send(ws, 'Anotado');
    await answer(2, resultLine(plannerOutput(reply: 'Anotei.')));
    await second;
    final (_, data) = await load();
    expect(data.openQuestions.single.text, 'Por qual canal?');
    expect(data.messages.last.text, 'Anotei.');
    expect(data.messages.last.note, isNull);
  });

  test('R5: the title typed by hand stays, even when typed during a turn, and '
      'the planner is told about it', () async {
    final first = planner().begin(ws, 'Ideia');
    await answer(1, resultLine(plannerOutput()));
    await first;

    final second = planner().send(ws, 'Mais');
    await settle();
    await planner().editTitle(ws, 'Avisos');
    await answer(2, resultLine(plannerOutput(title: 'Outro título')));
    await second;
    expect((await load()).$2.title, 'Avisos');

    final third = planner().send(ws, 'E mais');
    await answer(3, resultLine(plannerOutput(title: 'Terceiro')));
    await third;
    expect((await load()).$2.title, 'Avisos');
    expect(
      cli.last.writtenJson.single['message']['content'],
      contains('Título definido pela pessoa (mantenha): Avisos'),
    );
  });

  test('R5: only specs of the workspace become dependencies; the first turn '
      'lists them', () async {
    await c
        .read(specsRepoProvider)
        .insert(
          workspaceId: ws.id,
          code: 'SPEC-005',
          title: 'Agenda de consultas',
          path: 'specs/SPEC-005-agenda.md',
          status: SpecStatus.approved,
        );
    final first = planner().begin(ws, 'Ideia');
    await answer(
      1,
      resultLine(plannerOutput(dependsOn: ['SPEC-005', 'SPEC-099'])),
    );
    await first;
    expect((await load()).$2.dependsOn, ['SPEC-005']);
    expect(
      cli.last.writtenJson.single['message']['content'],
      contains('- SPEC-005 · Agenda de consultas'),
    );
  });

  test('R10: past 6 requirements the rest goes to Fora do escopo as a next '
      'spec; an id written by the planner is removed', () async {
    final first = planner().begin(ws, 'Ideia');
    await answer(
      1,
      resultLine(
        plannerOutput(
          requirements: [
            for (var i = 1; i <= 8; i++) 'R$i · O sistema deve fazer $i.',
          ],
          outOfScope: ['SMS'],
        ),
      ),
    );
    await first;
    final (_, data) = await load();
    expect(data.requirements, hasLength(SpecDraftData.maxRequirements));
    expect(data.requirements.first, 'O sistema deve fazer 1.');
    expect(data.outOfScope, [
      'SMS',
      'O sistema deve fazer 7: sugestão de próxima spec.',
      'O sistema deve fazer 8: sugestão de próxima spec.',
    ]);
  });

  test('R9: a failure keeps the message unanswered; "Tentar de novo" sends it '
      'again without repeating it; a new message goes along with it', () async {
    final first = planner().begin(ws, 'Ideia');
    await answer(1, resultLine(plannerOutput()));
    await first;

    cli.failStart = true;
    await planner().send(ws, 'Só e-mail');
    var (_, data) = await load();
    expect(data.unanswered, ['Só e-mail']);
    expect(c.read(specPlannerProvider), isEmpty);
    expect(data.requirements, hasLength(1));

    cli.failStart = false;
    final retry = planner().retry(ws);
    await answer(2, resultLine(plannerOutput(reply: 'Certo.')));
    await retry;
    (_, data) = await load();
    expect(cli.last.writtenJson.single['message']['content'], 'Só e-mail');
    expect(data.unanswered, isEmpty);
    expect(data.messages.where((m) => m.text == 'Só e-mail'), hasLength(1));

    cli.failStart = true;
    await planner().send(ws, 'Um');
    cli.failStart = false;
    final next = planner().send(ws, 'Dois');
    await answer(3, resultLine(plannerOutput()));
    await next;
    expect(cli.last.writtenJson.single['message']['content'], 'Um\n\nDois');
  });

  test('a draft discarded during a turn stays discarded', () async {
    final first = planner().begin(ws, 'Ideia');
    for (var i = 0; i < 200 && cli.processes.isEmpty; i++) {
      await settle();
    }
    await planner().discard(ws);
    cli.last.emit(resultLine(plannerOutput()));
    await first;
    expect(await c.read(specDraftsRepoProvider).get(ws.id), isNull);
  });

  test('R6: the spec has what the draft has; the rest stays as the template; '
      'the draft is removed', () async {
    final first = planner().begin(ws, 'Ideia');
    await answer(
      1,
      resultLine(
        plannerOutput(
          openQuestions: [
            {'text': 'Cancela pelo e-mail?', 'suggestion': 'Não nesta spec.'},
          ],
        ),
      ),
    );
    await first;
    final spec = await planner().create(ws, title: 'Lembretes');
    final text = File('${tmp.path}/${spec.path}').readAsStringSync();
    final doc = SpecDocument.parse(text);
    expect(doc.status, SpecStatus.draft);
    expect(doc.title, 'Lembretes');
    expect(doc.requirements.single.id, 'R1');
    expect(text, contains('Avisar o paciente antes da consulta.'));
    expect(text, contains('- P1 · Cancela pelo e-mail?'));
    expect(text, contains('  - Sugestão: Não nesta spec.'));
    expect(doc.openQuestionsScan.questions.single.id, 'P1');
    expect(text, contains('<!-- O que esta spec não faz'));
    expect(doc.design, isNull);
    expect(await c.read(specDraftsRepoProvider).get(ws.id), isNull);
  });

  test('R6: a failure to write keeps the draft and the same code', () async {
    final first = planner().begin(ws, 'Ideia');
    await answer(1, resultLine(plannerOutput()));
    await first;
    final folder = File('${tmp.path}/specs')..writeAsStringSync('');
    await expectLater(
      planner().create(ws, title: 'Lembretes'),
      throwsA(isA<FileSystemException>()),
    );
    expect((await load()).$2.requirements, hasLength(1));
    folder.deleteSync();
    final spec = await planner().create(ws, title: 'Lembretes');
    expect(spec.code, 'SPEC-001');
  });

  test('R6: the empty template did not change', () {
    final doc = SpecDocument.parse(
      newSpecMarkdown(code: 'SPEC-001', title: 'Vazia'),
    );
    expect(doc.status, SpecStatus.draft);
    expect(doc.hasDependsOn, isFalse);
    expect(doc.design, isNull);
    final text = newSpecMarkdown(code: 'SPEC-001', title: 'Vazia');
    expect(text, contains('Descreva o problema e o resultado esperado.'));
    expect(text, contains('- R1 ·\n'));
    expect(text, endsWith('("Responder perguntas"). -->\n'));
  });

  test('R8: survives a restart: the data round-trips and the date reads '
      'naturally', () {
    final at = DateTime(2026, 11, 5, 18, 20);
    final data = const SpecDraftData(
      title: 'Lembretes',
      titleEdited: true,
      requirements: ['a', 'b'],
      newRequirements: ['b'],
      openQuestions: [DraftQuestion('p', suggestion: 's')],
    ).withUserMessage('oi');
    final back = SpecDraftData.decode(data.encode());
    expect(back.title, 'Lembretes');
    expect(back.titleEdited, isTrue);
    expect(back.newRequirements, ['b']);
    expect(back.openQuestions.single.suggestion, 's');
    // A message with no answer after a restart is a failure to retry (R9).
    expect(back.unanswered, ['oi']);
    expect(
      draftSummary(back, at, DateTime(2026, 11, 6, 9)),
      'Lembretes · 2 requisitos · ontem às 18:20',
    );
    expect(draftDateLabel(at, DateTime(2026, 11, 5, 23)), 'hoje às 18:20');
    expect(draftDateLabel(at, DateTime(2026, 11, 9)), '05/11 às 18:20');
    expect(SpecDraftData.decode('nada').messages, isEmpty);
  });
}
