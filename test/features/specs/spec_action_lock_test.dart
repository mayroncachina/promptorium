import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/specs/spec_action.dart';
import 'package:promptorium/features/specs/spec_design.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/features/specs/specs_screen.dart';
import 'package:promptorium/features/project/spec_auto_planner.dart';
import 'package:promptorium/features/specs/widgets/spec_header.dart';
import 'package:promptorium/features/specs/workspace_watcher.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/theme/tokens.dart';
import 'package:re_editor/re_editor.dart' show CodeEditor;

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';
import 'spec_file_test.dart' show sample;
import 'specs_screen_test.dart' show QuietWorkspaceWatcher, settleIo;

/// "Planejar" without the CLI: the test decides when (and how) it ends.
class FakeDesigner extends SpecDesigner {
  FakeDesigner(super.ref);

  final calls = <({String text, Future<void>? cancelled})>[];
  Completer<String> next = Completer<String>();

  /// Thrown by the next call instead of waiting on [next].
  Object? error;

  @override
  Future<String> generate(
    Workspace ws,
    String specText, {
    Future<void>? cancelled,
  }) {
    calls.add((text: specText, cancelled: cancelled));
    if (error != null) return Future.error(error!);
    return next.future;
  }
}

/// A second spec, to switch to during an action.
const otherSpec = '''---
id: SPEC-003
status: rascunho
---

# Outra spec

## Requisitos

- R1 · Quando abrir, o sistema deve mostrar a lista
''';

String specPath(Directory tmp) => '${tmp.path}/specs/SPEC-002-sessoes.md';

/// The Specs screen on [tmp] (SPEC-002 open), with [designer] faking "Gerar
/// design".
Future<ProviderContainer> pumpSpecs(
  WidgetTester tester,
  Directory tmp, {
  required FakeDesigner Function(Ref ref) designer,
  Size size = const Size(1920, 1000),
  List<Override> overrides = const [],
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = memoryDatabase();
  final c = ProviderContainer(
    overrides: [
      ...sessionOverrides(db: db, cli: FakeCli(), notifier: FakeNotifier()),
      workspaceWatcherProvider.overrideWith(QuietWorkspaceWatcher.new),
      specDesignerProvider.overrideWith(designer),
      ...overrides,
    ],
  );
  // Built now, so the test holds it before the first tap.
  c.read(specDesignerProvider);
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
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
        find.byType(CodeEditor).evaluate().isNotEmpty &&
        find.text('Salvo').evaluate().isNotEmpty,
  );
  return c;
}

Finder key(String k) => find.byKey(ValueKey(k));

CodeEditor editorOf(WidgetTester tester) =>
    tester.widget<CodeEditor>(find.byType(CodeEditor));

/// Taps "Planejar" until the action starts.
Future<void> startDesign(WidgetTester tester, FakeDesigner Function() d) async {
  final before = d().calls.length;
  for (var i = 0; i < 5 && d().calls.length == before; i++) {
    await tester.tap(key('spec-design'));
    await settleIo(tester, until: () => d().calls.length > before);
  }
  expect(d().calls.length, before + 1);
}

/// re_editor takes its mobile key path (Enter inserts a line even when
/// read-only) under the default test platform; the app runs on Linux.
final desktop = TargetPlatformVariant.only(TargetPlatform.linux);

