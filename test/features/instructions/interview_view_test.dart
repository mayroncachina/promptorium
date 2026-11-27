import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_cli.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/instructions/interview_controller.dart';
import 'package:promptorium/features/instructions/interview_view.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/theme/tokens.dart';

import '../../helpers/test_db.dart';
import '../../ui/preferences_test.dart' show unmount;
import '../board/canvas_fixture.dart' show loadAppFonts;
import '../sessions/session_test_utils.dart' show FakeCli;
import 'instructions_view_test.dart' show settle, waitFor;

InterviewQuestion q(
  String id,
  String title,
  String text, {
  List<String> options = const [],
  String recommended = '',
  String reason = '',
  bool onlyClaude = false,
}) => InterviewQuestion(
  id: id,
  title: title,
  text: text,
  reason: reason,
  options: options,
  recommended: recommended,
  onlyClaude: onlyClaude,
  target: 'AGENTS.md › Regras',
);

/// The round 2 of the mock `4-entrevista.png`.
final mockData = InterviewData(
  rounds: [
    InterviewRound(
      number: 1,
      findings: const [
        InterviewFinding(text: 'Logger em', path: 'lib/core/log.dart'),
        InterviewFinding(text: 'CI roda a suíte inteira:', path: 'ci.yml'),
      ],
      questions: [
        q('Q1', 'Como rodar os testes', 'Como rodar os testes?'),
        q('Q2', 'Antes do commit', 'O que rodar antes do commit?'),
        q('Q3', 'Idioma dos textos', 'Em que idioma ficam os textos?'),
      ],
      answers: const {
        'Q1': InterviewAnswer(InterviewAnswerKind.text, 'flutter test'),
        'Q2': InterviewAnswer(InterviewAnswerKind.text, 'flutter analyze'),
        'Q3': InterviewAnswer(InterviewAnswerKind.option, 'PT-BR'),
      },
      draft: '## Comandos\n- Testes: `flutter test`.',
      sent: true,
    ),
    InterviewRound(
      number: 2,
      questions: [
        q(
          'Q4',
          'Teste em tela nova',
          'Toda tela nova precisa de teste de widget, ou só as que têm '
              'formulário?',
          reason:
              '8 das 11 telas têm teste. As 3 sem teste são só de leitura, e '
              'nenhuma regra diz se é de propósito.',
          options: const ['Toda tela nova', 'Só telas com formulário'],
          recommended: 'Toda tela nova',
        ),
        q(
          'Q5',
          'O que não mexer',
          'O que o agente nunca pode editar?',
          reason: 'Os gerados *.g.dart e a pasta packages/legado.',
          recommended: 'os *.g.dart e packages/legado',
        ),
        q(
          'Q6',
          'Modo plan no Claude',
          'O Claude deve começar em modo plan em toda mudança?',
          reason: 'As outras são pequenas.',
          recommended: 'não, só em mudança de banco',
          onlyClaude: true,
        ),
      ],
      draft:
          '## Comandos\n- Testes: `flutter test test/<area>`; a suíte inteira '
          'só no CI.\n- Antes de commitar: `flutter analyze`.\n\n## Regras\n'
          '- Textos em português do Brasil.',
    ),
  ],
);

