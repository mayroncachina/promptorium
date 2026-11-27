import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/providers/workspace_assets.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/app_settings_repo.dart';
import 'package:promptorium/features/instructions/instructions_view.dart';
import 'package:promptorium/features/instructions/interview_controller.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import '../../ui/preferences_test.dart' show unmount;
import '../board/canvas_fixture.dart' show loadAppFonts;
import 'instructions_view_test.dart' show settle, waitFor;
import 'proposal_apply_test.dart' show agents, claude, repo;

/// SPEC-113 T3 + T5 + T6: in Projeto › Instruções the interview hands its
/// proposal to the tab, and applying it goes back to the editor with the
/// new text.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('instructions-flow-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Finder key(String k) => find.byKey(ValueKey(k));

  Future<void> tap(WidgetTester tester, String k) async {
    await tester.ensureVisible(key(k));
    await tester.pump();
    await tester.tap(key(k));
    await tester.pump();
  }

  testWidgets('interview → proposal → Aplicar → Concluir: the editor shows '
      'the new text; "Voltar à entrevista" goes back', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = memoryDatabase();
    Workspace? active;
    final c = ProviderContainer(
      overrides: [
        databaseOverride(db),
        // No stream of the workspaces on screen: the proposal writes to the
        // database (a watched stream under fake async would hang).
        activeWorkspaceProvider.overrideWith((ref) => active),
        providerAvailabilityProvider.overrideWith(
          (ref, id) async =>
              const ProviderAvailability(ProviderStatus.ready, 'ok'),
        ),
        instructionsProofProvider.overrideWith((ref, id) async => null),
        instructionsInventoryProvider.overrideWith(
          (ref, root) => scanInstructions(root),
        ),
      ],
    );
    const proposal = InstructionProposal(
      provider: 'claude',
      model: 'Sonnet',
      questions: {'Q4': 'Teste em tela nova'},
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
    late Workspace ws;
    await tester.runAsync(() async {
      await loadAppFonts();
      final root = await repo(tmp);
      ws = await c.read(workspacesRepoProvider).add(path: root, name: 'v');
      active = ws;
      await AppSettingsRepo(db).setInt(AppSettingKeys.activeWorkspace, ws.id);
      await c.read(appSettingsProvider.notifier).load();
      // An interview that already ended with its proposal (R16).
      await c
          .read(instructionInterviewsRepoProvider)
          .start(
            ws.id,
            provider: 'claude',
            data: const InterviewData(
              stage: InterviewStage.proposal,
              proposal: proposal,
            ).encode(),
          );
    });
    addTearDown(() => unmount(tester, c));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: InstructionsView()),
        ),
      ),
    );
    await waitFor(tester, key('instructions-editor-AGENTS.md'));
    await settle(tester);
    expect(File('${ws.path}/AGENTS.md').readAsStringSync(), agents);
    expect(File('${ws.path}/CLAUDE.md').readAsStringSync(), claude);

    // "Começar entrevista" puts the interview in the tab.
    await tap(tester, 'instructions-interview');
    await waitFor(tester, key('interview-open-proposal'));
    await tap(tester, 'interview-open-proposal');
    await waitFor(tester, key('proposal-apply'));
    expect(c.read(instructionsModeProvider(ws.id)), InstructionsMode.proposal);

    // "Voltar à entrevista" and back to the proposal.
    await tap(tester, 'proposal-back');
    await waitFor(tester, key('interview-open-proposal'));
    await tap(tester, 'interview-open-proposal');
    await waitFor(tester, key('proposal-apply'));

    // The files were read (the panel "Depois de aplicar").
    await waitFor(tester, key('proposal-after-AGENTS.md'));
    await tap(tester, 'proposal-hunk-0-accept');
    await tap(tester, 'proposal-apply');
    await settle(tester);
    await waitFor(tester, key('proposal-done'));
    await settle(tester);
    expect(
      File('${ws.path}/AGENTS.md').readAsStringSync(),
      contains('- Tela nova leva teste de widget.'),
    );
    await tap(tester, 'proposal-finish');
    await waitFor(tester, key('instructions-editor-AGENTS.md'));
    await settle(tester);
    expect(c.read(instructionsModeProvider(ws.id)), InstructionsMode.editor);
    String text() =>
        tester.widget<TextField>(key('instructions-text')).controller!.text;
    // The files are read again.
    final end = DateTime.now().add(const Duration(seconds: 15));
    while (!text().contains('Tela nova') && DateTime.now().isBefore(end)) {
      await settle(tester);
    }
    expect(text(), contains('- Tela nova leva teste de widget.'));
    expect(key('instructions-state-saved'), findsOneWidget);
  });
}