/// WCAG contrast ratio of [a] on [b].
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  late Directory tmp;
  late FakeDesigner designer;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('promptorium-spec-lock-');
    Directory('${tmp.path}/specs').createSync();
    File(specPath(tmp)).writeAsStringSync(sample);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  FakeDesigner make(Ref ref) => designer = FakeDesigner(ref);

  testWidgets('R1: with "Planejar" running, typing, pasting, undoing '
      'and Ctrl+S change neither the text nor the file', (tester) async {
    await pumpSpecs(tester, tmp, designer: make);
    // An unsaved edit from before the action: Ctrl+S must not write it.
    final edited = sample.replaceFirst('# Sessões', '# Sessões editadas');
    editorOf(tester).controller!.text = edited;
    await tester.pump();
    await tester.pump();
    expect(key('spec-unsaved'), findsOneWidget);
    // Typing in the editor: its text input connection is open.
    await tester.tap(find.byType(CodeEditor));
    await tester.pump();
    expect(tester.testTextInput.hasAnyClients, isTrue);
    await startDesign(tester, () => designer);

    expect(editorOf(tester).readOnly, true);
    // The connection closes: the keyboard (and the IME) no longer reach it.
    expect(tester.testTextInput.hasAnyClients, isFalse);
    await tester.tap(find.byType(CodeEditor));
    await tester.pump();
    expect(tester.testTextInput.hasAnyClients, isFalse);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async =>
          call.method == 'Clipboard.getData' ? {'text': 'colado'} : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settleIo(tester);
    expect(editorOf(tester).controller!.text, edited);
    expect(File(specPath(tmp)).readAsStringSync(), sample);
    // No "Salvar" while held: the tabs line says why.
    expect(key('spec-save'), findsNothing);
    expect(
      tester.widget<Text>(key('spec-action-lock')).data,
      'Bloqueada: planejando',
    );
    designer.next.complete(edited);
    await settleIo(tester, until: () => editorOf(tester).readOnly != true);
    // Released with the focus still there: typing works again.
    await tester.pump();
    expect(tester.testTextInput.hasAnyClients, isTrue);
  }, variant: desktop);

  testWidgets('R2: the running action shows its gerund label with a spinner; '
      'the other actions and "Mais ações" are disabled', (tester) async {
    await pumpSpecs(tester, tmp, designer: make);
    await startDesign(tester, () => designer);
    await tester.pump(const Duration(milliseconds: 400));
    final design = tester.widget<SpecActionButton>(key('spec-design'));
    expect(design.action.busy, isTrue);
    expect(design.action.label, 'Planejando…');
    expect(
      find.descendant(
        of: key('spec-design'),
        matching: find.text('Planejando…'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: key('spec-design'),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    for (final k in ['spec-refine', 'spec-approve', 'spec-design']) {
      expect(tester.widget<SpecActionButton>(key(k)).onTap, isNull, reason: k);
    }
    expect(tester.widget<InkWell>(key('spec-more')).onTap, isNull);
    // Tapping the menu does nothing.
    await tester.tap(key('spec-more'));
    await tester.pump();
    expect(find.text('Excluir…'), findsNothing);
    designer.next.complete(sample);
    await settleIo(
      tester,
      until: () =>
          tester.widget<SpecActionButton>(key('spec-design')).onTap != null,
    );
    expect(find.text('Planejar'), findsOneWidget);
    expect(tester.widget<InkWell>(key('spec-more')).onTap, isNotNull);
  }, variant: desktop);

  testWidgets('R4: held, the text stays visible in the read-only style with '
      'no veil, and the mode tabs keep switching', (tester) async {
    await pumpSpecs(tester, tmp, designer: make);
    await startDesign(tester, () => designer);
    final editor = editorOf(tester);
    expect(editor.controller!.text, sample);
    expect(editor.style!.textColor, AppColors.textSecondary);
    expect(editor.style!.backgroundColor, AppColors.panel);
    final blocked = tester.widget<MouseRegion>(key('code-editor-blocked'));
    expect(blocked.cursor, SystemMouseCursors.forbidden);
    expect(blocked.opaque, isFalse);
    // No veil: no opacity or barrier over the editor.
    expect(
      find.ancestor(
        of: find.byType(CodeEditor),
        matching: find.byType(Opacity),
      ),
      findsNothing,
    );
    expect(find.byType(ModalBarrier), findsOneWidget); // the route's own
    await tester.tap(key('spec-mode-preview'));
    await tester.pump();
    expect(find.byType(CodeEditor), findsNothing);
    expect(key('spec-preview'), findsOneWidget);
    expect(find.text('Sessões com stream-json'), findsWidgets);
    await tester.tap(key('spec-mode-edit'));
    await tester.pump();
    expect(find.byType(CodeEditor), findsOneWidget);
    expect(editorOf(tester).readOnly, true);
    expect(key('spec-preview'), findsNothing);
    await tester.tap(key('spec-mode-split'));
    await tester.pump();
    expect(find.byType(CodeEditor), findsOneWidget);
    expect(key('spec-preview'), findsOneWidget);
    designer.next.complete(sample);
    await settleIo(tester, until: () => editorOf(tester).readOnly != true);
    expect(editorOf(tester).style!.textColor, AppColors.text);
    expect(key('code-editor-blocked'), findsNothing);
  }, variant: desktop);

  testWidgets('R5: Esc and "Cancelar geração" complete `cancelled`, release '
      'the spec and keep the text', (tester) async {
    await pumpSpecs(tester, tmp, designer: make);
    await startDesign(tester, () => designer);
    var cancelled = false;
    designer.calls.last.cancelled!.then((_) => cancelled = true);
    await tester.tap(find.byType(CodeEditor));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleIo(tester, until: () => editorOf(tester).readOnly != true);
    expect(cancelled, isTrue);
    expect(editorOf(tester).readOnly, isNot(true));
    expect(editorOf(tester).controller!.text, sample);
    expect(
      find.text('Geração cancelada. A spec não foi alterada.'),
      findsOneWidget,
    );
    expect(key('spec-action-banner'), findsNothing);
    // A late answer of the stopped run changes nothing.
    designer.next.complete('# outro texto');
    await settleIo(tester);
    expect(editorOf(tester).controller!.text, sample);

    designer.next = Completer<String>();
    await startDesign(tester, () => designer);
    var again = false;
    designer.calls.last.cancelled!.then((_) => again = true);
    await tester.tap(key('spec-action-cancel'));
    await settleIo(tester, until: () => editorOf(tester).readOnly != true);
    expect(again, isTrue);
    expect(editorOf(tester).controller!.text, sample);
    expect(File(specPath(tmp)).readAsStringSync(), sample);
  }, variant: desktop);

  testWidgets('R6: an action shorter than 300 ms shows no spinner; a longer '
      'one does', (tester) async {
    var state = const SpecHeaderState(
      runningId: 'approve',
      runningLabel: 'Aprovando…',
    );
    late StateSetter set;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setter) {
              set = setter;
              return SpecHeader(title: 'Spec', actions: state);
            },
          ),
        ),
      ),
    );
    Finder spinner() => find.descendant(
      of: key('spec-approve'),
      matching: find.byType(CircularProgressIndicator),
    );
    expect(find.text('Aprovando…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(spinner(), findsNothing);
    set(() => state = SpecHeaderState(onApprove: () {}));
    await tester.pump(const Duration(milliseconds: 400));
    expect(spinner(), findsNothing);
    expect(find.text('Aprovar'), findsOneWidget);

    set(
      () => state = const SpecHeaderState(
        runningId: 'approve',
        runningLabel: 'Aprovando…',
      ),
    );
    await tester.pump();
    expect(spinner(), findsNothing);
    await tester.pump(const Duration(milliseconds: 350));
    expect(spinner(), findsOneWidget);
    // Unmounted with the spinner on: no pending timer left.
    await tester.pumpWidget(const SizedBox());
  }, variant: desktop);

  testWidgets('R7: a generation that ends after the spec changed is not '
      'applied to the new spec', (tester) async {
    File('${tmp.path}/specs/SPEC-003-outra.md').writeAsStringSync(otherSpec);
    final c = await pumpSpecs(tester, tmp, designer: make);
    await startDesign(tester, () => designer);
    final ws = c.read(activeWorkspaceProvider)!;
    final specs = await tester.runAsync(
      () => c.read(specsRepoProvider).watchByWorkspace(ws.id).first,
    );
    final other = specs!.singleWhere((s) => s.code == 'SPEC-003');
    // Switched from outside the list (e.g. the Quadro), with the run on.
    c.read(selectedSpecProvider.notifier).select(other.id);
    await settleIo(
      tester,
      until: () => editorOf(tester).controller!.text == otherSpec,
    );
    designer.next.complete('# resultado do design\n');
    await settleIo(tester);
    expect(editorOf(tester).controller!.text, otherSpec);
    expect(File(specPath(tmp)).readAsStringSync(), sample);
    expect(
      File('${tmp.path}/specs/SPEC-003-outra.md').readAsStringSync(),
      otherSpec,
    );
    expect(c.read(specActionProvider), isNull);
  }, variant: desktop);

  testWidgets('R10: the disabled actions use #8A93A3 on #1A1E26 with a '
      'border (4.5:1 or more), without opacity', (tester) async {
    expect(AppColors.textDisabled, const Color(0xFF8A93A3));
    expect(AppColors.surfaceRaised, const Color(0xFF1A1E26));
    expect(
      contrast(AppColors.textDisabled, AppColors.surfaceRaised),
      greaterThanOrEqualTo(4.5),
    );
    await pumpSpecs(tester, tmp, designer: make);
    await startDesign(tester, () => designer);
    for (final k in ['spec-refine', 'spec-approve']) {
      final label = find.descendant(of: key(k), matching: find.byType(Text));
      expect(tester.widget<Text>(label).style!.color, AppColors.textDisabled);
      final material = tester.widget<Material>(
        find.descendant(of: key(k), matching: find.byType(Material)).first,
      );
      expect(material.color, AppColors.surfaceRaised);
      final shape = material.shape! as RoundedRectangleBorder;
      expect(shape.side.color, AppColors.border);
      expect(
        find.ancestor(of: key(k), matching: find.byType(Opacity)),
        findsNothing,
      );
      expect(
        find.descendant(of: key(k), matching: find.byType(Opacity)),
        findsNothing,
      );
    }
    designer.next.complete(sample);
    await settleIo(tester, until: () => editorOf(tester).readOnly != true);
  }, variant: desktop);

  group('SPEC-037 R10, R13: the automatic plan holds the spec', () {
    const lock = AutoPlanState(replanning: {});
    Future<(ProviderContainer, SeededPlanner, int)> pumpHeld(
      WidgetTester tester,
    ) async {
      late SeededPlanner planner;
      final c = await pumpSpecs(
        tester,
        tmp,
        designer: make,
        reduceMotion: true,
        overrides: [
          specAutoPlannerProvider.overrideWith(
            () => planner = SeededPlanner(lock),
          ),
        ],
      );
      c.read(specAutoPlannerProvider);
      final specs = await tester.runAsync(
        () => c.read(specsRepoProvider).watchByWorkspace(1).first,
      );
      return (c, planner, specs!.firstWhere((s) => s.code == 'SPEC-002').id);
    }

    AutoPlanState queued(int id) => AutoPlanState(
      queues: {
        1: AutoPlanQueue(
          active: {id},
          items: [
            const AutoPlanItem(
              specId: 900,
              code: 'SPEC-001',
              title: 'Base',
              path: 'specs/a.md',
              dependsOn: [],
              status: AutoPlanStatus.planning,
            ),
            AutoPlanItem(
              specId: id,
              code: 'SPEC-002',
              title: 'Sessões',
              path: 'specs/b.md',
              dependsOn: const [],
            ),
          ],
        ),
      },
    );

    testWidgets('in the queue: read-only, "Na fila", the strip with the '
        'position, and the actions off with the reason', (tester) async {
      final (_, planner, id) = await pumpHeld(tester);
      expect(editorOf(tester).readOnly, isFalse);
      planner.seed(queued(id));
      await tester.pump();
      await tester.pump();
      expect(editorOf(tester).readOnly, isTrue);
      expect(find.text('Na fila'), findsOneWidget);
      expect(
        find.text(
          'Planejando as specs do projeto · 1 de 2, em SPEC-001. Esta spec '
          'fica bloqueada até a fila passar por ela.',
        ),
        findsOneWidget,
      );
      final design = tester.widget<SpecActionButton>(
        find.byWidgetPredicate(
          (w) => w is SpecActionButton && w.action.id == 'design',
        ),
      );
      expect(design.action.onTap, isNull);
      expect(design.action.unavailableReason, autoPlanQueueReason);

      // Ctrl+S writes nothing while held.
      final before = File(specPath(tmp)).readAsStringSync();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(File(specPath(tmp)).readAsStringSync(), before);
    });

    testWidgets('R11: the reason and the strip fit at 1100×700', (
      tester,
    ) async {
      late SeededPlanner planner;
      final c = await pumpSpecs(
        tester,
        tmp,
        designer: make,
        reduceMotion: true,
        size: const Size(1048, 640),
        overrides: [
          specAutoPlannerProvider.overrideWith(
            () => planner = SeededPlanner(lock),
          ),
        ],
      );
      c.read(specAutoPlannerProvider);
      final specs = await tester.runAsync(
        () => c.read(specsRepoProvider).watchByWorkspace(1).first,
      );
      planner.seed(queued(specs!.firstWhere((s) => s.code == 'SPEC-002').id));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      final strip = key('spec-plan-lock');
      expect(strip, findsOneWidget);
      expect(find.text(autoPlanQueueReason), findsOneWidget);
    });

    testWidgets('when the round ends the editor shows what the agent wrote', (
      tester,
    ) async {
      final (_, planner, id) = await pumpHeld(tester);
      planner.seed(AutoPlanState(replanning: {id}));
      await tester.pump();
      await tester.pump();
      expect(find.text(autoPlanUpdateReason), findsOneWidget);
      expect(editorOf(tester).readOnly, isTrue);
      final written = sample.replaceFirst('# Sessões', '# Pelo agente');
      File(specPath(tmp)).writeAsStringSync(written);
      planner.seed(const AutoPlanState());
      await settleIo(
        tester,
        until: () => editorOf(tester).controller!.text == written,
      );
      expect(editorOf(tester).readOnly, isFalse);
    });

    testWidgets('saving by hand takes out `plano: automatico`', (tester) async {
      final marked = SpecDocument.parse(sample).withAutoPlan(true);
      File(specPath(tmp)).writeAsStringSync(marked);
      await pumpHeld(tester);
      expect(
        SpecDocument.parse(editorOf(tester).controller!.text).autoPlanned,
        isTrue,
      );
      await tester.tap(find.byType(CodeEditor));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settleIo(
        tester,
        until: () =>
            !SpecDocument.parse(File(specPath(tmp)).readAsStringSync())
                .autoPlanned,
      );
      expect(
        SpecDocument.parse(File(specPath(tmp)).readAsStringSync()).autoPlanned,
        isFalse,
      );
      await settleIo(tester);
      expect(key('spec-unsaved'), findsNothing);
    });
  });
}

/// [SpecAutoPlanner] with a state the test sets.
class SeededPlanner extends SpecAutoPlanner {
  SeededPlanner(this._seed);

  final AutoPlanState _seed;

  @override
  AutoPlanState build() => _seed;

  void seed(AutoPlanState value) => state = value;
}
