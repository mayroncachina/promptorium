import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_cli.dart';
import 'package:promptorium/core/claude/run_extensions.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/providers/claude_code_provider.dart';
import 'package:promptorium/core/providers/structured_run.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/instructions/interview_controller.dart';
import 'package:promptorium/features/sessions/session_manager.dart'
    show sessionIdGeneratorProvider;

import '../../core/codex/fake_codex.dart';
import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart' show FakeCli, until;

/// `result` line of a `--json-schema` run carrying [output].
String resultLine(Object output) => jsonEncode({
  'type': 'result',
  'subtype': 'success',
  'is_error': false,
  'total_cost_usd': 0.01,
  'usage': {'input_tokens': 1000, 'output_tokens': 200},
  'result': jsonEncode(output),
  'structured_output': output,
});

Map<String, Object?> question(
  String id,
  String text, {
  List<String> options = const ['Sim', 'Não'],
  String recommended = 'Sim',
  List<String> requires = const [],
  bool onlyClaude = false,
}) => {
  'id': id,
  'title': text,
  'text': text,
  'reason': 'Porque sim.',
  'options': options,
  'recommended': recommended,
  'requires': requires,
  'onlyClaude': onlyClaude,
  'target': 'AGENTS.md › Regras',
};

Map<String, Object?> round({
  List<Map<String, Object?>> questions = const [],
  List<Map<String, Object?>> findings = const [],
  String draft = '## Regras',
  String summary = '',
  bool done = false,
}) => {
  'findings': findings,
  'questions': questions,
  'draft': draft,
  'summary': summary,
  'done': done,
};

final round1 = round(
  findings: [
    {'text': 'Logger em', 'path': 'lib/core/log.dart'},
  ],
  questions: [
    question('Q1', 'Como rodar os testes?'),
    question('Q2', 'Antes do commit?', options: const []),
    question('Q3', 'Idioma dos textos?', recommended: 'Não'),
    // Depends on a question of this round: waits for the next (R13).
    question('Q4', 'Teste em tela nova?', requires: const ['Q1']),
  ],
  draft: '## Comandos\n- Testes: `flutter test`.',
);

final round2 = round(
  questions: [
    question('Q4', 'Teste em tela nova?', requires: const ['Q1']),
    question('Q5', 'O que não mexer?', onlyClaude: true),
  ],
  draft: '## Comandos\n- Testes: `flutter test`.\n\n## Regras\n- PT-BR.',
);

String git(String cwd, List<String> args) {
  final r = Process.runSync('git', args, workingDirectory: cwd);
  if (r.exitCode != 0) throw StateError('git ${args.join(' ')}: ${r.stderr}');
  return '${r.stdout}';
}

