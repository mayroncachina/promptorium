import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/process/process_runner.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/specs/prototype/prototype_files.dart';
import 'package:promptorium/features/specs/prototype/prototype_service.dart';
import 'package:promptorium/features/specs/prototype/prototype_thumbnails.dart';
import 'package:promptorium/features/specs/prototype/prototype_view.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/features/specs/specs_screen.dart';
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
        }) async {
          prompts.add(prompt);
          agentWrites();
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

  bool enabled(WidgetTester tester, String key) =>
      tester.widget<ProtoButton>(find.byKey(ValueKey(key))).onTap != null;

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
    expect(find.text('R1 · Lista'), findsOneWidget);
    expect(find.text('R2 · Detalhe'), findsOneWidget);
    expect(find.byKey(const ValueKey('proto-tab-ask')), findsOneWidget);
    expect(find.byKey(const ValueKey('proto-tab-versions')), findsOneWidget);
    expect(find.text('Comentários'), findsNothing);
    expect(find.byKey(const ValueKey('proto-generate')), findsOneWidget);
    expect(find.byKey(const ValueKey('spec-save')), findsNothing);
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
    expect(find.text('R1 · Lista · B'), findsOneWidget);
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
    await settleIo(tester);
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
      'and removes one that is not approved', (tester) async {
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
      findsNothing,
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
      'Tela R1 · Lista',
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
}
