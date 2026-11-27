import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/providers/workspace_assets.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/app_settings_repo.dart';
import 'package:promptorium/features/instructions/interview_data.dart';
import 'package:promptorium/features/instructions/instructions_view.dart';
import 'package:promptorium/features/project/widgets/project_widgets.dart'
    show NoticeBox;
import 'package:promptorium/features/sessions/widgets/session_style.dart'
    show SmallButton;
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import '../../ui/preferences_test.dart' show unmount;
import 'instructions_view_test.dart' show settle, waitFor;

/// SPEC-113 T3: Projeto › Instruções — the editor (R8), the CLAUDE.md
/// import (R9), who reads (R10), the size (R11) and the nested files (R12).
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('instructions-ed-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  void write(String rel, String text) {
    final f = File('${tmp.path}/$rel');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(text);
  }

  String read(String rel) => File('${tmp.path}/$rel').readAsStringSync();

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    InstructionsProof? proof,
    bool pausedInterview = false,
  }) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = memoryDatabase();
    addTearDown(db.close);
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        providerAvailabilityProvider.overrideWith(
          (ref, id) async =>
              const ProviderAvailability(ProviderStatus.ready, 'ok'),
        ),
        instructionsProofProvider.overrideWith((ref, id) async => proof),
        instructionsInventoryProvider.overrideWith(
          (ref, root) => scanInstructions(root),
        ),
      ],
    );
    await tester.runAsync(() async {
      final ws = await db
          .into(db.workspaces)
          .insertReturning(
            WorkspacesCompanion.insert(path: tmp.path, name: 'vitrine'),
          );
      await AppSettingsRepo(db).setInt(AppSettingKeys.activeWorkspace, ws.id);
      if (pausedInterview) {
        final repo = c.read(instructionInterviewsRepoProvider);
        await repo.start(
          ws.id,
          provider: 'claude',
          data: const InterviewData().encode(),
        );
        await repo.update(
          ws.id,
          InstructionInterviewsCompanion(pausedAt: Value(DateTime(2026, 11))),
        );
      }
      await c.read(appSettingsProvider.notifier).load();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: InstructionsView()),
        ),
      ),
    );
    await waitFor(tester, find.byKey(const ValueKey('instructions-detail')));
    await idle(tester);
    addTearDown(() => unmount(tester, c));
    return c;
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  TextEditingController editor(WidgetTester tester) =>
      tester.widget<TextField>(key('instructions-text')).controller!;

  Future<void> tap(WidgetTester tester, String k) async {
    await tester.ensureVisible(key(k));
    await tester.pump();
    await tester.tap(key(k));
    await tester.pump();
  }

  /// The file watcher saw the change (SPEC-113 R8).
  Future<void> rescan(WidgetTester tester, ProviderContainer c) async {
    c.invalidate(instructionsInventoryProvider(tmp.path));
    final end = DateTime.now().add(const Duration(seconds: 15));
    while (c.read(instructionsInventoryProvider(tmp.path)).isLoading) {
      if (DateTime.now().isAfter(end)) fail('não releu os arquivos');
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    await idle(tester);
    await settle(tester);
  }

  testWidgets('R6/R8: single source opens the AGENTS.md; an edit is "não '
      'salvo", Salvar writes it and Desfazer brings it back', (tester) async {
    write('AGENTS.md', '# vitrine\n\n## Regras\n- Textos em português.\n');
    write('CLAUDE.md', '@AGENTS.md\n');
    await pump(tester);
    expect(find.text('AGENTS.md'), findsWidgets);
    expect(key('instructions-editor-AGENTS.md'), findsOneWidget);
    expect(key('instructions-state-saved'), findsOneWidget);
    expect(key('instructions-improve'), findsOneWidget);
    expect(key('instructions-unify-card'), findsNothing);

    final ctl = editor(tester);
    await tester.enterText(
      key('instructions-text'),
      '${ctl.text}- Tela nova leva teste de widget.\n',
    );
    await tester.pump();
    expect(key('instructions-state-dirty'), findsOneWidget);
    expect(
      find.text(
        '1 linha alterada · o arquivo é relido se mudar fora do '
        'app',
      ),
      findsOneWidget,
    );
    // Not written before Salvar.
    expect(read('AGENTS.md'), isNot(contains('Tela nova')));

    // Prévia renders the markdown.
    await tap(tester, 'instructions-mode-preview');
    expect(key('instructions-markdown'), findsOneWidget);
    await tap(tester, 'instructions-mode-text');

    await tap(tester, 'instructions-save');
    await idle(tester);
    expect(read('AGENTS.md'), contains('- Tela nova leva teste de widget.'));
    expect(key('instructions-state-saved'), findsOneWidget);
    expect(key('instructions-undo'), findsOneWidget);

    await tap(tester, 'instructions-undo');
    await idle(tester);
    expect(read('AGENTS.md'), isNot(contains('Tela nova')));
    expect(editor(tester).text, isNot(contains('Tela nova')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('R8: a change outside without an edit is re-read', (
    tester,
  ) async {
    write('AGENTS.md', '# a\n');
    write('CLAUDE.md', '@AGENTS.md\n');
    final c = await pump(tester);
    write('AGENTS.md', '# b, de fora\n');
    await rescan(tester, c);
    expect(editor(tester).text, '# b, de fora\n');
    expect(key('instructions-external'), findsNothing);
    expect(key('instructions-state-saved'), findsOneWidget);
  });

  testWidgets('R8: a change outside with an edit asks first and loses '
      'neither side', (tester) async {
    write('AGENTS.md', '# a\n');
    write('CLAUDE.md', '@AGENTS.md\n');
    final c = await pump(tester);
    await tester.enterText(key('instructions-text'), '# a\n- minha regra\n');
    await tester.pump();
    write('AGENTS.md', '# a\n- regra de fora\n');
    await rescan(tester, c);
    // Both sides are still there: mine in the editor, theirs on disk.
    expect(key('instructions-external'), findsOneWidget);
    expect(editor(tester).text, '# a\n- minha regra\n');
    expect(read('AGENTS.md'), '# a\n- regra de fora\n');
    await tap(tester, 'instructions-compare');
    expect(key('instructions-external-diff'), findsOneWidget);

    // "Manter a minha edição" + Salvar replaces the file.
    await tap(tester, 'instructions-keep-mine');
    expect(key('instructions-external'), findsNothing);
    await tap(tester, 'instructions-save');
    await idle(tester);
    expect(read('AGENTS.md'), '# a\n- minha regra\n');
  });

  testWidgets('R8: "Usar a versão do disco" drops the edit; a save over a '
      'file changed since the reading writes nothing', (tester) async {
    write('AGENTS.md', '# a\n');
    write('CLAUDE.md', '@AGENTS.md\n');
    final c = await pump(tester);
    await tester.enterText(key('instructions-text'), '# minha\n');
    await tester.pump();
    // Changed outside, before the watcher saw it: Salvar refuses (R5).
    write('AGENTS.md', '# de fora\n');
    await tap(tester, 'instructions-save');
    await idle(tester);
    expect(read('AGENTS.md'), '# de fora\n');
    expect(key('instructions-external'), findsOneWidget);
    expect(editor(tester).text, '# minha\n');
    expect(find.textContaining('nada foi gravado'), findsOneWidget);

    await tap(tester, 'instructions-use-disk');
    await rescan(tester, c);
    expect(editor(tester).text, '# de fora\n');
    expect(key('instructions-state-saved'), findsOneWidget);
  });

  testWidgets('R8: an unsaved edit survives leaving the screen', (
    tester,
  ) async {
    write('AGENTS.md', '# a\n');
    write('CLAUDE.md', '@AGENTS.md\n');
    final c = await pump(tester);
    await tester.enterText(key('instructions-text'), '# rascunho\n');
    await tester.pump();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: SizedBox()),
        ),
      ),
    );
    await idle(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: InstructionsView()),
        ),
      ),
    );
    await waitFor(tester, key('instructions-text'));
    await idle(tester);
    expect(editor(tester).text, '# rascunho\n');
    expect(key('instructions-state-dirty'), findsOneWidget);
  });

  testWidgets('R9: the CLAUDE.md shows the import apart from the Claude-only '
      'part; "Mover seleção" takes a rule to the AGENTS.md and Salvar writes '
      'both', (tester) async {
    write('AGENTS.md', '# vitrine\n');
    write(
      'CLAUDE.md',
      '@AGENTS.md\n\n## Só para o Claude Code\n- Use o subagente tester.\n'
          '- Textos em português.\n',
    );
    await pump(tester);
    await tap(tester, 'instructions-file-CLAUDE.md');
    expect(key('instructions-import-line'), findsOneWidget);
    expect(find.text('SÓ PARA O CLAUDE CODE'), findsOneWidget);
    final ctl = editor(tester);
    expect(ctl.text, isNot(contains('@AGENTS.md')));
    expect(find.text('O Codex não lê este trecho.'), findsOneWidget);

    const rule = '- Textos em português.';
    final start = ctl.text.indexOf(rule);
    ctl.selection = TextSelection(
      baseOffset: start,
      extentOffset: start + rule.length,
    );
    await tap(tester, 'instructions-move-selection');
    expect(ctl.text, isNot(contains(rule)));
    expect(
      find.text('AGENTS.md e CLAUDE.md não salvos · salvos juntos'),
      findsOneWidget,
    );
    await tap(tester, 'instructions-save');
    await idle(tester);
    expect(read('AGENTS.md'), '# vitrine\n\n- Textos em português.\n');
    final claude = read('CLAUDE.md');
    expect(claude, startsWith('@AGENTS.md\n'));
    expect(claude, contains('- Use o subagente tester.'));
    expect(claude, isNot(contains(rule)));
  });

  testWidgets('R18: a paused interview has only its own card, no second '
      '"Começar entrevista"', (tester) async {
    write('AGENTS.md', '# vitrine\n');
    write('CLAUDE.md', '@AGENTS.md\n');
    await pump(tester, pausedInterview: true);
    await idle(tester);
    expect(find.text('Entrevista pausada'), findsOneWidget);
    expect(key('instructions-improve'), findsNothing);
  });

  testWidgets('R9: without the import the app warns and "Recolocar o import" '
      'puts it back', (tester) async {
    write('AGENTS.md', '# vitrine\n');
    write('CLAUDE.md', '# só do Claude\n');
    final c = await pump(tester);
    await tap(tester, 'instructions-file-CLAUDE.md');
    expect(key('instructions-no-import'), findsOneWidget);
    await tap(tester, 'instructions-restore-import');
    await rescan(tester, c);
    expect(read('CLAUDE.md'), '@AGENTS.md\n\n# só do Claude\n');
    expect(key('instructions-no-import'), findsNothing);
    expect(key('instructions-import-line'), findsOneWidget);
    // The app's own file watcher may rescan once more after the write.
    await waitFor(tester, key('instructions-single-source'));
    expect(key('instructions-single-source'), findsOneWidget);
    expect(key('instructions-undo'), findsOneWidget);
  });

  testWidgets('R10: "previsto" without the proof, "carregado" with it', (
    tester,
  ) async {
    write('AGENTS.md', '# a\n');
    write('CLAUDE.md', '@AGENTS.md\n');
    await pump(tester);
    Finder inRow(String p, String t) =>
        find.descendant(of: key('instructions-row-$p'), matching: find.text(t));
    expect(inRow('Codex', 'previsto'), findsOneWidget);
    expect(inRow('Codex', 'carregado'), findsNothing);
    expect(
      inRow('Claude Code', 'CLAUDE.md + AGENTS.md (import)'),
      findsOneWidget,
    );
  });

  testWidgets('R10: with the instructionSources of a run, "carregado"', (
    tester,
  ) async {
    write('AGENTS.md', '# a\n');
    write('CLAUDE.md', '@AGENTS.md\n');
    await pump(
      tester,
      proof: InstructionsProof(
        sources: const ['AGENTS.md'],
        at: DateTime.now(),
        where: 'sessão “Corrigir cache”',
      ),
    );
    expect(
      find.descendant(
        of: key('instructions-row-Codex'),
        matching: find.text('carregado'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('R11: from 80% a warning; 32 769 bytes show where the cut '
      'falls and "Ir para o corte" goes there', (tester) async {
    write('CLAUDE.md', '@AGENTS.md\n');
    // 80%: 26 215 bytes.
    write('AGENTS.md', '${'a' * 26214}\n');
    final c = await pump(tester);
    expect(key('instructions-size-warning'), findsOneWidget);
    expect(key('instructions-size-cut'), findsNothing);

    final line = '${'b' * 99}\n'; // 100 bytes
    write('AGENTS.md', '${line * 327}${'c' * 69}');
    expect(File('${tmp.path}/AGENTS.md').lengthSync(), 32769);
    await rescan(tester, c);
    expect(key('instructions-size-cut'), findsOneWidget);
    expect(
      find.textContaining('linha 328, coluna 69, no meio da linha'),
      findsOneWidget,
    );
    await tap(tester, 'instructions-go-to-cut');
    await tester.pump();
    expect(editor(tester).selection.baseOffset, 32768);
  });

  testWidgets('R12: a nested file is read only, without any write action', (
    tester,
  ) async {
    write('AGENTS.md', '# a\n');
    write('CLAUDE.md', '@AGENTS.md\n');
    write('packages/api/AGENTS.md', '# api\n');
    await pump(tester);
    await tap(tester, 'instructions-file-packages/api/AGENTS.md');
    expect(key('instructions-nested'), findsOneWidget);
    expect(find.text('só leitura'), findsOneWidget);
    expect(key('instructions-text'), findsNothing);
    expect(key('instructions-save'), findsNothing);
    expect(key('instructions-discard'), findsNothing);
    expect(key('instructions-open-editor'), findsNothing);
    expect(find.text('# api\n'), findsOneWidget);
  });

  testWidgets('R3: "Unificar instruções" shows for only a CLAUDE.md, two '
      'sources or a generated AGENTS.md; nothing is written on opening', (
    tester,
  ) async {
    write('CLAUDE.md', '# a\n');
    await pump(tester);
    expect(key('instructions-unify-card'), findsOneWidget);
    expect(
      tester.widget<SmallButton>(key('instructions-unify')).onTap,
      isNotNull,
    );
    // No warning on opening an old project: only the button (R3).
    for (final k in [
      'instructions-two-sources',
      'instructions-plan-b',
      'instructions-stale',
      'instructions-no-import',
      'instructions-external',
    ]) {
      expect(key(k), findsNothing, reason: k);
    }
    expect(find.byType(NoticeBox), findsNothing);
    expect(File('${tmp.path}/AGENTS.md').existsSync(), isFalse);
    expect(read('CLAUDE.md'), '# a\n');
    expect(tmp.listSync(recursive: true).map((e) => e.path.split('/').last), [
      'CLAUDE.md',
    ]);
    // The button opens the dialog of the unification (T4).
    await tap(tester, 'instructions-unify');
    await waitFor(tester, key('unify-dialog'));
  });

  test('R3: instructionsNeedUnify', () {
    InstructionsInventory inv(String? claude, String? agents) =>
        InstructionsInventory(
          root: '/r',
          claude: claude == null
              ? null
              : InstructionFile(
                  path: 'CLAUDE.md',
                  size: 1,
                  modified: DateTime(2026),
                  lines: 1,
                ),
          claudeText: claude,
          agentsText: agents,
        );
    expect(instructionsNeedUnify(inv('# a\n', null)), isTrue);
    expect(instructionsNeedUnify(inv('# a\n', '# meu\n')), isTrue);
    expect(
      instructionsNeedUnify(inv('# a\n', generatedAgentsMd('# a\n'))),
      isTrue,
    );
    expect(instructionsNeedUnify(inv('@AGENTS.md\n', '# meu\n')), isFalse);
    expect(instructionsNeedUnify(inv(null, null)), isFalse);
  });
}

/// Lets real IO run until nothing is busy (a save, an undo) and the
/// files are read again.
Future<void> idle(WidgetTester tester) async {
  final end = DateTime.now().add(const Duration(seconds: 15));
  var calm = 0;
  while (calm < 5) {
    if (DateTime.now().isAfter(end)) fail('a tela não terminou');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    final busy = find.textContaining('Salvando').evaluate().isNotEmpty;
    calm = busy ? 0 : calm + 1;
  }
}