void main() {
  late Directory tmp;
  late String repo;
  late FakeCli cli;
  late List<FakeCodex> servers;
  late FakeCodexStore store;
  late ProviderContainer c;
  late Workspace ws;
  var ids = 0;

  ProviderContainer container() => ProviderContainer(
    overrides: [
      databaseOverride(AppDatabase(NativeDatabase(File('${tmp.path}/db')))),
      claudeProcessStarterProvider.overrideWithValue(cli.start),
      runSettingsDirProvider.overrideWithValue('${tmp.path}/run'),
      sessionIdGeneratorProvider.overrideWithValue(() => 'sid-${++ids}'),
      codexProcessStarterProvider.overrideWithValue((
        exe,
        args, {
        workingDirectory,
        environment,
      }) async {
        final s = FakeCodex(threadId: 'th-${servers.length}')..store = store;
        servers.add(s);
        return s;
      }),
    ],
  );

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    tmp = Directory.systemTemp.createTempSync('promptorium-interview-');
    repo = '${tmp.path}/repo';
    Directory(repo).createSync();
    File('$repo/AGENTS.md').writeAsStringSync('# app\n\n## Regras\n- PT-BR.\n');
    File('$repo/CLAUDE.md').writeAsStringSync('@AGENTS.md\n');
    git(repo, ['init', '-q']);
    git(repo, ['add', '.']);
    git(repo, [
      '-c',
      'user.name=t',
      '-c',
      'user.email=t@t',
      'commit',
      '-qm',
      'init',
    ]);
    cli = FakeCli();
    servers = [];
    store = FakeCodexStore();
    ids = 0;
    c = container();
    await c.read(appSettingsProvider.notifier).load();
    ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'app');
  });

  tearDown(() async {
    c.dispose();
    for (final s in servers) {
      await s.finish();
    }
    tmp.deleteSync(recursive: true);
  });

  InterviewController ctl([ProviderContainer? on]) =>
      (on ?? c).read(instructionInterviewProvider(ws.id).notifier);
  InterviewState st([ProviderContainer? on]) =>
      (on ?? c).read(instructionInterviewProvider(ws.id));

  String option(List<String> args, String flag) => args[args.indexOf(flag) + 1];

  /// Waits for the Claude process number [n] and answers [output].
  Future<void> answerClaude(int n, Object output) async {
    await until(() async => cli.processes.length >= n);
    cli.processes[n - 1].emit(resultLine(output));
  }

  /// Waits for Codex turn number [n], checks the read-only thread and
  /// answers [output]. Returns the thread request and the turn.
  Future<(Map<String, dynamic>, Map<String, dynamic>)> answerCodex(
    int n,
    Object output,
  ) async {
    await until(
      () async =>
          servers.length >= n &&
          servers[n - 1].writtenJson.any((m) => m['method'] == 'turn/start'),
    );
    final s = servers[n - 1];
    final thread = s.writtenJson.lastWhere(
      (m) => m['method'] == 'thread/start' || m['method'] == 'thread/resume',
    );
    expect(thread['params']['sandbox'], 'read-only');
    expect(thread['params']['approvalPolicy'], 'never');
    final turn = s.writtenJson.lastWhere((m) => m['method'] == 'turn/start');
    expect(codexSchemaProblems(turn['params']['outputSchema']), isEmpty);
    final tid = '${turn['params']['threadId']}';
    s.emit(
      jsonEncode({
        'method': 'item/completed',
        'params': {
          'threadId': tid,
          'item': {
            'id': 'msg-$n',
            'type': 'agentMessage',
            'text': jsonEncode(output),
            'phase': 'final_answer',
          },
        },
      }),
    );
    store.complete(tid);
    return (thread, turn);
  }

  String promptOf(Map<String, dynamic> turn) =>
      (turn['params']['input'] as List).map((i) => i['text']).join('\n');

  /// Prompt the Claude process [n] received.
  String claudePrompt(int n) => jsonEncode(cli.processes[n - 1].writtenJson);

  void expectClean() => expect(
    git(repo, ['status', '--porcelain']),
    isEmpty,
    reason: 'a entrevista nunca grava arquivo',
  );

  group('Claude Code', () {
    test('R13–R15, R17: read-only rounds with numbered questions and a '
        'recommendation; the next round only after the answers', () async {
      final started = ctl().start(ws);
      await answerClaude(1, round1);
      await started;
      final args = cli.args.single;
      expect(cli.cwds.single, repo);
      expect(args, containsAllInOrder(['--permission-mode', 'default']));
      expect(option(args, '--session-id'), 'sid-1');
      expect(jsonDecode(option(args, '--json-schema')), interviewRoundSchema);
      expect(option(args, '--append-system-prompt'), interviewSystemPrompt);
      expect(
        args.sublist(args.indexOf('--disallowedTools') + 1),
        ClaudeCodeProvider.readOnlyDisallowedTools,
      );
      expect(
        option(args, '--tools'),
        ClaudeCodeProvider.readOnlyTools.join(','),
      );
      expect(claudePrompt(1), contains('A próxima pergunta nova é Q1.'));

      var s = st();
      expect(s.provider, 'claude');
      expect(s.tokens, 1200);
      final r1 = s.data.current!;
      expect(r1.questions.map((q) => q.id), ['Q1', 'Q2', 'Q3']);
      expect(r1.questions.every((q) => q.recommended.isNotEmpty), isTrue);
      expect(s.data.findings.single.path, 'lib/core/log.dart');
      expect(s.data.draft, contains('flutter test'));

      // Incomplete: nothing is sent.
      await ctl().answer(
        'Q1',
        const InterviewAnswer(InterviewAnswerKind.option, 'Não'),
      );
      await ctl().sendRound(ws);
      expect(cli.processes, hasLength(1));

      await ctl().answer('Q2', const InterviewAnswer.skipped());
      await ctl().acceptRemainingRecommended();
      expect(cli.processes, hasLength(1), reason: 'preenche sem enviar');
      s = st();
      expect(
        s.data.current!.answers['Q3'],
        const InterviewAnswer(InterviewAnswerKind.recommended, 'Não'),
      );
      expect(s.data.current!.answers['Q1']!.value, 'Não');
      final row = await c.read(instructionInterviewsRepoProvider).get(ws.id);
      expect(row!.data, contains('"Q3"'), reason: 'guardado a cada resposta');

      final sent = ctl().sendRound(ws);
      await answerClaude(2, round2);
      await sent;
      final args2 = cli.args.last;
      expect(option(args2, '--resume'), 'sid-1');
      expect(args2, isNot(contains('--session-id')));
      final p2 = claudePrompt(2);
      expect(p2, contains('Q1 · Como rodar os testes?: Não'));
      expect(p2, contains('Q2 · Antes do commit?: pulada (não vira regra)'));
      expect(p2, contains('aceita a recomendada: Não'));
      // Q4 waited for the Q1 (R13): it is asked again now.
      expect(p2, contains('A próxima pergunta nova é Q4.'));
      s = st();
      expect(s.data.rounds, hasLength(2));
      expect(s.data.current!.questions.map((q) => q.id), ['Q4', 'Q5']);
      expect(s.data.current!.questions.last.onlyClaude, isTrue);
      expect(s.data.previousDraft, isNot(s.data.draft));
      expectClean();
    });

    test('R16: without questions, the summary waits for confirmation; the '
        'proposal comes by trecho, with the files as they are', () async {
      final started = ctl().start(ws);
      await answerClaude(
        1,
        round(done: true, summary: '- Testes com flutter test.'),
      );
      await started;
      expect(st().data.stage, InterviewStage.summary);
      expect(st().data.summary, '- Testes com flutter test.');
      expect(cli.processes, hasLength(1), reason: 'confirma antes');

      final out = ctl().propose(ws);
      await answerClaude(2, {
        'summary': 'Uma regra nova.',
        'hunks': [
          {
            'file': 'AGENTS.md',
            'section': 'Regras',
            'oldText': '- PT-BR.',
            'newText': '- PT-BR.\n- Tela nova leva teste.',
            'questions': ['q1'],
          },
          {
            'file': 'lib/x.dart',
            'section': '',
            'oldText': '',
            'newText': 'x',
            'questions': <String>[],
          },
        ],
      });
      final proposal = (await out)!;
      final args = cli.args.last;
      expect(
        jsonDecode(option(args, '--json-schema')),
        interviewProposalSchema,
      );
      expect(option(args, '--resume'), 'sid-1');
      expect(claudePrompt(2), contains('## Regras\\n- PT-BR.'));
      expect(proposal.provider, 'claude');
      expect(proposal.summary, 'Uma regra nova.');
      final h = proposal.hunks.single;
      expect(
        (h.file, h.section, h.oldText),
        ('AGENTS.md', 'Regras', '- PT-BR.'),
      );
      expect(h.questions, ['Q1']);
      expect(st().data.stage, InterviewStage.proposal);
      final row = await c.read(instructionInterviewsRepoProvider).get(ws.id);
      expect(
        InterviewData.decode(row!.data).proposal!.hunks.single.newText,
        contains('Tela nova'),
      );
      expectClean();
    });

    test('R16: "Encerrar e ver a proposta" ends before; what stayed open '
        'does not become a rule', () async {
      final started = ctl().start(ws);
      await answerClaude(1, round1);
      await started;
      await ctl().answer(
        'Q1',
        const InterviewAnswer(InterviewAnswerKind.text, 'flutter test'),
      );
      final out = ctl().finishEarly(ws);
      await answerClaude(2, {'summary': '', 'hunks': <Object>[]});
      final proposal = await out;
      expect(proposal!.endedEarly, isTrue);
      final p = claudePrompt(2);
      expect(p, contains('Q1 · Como rodar os testes?: flutter test'));
      expect(p, contains('As perguntas Q2, Q3 ficaram abertas e não viram'));
      expect(proposal.questions['Q1'], 'Como rodar os testes?');
      expectClean();
    });

    test('R18: closing the app keeps the answers; continuing uses the same '
        'thread and re-reads changed files', () async {
      final started = ctl().start(ws);
      await answerClaude(1, round1);
      await started;
      await ctl().answer('Q1', const InterviewAnswer.skipped());
      await ctl().pause();
      c.dispose();

      File('$repo/AGENTS.md').writeAsStringSync('# app\n\nmudou\n');
      c = container();
      await c.read(appSettingsProvider.notifier).load();
      await ctl().load(ws);
      var s = st();
      expect(s.paused, isTrue);
      expect(s.filesChanged, isTrue);
      expect(s.data.current!.answers['Q1']!.skipped, isTrue);
      expect(s.data.current!.questions, hasLength(3));

      await ctl().resume(ws);
      expect(st().paused, isFalse);
      expect(cli.processes, hasLength(1), reason: 'a rodada está aberta');
      await ctl().acceptRemainingRecommended();
      final sent = ctl().sendRound(ws);
      await answerClaude(2, round2);
      await sent;
      expect(option(cli.args.last, '--resume'), 'sid-1');
      expect(claudePrompt(2), contains('releia o AGENTS.md'));
      expect(st().filesChanged, isFalse);
      git(repo, ['checkout', 'AGENTS.md']);
      expectClean();
    });

    test('R18: when the old thread is gone, another starts with the stored '
        'answers, on the same provider', () async {
      final started = ctl().start(ws);
      await answerClaude(1, round1);
      await started;
      await ctl().answer('Q2', const InterviewAnswer.skipped());
      await ctl().acceptRemainingRecommended();
      c.dispose();
      c = container();
      await c.read(appSettingsProvider.notifier).load();
      // The kind moved to the Codex meanwhile: the interview stays (R17).
      await c
          .read(appSettingsProvider.notifier)
          .set(ProviderKind.planner.settingKey, 'codex');
      await ctl().load(ws);
      final sent = ctl().sendRound(ws);
      await until(() async => cli.processes.length >= 2);
      expect(option(cli.args[1], '--resume'), 'sid-1');
      cli.processes[1].emitErr('No conversation found with session ID: sid-1');
      await cli.processes[1].finish(1);
      await answerClaude(3, round2);
      await sent;
      final args = cli.args[2];
      expect(option(args, '--session-id'), 'sid-2');
      final p = claudePrompt(3);
      expect(p, contains('começou em outra conversa'));
      expect(p, contains('Q2 · Antes do commit?: pulada'));
      expect(p, contains('Q1 · Como rodar os testes?'));
      expect(servers, isEmpty);
      final row = await c.read(instructionInterviewsRepoProvider).get(ws.id);
      expect((row!.threadId, row.provider), ('sid-2', 'claude'));
      expect(st().data.rounds, hasLength(2));
      expectClean();
    });
  });

  group('Codex', () {
    setUp(() async {
      await c
          .read(appSettingsProvider.notifier)
          .set(ProviderKind.planner.settingKey, 'codex');
    });

    test('R13, R17: rounds on the Codex, read-only thread, resumed on the '
        'next round', () async {
      final started = ctl().start(ws);
      final (thread, turn) = await answerCodex(1, round1);
      await started;
      expect(thread['method'], 'thread/start');
      expect(cli.processes, isEmpty);
      expect(promptOf(turn), contains('Comece a entrevista'));
      expect(st().provider, 'codex');
      expect(st().data.current!.questions, hasLength(3));
      await ctl().acceptRemainingRecommended();
      // The kind moves to the Claude Code: the interview stays (R17).
      await c
          .read(appSettingsProvider.notifier)
          .set(ProviderKind.planner.settingKey, 'claude');
      final sent = ctl().sendRound(ws);
      final (thread2, turn2) = await answerCodex(2, round2);
      await sent;
      expect(thread2['method'], 'thread/resume');
      expect(thread2['params']['threadId'], 'th-0');
      expect(promptOf(turn2), contains('aceita a recomendada'));
      expect(cli.processes, isEmpty);
      expect(st().data.rounds, hasLength(2));
      expectClean();
    });

    test('R18: without the old thread, a new one starts with the stored '
        'answers', () async {
      final started = ctl().start(ws);
      await answerCodex(1, round1);
      await started;
      await ctl().acceptRemainingRecommended();
      store.threads.remove('th-0');
      final sent = ctl().sendRound(ws);
      final (thread, turn) = await answerCodex(3, round2);
      await sent;
      expect(store.calls, isNot(contains('resume th-0')));
      expect(thread['method'], 'thread/start');
      expect(promptOf(turn), contains('começou em outra conversa'));
      expect(promptOf(turn), contains('Q1 · Como rodar os testes?'));
      final row = await c.read(instructionInterviewsRepoProvider).get(ws.id);
      expect((row!.threadId, row.provider), ('sid-2', 'codex'));
      expectClean();
    });
  });

  test('parseInterviewRound numbers repeated ids and keeps a question whose '
      'prerequisite was answered before', () {
    final before = InterviewData(
      rounds: [
        InterviewRound(
          number: 1,
          questions: [
            InterviewQuestion.fromJson(question('Q1', 'a'))!,
            InterviewQuestion.fromJson(question('Q2', 'b'))!,
          ],
          answers: const {'Q1': InterviewAnswer.skipped()},
          sent: true,
        ),
      ],
    );
    final r = parseInterviewRound(
      round(
        questions: [
          question('Q1', 'repetida'),
          question('Q9', 'depende da Q1', requires: const ['Q1']),
          question('', 'sem id'),
        ],
      ),
      before,
    );
    expect(r.number, 2);
    expect(r.questions.map((q) => q.id), ['Q3', 'Q9', 'Q10']);
    expect(r.questions[1].requires, ['Q1']);
  });
}
