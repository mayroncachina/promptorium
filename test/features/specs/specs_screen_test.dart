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
import 'package:promptorium/features/specs/specs_screen.dart';
import 'package:promptorium/features/specs/workspace_watcher.dart';
import 'package:promptorium/features/board/widgets/spec_steps_panel.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:re_editor/re_editor.dart' show CodeEditor;

import '../../helpers/test_db.dart';
import '../prompt/prompt_test_utils.dart' show SilentConversationManager;
import '../sessions/session_test_utils.dart';
import 'spec_file_test.dart' show sample;

/// Real file IO does not run under FakeAsync: let it run, then pump, until
/// [until] holds (up to 15 s of real time: the full suite runs files in
/// parallel).
Future<void> settleIo(WidgetTester tester, {bool Function()? until}) async {
  final end = DateTime.now().add(const Duration(seconds: 15));
  for (var i = 0; DateTime.now().isBefore(end); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
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

/// A spec without structure warnings, with two open questions and no Design.
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

1. Vale para o quadro?
2. E no grafo?
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
    expect(find.text('A spec não tem seção Design.'), findsOneWidget);
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
    expect(find.text('Aprovar spec'), findsOneWidget);
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

  testWidgets('editing marks "não salvo"; Salvar writes the file', (
    tester,
  ) async {
    await pump(tester, const Size(1440, 900));
    final editor = tester.widget<CodeEditor>(find.byType(CodeEditor));
    editor.controller!.text = sample.replaceFirst(
      '# Sessões com stream-json',
      '# Sessões revisadas',
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('spec-unsaved')), findsOneWidget);
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

    testWidgets('R6, R7: open questions come before the Design dialog; '
        'Cancelar keeps the file; "Aprovar assumindo premissas" moves them '
        'to Premissas with the date and approves', (tester) async {
      writeSpec(questionsSpec);
      await pump(tester, const Size(1440, 900));
      await tapApprove(tester, checksDialog);
      expect(find.text('A spec tem 2 perguntas em aberto'), findsOneWidget);
      expect(find.text('1. Vale para o quadro?'), findsOneWidget);
      expect(find.text('2. E no grafo?'), findsOneWidget);
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
          '- (sem resposta, aceita em $day) Vale para o quadro?\n'
          '- (sem resposta, aceita em $day) E no grafo?\n\n'
          '## Critérios de aceite',
        ),
      );
      expect(saved, endsWith('## Perguntas em aberto\n'));
    });

    testWidgets('R6: "Refinar com IA" in the questions dialog opens the '
        'refine conversation of the spec', (tester) async {
      writeSpec(questionsSpec);
      final manager = SilentConversationManager();
      final c = await pump(
        tester,
        const Size(1440, 900),
        overrides: [conversationManagerProvider.overrideWith(() => manager)],
      );
      await tapApprove(tester, checksDialog);
      await tester.tap(find.byKey(const ValueKey('spec-approve-refine')));
      await settleIo(tester, until: () => manager.sent.isNotEmpty);
      final conv = await tester.runAsync(
        () => c.read(conversationsRepoProvider).getById(manager.sent.single.$1),
      );
      expect(conv!.mode, PromptMode.refine.name);
      expect(conv.refineSpecCode, 'SPEC-002');
      expect(manager.sent.single.$2, contains('"Perguntas em aberto"'));
      expect(readSpec(tmp), questionsSpec);
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
            .widget<SmallButton>(find.byKey(const ValueKey('spec-approve')))
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
}
