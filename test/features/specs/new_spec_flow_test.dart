import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/ideas/idea_import.dart' show ideaMaxChars;
import 'package:promptorium/features/specs/new_spec_view.dart';
import 'package:promptorium/features/specs/spec_design.dart';
import 'package:promptorium/features/specs/spec_draft.dart';
import 'package:promptorium/features/specs/spec_planner.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/features/specs/specs_screen.dart';
import 'package:promptorium/features/specs/workspace_watcher.dart';
import 'package:promptorium/ui/shell/command_palette.dart';
import 'package:promptorium/ui/shell/footer_stats.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/theme/tokens.dart';
import 'package:re_editor/re_editor.dart' show CodeEditor;

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';
import 'specs_screen_test.dart' show QuietWorkspaceWatcher;
import 'spec_action_lock_test.dart' show FakeDesigner;
import 'spec_file_test.dart' show sample;
import 'spec_planner_test.dart' show plannerOutput, resultLine;
import 'specs_screen_test.dart' show settleIo;

Finder key(String k) => find.byKey(ValueKey(k));

void main() {
  late Directory tmp;
  late FakeCli cli;
  late ProviderContainer c;
  late Workspace ws;
  FakeDesigner? designer;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('promptorium-new-spec-');
    Directory('${tmp.path}/specs').createSync();
    File('${tmp.path}/specs/SPEC-002-sessoes.md').writeAsStringSync(sample);
    designer = null;
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Specs screen at [size], with a button that does what the shell does.
  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1400, 900),
    bool open = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = memoryDatabase();
    cli = FakeCli();
    c = ProviderContainer(
      overrides: [
        ...sessionOverrides(db: db, cli: cli, notifier: FakeNotifier()),
        workspaceWatcherProvider.overrideWith(QuietWorkspaceWatcher.new),
        specDesignerProvider.overrideWith(
          (ref) => designer ??= FakeDesigner(ref),
        ),
      ],
    );
    await tester.runAsync(() async {
      ws = await db
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
    c.read(navigationProvider.notifier).go(AppSection.specs);
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
    if (open) {
      c.read(newSpecFlowProvider.notifier).open();
      await settleIo(tester, until: () => key('new-spec-idea').present);
    }
  }

  Future<void> tap(WidgetTester tester, String k) async {
    await tester.ensureVisible(key(k));
    await tester.tap(key(k));
    await settleIo(tester);
  }

  /// Types the idea and answers the first turn with [output].
  Future<void> plan(
    WidgetTester tester, {
    Map<String, Object?>? output,
    String idea = 'Quero avisar o paciente',
  }) async {
    await tester.enterText(key('new-spec-idea'), idea);
    await tester.pump();
    await tester.tap(key('new-spec-plan'));
    await settleIo(tester, until: () => cli.processes.isNotEmpty);
    cli.last.emit(resultLine(output ?? plannerOutput()));
    await settleIo(tester, until: () => key('new-spec-create').present);
    await settleIo(tester, until: () => c.read(specPlannerProvider).isEmpty);
    await settleIo(tester);
  }

  /// Sends [text] and answers the turn with [output].
  Future<void> reply(
    WidgetTester tester,
    String text,
    Map<String, Object?> output,
  ) async {
    final n = cli.processes.length;
    await tester.enterText(key('new-spec-composer'), text);
    await tester.pump();
    await tester.tap(key('new-spec-send'));
    await settleIo(tester, until: () => cli.processes.length > n);
    cli.last.emit(resultLine(output));
    await settleIo(tester, until: () => c.read(specPlannerProvider).isEmpty);
    await settleIo(tester);
  }

  bool enabled(WidgetTester tester, String k) {
    final w = tester.widget(key(k)) as dynamic;
    return w.onTap != null;
  }

  /// Runs [job] in the zone of the test: the locks of the database were made
  /// there, so `runAsync` would wait for them forever.
  Future<T> db<T>(WidgetTester tester, Future<T> Function() job) async {
    late T value;
    var done = false;
    job().then((v) {
      value = v;
      done = true;
    });
    await settleIo(tester, until: () => done);
    return value;
  }

  Future<SpecDraft?> draft(WidgetTester tester) =>
      db(tester, () => c.read(specDraftsRepoProvider).get(ws.id));

  /// A draft saved in an earlier run of the app.
  Future<void> seed(WidgetTester tester, [String title = '']) => db(
    tester,
    () async {
      final repo = c.read(specDraftsRepoProvider);
      await repo.start(ws.id);
      await repo.update(
        ws.id,
        SpecDraftsCompanion(data: Value(SpecDraftData(title: title).encode())),
      );
    },
  );

  List<File> specFiles() => [
    for (final f in Directory('${tmp.path}/specs').listSync())
      if (f is File) f,
  ];

  File newSpecFile() =>
      specFiles().singleWhere((f) => f.path.contains('SPEC-003'));

  group('R1', () {
    testWidgets('the palette and the title bar open the idea; Planejar a '
        'spec needs text', (tester) async {
      await pump(tester, open: false);
      expect(key('new-spec-idea'), findsNothing);
      late WidgetRef widgetRef;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  widgetRef = ref;
                  return const SpecsScreen();
                },
              ),
            ),
          ),
        ),
      );
      await settleIo(tester);
      final context = tester.element(find.byType(SpecsScreen));
      final command = paletteCommands(
        context,
        widgetRef,
        onNavigate: (_) {},
      ).singleWhere((p) => p.label == 'Nova spec');
      command.run();
      await settleIo(tester, until: () => key('new-spec-idea').present);
      expect(find.text('Conte a ideia'), findsOneWidget);
      expect(find.text('Nova spec'), findsOneWidget);
      expect(enabled(tester, 'new-spec-plan'), isFalse);
      expect(tester.getSize(key('new-spec-plan')).width, lessThan(300));
      await tester.enterText(key('new-spec-idea'), 'Uma ideia');
      await tester.pump();
      expect(enabled(tester, 'new-spec-plan'), isTrue);

      // "Specs" in the trail goes back.
      await tap(tester, 'new-spec-trail-specs');
      expect(key('new-spec-idea'), findsNothing);

      // The title bar, from another section, comes to the Specs screen.
      c.read(navigationProvider.notifier).go(AppSection.tasks);
      await openNewSpec(widgetRef);
      expect(c.read(navigationProvider), AppSection.specs);
      expect(c.read(newSpecFlowProvider), NewSpecStage.idea);
    });
  });

  testWidgets('R2: Criar em branco writes the template, with no planner, and '
      'opens the spec, even without the CLI', (tester) async {
    await pump(tester);
    c.read(cliStatusProvider.notifier).set(CliStatus.notFound);
    await settleIo(tester);
    await tap(tester, 'new-spec-blank');
    await tester.enterText(key('new-spec-title'), 'Kanban');
    await tester.tap(key('new-spec-submit'));
    await settleIo(
      tester,
      until: () => key('new-spec-idea').evaluate().isEmpty,
    );
    await settleIo(tester, until: () => find.text('Kanban').present);
    expect(cli.processes, isEmpty);
    final text = newSpecFile().readAsStringSync();
    expect(text, contains('Descreva o problema e o resultado esperado.'));
    expect(c.read(pendingDesignProvider), isNull);
    expect(c.read(newSpecFlowProvider), NewSpecStage.closed);
  });

  group('the conversation', () {
    testWidgets('R3, R5: suggestions, what changed, the draft and "novo"; '
        'a suggestion answers; "novo" lasts one answer', (tester) async {
      await pump(tester);
      await plan(tester);
      expect(find.text('Mini planejamento'), findsOneWidget);
      expect(find.text('planner · somente leitura'), findsOneWidget);
      // The buttons keep the size of their text.
      for (final k in ['new-spec-create', 'new-spec-suggestion-Só e-mail']) {
        expect(tester.getSize(key(k)).width, lessThan(300), reason: k);
      }
      expect(find.text('Quero avisar o paciente'), findsOneWidget);
      expect(
        find.textContaining('Rascunho atualizado · Título · Objetivo'),
        findsOneWidget,
      );
      expect(key('new-spec-suggestion-Só e-mail'), findsOneWidget);
      expect(find.text('SPEC-003'), findsOneWidget);
      expect(find.text('1 · máximo 6'), findsOneWidget);
      expect(find.text('novo'), findsOneWidget);
      expect(find.text('Ainda vazio'), findsNWidgets(2)); // escopo, depende

      await tester.tap(key('new-spec-suggestion-Só e-mail'));
      await settleIo(tester, until: () => cli.processes.length == 2);
      // Nothing to pick while the planner answers.
      expect(key('new-spec-suggestion-Só e-mail'), findsNothing);
      expect(find.text('Pensando…'), findsOneWidget);
      expect(enabled(tester, 'new-spec-create'), isFalse);
      expect(enabled(tester, 'new-spec-send'), isFalse);
      cli.last.emit(resultLine(plannerOutput(reply: 'Anotei.')));
      await settleIo(tester, until: () => find.text('Anotei.').present);
      await settleIo(tester);
      expect(find.text('novo'), findsNothing);
    });

    testWidgets('R5: the title typed by hand stays in the field and in the '
        'spec; an empty title blocks Criar', (tester) async {
      await pump(tester);
      await plan(tester);
      await tester.enterText(key('new-spec-draft-title'), '');
      await settleIo(tester);
      expect(enabled(tester, 'new-spec-create'), isFalse);
      await tester.enterText(key('new-spec-draft-title'), 'Avisos');
      await settleIo(tester);
      await reply(tester, 'Mais', plannerOutput(title: 'Do planner'));
      expect(
        tester.widget<TextField>(key('new-spec-draft-title')).controller!.text,
        'Avisos',
      );
      expect(enabled(tester, 'new-spec-create'), isTrue);
    });

    // 1044×628 is what is left of a 1100×700 window for the screen.
    for (final size in [const Size(1044, 628), const Size(1400, 900)]) {
      testWidgets('R3, R12: at ${size.width.toInt()}×${size.height.toInt()} '
          'the last message stays in view, also on the way back; the field '
          'and Criar stay fixed; nothing overflows', (tester) async {
        await pump(tester, size: size);
        await plan(tester);
        for (var i = 0; i < 6; i++) {
          await reply(
            tester,
            'Resposta número $i, com um texto de tamanho normal.',
            plannerOutput(
              reply: 'Pergunta $i',
              requirements: [
                for (var r = 0; r < 6; r++)
                  'Quando algo $r acontecer, o sistema deve responder com '
                      'uma ação verificável.',
              ],
              outOfScope: ['WhatsApp e SMS.', 'Relatório mensal.'],
            ),
          );
        }
        void expectEndInView() {
          final view = tester.getRect(key('new-spec-conversation'));
          final last = tester.getRect(find.text('Pergunta 5'));
          expect(last.bottom, lessThanOrEqualTo(view.bottom));
          expect(last.top, greaterThanOrEqualTo(view.top));
        }

        expectEndInView();
        final height = size.height;
        for (final k in ['new-spec-composer', 'new-spec-create']) {
          expect(tester.getRect(key(k)).bottom, lessThanOrEqualTo(height));
        }
        expect(tester.takeException(), isNull);

        await tap(tester, 'new-spec-leave');
        c.read(newSpecFlowProvider.notifier).open();
        await settleIo(tester, until: () => key('new-spec-continue').present);
        await tap(tester, 'new-spec-continue');
        await settleIo(tester);
        expectEndInView();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('R12: the fields use the new border; the old token stays; '
        'Tab reaches the actions', (tester) async {
      await pump(tester);
      await plan(tester);
      final decoration = tester
          .widget<TextField>(key('new-spec-composer'))
          .decoration!;
      final border = decoration.enabledBorder! as OutlineInputBorder;
      expect(border.borderSide.color, AppColors.inputBorder);
      expect(AppColors.inputBorder, const Color(0xFF626C7C));
      // 3:1 against the background.
      final a = AppColors.inputBorder.computeLuminance() + .05;
      final b = AppColors.background.computeLuminance() + .05;
      expect(a / b, greaterThanOrEqualTo(3));
      expect(tester.takeException(), isNull);
    });
  });

  group('R6', () {
    testWidgets('Criar spec writes the draft, opens the spec and removes the '
        'draft; it waits for the first answer', (tester) async {
      await pump(tester);
      await tester.enterText(key('new-spec-idea'), 'Ideia');
      await tester.pump();
      await tester.tap(key('new-spec-plan'));
      await settleIo(tester, until: () => cli.processes.isNotEmpty);
      await settleIo(tester, until: () => key('new-spec-create').present);
      expect(enabled(tester, 'new-spec-create'), isFalse);
      cli.last.emit(resultLine(plannerOutput()));
      await settleIo(tester, until: () => c.read(specPlannerProvider).isEmpty);
      await settleIo(tester);
      await tap(tester, 'new-spec-plan-next'); // off: "Criar spec"
      expect(find.text('Criar spec'), findsOneWidget);
      await tester.tap(key('new-spec-create'));
      await settleIo(
        tester,
        until: () => key('new-spec-create').present == false,
      );
      await settleIo(
        tester,
        until: () => find.text('Lembretes de consulta').present,
      );
      final text = newSpecFile().readAsStringSync();
      expect(text, contains('status: rascunho'));
      expect(text, contains('- R1 · Quando uma consulta for marcada'));
      expect(await draft(tester), isNull);
      expect(designer?.calls ?? const [], isEmpty);
      expect(c.read(newSpecFlowProvider), NewSpecStage.closed);
    });

    testWidgets('a failure to write keeps everything, and Criar tries again', (
      tester,
    ) async {
      await pump(tester);
      await plan(tester);
      await tap(tester, 'new-spec-plan-next');
      final specs = Directory('${tmp.path}/specs');
      final moved = specs.renameSync('${tmp.path}/guardadas');
      File('${tmp.path}/specs').writeAsStringSync('');
      await tester.tap(key('new-spec-create'));
      await settleIo(
        tester,
        until: () => key('new-spec-create-failed').present,
      );
      expect(find.text('Não foi possível criar a spec'), findsOneWidget);
      expect(find.textContaining('A pasta specs/ não aceitou'), findsOneWidget);
      expect(key('new-spec-conversation'), findsOneWidget);
      expect(await draft(tester), isNotNull);
      expect(enabled(tester, 'new-spec-create'), isTrue);

      File('${tmp.path}/specs').deleteSync();
      moved.renameSync('${tmp.path}/specs');
      await tester.tap(key('new-spec-create'));
      await settleIo(
        tester,
        until: () => key('new-spec-create').present == false,
      );
      expect(await draft(tester), isNull);
      expect(newSpecFile().existsSync(), isTrue);
    });
  });

  group('R7', () {
    Future<void> createAndPlan(WidgetTester tester) async {
      await pump(tester);
      await plan(tester);
      expect(find.text('Criar e planejar'), findsOneWidget);
      await tester.tap(key('new-spec-create'));
      await settleIo(tester, until: () => designer?.calls.isNotEmpty ?? false);
    }

    testWidgets('Criar e planejar starts Planejar on the new spec; the plan '
        'stays in the editor to review', (tester) async {
      await createAndPlan(tester);
      expect(designer!.calls.single.text, contains('id: SPEC-003'));
      expect(key('spec-action-banner'), findsOneWidget);
      final written = newSpecFile().readAsStringSync();
      designer!.next.complete('$written\n<!-- plano -->');
      await settleIo(
        tester,
        until: () => find.text('Plano pronto. Revise e salve.').present,
      );
      expect(find.text('Plano pronto. Revise e salve.'), findsOneWidget);
      expect(newSpecFile().readAsStringSync(), written); // not saved yet
    });

    testWidgets('a failure of Planejar keeps the spec, with Planejar there', (
      tester,
    ) async {
      await createAndPlan(tester);
      designer!.next.completeError(Exception('sem rede'));
      await settleIo(
        tester,
        until: () => key('spec-action-banner').evaluate().isEmpty,
      );
      await settleIo(tester);
      expect(newSpecFile().existsSync(), isTrue);
      expect(key('spec-design'), findsOneWidget);
    });

    testWidgets('Cancelar keeps the spec, with Planejar there', (tester) async {
      await createAndPlan(tester);
      await tester.tap(key('spec-action-cancel'));
      await settleIo(tester, until: () => !key('spec-action-banner').present);
      expect(
        find.text('Geração cancelada. A spec não foi alterada.'),
        findsOneWidget,
      );
      expect(newSpecFile().existsSync(), isTrue);
      expect(key('spec-design'), findsOneWidget);
    });

    testWidgets('the choice is saved', (tester) async {
      await pump(tester);
      await plan(tester);
      await tap(tester, 'new-spec-plan-next');
      expect(
        c.read(appSettingsProvider.notifier).get(AppSettingKeys.specPlanNext),
        '0',
      );
      expect(find.text('Criar spec'), findsOneWidget);
    });
  });

  group('R8', () {
    testWidgets('Sair e guardar shows "Rascunho guardado"; Nova spec offers '
        'it; Continuar comes back and resumes the session', (tester) async {
      await pump(tester);
      await plan(tester);
      await tap(tester, 'new-spec-leave');
      await settleIo(tester, until: () => key('specs-saved-draft').present);
      expect(find.text('Rascunho guardado'), findsOneWidget);
      expect(
        find.textContaining('Lembretes de consulta · 1 requisito · hoje às'),
        findsOneWidget,
      );

      await tap(tester, 'specs-saved-draft');
      expect(find.text('Você tem um rascunho'), findsOneWidget);
      await tester.enterText(key('new-spec-idea'), 'Outra ideia');
      await tester.pump();
      expect(enabled(tester, 'new-spec-plan'), isFalse);
      expect(enabled(tester, 'new-spec-blank'), isTrue);

      await tap(tester, 'new-spec-continue');
      expect(find.text('Quero avisar o paciente'), findsOneWidget);
      await reply(tester, 'Só e-mail', plannerOutput(reply: 'Certo.'));
      final args = cli.args.last;
      expect(args, contains('--resume'));
    });

    testWidgets('leaving the screen keeps the conversation open', (
      tester,
    ) async {
      await pump(tester);
      await plan(tester);
      final app = tester.widget<UncontrolledProviderScope>(
        find.byType(UncontrolledProviderScope),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: SizedBox()),
          ),
        ),
      );
      await tester.pumpWidget(app);
      await settleIo(tester, until: () => key('new-spec-composer').present);
      expect(find.text('Quero avisar o paciente'), findsOneWidget);
    });

    testWidgets('a restart finds the draft in the database', (tester) async {
      await pump(tester);
      await seed(tester, 'Guardado');
      await settleIo(tester, until: () => key('new-spec-draft-card').present);
      expect(find.textContaining('Guardado · 0 requisitos'), findsOneWidget);
    });

    testWidgets('Descartar asks when there are requirements, with the focus '
        'on Manter rascunho; Esc keeps; confirming removes', (tester) async {
      await pump(tester);
      await plan(tester);
      await tap(tester, 'new-spec-leave');
      c.read(newSpecFlowProvider.notifier).open();
      await settleIo(tester, until: () => key('new-spec-discard').present);
      await tap(tester, 'new-spec-discard');
      expect(find.text('Descartar o rascunho?'), findsOneWidget);
      expect(
        find.textContaining('Lembretes de consulta tem 1 requisito e a'),
        findsOneWidget,
      );
      final keep = tester.widget<FilledButton>(key('new-spec-discard-keep'));
      expect(keep.autofocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleIo(tester);
      expect(find.text('Descartar o rascunho?'), findsNothing);
      expect(await draft(tester), isNotNull);

      await tap(tester, 'new-spec-discard');
      await tap(tester, 'new-spec-discard-confirm');
      await settleIo(
        tester,
        until: () => key('new-spec-draft-card').evaluate().isEmpty,
      );
      expect(await draft(tester), isNull);
      expect(key('new-spec-draft-card'), findsNothing);
    });

    testWidgets('Descartar without requirements does not ask', (tester) async {
      await pump(tester);
      await seed(tester);
      await settleIo(tester, until: () => key('new-spec-discard').present);
      await tap(tester, 'new-spec-discard');
      expect(find.text('Descartar o rascunho?'), findsNothing);
      await settleIo(
        tester,
        until: () => key('new-spec-draft-card').evaluate().isEmpty,
      );
      expect(await draft(tester), isNull);
    });
  });

  group('R9', () {
    testWidgets('a failure keeps the conversation; Tentar de novo does not '
        'repeat the message; Criar stays available', (tester) async {
      await pump(tester);
      await plan(tester);
      cli.failStart = true;
      await tester.enterText(key('new-spec-composer'), 'Canal: e-mail');
      await tester.pump();
      await tester.tap(key('new-spec-send'));
      await settleIo(
        tester,
        until: () => key('new-spec-planner-failed').present,
      );
      expect(find.text('O planner não respondeu'), findsOneWidget);
      expect(find.text('Canal: e-mail'), findsOneWidget);
      expect(enabled(tester, 'new-spec-create'), isTrue);

      cli.failStart = false;
      final n = cli.processes.length;
      await tester.ensureVisible(key('new-spec-retry'));
      await tester.tap(key('new-spec-retry'));
      await settleIo(tester, until: () => cli.processes.length > n);
      cli.last.emit(resultLine(plannerOutput(reply: 'Certo.')));
      await settleIo(tester, until: () => find.text('Certo.').present);
      await settleIo(tester);
      expect(key('new-spec-planner-failed'), findsNothing);
      expect(find.text('Canal: e-mail'), findsOneWidget);
    });

    testWidgets('the first answer failing leaves Criar off, with nothing to '
        'write', (tester) async {
      await pump(tester);
      cli.failStart = true;
      await tester.enterText(key('new-spec-idea'), 'Ideia');
      await tester.pump();
      await tester.tap(key('new-spec-plan'));
      await settleIo(
        tester,
        until: () => key('new-spec-planner-failed').present,
      );
      expect(enabled(tester, 'new-spec-create'), isFalse);
    });

    testWidgets('without the CLI only Criar em branco is available; Verificar '
        'de novo brings Planejar back', (tester) async {
      await pump(tester);
      c.read(cliStatusProvider.notifier).set(CliStatus.notFound);
      await settleIo(tester, until: () => key('new-spec-no-cli').present);
      expect(find.text('Claude Code CLI não encontrado'), findsOneWidget);
      await tester.enterText(key('new-spec-idea'), 'Ideia');
      await tester.pump();
      expect(enabled(tester, 'new-spec-plan'), isFalse);
      expect(enabled(tester, 'new-spec-blank'), isTrue);
      expect(find.text('Em branco abre o modelo de sempre.'), findsOneWidget);

      await seed(tester);
      await settleIo(tester, until: () => key('new-spec-continue').present);
      expect(enabled(tester, 'new-spec-continue'), isFalse);
      await db(tester, () => c.read(specDraftsRepoProvider).delete(ws.id));
      await settleIo(tester);

      c.read(cliStatusProvider.notifier).set(CliStatus.connected);
      await settleIo(tester, until: () => !key('new-spec-no-cli').present);
      expect(enabled(tester, 'new-spec-plan'), isTrue);
    });
  });

  group('SPEC-057 importar arquivo', () {
    testWidgets('the field has the import button, the limit and the hint', (
      tester,
    ) async {
      await pump(tester);
      expect(key('idea-import'), findsOneWidget);
      expect(
        find.textContaining('Já tem um documento? Importe o texto dele.'),
        findsOneWidget,
      );
      await tester.enterText(key('new-spec-idea'), 'a' * (ideaMaxChars + 10));
      await tester.pump();
      final field = tester.widget<TextField>(key('new-spec-idea'));
      expect(field.controller!.text.length, ideaMaxChars);
      expect(find.text('40.000 / 40.000'), findsOneWidget);
    });

    testWidgets('dropping a TXT fills the idea and lets it be planned', (
      tester,
    ) async {
      await pump(tester);
      expect(enabled(tester, 'new-spec-plan'), isFalse);
      final f = File('${tmp.path}/ideia.txt')
        ..writeAsStringSync('Lembrete de consulta por WhatsApp.\n');
      tester.widget<DropTarget>(key('idea-drop')).onDragDone!(
        DropDoneDetails(
          files: [DropItemFile(f.path)],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await settleIo(tester, until: () => key('idea-source').present);
      final field = tester.widget<TextField>(key('new-spec-idea'));
      expect(field.controller!.text, 'Lembrete de consulta por WhatsApp.');
      expect(find.text('ideia.txt'), findsOneWidget);
      expect(enabled(tester, 'new-spec-plan'), isTrue);
    });
  });
}

extension on Finder {
  bool get present => evaluate().isNotEmpty;
}
