import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/instructions/interview_controller.dart';
import 'package:promptorium/features/instructions/proposal_view.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/theme/tokens.dart';

import '../../helpers/test_db.dart';
import '../../ui/preferences_test.dart' show unmount;
import '../board/canvas_fixture.dart' show loadAppFonts;
import 'instructions_view_test.dart' show settle, waitFor;
import 'interview_view_test.dart' show shot;
import 'proposal_apply_test.dart' show agents, claude, gitOut, repo;

/// The proposal of the mock `5-proposta.png`.
const mockProposal = InstructionProposal(
  provider: 'claude',
  model: 'Sonnet',
  questions: {
    'Q1': 'Como rodar os testes',
    'Q4': 'Teste em tela nova',
    'Q5': 'O que não mexer',
    'Q6': 'Modo plan no Claude',
    'Q2': 'Antes do commit',
    'Q3': 'Idioma',
  },
  hunks: [
    InstructionProposalHunk(
      file: 'AGENTS.md',
      section: 'Comandos',
      oldText: '- Testes: `flutter test`.',
      newText:
          '- Testes: `flutter test test/<area>`; a suíte inteira só no CI.',
      questions: ['Q1'],
    ),
    InstructionProposalHunk(
      file: 'AGENTS.md',
      section: 'Regras',
      oldText: '',
      newText: '- Tela nova leva teste de widget.',
      questions: ['Q4'],
    ),
    InstructionProposalHunk(
      file: 'AGENTS.md',
      section: 'Não mexer',
      oldText: '',
      newText:
          '## Não mexer\n'
          '- Não edite `lib/data/db/*.g.dart`: é gerado pelo build_runner.\n'
          '- Não mude `packages/legado` sem uma spec aprovada.',
      questions: ['Q5'],
    ),
    InstructionProposalHunk(
      file: 'CLAUDE.md',
      section: 'Só para o Claude Code',
      oldText: '',
      newText: '- Em mudança de banco, comece no modo plan.',
      questions: ['Q6'],
    ),
  ],
);

