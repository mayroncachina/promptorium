import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/core/providers/agent_provider.dart' show PromptMode;
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/prompt/refine_origin.dart';
import 'package:promptorium/features/sessions/widgets/session_style.dart'
    show SmallButton;
import 'package:promptorium/features/specs/spec_action.dart';
import 'package:promptorium/features/specs/spec_answers.dart'
    show specQuestionOptionsProvider;
import 'package:promptorium/features/specs/spec_design.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/features/specs/specs_screen.dart';
import 'package:promptorium/features/specs/widgets/spec_header.dart'
    show SpecActionButton, SpecActionEmphasis;
import 'package:promptorium/features/specs/workspace_watcher.dart';
import 'package:promptorium/features/board/widgets/spec_steps_panel.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:re_editor/re_editor.dart' show CodeEditor;

import '../../helpers/test_db.dart';
import '../prompt/prompt_test_utils.dart' show SilentConversationManager;
import '../sessions/session_test_utils.dart';

import 'package:promptorium/core/process/process_runner.dart';
import 'package:promptorium/features/specs/prototype/prototype_service.dart';
import 'package:promptorium/features/specs/prototype/prototype_thumbnails.dart';

import 'spec_action_lock_test.dart' show FakeDesigner, otherSpec;
import 'prototype_thumbnails_test.dart' show FakeBrowser;
import 'spec_file_test.dart' show sample;
import 'spec_questions_panel_test.dart' show FakeQuestionOptions;

/// Real file IO does not run under FakeAsync: let it run, then pump, until
/// [until] holds (up to 15 s of real time: the full suite runs files in
/// parallel).
Future<void> settleIo(WidgetTester tester, {bool Function()? until}) async {
  // Each lap moves the real IO a little: with the full suite in parallel a
  // chain of them passed 20 s.
  final end = DateTime.now().add(const Duration(seconds: 45));
  // Without [until] the fixed laps are the wait: keep them 20 ms of real
  // time. With it the condition decides, so short laps only stop sooner.
  final lap = Duration(milliseconds: until == null ? 20 : 4);
  for (var i = 0; DateTime.now().isBefore(end); i++) {
    await tester.runAsync(() => Future<void>.delayed(lap));
    // The first laps move the clock 120 ms as before; then it moves no
    // faster than real time, so a slow IO does not run out a timer (a
    // toast) before the condition holds.
    await tester.pump(i < 6 ? const Duration(milliseconds: 20) : lap);
    if (i >= 5 && (until?.call() ?? true)) return;
  }
}

String readSpec(Directory tmp) =>
    File('${tmp.path}/specs/SPEC-002-sessoes.md').readAsStringSync();

// Legacy editor tests isolate filesystem events; discovery is tested separately.
class QuietWorkspaceWatcher extends WorkspaceWatcher {
  @override
  Set<int> build() => {};
}

final checksDialog = find.byKey(const ValueKey('spec-approve-checks-dialog'));

/// Taps "Aprovar spec" until [dialog] opens (the button only acts once the
/// file is loaded).
Future<void> tapApprove(WidgetTester tester, Finder dialog) async {
  for (var i = 0; i < 5 && dialog.evaluate().isEmpty; i++) {
    await tester.tap(find.byKey(const ValueKey('spec-approve')));
    await settleIo(tester, until: () => dialog.evaluate().isNotEmpty);
  }
  expect(dialog, findsOneWidget);
}

/// Presses Tab until the focus is inside [target] (false = never reached).
Future<bool> tabTo(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 80; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    if (focusedIn(target)) return true;
  }
  return false;
}

bool focusedIn(Finder target) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  return find
      .descendant(
        of: target,
        matching: find.byWidgetPredicate((w) => identical(w, ctx.widget)),
      )
      .evaluate()
      .isNotEmpty;
}

