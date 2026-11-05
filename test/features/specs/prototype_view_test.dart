import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/process/process_runner.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/specs/prototype/prototype_delete.dart';
import 'package:promptorium/features/specs/prototype/prototype_files.dart';
import 'package:promptorium/features/specs/prototype/prototype_service.dart';
import 'package:promptorium/features/specs/prototype/prototype_thumbnails.dart';
import 'package:promptorium/features/specs/prototype/prototype_view.dart';
import 'package:promptorium/features/specs/spec_action.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/core/claude/readonly_run.dart'
    show PlannerException;
import 'package:promptorium/features/specs/specs_screen.dart';
import 'package:promptorium/features/specs/widgets/spec_header.dart'
    show SpecActionButton, SpecActionEmphasis;
import 'package:promptorium/features/specs/workspace_watcher.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:re_editor/re_editor.dart' show CodeEditor;

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';
import 'prototype_files_test.dart' show spec;
import 'prototype_thumbnails_test.dart' show FakeBrowser;
import 'specs_screen_test.dart' show QuietWorkspaceWatcher, settleIo;

/// Fake browser that also records `xdg-open`.
class Runner extends FakeBrowser {
  Runner({super.installed});

  final opened = <String>[];

  @override
  Future<ProcessResult> run(String exe, List<String> args) async {
    if (exe == 'xdg-open') {
      opened.add(args.single);
      return ProcessResult(1, 0, '', '');
    }
    return super.run(exe, args);
  }
}

