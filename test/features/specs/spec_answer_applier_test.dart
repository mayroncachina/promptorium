import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/specs/spec_action.dart';
import 'package:promptorium/features/specs/spec_answers.dart';
import 'package:promptorium/features/specs/spec_file.dart';

import '../../helpers/test_db.dart';
import '../project/project_planner_test.dart' show resultLine;
import '../sessions/session_test_utils.dart';
import 'spec_file_test.dart' show newFormatSpec;

/// SPEC-028 R10: "Atualizar requisitos e critérios com as respostas" runs
/// the Claude read-only and returns the final text by structured output;
/// nothing is written.
void main() {
  late FakeCli cli;
  late ProviderContainer c;
  late Workspace ws;
  late Directory tmp;
  late File file;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-answers-');
    file = File('${tmp.path}/SPEC-012-grupos.md')
      ..writeAsStringSync(newFormatSpec);
    cli = FakeCli();
    c = ProviderContainer(
      overrides: sessionOverrides(
        db: memoryDatabase(),
        cli: cli,
        notifier: FakeNotifier(),
      ),
    );
    await c.read(appSettingsProvider.notifier).load();
    ws = await c.read(workspacesRepoProvider).add(path: tmp.path, name: 'w');
  });
  tearDown(() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  String option(List<String> args, String flag) => args[args.indexOf(flag) + 1];

  final withDecisions = SpecDocument.parse(newFormatSpec)
      .withAnswers({'P1': 'Seleção na tabela'}, DateTime(2026, 11, 1));
  final answers = {
    const OpenQuestion(id: 'P1', text: 'Como adicionar?'): const Answer(
      option: AnswerOption.suggestion,
      text: 'Seleção na tabela',
    ),
    const OpenQuestion(id: 'P2', text: 'Lembrar?'): const Answer.deferred(),
  };

  test('read-only run with --json-schema; the text of the Claude comes back '
      'and the file does not change', () async {
    final run = c
        .read(specAnswerApplierProvider)
        .apply(ws, withDecisions, answers);
    await settle();
    final args = cli.args.single;
    expect(cli.cwds.single, tmp.path);
    expect(jsonDecode(option(args, '--json-schema')), applyAnswersSchema);
    expect(option(args, '--append-system-prompt'), applyAnswersPrompt);
    // No tool that writes.
    final tools = option(args, '--tools').split(',');
    expect(tools, isNot(contains('Write')));
    expect(tools, isNot(contains('Edit')));
    expect(args, isNot(contains('--allowedTools')));
    final prompt = '${cli.last.writtenJson.single['message']['content']}';
    expect(prompt, contains('- P1 · Como adicionar? → Seleção na tabela'));
    expect(prompt, isNot(contains('P2 · Lembrar?')));
    expect(prompt, contains(withDecisions.trimRight()));

    final updated = withDecisions.replaceFirst(
      '- R1 · Quando agrupar, o sistema deve mostrar o grupo',
      '- R1 · Quando agrupar, o sistema deve mostrar o grupo\n'
          '- R2 · Quando o usuário selecionar máquinas na tabela, o sistema '
          'deve oferecer "Agrupar"',
    );
    cli.last.emit(resultLine({'markdown': updated}));
    expect(await run, updated);
    expect(file.readAsStringSync(), newFormatSpec);
  });

  test('the id and the status of the spec are kept whatever the Claude '
      'returns; an empty answer fails', () {
    final changed = withDecisions.replaceFirst(
      'status: rascunho',
      'status: aprovada',
    );
    final out = answeredSpecText(withDecisions, {'markdown': changed});
    expect(SpecDocument.parse(out).status, SpecStatus.draft);
    expect(out, withDecisions);
    expect(
      () => answeredSpecText(withDecisions, {'markdown': ' '}),
      throwsA(isA<Exception>()),
    );
  });

  test('cancelling stops the run with SpecActionCancelled', () async {
    final cancel = Completer<void>();
    final run = c
        .read(specAnswerApplierProvider)
        .apply(ws, withDecisions, answers, cancelled: cancel.future);
    await settle();
    cancel.complete();
    await expectLater(run, throwsA(isA<SpecActionCancelled>()));
    expect(file.readAsStringSync(), newFormatSpec);
  });

  test(
    'the alternatives of a question: read-only run, at most three (SPEC-061)',
    () async {
      final run = c
          .read(specQuestionOptionsProvider)
          .forQuestion(
            ws,
            1,
            newFormatSpec,
            const OpenQuestion(id: 'P2', text: 'Lembrar?', suggestion: 'Não'),
          );
      await settle();
      final args = cli.args.single;
      expect(jsonDecode(option(args, '--json-schema')), questionOptionsSchema);
      final prompt = '${cli.last.writtenJson.single['message']['content']}';
      expect(prompt, contains('Pergunta P2: Lembrar?'));
      expect(prompt, contains('Sugestão da spec: Não'));
      expect(prompt, isNot(contains('Já mostradas')));
      cli.last.emit(
        resultLine({
          'options': [
            {'title': 'Lembrar', 'consequence': 'Guarda por usuário.'},
            {'title': 'Perguntar', 'consequence': 'Pede ao abrir.'},
            {'title': 'Esquecer', 'consequence': 'Volta ao padrão.'},
            {'title': 'Demais', 'consequence': ''},
          ],
        }),
      );
      final alts = await run;
      expect(alts.map((a) => a.title), ['Lembrar', 'Perguntar', 'Esquecer']);
      // Cached: no new run for the same question.
      await c
          .read(specQuestionOptionsProvider)
          .forQuestion(
            ws,
            1,
            newFormatSpec,
            const OpenQuestion(id: 'P2', text: 'Lembrar?', suggestion: 'Não'),
          );
      expect(cli.args, hasLength(1));
    },
  );
  test('SPEC-061 R4: "Outras sugestões" asks for a new set without the ones '
      'already shown, keeps the chosen one in its place and replaces the '
      'cache', () async {
    const q = OpenQuestion(id: 'P2', text: 'Lembrar?', suggestion: 'Não');
    final options = c.read(specQuestionOptionsProvider);
    final first = options.forQuestion(ws, 1, newFormatSpec, q);
    await settle();
    cli.last.emit(
      resultLine({
        'options': [
          {'title': 'Lembrar', 'consequence': 'Guarda por usuário.'},
          {'title': 'Perguntar', 'consequence': 'Pede ao abrir.'},
          {'title': 'Esquecer', 'consequence': 'Volta ao padrão.'},
        ],
      }),
    );
    final current = await first;

    // The second one was chosen: it stays, two new ones come.
    final more = options.more(
      ws,
      1,
      newFormatSpec,
      q,
      current: current,
      keep: 1,
    );
    await settle();
    expect(cli.args, hasLength(2));
    final prompt = '${cli.last.writtenJson.single['message']['content']}';
    expect(prompt, contains('Já mostradas (não repita nem reformule):'));
    expect(prompt, contains('- Lembrar: Guarda por usuário.'));
    expect(prompt, contains('- Esquecer: Volta ao padrão.'));
    expect(prompt, contains('Proponha só 2 respostas.'));
    cli.last.emit(
      resultLine({
        'options': [
          // A repeated one is dropped even when the Claude sends it.
          {'title': 'lembrar', 'consequence': 'De novo.'},
          {'title': 'Por workspace', 'consequence': 'Cada pasta lembra.'},
          {'title': 'Por sessão', 'consequence': 'Some ao fechar.'},
        ],
      }),
    );
    final next = await more;
    expect(next.map((a) => a.title), [
      'Por workspace',
      'Perguntar',
      'Por sessão',
    ]);
    // The next visit shows the new set, with no new run.
    expect(
      (await options.forQuestion(ws, 1, newFormatSpec, q)).map((a) => a.title),
      ['Por workspace', 'Perguntar', 'Por sessão'],
    );
    expect(cli.args, hasLength(2));

    // Nothing chosen: three new ones, none of the five shown before.
    final again = options.more(ws, 1, newFormatSpec, q, current: next);
    await settle();
    final p2 = '${cli.last.writtenJson.single['message']['content']}';
    for (final t in ['Lembrar', 'Esquecer', 'Por workspace', 'Por sessão']) {
      expect(p2, contains('- $t:'));
    }
    expect(p2, isNot(contains('Proponha só')));
    cli.last.emit(
      resultLine({
        'options': [
          {'title': 'Perguntar', 'consequence': 'Repetida.'},
        ],
      }),
    );
    // Only repeated ones: an error, and the cache stays as it was.
    await expectLater(again, throwsStateError);
    expect(
      (await options.forQuestion(ws, 1, newFormatSpec, q)).map((a) => a.title),
      ['Por workspace', 'Perguntar', 'Por sessão'],
    );
  });
}