void main() {
  late Directory tmp;
  late String root;

  setUp(() => tmp = Directory.systemTemp.createTempSync('proposal-view-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Finder key(String k) => find.byKey(ValueKey(k));

  String text(String k) {
    String of(Widget w) => w is Text
        ? (w.data ?? w.textSpan!.toPlainText())
        : (w as RichText).text.toPlainText();
    final w = key(k).evaluate().single.widget;
    if (w is Text || w is RichText) return of(w);
    return of(
      find
          .descendant(of: key(k), matching: find.byType(Text))
          .evaluate()
          .first
          .widget,
    );
  }

  Future<(ProviderContainer, Workspace)> pump(
    WidgetTester tester, {
    InstructionProposal proposal = mockProposal,
    Future<void> Function(String root)? prepare,
    VoidCallback? onDone,
    VoidCallback? onBack,
  }) async {
    tester.view.physicalSize = const Size(1366, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = memoryDatabase();
    final c = ProviderContainer(overrides: [databaseOverride(db)]);
    late Workspace ws;
    await tester.runAsync(() async {
      await loadAppFonts();
      root = await repo(tmp);
      Directory('$root/lib/data/db').createSync(recursive: true);
      File('$root/lib/data/db/app.g.dart').writeAsStringSync('');
      Directory('$root/packages/legado').createSync(recursive: true);
      await prepare?.call(root);
      ws = await c.read(workspacesRepoProvider).add(path: root, name: 'v');
      final data = InterviewData(
        stage: InterviewStage.proposal,
        proposal: proposal,
      );
      await c
          .read(instructionInterviewsRepoProvider)
          .start(ws.id, provider: 'claude', data: data.encode());
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            backgroundColor: AppColors.backgroundSolid,
            body: InstructionsProposalView(
              workspace: ws,
              proposal: proposal,
              onDone: onDone ?? () {},
              onBackToInterview: onBack,
            ),
          ),
        ),
      ),
    );
    await waitFor(tester, key('proposal-commit'));
    await waitFor(tester, key('proposal-after-AGENTS.md'));
    await settle(tester);
    addTearDown(() => unmount(tester, c));
    return (c, ws);
  }

  testWidgets('R19–R21: the trechos as in the mock, deciding each one, the '
      'panel "Depois de aplicar", the check of the paths and the commit '
      'box with the branch', (tester) async {
    var back = 0;
    await pump(tester, onBack: () => back++);
    expect(find.text('Proposta da IA'), findsOneWidget);
    expect(find.text('6 perguntas'), findsOneWidget);
    expect(find.text('Claude Code · Sonnet'), findsOneWidget);
    expect(text('proposal-counts'), '4 trechos · 4 a decidir');
    expect(find.text('AGENTS.md › Comandos'), findsOneWidget);
    expect(find.text('Q5'), findsOneWidget);
    expect(key('proposal-new-section'), findsOneWidget);
    expect(text('proposal-apply'), 'Aplicar 0 trechos');

    await tester.tap(key('proposal-hunk-0-accept'));
    await tester.tap(key('proposal-hunk-1-accept'));
    await tester.tap(key('proposal-hunk-3-reject'));
    await tester.pump();
    expect(
      text('proposal-counts'),
      '4 trechos · 2 aceitos, 1 recusado, 1 a decidir',
    );
    expect(find.text('aceito'), findsNWidgets(2));
    expect(find.text('recusado'), findsOneWidget);
    expect(find.text('Aplicar 2 trechos'), findsOneWidget);
    // "Depois de aplicar".
    expect(text('proposal-after-AGENTS.md-lines'), '+2 −1 linhas');
    expect(text('proposal-after-CLAUDE.md-size'), 'sem mudança');
    expect(text('proposal-after-AGENTS.md-size'), contains(' → '));
    // R20: the 2 paths cited exist (commands and placeholders do not count).
    expect(
      find.text(
        'Conferido no projeto. Os 2 caminhos citados na proposta '
        'existem.',
      ),
      findsOneWidget,
    );
    // R21: unchecked, with the branch, and the warning without commit.
    expect(text('proposal-commit-label'), 'Commitar ao aplicar em main');
    expect(find.text('docs: instruções dos agentes'), findsOneWidget);
    expect(key('proposal-no-commit'), findsOneWidget);
    expect(
      tester.widget<Checkbox>(key('proposal-commit-check')).value,
      isFalse,
    );
    expect(
      find.text('Vale para a próxima sessão. As sessões abertas não mudam.'),
      findsOneWidget,
    );

    final png = Platform.environment['PROPOSTA_PNG'];
    if (png != null) await shot(tester, png);

    // Desfazer of a decision: back to decide.
    await tester.tap(key('proposal-hunk-3-undo'));
    await tester.pump();
    expect(text('proposal-counts'), '4 trechos · 2 aceitos, 2 a decidir');
    await tester.tap(key('proposal-back'));
    expect(back, 1);
  });

  testWidgets('R19: "Aplicar" writes only the accepted, keeps the import, '
      'ends the interview, and "Desfazer" puts the files back', (tester) async {
    var done = 0;
    final (c, ws) = await pump(tester, onDone: () => done++);
    await tester.tap(key('proposal-hunk-1-accept'));
    await tester.tap(key('proposal-hunk-3-accept'));
    await tester.tap(key('proposal-hunk-0-reject'));
    await tester.pump();
    await tester.tap(key('proposal-apply'));
    await waitFor(tester, key('proposal-done'));
    await settle(tester);
    final now = File('$root/AGENTS.md').readAsStringSync();
    expect(now, contains('- Tela nova leva teste de widget.'));
    expect(now, contains('- Testes: `flutter test`.'));
    expect(now, isNot(contains('Não mexer')));
    final claudeNow = File('$root/CLAUDE.md').readAsStringSync();
    expect(claudeNow, startsWith('@AGENTS.md\n'));
    expect(claudeNow, contains('- Em mudança de banco, comece no modo plan.'));
    expect(find.text('aplicado'), findsNWidgets(2));
    expect(find.text('Gravado em AGENTS.md e CLAUDE.md.'), findsOneWidget);
    // No commit: the tree has the two files changed.
    expect(
      await tester.runAsync(
        () => gitOut(root, ['rev-list', '--count', 'HEAD']),
      ),
      '1',
    );
    // The interview is gone.
    final row = await tester.runAsync(
      () => c.read(instructionInterviewsRepoProvider).get(ws.id),
    );
    expect(row, isNull);
    expect(key('proposal-back'), findsNothing);

    await tester.tap(key('proposal-undo-write'));
    await waitFor(tester, find.textContaining('Desfeito'));
    expect(File('$root/AGENTS.md').readAsStringSync(), agents);
    expect(File('$root/CLAUDE.md').readAsStringSync(), claude);
    await tester.tap(key('proposal-finish'));
    expect(done, 1);
  });

  testWidgets('R19: a trecho that no longer matches comes back as a '
      'conflict; editing the old text applies it', (tester) async {
    await pump(tester);
    // The file changed after the proposal was made.
    File(
      '$root/AGENTS.md',
    ).writeAsStringSync(agents.replaceFirst('`flutter test`', '`make test`'));
    await tester.tap(key('proposal-hunk-0-accept'));
    await tester.tap(key('proposal-hunk-1-accept'));
    await tester.pump();
    await tester.tap(key('proposal-apply'));
    await waitFor(tester, key('proposal-conflicts'));
    expect(key('proposal-hunk-0-conflict'), findsOneWidget);
    expect(text('proposal-hunk-0-state'), 'conflito');
    expect(text('proposal-hunk-1-state'), 'aplicado');
    final now = File('$root/AGENTS.md').readAsStringSync();
    expect(now, contains('`make test`'));
    expect(now, contains('- Tela nova leva teste de widget.'));

    await tester.tap(key('proposal-hunk-0-edit'));
    await tester.pump();
    await tester.enterText(
      key('proposal-hunk-0-old'),
      '- Testes: `make test`.',
    );
    await tester.tap(key('proposal-hunk-0-save'));
    await tester.pump();
    expect(text('proposal-hunk-0-state'), 'aceito');
    await tester.tap(key('proposal-apply'));
    await waitFor(
      tester,
      find.descendant(
        of: key('proposal-hunk-0-state'),
        matching: find.text('aplicado'),
      ),
    );
    expect(
      File('$root/AGENTS.md').readAsStringSync(),
      contains('`flutter test test/<area>`'),
    );
  });

  testWidgets('R20: a cited path that does not exist is marked', (
    tester,
  ) async {
    await pump(
      tester,
      prepare: (root) async =>
          Directory('$root/packages/legado').deleteSync(recursive: true),
    );
    expect(key('proposal-paths-missing'), findsOneWidget);
    expect(find.textContaining('packages/legado'), findsWidgets);
    expect(key('proposal-hunk-2-missing'), findsOneWidget);
    expect(key('proposal-hunk-0-missing'), findsNothing);
  });

  testWidgets('R21: checked, it commits on the current branch; off the base '
      'it warns that new specs get the text after the merge', (tester) async {
    await pump(
      tester,
      prepare: (root) async {
        await gitOut(root, ['checkout', '-q', '-b', 'ajuste-carrinho']);
        File('$root/README.md').writeAsStringSync('# sujo\n');
      },
    );
    expect(
      text('proposal-commit-label'),
      'Commitar ao aplicar em ajuste-carrinho',
    );
    expect(key('proposal-commit-off-base'), findsNothing);
    await tester.tap(key('proposal-commit-check'));
    await tester.pump();
    expect(key('proposal-commit-off-base'), findsOneWidget);
    expect(
      find.textContaining(
        'ajuste-carrinho não é a base do projeto '
        '(main)',
      ),
      findsOneWidget,
    );
    expect(key('proposal-no-commit'), findsNothing);
    final png = Platform.environment['PROPOSTA_COMMIT_PNG'];
    if (png != null) {
      await tester.pump(const Duration(milliseconds: 300));
      await shot(tester, png);
    }

    await tester.tap(key('proposal-hunk-1-accept'));
    await tester.pump();
    await tester.tap(key('proposal-apply'));
    await waitFor(tester, key('proposal-done'));
    await settle(tester);
    expect(find.textContaining('commitado em ajuste-carrinho'), findsOneWidget);
    final (subject, files, branch, status) = (await tester.runAsync(
      () async => (
        await gitOut(root, ['log', '-1', '--format=%s']),
        await gitOut(root, ['show', '--name-only', '--format=', 'HEAD']),
        await gitOut(root, ['branch', '--show-current']),
        await gitOut(root, ['status', '--porcelain']),
      ),
    ))!;
    expect(subject, 'docs: instruções dos agentes');
    expect(files, 'AGENTS.md');
    expect(branch, 'ajuste-carrinho');
    expect(status, contains('M README.md'));
    expect(status, isNot(contains('AGENTS.md')));
    // Committed: "Desfazer" is off.
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(
              of: key('proposal-undo-write'),
              matching: find.byType(Tooltip),
            ),
          )
          .message,
      startsWith('Já está no commit'),
    );
  });

  testWidgets('R21: with HEAD solto the box is off, with the reason', (
    tester,
  ) async {
    await pump(
      tester,
      prepare: (root) => gitOut(root, ['checkout', '-q', '--detach']),
    );
    expect(text('proposal-commit-label'), 'Commitar ao aplicar');
    expect(key('proposal-commit-disabled'), findsOneWidget);
    expect(find.textContaining('HEAD solto'), findsOneWidget);
    expect(
      tester.widget<Checkbox>(key('proposal-commit-check')).onChanged,
      isNull,
    );
  });

  testWidgets('"Descartar proposta" asks, ends the interview and leaves the '
      'files', (tester) async {
    var done = 0;
    final (c, ws) = await pump(tester, onDone: () => done++);
    await tester.tap(key('proposal-discard'));
    await tester.pumpAndSettle();
    await tester.tap(key('proposal-discard-confirm'));
    await settle(tester);
    expect(done, 1);
    final row = await tester.runAsync(
      () => c.read(instructionInterviewsRepoProvider).get(ws.id),
    );
    expect(row, isNull);
    expect(File('$root/AGENTS.md').readAsStringSync(), agents);
  });
}