void main() {
  late Directory tmp;
  late String mockups;
  late Runner runner;
  late List<String> prompts;
  late void Function() agentWrites;
  late Future<void> Function(Future<void>? cancelled) agentWait;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('promptorium-proto-ui-');
    Directory('${tmp.path}/specs').createSync();
    File('${tmp.path}/specs/SPEC-022-prototipo.md').writeAsStringSync(spec);
    mockups = '${tmp.path}/docs/mockups/spec-022';
    Directory(mockups).createSync(recursive: true);
    File('$mockups/R1-lista.html').writeAsStringSync('<p>A</p>');
    File('$mockups/R2-detalhe.html').writeAsStringSync('<p>D</p>');
    runner = Runner();
    prompts = [];
    agentWrites = () {};
    agentWait = (_) async {};
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  String specFile() =>
      File('${tmp.path}/specs/SPEC-022-prototipo.md').readAsStringSync();

  Future<ProviderContainer> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = memoryDatabase();
    final c = ProviderContainer(
      overrides: [
        ...sessionOverrides(db: db, cli: FakeCli(), notifier: FakeNotifier()),
        workspaceWatcherProvider.overrideWith(QuietWorkspaceWatcher.new),
        prototypeWatchProvider.overrideWithValue(false),
        processRunnerProvider.overrideWithValue(runner.run),
        prototypeCacheDirProvider.overrideWithValue('${tmp.path}/cache'),
        prototypeAgentProvider.overrideWithValue(({
          required cwd,
          required options,
          required prompt,
          cancelled,
        }) async {
          prompts.add(prompt);
          agentWrites();
          await agentWait(cancelled);
          return {
            'telas': [
              {
                'arquivo': 'R1-lista.b.html',
                'requisito': 'R1',
                'descricao': 'busca e filtros',
              },
            ],
            'resposta': 'Variação criada.',
          };
        }),
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
      until: () => find.byType(CodeEditor).evaluate().isNotEmpty,
    );
    return c;
  }

  Future<void> openPrototype(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('spec-mode-prototype')));
    await settleIo(
      tester,
      until: () => find
          .byKey(const ValueKey('proto-card-R2-detalhe.html'))
          .evaluate()
          .isNotEmpty,
    );
  }

  Future<void> tapCard(WidgetTester tester, String file) async {
    await tester.tap(find.byKey(ValueKey('proto-card-$file')));
    // onDoubleTap is set: the single tap is decided after the timeout.
    await tester.pump(const Duration(milliseconds: 400));
  }

  // The header actions are SpecActionButton (SPEC-024); the panel keeps
  // ProtoButton.
  Finder cardText(String file, String text) => find.descendant(
    of: find.byKey(ValueKey('proto-card-$file')),
    matching: find.text(text),
  );

  bool enabled(WidgetTester tester, String key) =>
      switch (tester.widget(find.byKey(ValueKey(key)))) {
        final SpecActionButton b => b.onTap != null,
        final ProtoButton b => b.onTap != null,
        _ => throw StateError('$key não é um botão'),
      };

  testWidgets('R1 R3: the Protótipo mode shows the canvas with one labelled '
      'screen per file and the panel; a screen being generated is marked', (
    tester,
  ) async {
    final c = await pump(tester);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('spec-mode-prototype')),
        matching: find.text('Protótipo'),
      ),
      findsOneWidget,
    );
    await openPrototype(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(CodeEditor), findsNothing);
    expect(
      find.text('docs/mockups/spec-022/ · 2 telas · salvo'),
      findsOneWidget,
    );
    expect(cardText('R1-lista.html', 'Lista'), findsOneWidget);
    expect(cardText('R2-detalhe.html', 'Detalhe'), findsOneWidget);
    expect(find.byKey(const ValueKey('proto-tab-ask')), findsOneWidget);
    expect(find.byKey(const ValueKey('proto-tab-versions')), findsOneWidget);
    expect(find.text('Comentários'), findsNothing);
    expect(find.byKey(const ValueKey('proto-generate')), findsOneWidget);
    expect(find.byKey(const ValueKey('spec-save')), findsNothing);
    // SPEC-024 R6: "Gerar telas da spec" primary, "Comparar variações"
    // secondary.
    SpecActionEmphasis emphasis(String key) => tester
        .widget<SpecActionButton>(find.byKey(ValueKey(key)))
        .action
        .emphasis;
    expect(emphasis('proto-generate'), SpecActionEmphasis.primary);
    expect(emphasis('proto-compare'), SpecActionEmphasis.secondary);
    expect(
      tester.getCenter(find.byKey(const ValueKey('proto-compare'))).dx,
      lessThan(
        tester.getCenter(find.byKey(const ValueKey('proto-generate'))).dx,
      ),
    );
    // Zoom.
    expect(find.text('80%'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('proto-zoom-in')));
    await tester.pump();
    expect(find.text('90%'), findsOneWidget);

    final specId =
        c.read(selectedSpecProvider) ??
        (await tester.runAsync(
          () => c.read(specsRepoProvider).watchByWorkspace(1).first,
        ))!.single.id;
    c
        .read(prototypeJobsProvider.notifier)
        .start(
          specId,
          const PrototypeJob(
            requirements: ['R1'],
            targets: ['R1-lista.b.html'],
          ),
        );
    await tester.pump();
    expect(find.text('Gerando variação B de R1…'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('proto-generating-R1-lista.b.html')),
      findsOneWidget,
    );
    expect(find.textContaining('· gerando…'), findsOneWidget);
    expect(enabled(tester, 'proto-generate'), isFalse);
    c.read(prototypeJobsProvider.notifier).finish(specId);
    await tester.pump();
    expect(find.text('Gerando variação B de R1…'), findsNothing);
  });

  testWidgets('R4: with a browser the cards show the generated thumbnail', (
    tester,
  ) async {
    await pump(tester);
    await openPrototype(tester);
    await settleIo(
      tester,
      until: () => find
          .byKey(const ValueKey('proto-thumb-R2-detalhe.html'))
          .evaluate()
          .isNotEmpty,
    );
    expect(
      find.byKey(const ValueKey('proto-thumb-R1-lista.html')),
      findsOneWidget,
    );
    expect(runner.calls.first, contains('--window-size=1440,900'));
    expect(
      find.byKey(const ValueKey('proto-open-R1-lista.html')),
      findsNothing,
    );
  });

  testWidgets('R5 R6: without a headless browser the card offers "Abrir no '
      'navegador" (xdg-open) and the hint shows only once', (tester) async {
    runner = Runner(installed: false);
    await pump(tester);
    await openPrototype(tester);
    await settleIo(
      tester,
      until: () => find
          .byKey(const ValueKey('proto-open-R1-lista.html'))
          .evaluate()
          .isNotEmpty,
    );
    expect(find.text('R1-lista.html'), findsOneWidget);
    await tester.pump();
    expect(find.text(headlessInstallHint), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('proto-open-R1-lista.html')));
    await settleIo(tester, until: () => runner.opened.isNotEmpty);
    expect(runner.opened, ['$mockups/R1-lista.html']);
    // Double click on a card opens it too (R6).
    await tester.tap(find.byKey(const ValueKey('proto-card-R2-detalhe.html')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const ValueKey('proto-card-R2-detalhe.html')));
    await settleIo(tester, until: () => runner.opened.length == 2);
    expect(runner.opened.last, '$mockups/R2-detalhe.html');

    // Let the snack go, leave and come back: no second hint.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(headlessInstallHint), findsNothing);
    await tester.tap(find.byKey(const ValueKey('spec-mode-preview')));
    await tester.pump();
    await openPrototype(tester);
    await settleIo(tester);
    expect(find.text(headlessInstallHint), findsNothing);
  });

  testWidgets('R7: "Enviar" with R1 selected creates R1-lista.b.html and '
      'keeps the original; the history shows the answer and the file chip', (
    tester,
  ) async {
    await pump(tester);
    await openPrototype(tester);
    expect(enabled(tester, 'proto-send'), isFalse);
    await tapCard(tester, 'R1-lista.html');
    expect(find.text('Selecionada: R1'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('proto-request')),
      'mais denso',
    );
    await tester.pump();
    agentWrites = () =>
        File('$mockups/R1-lista.b.html').writeAsStringSync('<p>B</p>');
    await tester.tap(find.byKey(const ValueKey('proto-send')));
    await settleIo(
      tester,
      until: () => find
          .byKey(const ValueKey('proto-card-R1-lista.b.html'))
          .evaluate()
          .isNotEmpty,
    );
    expect(prompts.single, contains('mais denso'));
    expect(
      prompts.single,
      contains('novo `docs/mockups/spec-022/R1-lista.b.html`'),
    );
    expect(File('$mockups/R1-lista.html').readAsStringSync(), '<p>A</p>');
    expect(cardText('R1-lista.b.html', 'B'), findsOneWidget);
    expect(find.textContaining('Variação criada.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('proto-chip-R1-lista.b.html')),
      findsOneWidget,
    );
  });

  testWidgets('R8 R9: "Comparar variações" is disabled with one variation; '
      'with two it shows both side by side and approving writes '
      '"## Protótipo" without changing the status', (tester) async {
    await pump(tester);
    await openPrototype(tester);
    await tapCard(tester, 'R1-lista.html');
    expect(enabled(tester, 'proto-compare'), isFalse);

    await tester.runAsync(() async {
      File('$mockups/R1-lista.b.html').writeAsStringSync('<p>B</p>');
      await PrototypeIndex(
        screens: {
          'R1-lista.b.html': ScreenMeta(
            description: 'busca e filtros',
            createdAt: DateTime(2026, 10, 24, 10, 41),
          ),
        },
      ).write(mockups);
    });
    // The real app sees it through the folder watcher.
    final ws = (root: tmp.path, code: 'SPEC-022');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SpecsScreen)),
    );
    await tester.runAsync(
      () => container.read(prototypeScreensProvider(ws).notifier).reload(),
    );
    await tester.pump();
    expect(enabled(tester, 'proto-compare'), isTrue);
    await tester.tap(find.byKey(const ValueKey('proto-compare')));
    await settleIo(tester);
    expect(find.text('SPEC-022 · R1 · Lista'), findsOneWidget);
    expect(find.text('Variação A'), findsOneWidget);
    expect(find.text('Variação B'), findsOneWidget);
    expect(find.text('busca e filtros · 10:41'), findsOneWidget);
    final a = tester.getTopLeft(
      find.byKey(const ValueKey('proto-variation-R1-lista.html')),
    );
    final b = tester.getTopLeft(
      find.byKey(const ValueKey('proto-variation-R1-lista.b.html')),
    );
    expect(a.dy, b.dy); // side by side
    expect(b.dx, greaterThan(a.dx));
    // A is the selected one: "escolhida".
    expect(find.byKey(const ValueKey('proto-chosen')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('proto-use-R1-lista.b.html')),
      findsOneWidget,
    );
    expect(find.textContaining('o gate não muda'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('proto-size-1100')));
    // The 1100×700 thumbnail is rendered asynchronously; under the full
    // suite's load it can take longer than a fixed settle.
    await settleIo(
      tester,
      until: () =>
          runner.calls.any((c) => c.contains('--window-size=1100,700')),
    );
    expect(
      runner.calls.any((c) => c.contains('--window-size=1100,700')),
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('proto-approve')));
    await settleIo(tester, until: () => specFile().contains('## Protótipo'));
    expect(specFile(), contains('- R1 → docs/mockups/spec-022/R1-lista.html'));

    await tester.tap(find.byKey(const ValueKey('proto-use-R1-lista.b.html')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('proto-approve')));
    await settleIo(tester, until: () => specFile().contains('R1-lista.b.html'));
    final text = specFile();
    expect(text, contains('- R1 → docs/mockups/spec-022/R1-lista.b.html'));
    expect(text, isNot(contains('R1-lista.html')));
    expect('## Protótipo'.allMatches(text), hasLength(1));
    expect(text, contains('status: em-revisao'));
    expect(find.byKey(const ValueKey('spec-unsaved')), findsNothing);

    // "Ver na spec" goes to the preview.
    await tester.tap(find.byKey(const ValueKey('proto-view-spec')));
    await tester.pump();
    expect(find.byKey(const ValueKey('spec-preview')), findsOneWidget);
  });

  testWidgets('R11: "Versões" lists the variations, marks the approved one '
      'and removes one that is not approved (SPEC-027 R9: the approved one '
      'has a trash button too)', (tester) async {
    File('${tmp.path}/specs/SPEC-022-prototipo.md').writeAsStringSync(
      '${spec.trimRight()}\n\n## Protótipo\n\n'
      '- R1 → docs/mockups/spec-022/R1-lista.html\n',
    );
    File('$mockups/R1-lista.b.html').writeAsStringSync('<p>B</p>');
    await pump(tester);
    await openPrototype(tester);
    await tester.tap(find.byKey(const ValueKey('proto-tab-versions')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('proto-version-R1-lista.b.html')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('proto-approved-R1-lista.html')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('proto-remove-R1-lista.html')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('proto-remove-R1-lista.b.html')),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('proto-remove-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('proto-remove-confirm')));
    await settleIo(
      tester,
      until: () => find
          .byKey(const ValueKey('proto-version-R1-lista.b.html'))
          .evaluate()
          .isEmpty,
    );
    expect(File('$mockups/R1-lista.b.html').existsSync(), isFalse);
    expect(File('$mockups/R1-lista.html').existsSync(), isTrue);
  });

  testWidgets('SPEC-025 R9: while "Gerar telas da spec" runs, its card shows '
      'the elapsed time and "Cancelar geração"; cancelling stops the agent '
      'and releases the spec', (tester) async {
    var stopped = false;
    agentWait = (cancelled) async {
      await cancelled;
      stopped = true;
      throw const PlannerException('Verificação cancelada.');
    };
    final c = await pump(tester);
    await openPrototype(tester);
    await tester.tap(find.byKey(const ValueKey('proto-generate')));
    await settleIo(tester, until: () => prompts.isNotEmpty);
    await tester.pump(const Duration(milliseconds: 400));
    final card = find.byKey(const ValueKey('proto-generating-spec'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('Gerando telas da spec…')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.byKey(const ValueKey('spec-action-elapsed')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Cancelar geração')),
      findsOneWidget,
    );
    expect(
      find.text('A spec fica bloqueada até as telas ficarem prontas.'),
      findsOneWidget,
    );
    expect(find.text('Bloqueada: gerando as telas'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('proto-generate')),
        matching: find.text('Gerando telas…'),
      ),
      findsOneWidget,
    );
    expect(enabled(tester, 'proto-compare'), isFalse);
    // R1 in the other tabs: the editor is read-only meanwhile.
    await tester.tap(find.byKey(const ValueKey('spec-mode-edit')));
    await tester.pump();
    expect(tester.widget<CodeEditor>(find.byType(CodeEditor)).readOnly, true);
    expect(find.byKey(const ValueKey('spec-action-banner')), findsOneWidget);
    expect(find.text('Gerando as telas de SPEC-022…'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('spec-mode-prototype')));
    await tester.pump();

    await tester.tap(
      find.descendant(
        of: card,
        matching: find.byKey(const ValueKey('spec-action-cancel')),
      ),
    );
    // The notice lasts 4 s of test time: on a busy machine it can come and go
    // before the rest settles, so remember that it showed.
    var noticed = false;
    await settleIo(
      tester,
      until: () {
        noticed =
            noticed ||
            find
                .text('Geração cancelada. A spec não foi alterada.')
                .evaluate()
                .isNotEmpty;
        return stopped &&
            c.read(prototypeJobsProvider).isEmpty &&
            card.evaluate().isEmpty &&
            noticed;
      },
    );
    expect(stopped, isTrue);
    expect(card, findsNothing);
    expect(c.read(specActionProvider), isNull);
    expect(noticed, isTrue);
    expect(specFile(), spec);
  });

  testWidgets('R12: the controls take focus with Tab, act on Enter / Space '
      'and have accessible labels', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);

    bool focusedIn(Finder f) {
      final node = FocusManager.instance.primaryFocus;
      final ctx = node?.context;
      if (ctx == null) return false;
      final target = f.evaluate().single;
      var hit = false;
      ctx.visitAncestorElements((e) {
        if (e == target) hit = true;
        return !hit;
      });
      return hit || ctx == target;
    }

    Future<void> tabTo(Finder f) async {
      for (var i = 0; i < 80 && !focusedIn(f); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(focusedIn(f), isTrue, reason: 'Tab não chegou em $f');
    }

    expect(find.bySemanticsLabel('Modo Protótipo'), findsOneWidget);
    await tabTo(find.byKey(const ValueKey('spec-mode-prototype')));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settleIo(
      tester,
      until: () => find
          .byKey(const ValueKey('proto-card-R1-lista.html'))
          .evaluate()
          .isNotEmpty,
    );
    expect(find.byType(CodeEditor), findsNothing);

    for (final label in [
      'Gerar telas da spec',
      'Comparar variações',
      'Enviar pedido ao Claude',
      'Tela R1, Lista, variação A',
      'Pedir ao Claude',
      'Versões',
      'Aumentar zoom do protótipo',
    ]) {
      expect(
        find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}')),
        findsWidgets,
        reason: label,
      );
    }

    // A card is selected from the keyboard.
    await tabTo(find.byKey(const ValueKey('proto-card-R1-lista.html')));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Selecionada: R1'), findsOneWidget);

    // "Gerar telas da spec" runs with Space.
    await tabTo(find.byKey(const ValueKey('proto-generate')));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await settleIo(tester, until: () => prompts.isNotEmpty);
    expect(prompts.single, contains('Gere as telas da spec SPEC-022'));
    semantics.dispose();
  });

  // --- SPEC-027 ------------------------------------------------------------

  Finder key(String k) => find.byKey(ValueKey(k));

  /// Lists the folder again (the real app has the folder watcher); the
  /// thumbnails run in the test zone, so this is not awaited in runAsync.
  Future<void> reloadScreens(WidgetTester tester, String until) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SpecsScreen)),
    );
    unawaited(
      container
          .read(
            prototypeScreensProvider((root: tmp.path, code: 'SPEC-022'))
                .notifier,
          )
          .refresh(),
    );
    await settleIo(
      tester,
      until: () => key('proto-card-$until').evaluate().isNotEmpty,
    );
  }

  Future<void> ctrlTap(WidgetTester tester, String file) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(key('proto-card-$file'));
    // onDoubleTap is set: the tap is decided after the timeout.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  bool focusedIn(Finder f) {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    final target = f.evaluate().single;
    var hit = ctx == target;
    ctx.visitAncestorElements((e) {
      if (e == target) hit = true;
      return !hit;
    });
    return hit;
  }

  testWidgets('SPEC-027 R1 R1a: the label shows requirement, title and the '
      'variation badge (A too), "Aprovada" outside the thumbnail; "Mais '
      'ações da tela" shows on hover, focus or selection, with its menu', (
    tester,
  ) async {
    File('${tmp.path}/specs/SPEC-022-prototipo.md').writeAsStringSync(
      '${spec.trimRight()}\n\n## Protótipo\n\n'
      '- R1 → docs/mockups/spec-022/R1-lista.html\n',
    );
    final semantics = tester.ensureSemantics();
    await pump(tester);
    await openPrototype(tester);
    expect(cardText('R1-lista.html', 'R1'), findsOneWidget);
    expect(cardText('R1-lista.html', 'Lista'), findsOneWidget);
    expect(
      find.descendant(
        of: key('proto-letter-R1-lista.html'),
        matching: find.text('A'),
      ),
      findsOneWidget,
    );
    expect(key('proto-card-approved-R1-lista.html'), findsOneWidget);
    expect(key('proto-card-approved-R2-detalhe.html'), findsNothing);
    expect(
      find.descendant(
        of: key('proto-frame-R1-lista.html'),
        matching: key('proto-card-approved-R1-lista.html'),
      ),
      findsNothing,
    );
    expect(find.text('Aprovada'), findsOneWidget);

    // Hidden at rest.
    expect(key('proto-more-R1-lista.html'), findsNothing);
    // Hover.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(key('proto-card-R2-detalhe.html')));
    await tester.pump();
    expect(key('proto-more-R2-detalhe.html'), findsOneWidget);
    await mouse.moveTo(const Offset(5, 5));
    await tester.pump();
    expect(key('proto-more-R2-detalhe.html'), findsNothing);
    // Selected: always visible.
    await tapCard(tester, 'R1-lista.html');
    await mouse.moveTo(const Offset(5, 5));
    await tester.pump();
    expect(key('proto-more-R1-lista.html'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Mais ações da tela R1, Lista, variação A'),
      findsOneWidget,
    );
    // Focus (keyboard) on a card that is not selected.
    final r2 = find.descendant(
      of: key('proto-card-R2-detalhe.html'),
      matching: find.byType(InkWell),
    );
    tester
        .widget<Focus>(
          find.descendant(of: r2.first, matching: find.byType(Focus)).first,
        )
        .focusNode!
        .requestFocus();
    await tester.pump();
    expect(key('proto-more-R2-detalhe.html'), findsOneWidget);

    // The menu.
    await tester.tap(key('proto-more-R1-lista.html'));
    await tester.pump();
    expect(find.text('Abrir no navegador'), findsOneWidget);
    expect(find.text('Pedir variação'), findsOneWidget);
    expect(find.text('Apagar tela…'), findsOneWidget);
    expect(key('proto-menu-divider'), findsOneWidget);
    expect(
      find.descendant(of: key('proto-menu-delete'), matching: find.text('Del')),
      findsOneWidget,
    );
    await tester.tap(key('proto-menu-open'));
    await settleIo(tester, until: () => runner.opened.isNotEmpty);
    expect(runner.opened, ['$mockups/R1-lista.html']);
    // "Pedir variação" selects the screen and focuses the request field.
    await tester.tap(key('proto-more-R1-lista.html'));
    await tester.pump();
    await tester.tap(key('proto-menu-ask'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Selecionada: R1'), findsOneWidget);
    expect(focusedIn(key('proto-request')), isTrue);
    semantics.dispose();
  });

  testWidgets('SPEC-027 R2 R4: Delete with a selected card opens the '
      'confirmation; it shows thumbnail, file and folder, starts on '
      '"Cancelar" and deletes nothing when cancelled', (tester) async {
    await pump(tester);
    await openPrototype(tester);
    await tapCard(tester, 'R2-detalhe.html');
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(key('proto-remove-dialog'), findsOneWidget);
    expect(find.text('Apagar a tela R2, Detalhe, variação A?'), findsOneWidget);
    expect(key('proto-remove-thumb-R2-detalhe.html'), findsOneWidget);
    final files = tester
        .widget<RichText>(
          find.descendant(
            of: key('proto-remove-files'),
            matching: find.byType(RichText),
          ),
        )
        .text
        .toPlainText();
    expect(
      files,
      'O arquivo R2-detalhe.html sai da pasta docs/mockups/spec-022/.',
    );
    expect(
      find.text('Logo depois, dá para desfazer por alguns segundos.'),
      findsOneWidget,
    );
    expect(key('proto-remove-approved-R2'), findsNothing);
    expect(
      find.descendant(
        of: key('proto-remove-confirm'),
        matching: find.text('Apagar tela'),
      ),
      findsOneWidget,
    );
    expect(focusedIn(key('proto-remove-cancel')), isTrue);
    // Esc cancels.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleIo(tester);
    expect(key('proto-remove-dialog'), findsNothing);
    expect(File('$mockups/R2-detalhe.html').existsSync(), isTrue);
    expect(key('proto-undo-toast'), findsNothing);
    // "Cancelar" too.
    await tester.tap(key('proto-more-R2-detalhe.html'));
    await tester.pump();
    await tester.tap(key('proto-menu-delete'));
    await tester.pump();
    await tester.pump();
    expect(key('proto-remove-dialog'), findsOneWidget);
    await tester.tap(key('proto-remove-cancel'));
    await settleIo(tester);
    expect(File('$mockups/R2-detalhe.html').existsSync(), isTrue);
  });

  testWidgets('SPEC-027 R3: with two screens selected the bar shows "2 telas '
      'selecionadas" and "Apagar 2 telas…", the cards a checkbox, and Esc '
      'clears the selection', (tester) async {
    await pump(tester);
    await openPrototype(tester);
    await tapCard(tester, 'R1-lista.html');
    expect(key('proto-selection-bar'), findsNothing);
    expect(key('proto-check-R1-lista.html'), findsNothing);
    await ctrlTap(tester, 'R2-detalhe.html');
    expect(key('proto-selection-bar'), findsOneWidget);
    expect(find.text('2 telas selecionadas'), findsOneWidget);
    expect(find.text('Apagar 2 telas…'), findsOneWidget);
    expect(
      tester.widget<Icon>(key('proto-check-R1-lista.html')).icon,
      Icons.check_box,
    );
    // No "Pedir variação" in the bar.
    expect(
      find.descendant(
        of: key('proto-selection-bar'),
        matching: find.textContaining('variação'),
      ),
      findsNothing,
    );
    await tester.tap(key('proto-selection-delete'));
    await tester.pump();
    expect(find.text('Apagar 2 telas?'), findsOneWidget);
    await tester.tap(key('proto-remove-cancel'));
    await settleIo(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(key('proto-selection-bar'), findsNothing);
    expect(find.text('Nenhuma tela selecionada'), findsOneWidget);
  });

  testWidgets('SPEC-027 R6: "Desfazer" within 10 s restores file and index; '
      'Ctrl+Z too; after 10 s the notice goes and the deletion stays', (
    tester,
  ) async {
    await tester.runAsync(
      () => PrototypeIndex(
        screens: {'R2-detalhe.html': const ScreenMeta(description: 'x')},
      ).write(mockups),
    );
    await pump(tester);
    await openPrototype(tester);
    Future<void> deleteR2() async {
      await tapCard(tester, 'R2-detalhe.html');
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      await tester.tap(key('proto-remove-confirm'));
      await settleIo(
        tester,
        until: () => key('proto-undo-toast').evaluate().isNotEmpty,
      );
      expect(File('$mockups/R2-detalhe.html').existsSync(), isFalse);
    }

    await deleteR2();
    expect(find.text('Tela R2, variação A, apagada.'), findsOneWidget);
    expect(
      find.descendant(of: key('proto-undo'), matching: find.text('Ctrl+Z')),
      findsOneWidget,
    );
    expect(
      (await tester.runAsync(() => PrototypeIndex.read(mockups)))!.screens
          .containsKey('R2-detalhe.html'),
      isFalse,
    );
    await tester.pump(const Duration(seconds: 9));
    await tester.tap(key('proto-undo'));
    await settleIo(
      tester,
      until: () => key('proto-card-R2-detalhe.html').evaluate().isNotEmpty,
    );
    expect(File('$mockups/R2-detalhe.html').readAsStringSync(), '<p>D</p>');
    expect(
      (await tester.runAsync(() => PrototypeIndex.read(mockups)))!
          .screens['R2-detalhe.html']!
          .description,
      'x',
    );
    expect(key('proto-undo-toast'), findsNothing);

    // Ctrl+Z (the focus went to the next card).
    await deleteR2();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settleIo(
      tester,
      until: () => File('$mockups/R2-detalhe.html').existsSync(),
    );
    expect(File('$mockups/R2-detalhe.html').existsSync(), isTrue);

    // After the window the deletion is final.
    await settleIo(
      tester,
      until: () => key('proto-card-R2-detalhe.html').evaluate().isNotEmpty,
    );
    await deleteR2();
    await tester.pump(prototypeUndoWindow);
    await tester.pump();
    expect(key('proto-undo-toast'), findsNothing);
    expect(File('$mockups/R2-detalhe.html').existsSync(), isFalse);
  });

  testWidgets('SPEC-027 R7: deleting the last screen of a requirement shows '
      'the empty slot with "Gerar tela do R1", which generates only R1', (
    tester,
  ) async {
    await pump(tester);
    await openPrototype(tester);
    await tapCard(tester, 'R1-lista.html');
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    await tester.tap(key('proto-remove-confirm'));
    await settleIo(
      tester,
      until: () => key('proto-empty-R1').evaluate().isNotEmpty,
    );
    expect(find.text('O R1 ficou sem tela.'), findsOneWidget);
    expect(find.text('Gerar tela do R1'), findsOneWidget);
    // Before R2 on the canvas.
    expect(
      tester.getTopLeft(key('proto-empty-R1')).dx,
      lessThan(tester.getTopLeft(key('proto-card-R2-detalhe.html')).dx),
    );
    // "Versões" says it too.
    await tester.tap(key('proto-tab-versions'));
    await tester.pump();
    expect(key('proto-version-empty-R1'), findsOneWidget);

    agentWrites = () =>
        File('$mockups/R1-lista.html').writeAsStringSync('<p>novo</p>');
    await tester.tap(key('proto-empty-generate-R1'));
    await settleIo(
      tester,
      until: () =>
          prompts.isNotEmpty && key('proto-empty-R1').evaluate().isEmpty,
    );
    expect(prompts.single, contains('Gere somente a tela de R1'));
    expect(key('proto-empty-R1'), findsNothing);
    expect(key('proto-card-R1-lista.html'), findsOneWidget);
  });

  testWidgets('SPEC-027 R8: during a generation deleting is disabled with '
      '"Aguarde a geração terminar"', (tester) async {
    final c = await pump(tester);
    await openPrototype(tester);
    await tapCard(tester, 'R1-lista.html');
    await ctrlTap(tester, 'R2-detalhe.html');
    final specId =
        c.read(selectedSpecProvider) ??
        (await tester.runAsync(
          () => c.read(specsRepoProvider).watchByWorkspace(1).first,
        ))!.single.id;
    c
        .read(prototypeJobsProvider.notifier)
        .start(specId, const PrototypeJob(requirements: []));
    await tester.pump();
    expect(
      tester.widget<OutlinedButton>(key('proto-selection-delete')).onPressed,
      isNull,
    );
    expect(find.byTooltip(deleteBusyHint), findsWidgets);
    await tester.tap(key('proto-more-R1-lista.html'));
    await tester.pump();
    expect(
      tester.widget<MenuItemButton>(key('proto-menu-delete')).onPressed,
      isNull,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    // Delete does nothing.
    await tapCard(tester, 'R1-lista.html');
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(key('proto-remove-dialog'), findsNothing);
    await tester.tap(key('proto-tab-versions'));
    await tester.pump();
    expect(
      tester
          .widget<Semantics>(
            find
                .ancestor(
                  of: key('proto-remove-R1-lista.html'),
                  matching: find.byType(Semantics),
                )
                .first,
          )
          .properties
          .enabled,
      isFalse,
    );
    c.read(prototypeJobsProvider.notifier).finish(specId);
    await tester.pump();
    expect(find.byTooltip(deleteBusyHint), findsNothing);
  });

  testWidgets('SPEC-027 R9: in "Versões" the approved variation is deleted '
      'through the same dialog, with the approval warning', (tester) async {
    File('${tmp.path}/specs/SPEC-022-prototipo.md').writeAsStringSync(
      '${spec.trimRight()}\n\n## Protótipo\n\n'
      '- R1 → docs/mockups/spec-022/R1-lista.html\n',
    );
    final semantics = tester.ensureSemantics();
    await pump(tester);
    await openPrototype(tester);
    await tester.tap(key('proto-tab-versions'));
    await tester.pump();
    expect(find.bySemanticsLabel('Apagar R2-detalhe.html'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp('^Apagar R1-lista.html, a variação aprovada'),
      ),
      findsOneWidget,
    );
    expect(
      find.byTooltip('Apagar esta variação tira a aprovação da spec'),
      findsOneWidget,
    );
    await tester.tap(key('proto-remove-R1-lista.html'));
    await tester.pump();
    expect(key('proto-remove-dialog'), findsOneWidget);
    expect(key('proto-remove-approved-R1'), findsOneWidget);
    await tester.tap(key('proto-remove-confirm'));
    await settleIo(
      tester,
      until: () =>
          !specFile().contains('R1-lista.html') &&
          key('proto-version-empty-R1').evaluate().isNotEmpty &&
          key('proto-undo-toast').evaluate().isNotEmpty,
    );
    expect(File('$mockups/R1-lista.html').existsSync(), isFalse);
    expect(specFile(), contains('status: em-revisao'));
    expect(
      find.text('Nenhuma tela. A aprovação saiu da spec.'),
      findsOneWidget,
    );
    expect(key('proto-undo-toast'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('SPEC-027 R10: after deleting, the screen leaves the selection '
      'and "Comparar variações", the focus goes to the next card and the '
      'screen reader hears it', (tester) async {
    final announced = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (msg) async {
        if (msg is Map && msg['type'] == 'announce') {
          announced.add('${(msg['data'] as Map)['message']}');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility,
            null,
          ),
    );
    File('$mockups/R1-lista.b.html').writeAsStringSync('<p>B</p>');
    File('$mockups/R1-lista.c.html').writeAsStringSync('<p>C</p>');
    await pump(tester);
    await openPrototype(tester);
    // Comparison of R1 open, on B.
    await tapCard(tester, 'R1-lista.b.html');
    await tester.tap(key('proto-compare'));
    await settleIo(tester);
    expect(key('proto-variation-R1-lista.b.html'), findsOneWidget);
    // Deleted from "Versões" while comparing.
    await tester.tap(key('proto-tab-versions'));
    await tester.pump();
    await tester.tap(key('proto-remove-R1-lista.b.html'));
    await tester.pump();
    await tester.tap(key('proto-remove-confirm'));
    await settleIo(
      tester,
      until: () => key('proto-variation-R1-lista.b.html').evaluate().isEmpty,
    );
    expect(key('proto-variation-R1-lista.html'), findsOneWidget);
    expect(key('proto-variation-R1-lista.c.html'), findsOneWidget);
    expect(announced, ['1 tela apagada']);
    await tester.tap(key('proto-compare-back'));
    await tester.pump();

    // Two selected on the canvas, deleted together.
    await tapCard(tester, 'R1-lista.html');
    await ctrlTap(tester, 'R1-lista.c.html');
    await tester.tap(key('proto-selection-delete'));
    await tester.pump();
    await tester.tap(key('proto-remove-confirm'));
    await settleIo(
      tester,
      until: () =>
          key('proto-card-R1-lista.c.html').evaluate().isEmpty &&
          key('proto-empty-R1').evaluate().isNotEmpty,
    );
    expect(find.text('2 telas apagadas.'), findsOneWidget);
    expect(announced.last, '2 telas apagadas');
    expect(key('proto-selection-bar'), findsNothing);
    expect(key('proto-check-R2-detalhe.html'), findsNothing);
    // R1 was left empty: the focus is on its slot ("Gerar tela do R1").
    expect(focusedIn(key('proto-empty-R1')), isTrue);
    expect(focusedIn(key('proto-empty-generate-R1')), isTrue);

    // A card in the middle: the focus goes to the next one.
    await tester.runAsync(() async {
      File('$mockups/R2-detalhe.b.html').writeAsStringSync('<p>2B</p>');
      File('$mockups/R3-fim.html').writeAsStringSync('<p>3</p>');
    });
    await reloadScreens(tester, 'R3-fim.html');
    await tapCard(tester, 'R2-detalhe.html');
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    await tester.tap(key('proto-remove-confirm'));
    await settleIo(
      tester,
      until: () =>
          key('proto-card-R2-detalhe.html').evaluate().isEmpty &&
          focusedIn(key('proto-card-R2-detalhe.b.html')),
    );
    expect(focusedIn(key('proto-card-R2-detalhe.b.html')), isTrue);
  });
}