/// A spec without structure warnings, with two open questions (one with a
/// suggestion, SPEC-028 R1) and no Design.
const questionsSpec = '''---
id: SPEC-002
status: rascunho
---

# Sessões com stream-json

## Requisitos

- R1 · Quando abrir, o sistema deve mostrar as sessões

## Critérios de aceite

- [ ] Mostra [R1] verificar: true

## Perguntas em aberto

- P1 · Vale para o quadro?
  - Sugestão: sim, como na lista.
- P2 · E no grafo?
''';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('promptorium-specs-ui-');
    Directory('${tmp.path}/specs').createSync();
    File('${tmp.path}/specs/SPEC-002-sessoes.md').writeAsStringSync(sample);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Size size, {
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = memoryDatabase();
    final c = ProviderContainer(
      overrides: [
        ...sessionOverrides(db: db, cli: FakeCli(), notifier: FakeNotifier()),
        workspaceWatcherProvider.overrideWith(QuietWorkspaceWatcher.new),
        ...overrides,
      ],
    );
    await tester.runAsync(() async {
      final ws = await db
          .into(db.workspaces)
          .insertReturning(
            WorkspacesCompanion.insert(path: tmp.path, name: 'ws'),
          );
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: AppSettingKeys.activeWorkspace,
              value: '${ws.id}',
            ),
          );
      await c.read(appSettingsProvider.notifier).load();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: SpecsScreen()),
        ),
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      await tester.pump(Duration.zero);
    });
    await settleIo(
      tester,
      until: () =>
          find.byType(CodeEditor).evaluate().isNotEmpty ||
          find.byKey(const ValueKey('spec-preview')).evaluate().isNotEmpty,
    );
    return c;
  }

  testWidgets('lists specs/, opens the file in the editor and renders the '
      'preview; modes switch; fits 1100×700', (tester) async {
    await pump(tester, const Size(1044, 628));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('spec-item-SPEC-002')), findsOneWidget);
    expect(find.text('specs/SPEC-002-sessoes.md'), findsOneWidget);
    expect(find.byType(CodeEditor), findsOneWidget);
    expect(find.byKey(const ValueKey('spec-preview')), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    // The steps panel lists the requirements of the file.
    expect(find.byKey(const ValueKey('step-R1')), findsOneWidget);
    await tester.drag(
      find
          .descendant(
            of: find.byType(SpecStepsPanel),
            matching: find.byType(ListView),
          )
          .first,
      const Offset(0, -150),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('step-R3')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('spec-mode-preview')));
    await tester.pump();
    expect(find.byType(CodeEditor), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('spec-mode-edit')));
    await tester.pump();
    expect(find.byKey(const ValueKey('spec-preview')), findsNothing);
    expect(find.byType(CodeEditor), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clicking a step opens its traceability panel (UX v2, U5)', (
    tester,
  ) async {
    await pump(tester, const Size(1440, 900));
    expect(find.byKey(const ValueKey('step-trace-R2')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('step-R2')));
    await tester.pump();
    expect(find.byKey(const ValueKey('step-trace-R2')), findsOneWidget);
    expect(find.text('Eventos persistidos no SQLite'), findsWidgets);
    expect(find.textContaining('Nenhum critério cita'), findsOneWidget);
    expect(find.text('A spec não tem seção Plano.'), findsOneWidget);
    expect(find.text('A etapa ainda não rodou.'), findsOneWidget);
    expect(find.text('Sem sessão para esta etapa.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Same step again closes it; another step switches.
    await tester.tap(find.byKey(const ValueKey('step-R2')));
    await tester.pump();
    expect(find.byKey(const ValueKey('step-trace-R2')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('step-R1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('step-trace-R1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('step-trace-close')));
    await tester.pump();
    expect(find.byKey(const ValueKey('step-trace-R1')), findsNothing);
  });

  testWidgets('"Aprovar spec" writes status: aprovada in the file', (
    tester,
  ) async {
    await pump(tester, const Size(1440, 900));
    expect(find.text('Aprovar'), findsOneWidget);
    // The sample has structure warnings: their count comes first (SPEC-023
    // R10), "Aprovar mesmo assim" goes on.
    await tapApprove(tester, checksDialog);
    expect(find.byKey(const ValueKey('spec-approve-warnings')), findsOneWidget);
    expect(find.byKey(const ValueKey('spec-approve-refine')), findsNothing);
    final dialog = find.byKey(const ValueKey('spec-no-design-dialog'));
    await tester.tap(find.byKey(const ValueKey('spec-approve-anyway')));
    await settleIo(tester, until: () => dialog.evaluate().isNotEmpty);
    // No ## Design: asks first (F7); a trivial spec goes without it.
    expect(find.byKey(const ValueKey('spec-no-design-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('spec-approve-no-design')));
    await settleIo(
      tester,
      until: () =>
          readSpec(tmp).contains('status: aprovada') &&
          find.text('Aprovada').evaluate().isNotEmpty,
    );
    final saved = File('${tmp.path}/specs/SPEC-002-sessoes.md')
        .readAsStringSync();
    expect(saved, contains('status: aprovada'));
    expect(saved, contains('design: dispensado'));
    expect(find.text('Aprovada'), findsWidgets);
    expect(find.byKey(const ValueKey('spec-unsaved')), findsNothing);
  });

  testWidgets('the zoom also scales the preview text, not only the editor', (
    tester,
  ) async {
    await pump(tester, const Size(1440, 900));
    TextScaler heading() => tester
        .widget<RichText>(
          find.descendant(
            of: find.byKey(const ValueKey('spec-preview')),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is RichText &&
                  w.text.toPlainText() == 'Sessões com stream-json',
            ),
          ),
        )
        .textScaler;
    expect(heading(), const TextScaler.linear(1));
    await tester.tap(find.byTooltip('Aumentar zoom (Ctrl =)'));
    await tester.tap(find.byTooltip('Aumentar zoom (Ctrl =)'));
    await tester.pump();
    expect(find.text('120%'), findsOneWidget);
    expect(heading(), const TextScaler.linear(1.2));
    // A click on the percent goes back to 100%, the preview too.
    await tester.tap(find.byKey(const ValueKey('zoom-specs')));
    await tester.pump();
    expect(heading(), const TextScaler.linear(1));
  });

  testWidgets('SPEC-024 R8: editing shows "Não salvo" and "Salvar" with '
      'Ctrl+S; saving writes the file and goes back to "Salvo"', (
    tester,
  ) async {
    await pump(tester, const Size(1440, 900));
    expect(find.text('Salvo'), findsOneWidget);
    expect(find.byKey(const ValueKey('spec-save')), findsNothing);
    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    editor.controller!.text = sample.replaceFirst(
      '# Sessões com stream-json',
      '# Sessões revisadas',
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('spec-unsaved')), findsOneWidget);
    expect(find.text('Não salvo'), findsOneWidget);
    expect(find.text('Salvo'), findsNothing);
    final save = find.byKey(const ValueKey('spec-save'));
    expect(
      find.descendant(of: save, matching: find.text('Salvar')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: save, matching: find.text('Ctrl+S')),
      findsOneWidget,
    );
    // Preview follows the editor.
    expect(find.text('Sessões revisadas'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('spec-save')));
    await settleIo(
      tester,
      until: () =>
          readSpec(tmp).contains('# Sessões revisadas') &&
          find.byKey(const ValueKey('spec-unsaved')).evaluate().isEmpty,
    );
    expect(
      File('${tmp.path}/specs/SPEC-002-sessoes.md').readAsStringSync(),
      contains('# Sessões revisadas'),
    );
    expect(find.byKey(const ValueKey('spec-unsaved')), findsNothing);
    expect(find.text('Salvo'), findsOneWidget);
    expect(find.byKey(const ValueKey('spec-save')), findsNothing);
  });

  group('SPEC-024', () {
    Finder key(String k) => find.byKey(ValueKey(k));

    testWidgets('R3, R8: a spec just created by "Nova spec" opens with '
        '"Salvo", the "Rascunho" badge and the R3 actions', (tester) async {
      // Wide: the test font is wider than IBM Plex Sans and would move
      // "Planejar" to the menu (R9, covered in spec_header_test).
      final c = await pump(tester, const Size(1920, 1000));
      final ws = c.read(activeWorkspaceProvider)!;
      final spec = await tester.runAsync(
        () => c
            .read(specServiceProvider)
            .create(ws, title: 'Atalhos do editor de specs'),
      );
      c.read(selectedSpecProvider.notifier).select(spec!.id);
      await settleIo(
        tester,
        until: () =>
            find.text('Atalhos do editor de specs').evaluate().isNotEmpty &&
            find.text('Salvo').evaluate().isNotEmpty,
      );
      expect(find.text(spec.path), findsOneWidget);
      expect(
        find.descendant(
          of: key('spec-status'),
          matching: find.text('Rascunho'),
        ),
        findsOneWidget,
      );
      expect(find.text('Salvo'), findsOneWidget);
      expect(key('spec-unsaved'), findsNothing);
      final xs = [
        for (final k in [
          'spec-refine',
          'spec-design',
          'spec-approve',
          'spec-more',
        ])
          tester.getCenter(key(k)).dx,
      ];
      expect(xs, [...xs]..sort());
      // SPEC-039 R7: a new spec has no Plano yet.
      expect(
        tester.widget<SpecActionButton>(key('spec-design')).action.emphasis,
        SpecActionEmphasis.primary,
      );
      expect(
        tester.widget<SpecActionButton>(key('spec-approve')).action.emphasis,
        SpecActionEmphasis.secondary,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('R7: "Mais ações" holds "Excluir…", which asks first; a '
        'finished spec has "Arquivar"; a running one has no menu', (
      tester,
    ) async {
      final c = await pump(tester, const Size(1440, 900));
      await tester.tap(key('spec-more'));
      await tester.pumpAndSettle();
      expect(find.text('Excluir…'), findsOneWidget);
      expect(find.text('Arquivar'), findsNothing);
      await tester.tap(key('spec-delete'));
      await settleIo(
        tester,
        until: () => key('spec-delete-confirm').evaluate().isNotEmpty,
      );
      expect(key('spec-delete-confirm'), findsOneWidget);
      expect(find.text('Excluir SPEC-002?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(
        File('${tmp.path}/specs/SPEC-002-sessoes.md').existsSync(),
        isTrue,
      );

      final repo = c.read(specsRepoProvider);
      final id =
          c.read(selectedSpecProvider) ??
          (await tester.runAsync(
            () => repo
                .watchByWorkspace(c.read(activeWorkspaceProvider)!.id)
                .first,
          ))!.single.id;
      await tester.runAsync(() => repo.setStage(id, SpecStage.done));
      await settleIo(
        tester,
        until: () => key('spec-clone').evaluate().isNotEmpty,
      );
      await tester.tap(key('spec-more'));
      await tester.pumpAndSettle();
      expect(find.text('Arquivar'), findsOneWidget);
      expect(find.text('Excluir…'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await tester.runAsync(() => repo.setStage(id, SpecStage.running));
      await settleIo(tester, until: () => key('spec-more').evaluate().isEmpty);
      expect(key('spec-more'), findsNothing);
      expect(key('spec-clone'), findsOneWidget);
      expect(find.text('Somente leitura'), findsOneWidget);
    });
  });

  testWidgets('"Refinar com IA" stores the spec code and the Specs origin in '
      'the refine conversation (SPEC-021 R1)', (tester) async {
    final manager = SilentConversationManager();
    final c = await pump(
      tester,
      const Size(1440, 900),
      overrides: [conversationManagerProvider.overrideWith(() => manager)],
    );
    await tester.tap(find.byKey(const ValueKey('spec-refine')));
    await settleIo(tester, until: () => manager.sent.isNotEmpty);
    final conv = await tester.runAsync(
      () => c.read(conversationsRepoProvider).getById(manager.sent.single.$1),
    );
    expect(conv!.mode, PromptMode.refine.name);
    expect(conv.refineSpecCode, 'SPEC-002');
    expect(conv.refineOrigin, RefineSource.specs.name);
    expect(c.read(selectedConversationProvider), conv.id);
  });

  group('SPEC-023', () {
    void writeSpec(String text) =>
        File('${tmp.path}/specs/SPEC-002-sessoes.md').writeAsStringSync(text);

    testWidgets('R6, R7 (SPEC-028 R4, R5): open questions come before the '
        'Design dialog; Cancelar keeps the file; "Aprovar com as sugestões" '
        'moves them to Premissas with the date and approves', (tester) async {
      writeSpec(questionsSpec);
      await pump(tester, const Size(1440, 900));
      await tapApprove(tester, checksDialog);
      expect(find.text('A SPEC-002 tem 2 perguntas em aberto'), findsOneWidget);
      expect(find.text('P1 Vale para o quadro?'), findsOneWidget);
      expect(
        find.descendant(
          of: checksDialog,
          matching: find.text('Sugestão: sim, como na lista.'),
        ),
        findsOneWidget,
      );
      expect(find.text('P2 E no grafo?'), findsOneWidget);
      expect(find.byKey(const ValueKey('spec-no-design-dialog')), findsNothing);
      expect(find.byKey(const ValueKey('spec-approve-warnings')), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('spec-approve-checks-cancel')),
      );
      await settleIo(tester, until: () => checksDialog.evaluate().isEmpty);
      expect(find.byKey(const ValueKey('spec-no-design-dialog')), findsNothing);
      expect(readSpec(tmp), questionsSpec);

      await tapApprove(tester, checksDialog);
      await tester.tap(find.byKey(const ValueKey('spec-approve-assume')));
      final design = find.byKey(const ValueKey('spec-no-design-dialog'));
      await settleIo(tester, until: () => design.evaluate().isNotEmpty);
      expect(design, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('spec-approve-no-design')));
      await settleIo(
        tester,
        until: () => readSpec(tmp).contains('status: aprovada'),
      );
      final now = DateTime.now();
      final day =
          '${now.year}-${'${now.month}'.padLeft(2, '0')}-'
          '${'${now.day}'.padLeft(2, '0')}';
      final saved = readSpec(tmp);
      expect(saved, contains('status: aprovada'));
      expect(
        saved,
        contains(
          '## Premissas\n\n'
          '- (assumida em $day) P1 · Vale para o quadro? → sim, como na '
          'lista.\n'
          '- (sem resposta, aceita em $day) P2 · E no grafo?\n\n'
          '## Critérios de aceite',
        ),
      );
      expect(saved, endsWith('## Perguntas em aberto\n'));
    });

    testWidgets('SPEC-028 R4: 4 questions with their suggestions, the '
        'warnings by name and Cancelar / "Aprovar com as sugestões" / '
        '"Responder perguntas" (no "Refinar com IA"); "Responder perguntas" '
        'opens the panel', (tester) async {
      writeSpec(
        questionsSpec
            .replaceFirst(
              '- R1 · Quando abrir, o sistema deve mostrar as sessões',
              '- R1 · Quando abrir, o sistema deve mostrar as sessões\n'
                  '- R2 · Quando fechar, o sistema deve salvar',
            )
            .replaceFirst(
              '- P2 · E no grafo?\n',
              '- P2 · E no grafo?\n'
                  '  - Sugestão: não.\n'
                  '3. E no terminal?\n'
                  '4. Sugestão: só no quadro.\n'
                  '- P4 · E no mapa?\n',
            ),
      );
      await pump(
        tester,
        const Size(1440, 900),
        overrides: [
          specQuestionOptionsProvider.overrideWith(FakeQuestionOptions.new),
        ],
      );
      await tapApprove(tester, checksDialog);
      expect(find.text('A SPEC-002 tem 4 perguntas em aberto'), findsOneWidget);
      for (final id in ['P1', 'P2', 'P3', 'P4']) {
        expect(
          find.byKey(ValueKey('spec-approve-question-$id')),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(
          of: checksDialog,
          matching: find.text('Sugestão: não.'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: checksDialog,
          matching: find.text('Sugestão: só no quadro.'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('spec-approve-suggestion-P4')),
        findsNothing,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('spec-approve-warnings')))
            .data,
        'Há também 1 aviso de estrutura: R2 sem critério de aceite.',
      );
      expect(
        find.descendant(of: checksDialog, matching: find.text('Cancelar')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: checksDialog, matching: find.text('Esc')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: checksDialog,
          matching: find.text('Aprovar com as sugestões'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: checksDialog,
          matching: find.text('Responder perguntas'),
        ),
        findsOneWidget,
      );
      expect(find.text('Refinar com IA'), findsOneWidget); // the header's
      expect(
        find.descendant(
          of: checksDialog,
          matching: find.text('Refinar com IA'),
        ),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('spec-approve-refine')), findsNothing);
      expect(
        find.byKey(const ValueKey('spec-approve-show-warnings')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('spec-approve-answer')));
      final panel = find.byKey(const ValueKey('spec-questions-panel'));
      await settleIo(tester, until: () => panel.evaluate().isNotEmpty);
      expect(panel, findsOneWidget);
      expect(find.byKey(const ValueKey('spec-no-design-dialog')), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('spec-questions-subtitle')))
            .data,
        'SPEC-002 · Sessões com stream-json · pergunta 1 de 4',
      );
      expect(readSpec(tmp), contains('3. E no terminal?'));
    });

    testWidgets('R8, R9: the warnings strip follows the editor without '
        'saving; a warning puts the cursor on its line; saving and approving '
        'stay available', (tester) async {
      await pump(tester, const Size(1440, 900));
      final count = find.byKey(const ValueKey('spec-warnings-count'));
      // sample: R1–R3 without "deve" and without a criterion.
      expect(tester.widget<Text>(count).data, '6 avisos de estrutura');
      expect(find.byKey(const ValueKey('spec-warnings-list')), findsNothing);
      final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
      editor.controller!.text = sample.replaceFirst(
        'R1 · Cada sessão roda em um worktree',
        'R1 · Quando a sessão abrir, o sistema deve usar um worktree',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.widget<Text>(count).data, '5 avisos de estrutura');
      expect(readSpec(tmp), sample);

      await tester.tap(find.byKey(const ValueKey('spec-warnings-toggle')));
      await tester.pump();
      expect(find.byKey(const ValueKey('spec-warnings-list')), findsOneWidget);
      expect(find.text('R3 sem "deve" (fora do estilo EARS)'), findsOneWidget);
      await tester.ensureVisible(
        find.text('R3 sem "deve" (fora do estilo EARS)'),
      );
      await tester.pump();
      await tester.tap(find.text('R3 sem "deve" (fora do estilo EARS)'));
      await tester.pump();
      await tester.pump();
      // Line 13 of the file (1-based) = index 12.
      expect(editor.controller!.selection.baseIndex, 12);
      expect(editor.controller!.selection.isCollapsed, isTrue);
      expect(
        tester
            .widget<SmallButton>(find.byKey(const ValueKey('spec-save')))
            .onTap,
        isNotNull,
      );
      expect(
        tester
            .widget<SpecActionButton>(
              find.byKey(const ValueKey('spec-approve')),
            )
            .onTap,
        isNotNull,
      );
      // The editor took the focus: its cursor blinks until it loses it.
      expect(focusedIn(find.byType(CodeEditor)), isTrue);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('R10: with warnings the dialog shows the count and "Ver '
        'avisos" opens the list', (tester) async {
      await pump(tester, const Size(1440, 900));
      await tapApprove(tester, checksDialog);
      expect(find.text('A spec tem 6 avisos de estrutura'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('spec-approve-show-warnings')),
      );
      await settleIo(tester, until: () => checksDialog.evaluate().isEmpty);
      expect(find.byKey(const ValueKey('spec-warnings-list')), findsOneWidget);
      expect(find.byKey(const ValueKey('spec-no-design-dialog')), findsNothing);
      expect(readSpec(tmp), sample);
    });

    testWidgets('R14: the strip and its warnings take the focus by Tab and '
        'act on Enter, with labels; the dialog buttons too', (tester) async {
      await pump(tester, const Size(1440, 900));
      final semantics = tester.ensureSemantics();
      final toggle = find.byKey(const ValueKey('spec-warnings-toggle'));
      expect(
        find.bySemanticsLabel('6 avisos de estrutura. Mostrar a lista'),
        findsOneWidget,
      );
      expect(await tabTo(tester, toggle), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.byKey(const ValueKey('spec-warnings-list')), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Linha 11: R1 sem critério de aceite. Ir para a linha',
        ),
        findsOneWidget,
      );
      final first = find.byKey(const ValueKey('spec-warning-0'));
      expect(await tabTo(tester, first), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
      expect(editor.controller!.selection.baseIndex, 10);

      await tapApprove(tester, checksDialog);
      // The dialog opens on Cancelar; Tab reaches the others.
      final cancel = find.byKey(const ValueKey('spec-approve-checks-cancel'));
      expect(focusedIn(cancel), isTrue);
      final anyway = find.byKey(const ValueKey('spec-approve-anyway'));
      expect(await tabTo(tester, anyway), isTrue);
      expect(find.bySemanticsLabel('Aprovar mesmo assim'), findsOneWidget);
      expect(find.bySemanticsLabel('Ver avisos'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      final design = find.byKey(const ValueKey('spec-no-design-dialog'));
      await settleIo(tester, until: () => design.evaluate().isNotEmpty);
      expect(design, findsOneWidget);
      semantics.dispose();
    });
  });

  group('SPEC-025 R7', () {
    Finder key(String k) => find.byKey(ValueKey(k));
    FakeDesigner? designer;

    Future<ProviderContainer> pumpDesign(WidgetTester tester) async {
      designer = null;
      File('${tmp.path}/specs/SPEC-003-outra.md').writeAsStringSync(otherSpec);
      final c = await pump(
        tester,
        const Size(1920, 1000),
        overrides: [
          specDesignerProvider.overrideWith(
            (ref) => designer ??= FakeDesigner(ref),
          ),
        ],
      );
      for (var i = 0; i < 5 && (designer?.calls.isEmpty ?? true); i++) {
        await tester.tap(key('spec-design'));
        await settleIo(
          tester,
          until: () => designer?.calls.isNotEmpty ?? false,
        );
      }
      expect(designer!.calls, hasLength(1));
      expect(key('spec-action-banner'), findsOneWidget);
      return c;
    }

    // The spinners never settle: dialogs get a fixed time.
    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    String editorText(WidgetTester tester) =>
        tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!.text;

    testWidgets('choosing another spec during "Planejar" asks first; '
        '"Continuar aqui" and Esc keep the spec; the other option cancels '
        'and opens the chosen one', (tester) async {
      await pumpDesign(tester);
      var cancelled = false;
      designer!.calls.single.cancelled!.then((_) => cancelled = true);
      final dialog = key('spec-leave-dialog');

      await tester.tap(key('spec-item-SPEC-003'));
      await settle(tester);
      expect(dialog, findsOneWidget);
      expect(find.text('Sair da SPEC-002 durante a geração?'), findsOneWidget);
      expect(
        find.text(
          'O plano ainda está sendo escrito. Se você abrir a SPEC-003 agora, '
          'a geração é cancelada e a SPEC-002 não muda.',
        ),
        findsOneWidget,
      );
      expect(find.text('Cancelar geração e abrir SPEC-003'), findsOneWidget);
      expect(find.text('Continuar aqui'), findsOneWidget);
      // "Continuar aqui" is the default (focused) button.
      expect(focusedIn(key('spec-leave-stay')), isTrue);
      await tester.tap(key('spec-leave-stay'));
      await settle(tester);
      expect(dialog, findsNothing);
      expect(cancelled, isFalse);
      expect(editorText(tester), sample);
      expect(key('spec-action-banner'), findsOneWidget);

      // Esc closes the dialog like "Continuar aqui": the generation goes on.
      await tester.tap(key('spec-item-SPEC-003'));
      await settle(tester);
      expect(dialog, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(dialog, findsNothing);
      expect(cancelled, isFalse);
      expect(key('spec-action-banner'), findsOneWidget);

      await tester.tap(key('spec-item-SPEC-003'));
      await settle(tester);
      await tester.tap(key('spec-leave-cancel-action'));
      await settleIo(tester, until: () => editorText(tester) == otherSpec);
      expect(cancelled, isTrue);
      expect(editorText(tester), otherSpec);
      expect(key('spec-action-banner'), findsNothing);
      // The late answer goes nowhere.
      designer!.next.complete('# resultado\n');
      await settleIo(tester);
      expect(editorText(tester), otherSpec);
      expect(readSpec(tmp), sample);
    });

    testWidgets('leaving the Specs section during the generation asks too', (
      tester,
    ) async {
      final c = await pumpDesign(tester);
      final nav = c.read(navigationProvider.notifier)..go(AppSection.specs);
      unawaited(nav.request(AppSection.tasks));
      await settle(tester);
      expect(find.text('Cancelar geração e abrir Quadro'), findsOneWidget);
      await tester.tap(key('spec-leave-stay'));
      await settle(tester);
      expect(c.read(navigationProvider), AppSection.specs);
      expect(key('spec-action-banner'), findsOneWidget);
      unawaited(nav.request(AppSection.tasks));
      await settle(tester);
      await tester.tap(key('spec-leave-cancel-action'));
      await settleIo(tester);
      expect(c.read(navigationProvider), AppSection.tasks);
      expect(c.read(specActionProvider), isNull);
    });
  });

  testWidgets('SPEC-027 R5: deleting the approved screen warns, removes its '
      'line from "## Protótipo" without changing the status; with unsaved '
      'edits the editor loses the line too and stays unsaved; "Desfazer" '
      'puts the line back', (tester) async {
    const line = '- R1 → docs/mockups/spec-002/R1-sessoes.html';
    File('${tmp.path}/specs/SPEC-002-sessoes.md')
        .writeAsStringSync('${sample.trimRight()}\n\n## Protótipo\n\n$line\n');
    final mockups = '${tmp.path}/docs/mockups/spec-002';
    Directory(mockups).createSync(recursive: true);
    File('$mockups/R1-sessoes.html').writeAsStringSync('<p>A</p>');
    File('$mockups/R1-sessoes.b.html').writeAsStringSync('<p>B</p>');
    final browser = FakeBrowser();
    await pump(
      tester,
      const Size(1440, 900),
      overrides: [
        prototypeWatchProvider.overrideWithValue(false),
        processRunnerProvider.overrideWithValue(browser.run),
        prototypeCacheDirProvider.overrideWithValue('${tmp.path}/cache'),
      ],
    );
    // Unsaved edit.
    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    editor.controller!.text = editor.controller!.text.replaceFirst(
      '# Sessões com stream-json',
      '# Sessões revisadas',
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('spec-unsaved')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('spec-mode-prototype')));
    await settleIo(
      tester,
      until: () => find
          .byKey(const ValueKey('proto-card-R1-sessoes.html'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.tap(find.byKey(const ValueKey('proto-tab-versions')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('proto-remove-R1-sessoes.html')),
    );
    await tester.pump();
    expect(
      find.text(
        'Esta é a tela aprovada do R1. A linha dela também sai da seção '
        'Protótipo da spec, e o R1 fica sem tela aprovada.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('proto-remove-confirm')));
    await settleIo(
      tester,
      until: () =>
          !readSpec(tmp).contains(line) &&
          !editor.controller!.text.contains(line),
    );
    final disk = readSpec(tmp);
    expect(disk, isNot(contains(line)));
    expect(disk, contains('status: em-revisao'));
    expect(disk, contains('# Sessões com stream-json'));
    expect(File('$mockups/R1-sessoes.html').existsSync(), isFalse);
    final text = editor.controller!.text;
    expect(text, isNot(contains(line)));
    expect(text, contains('# Sessões revisadas'));
    expect(text, contains('status: em-revisao'));
    expect(find.byKey(const ValueKey('spec-unsaved')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('proto-undo')));
    await settleIo(
      tester,
      until: () =>
          readSpec(tmp).contains(line) &&
          editor.controller!.text.contains(line),
    );
    expect(File('$mockups/R1-sessoes.html').readAsStringSync(), '<p>A</p>');
    expect(editor.controller!.text, contains(line));
    expect(editor.controller!.text, contains('# Sessões revisadas'));
    expect(find.byKey(const ValueKey('spec-unsaved')), findsOneWidget);
  });
}