void main() {
  test('the AI Markdown: backticks become code spans, list items bullets', () {
    final spans = interviewCodeSpans('Rode `flutter test` antes');
    expect(
      [for (final x in spans) (x as TextSpan).text],
      ['Rode ', 'flutter test', ' antes'],
    );
    expect((spans[1] as TextSpan).style?.fontFamily, isNotNull);
    expect(interviewCodeSpans('um ` solto'), hasLength(1));
    expect(interviewBullets('- a\n- b\nc'), '• a\n• b\nc');
  });

  late Directory tmp;
  late FakeCli cli;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('interview-view-');
    File('${tmp.path}/AGENTS.md').writeAsStringSync('# vitrine\n');
    cli = FakeCli();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Finder key(String k) => find.byKey(ValueKey(k));

  Future<(ProviderContainer, AppDatabase, Workspace)> pump(
    WidgetTester tester, {
    InterviewData? data,
    DateTime? pausedAt,
    String? filesHash,
    bool card = false,
    void Function(InstructionProposal)? onProposal,
    VoidCallback? onPaused,
  }) async {
    tester.view.physicalSize = const Size(1366, 680);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = memoryDatabase();
    final c = ProviderContainer(
      overrides: [
        databaseOverride(db),
        claudeProcessStarterProvider.overrideWithValue(cli.start),
      ],
    );
    late Workspace ws;
    await tester.runAsync(() async {
      await loadAppFonts();
      ws = await c.read(workspacesRepoProvider).add(path: tmp.path, name: 'v');
      await c.read(appSettingsProvider.notifier).load();
      if (data != null) {
        final repo = c.read(instructionInterviewsRepoProvider);
        await repo.start(ws.id, provider: 'claude', data: data.encode());
        await repo.update(
          ws.id,
          InstructionInterviewsCompanion(
            model: const Value('Sonnet'),
            tokens: const Value(18400),
            threadId: const Value('sid-1'),
            pausedAt: Value(pausedAt),
            filesHash: Value(
              filesHash ?? (await readInterviewFiles(tmp.path)).hash,
            ),
          ),
        );
      }
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            backgroundColor: AppColors.backgroundSolid,
            body: card
                ? Align(
                    alignment: Alignment.topRight,
                    child: SizedBox(
                      width: 300,
                      child: InterviewResumeCard(workspace: ws),
                    ),
                  )
                : InstructionsInterviewView(
                    workspace: ws,
                    onProposalReady: onProposal ?? (_) {},
                    onPaused: onPaused,
                  ),
          ),
        ),
      ),
    );
    await settle(tester);
    addTearDown(() => unmount(tester, c));
    return (c, db, ws);
  }

  testWidgets('R13–R15, R17: the round with its questions, findings, draft '
      'and the provider bar; "Aceitar as recomendadas que faltam" fills '
      'without sending', (tester) async {
    final (c, _, ws) = await pump(tester, data: mockData);
    await waitFor(tester, key('interview-q-Q4'));
    expect(find.text('rodada 2'), findsOneWidget);
    expect(find.text('Claude Code · Sonnet'), findsOneWidget);
    expect(find.text('somente leitura · 18 mil tokens'), findsOneWidget);
    expect(find.text('recomendada'), findsOneWidget);
    expect(find.text('só do Claude'), findsOneWidget);
    expect(find.text('ACHADO NO CÓDIGO · 2'), findsOneWidget);
    expect(find.text('3 respondidas'), findsOneWidget);
    expect(find.textContaining('Recomendo: os *.g.dart'), findsOneWidget);
    expect(find.text('Faltam 3 respostas'), findsOneWidget);

    // An option, then a written answer.
    await tester.tap(key('interview-q-Q4-opt-0'));
    await settle(tester);
    expect(key('interview-answered'), findsOneWidget);
    expect(find.text('COM A Q4 RESPONDIDA'), findsOneWidget);
    await tester.tap(key('interview-q-Q5-write'));
    await settle(tester);
    await tester.enterText(
      key('interview-q-Q5-text'),
      'os .g.dart sim; o legado só com spec aprovada',
    );
    await settle(tester);
    expect(find.text('Falta 1 resposta'), findsOneWidget);

    final png = Platform.environment['ENTREVISTA_PNG'];
    if (png != null) await shot(tester, png);

    await tester.tap(key('interview-accept-all'));
    await settle(tester);
    expect(cli.processes, isEmpty, reason: 'preenche sem enviar');
    final s = c.read(instructionInterviewProvider(ws.id));
    final answers = s.data.current!.answers;
    expect(answers['Q4']!.kind, InterviewAnswerKind.recommended);
    expect(
      answers['Q5']!.value,
      'os .g.dart sim; o legado só com spec aprovada',
    );
    expect(answers['Q6']!.kind, InterviewAnswerKind.recommended);
    expect(find.textContaining('Faltam'), findsNothing);
    late InstructionInterview? row;
    await tester.runAsync(
      () async =>
          row = await c.read(instructionInterviewsRepoProvider).get(ws.id),
    );
    expect(InterviewData.decode(row!.data).current!.complete, isTrue);
  });

  testWidgets('R18: "Pausar" keeps it and shows the paused card', (
    tester,
  ) async {
    var paused = 0;
    final (c, _, ws) = await pump(
      tester,
      data: mockData,
      onPaused: () => paused++,
    );
    await waitFor(tester, key('interview-pause'));
    await tester.tap(key('interview-pause'));
    await settle(tester);
    expect(paused, 1);
    expect(key('interview-paused'), findsOneWidget);
    late InstructionInterview? row;
    await tester.runAsync(
      () async =>
          row = await c.read(instructionInterviewsRepoProvider).get(ws.id),
    );
    expect(row!.pausedAt, isNotNull);
  });

  testWidgets('R18: the paused card says the progress and warns that the '
      'files changed (mock 6)', (tester) async {
    await pump(
      tester,
      data: mockData,
      pausedAt: DateTime.now(),
      filesHash: 'antes',
      card: true,
    );
    await waitFor(tester, key('interview-paused'));
    expect(find.text('Entrevista pausada'), findsOneWidget);
    expect(
      find.textContaining('3 perguntas respondidas e 3 abertas'),
      findsOneWidget,
    );
    expect(key('interview-paused-files-changed'), findsOneWidget);
    expect(find.text('Continua no Claude Code, onde começou.'), findsOneWidget);
    final png = Platform.environment['RETOMAR_PNG'];
    if (png != null) await shot(tester, png);
  });

  testWidgets('a finished interview hands its proposal to onProposalReady', (
    tester,
  ) async {
    InstructionProposal? got;
    const proposal = InstructionProposal(
      provider: 'claude',
      hunks: [
        InstructionProposalHunk(
          file: 'AGENTS.md',
          section: 'Regras',
          oldText: '',
          newText: '- Tela nova leva teste de widget.',
          questions: ['Q4'],
        ),
      ],
    );
    await pump(
      tester,
      data: mockData.copyWith(
        stage: InterviewStage.proposal,
        proposal: proposal,
      ),
      onProposal: (p) => got = p,
    );
    await waitFor(tester, key('interview-open-proposal'));
    await tester.tap(key('interview-open-proposal'));
    await tester.pump();
    expect(got!.hunks.single.questions, ['Q4']);
  });

  testWidgets('R16: the summary asks for confirmation', (tester) async {
    await pump(
      tester,
      data: mockData.copyWith(
        stage: InterviewStage.summary,
        summary: '- Testes com flutter test.',
      ),
    );
    await waitFor(tester, key('interview-summary'));
    expect(find.text('• Testes com flutter test.'), findsOneWidget);
    expect(key('interview-confirm'), findsOneWidget);
    expect(cli.processes, isEmpty);
  });
}

Future<void> shot(WidgetTester tester, String file) async {
  await tester.runAsync(() async {
    final rb = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    final img = await rb.toImage();
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    File(file).writeAsBytesSync(data!.buffer.asUint8List());
  });
}
