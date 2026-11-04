import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/specs/prototype/prototype_view.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/features/specs/specs_screen.dart';
import 'package:promptorium/features/specs/widgets/spec_skeleton.dart';
import 'package:promptorium/features/specs/workspace_watcher.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/theme/motion.dart';
import 'package:promptorium/ui/widgets/code_editor/app_code_editor.dart';
import 'package:re_editor/re_editor.dart' show CodeEditor;

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';
import 'spec_file_test.dart' show sample;
import 'specs_screen_test.dart' show QuietWorkspaceWatcher, settleIo;

void motionOn() {
  AppMotion.enabled = true;
  addTearDown(() => AppMotion.enabled = false);
}

/// [read] of a gated spec waits for the test; saves are only recorded.
class GatedSpecs extends SpecService {
  GatedSpecs(super.repo);

  final gates = <String, Completer<String?>>{};
  final saves = <String>[];

  Completer<String?> gate(String code) => gates[code] = Completer();

  @override
  Future<String?> read(Workspace ws, Spec spec) {
    final gate = gates[spec.code];
    return gate != null ? gate.future : super.read(ws, spec);
  }

  @override
  Future<Spec> save(
    Workspace ws,
    Spec spec,
    String text, {
    String? expectedText,
  }) async {
    saves.add('${spec.code}: $text');
    return spec;
  }
}

String specText(String code, String title) => sample
    .replaceFirst('id: SPEC-002', 'id: $code')
    .replaceFirst(RegExp(r'^# .*$', multiLine: true), '# $title');

final skeleton = find.byKey(const ValueKey('spec-skeleton'));
final openError = find.byKey(const ValueKey('spec-open-error'));
final retry = find.byKey(const ValueKey('spec-open-retry'));

String editorText(WidgetTester tester) =>
    tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!.text;

double fadeOf(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find
          .descendant(
            of: find.byType(SpecTextFade),
            matching: find.byType(FadeTransition),
          )
          .first,
    )
    .opacity
    .value;

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('promptorium-skeleton-');
    Directory('${tmp.path}/specs').createSync();
    for (final (code, title) in [
      ('SPEC-002', 'Primeira'),
      ('SPEC-003', 'Segunda'),
      ('SPEC-004', 'Terceira'),
    ]) {
      File('${tmp.path}/specs/$code-doc.md')
          .writeAsStringSync(specText(code, title));
    }
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  /// The screen with SPEC-002 open.
  Future<(ProviderContainer, GatedSpecs)> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = memoryDatabase();
    late GatedSpecs specs;
    final c = ProviderContainer(
      overrides: [
        ...sessionOverrides(db: db, cli: FakeCli(), notifier: FakeNotifier()),
        workspaceWatcherProvider.overrideWith(QuietWorkspaceWatcher.new),
        specServiceProvider.overrideWith(
          (ref) => specs = GatedSpecs(ref.watch(specsRepoProvider)),
        ),
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
          find.byType(CodeEditor).evaluate().isNotEmpty &&
          find
              .byKey(const ValueKey('spec-item-SPEC-004'))
              .evaluate()
              .isNotEmpty,
    );
    expect(editorText(tester), contains('# Primeira'));
    return (c, specs);
  }

  Future<void> open(WidgetTester tester, String code) async {
    await tester.tap(find.byKey(ValueKey('spec-item-$code')));
    await tester.pump();
  }

  group('opening a spec', () {
    testWidgets('the current document stays for 300 ms, untouched, and the '
        'skeleton comes after that; the text then fades in over base', (
      tester,
    ) async {
      motionOn();
      final (_, specs) = await pump(tester);
      final editor = tester.element(find.byType(CodeEditor));
      final gate = specs.gate('SPEC-003');

      await open(tester, 'SPEC-003');
      await tester.pump(const Duration(milliseconds: 299));
      expect(skeleton, findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(editorText(tester), contains('# Primeira'));
      // The same element: nothing was rebuilt from scratch, so nothing blinks.
      expect(tester.element(find.byType(CodeEditor)), same(editor));
      expect(fadeOf(tester), 1);

      await tester.pump(const Duration(milliseconds: 2));
      expect(skeleton, findsOneWidget);
      expect(find.byType(CodeEditor), findsNothing);

      gate.complete(specText('SPEC-003', 'Segunda'));
      await tester.pump();
      await tester.pump();
      expect(skeleton, findsNothing);
      expect(editorText(tester), contains('# Segunda'));
      expect(fadeOf(tester), lessThan(.2));
      await tester.pump(AppMotion.base ~/ 2);
      expect(fadeOf(tester), inExclusiveRange(0, 1));
      await tester.pump(AppMotion.base);
      expect(fadeOf(tester), 1);
    });

    testWidgets('a file that arrives within 300 ms never shows the skeleton', (
      tester,
    ) async {
      final (_, specs) = await pump(tester);
      final gate = specs.gate('SPEC-003');
      await open(tester, 'SPEC-003');
      await tester.pump(const Duration(milliseconds: 100));
      gate.complete(specText('SPEC-003', 'Segunda'));
      await tester.pump();
      await tester.pump();
      expect(editorText(tester), contains('# Segunda'));
      await tester.pump(const Duration(seconds: 1));
      expect(skeleton, findsNothing);
    });

    testWidgets('opening another spec cancels the wait: the late file does '
        'not replace the newer one', (tester) async {
      final (_, specs) = await pump(tester);
      final slow = specs.gate('SPEC-003');
      final fast = specs.gate('SPEC-004');

      await open(tester, 'SPEC-003');
      await tester.pump(const Duration(milliseconds: 200));
      await open(tester, 'SPEC-004');
      // The wait is new: the 300 ms of the first spec no longer count.
      await tester.pump(const Duration(milliseconds: 200));
      expect(skeleton, findsNothing);

      fast.complete(specText('SPEC-004', 'Terceira'));
      await tester.pump();
      await tester.pump();
      expect(editorText(tester), contains('# Terceira'));

      slow.complete(specText('SPEC-003', 'Segunda'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(editorText(tester), contains('# Terceira'));
      expect(skeleton, findsNothing);
    });

    testWidgets('a skeleton on screen stays when another spec is opened: the '
        'old document does not come back', (tester) async {
      final (_, specs) = await pump(tester);
      specs.gate('SPEC-003');
      specs.gate('SPEC-004');
      await open(tester, 'SPEC-003');
      await tester.pump(const Duration(milliseconds: 301));
      expect(skeleton, findsOneWidget);
      await open(tester, 'SPEC-004');
      await tester.pump();
      expect(skeleton, findsOneWidget);
      expect(find.byType(CodeEditor), findsNothing);
    });
  });

  group('the document during the wait', () {
    testWidgets('is read-only: typing does nothing and saving writes nothing, '
        'in either spec', (tester) async {
      final (_, specs) = await pump(tester);
      final before = editorText(tester);
      await tester.tap(find.byType(CodeEditor));
      // The first blink of the cursor comes 100 ms later on the test platform.
      await tester.pump(const Duration(milliseconds: 200));
      final gate = specs.gate('SPEC-003');
      await open(tester, 'SPEC-003');
      await tester.pump(const Duration(milliseconds: 50));

      final held = tester.widget<AppCodeEditor>(find.byType(AppCodeEditor));
      expect(held.readOnly, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      // Even with the shortcut reaching it, the save refuses the old text.
      held.onSave!();
      await tester.pump();

      expect(editorText(tester), before);
      expect(specs.saves, isEmpty);
      expect(
        FocusManager.instance.primaryFocus?.context?.widget,
        isNot(isA<CodeEditor>()),
      );

      gate.complete(specText('SPEC-003', 'Segunda'));
      await tester.pump();
      await tester.pump();
      expect(editorText(tester), contains('# Segunda'));
      expect(specs.saves, isEmpty);
      // The cursor of a focused editor leaves a blink timer behind.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('in Protótipo the canvas of the current spec stays too', (
      tester,
    ) async {
      final (_, specs) = await pump(tester);
      await tester.tap(find.byKey(const ValueKey('spec-mode-prototype')));
      await settleIo(
        tester,
        until: () => find.byType(PrototypeCanvas).evaluate().isNotEmpty,
      );
      final gate = specs.gate('SPEC-003');
      await open(tester, 'SPEC-003');
      await tester.pump(const Duration(milliseconds: 50));
      final held = tester.widget<PrototypeCanvas>(find.byType(PrototypeCanvas));
      expect(held.spec.code, 'SPEC-002');

      gate.complete(specText('SPEC-003', 'Segunda'));
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<PrototypeCanvas>(find.byType(PrototypeCanvas)).spec.code,
        'SPEC-003',
      );
    });

    testWidgets('does not take clicks', (tester) async {
      final (_, specs) = await pump(tester);
      specs.gate('SPEC-003');
      await open(tester, 'SPEC-003');
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.byType(CodeEditor).hitTestable(),
        findsNothing,
        reason: 'the document on the way out is only shown',
      );
    });

    testWidgets('discarded changes do not become a draft of the next spec', (
      tester,
    ) async {
      final (c, specs) = await pump(tester);
      tester.widget<CodeEditor>(find.byType(CodeEditor)).controller!.text =
          'rascunho descartado';
      await tester.pump();
      expect(c.read(specDirtyProvider), isTrue);

      specs.gate('SPEC-003');
      await tester.tap(find.byKey(const ValueKey('spec-item-SPEC-003')));
      await tester.pump();
      await tester.tap(find.text('Descartar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(c.read(specDirtyProvider), isFalse);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const SizedBox()),
      );
      await tester.pump();
      expect(c.read(specUnsavedProvider), isEmpty);
    });
  });

  group('a spec that does not open', () {
    testWidgets('shows the reason and "Tentar de novo", which opens it', (
      tester,
    ) async {
      final (_, specs) = await pump(tester);
      final gate = specs.gate('SPEC-003');
      await open(tester, 'SPEC-003');
      gate.completeError(
        const FileSystemException('read', 'x', OSError('Permissão negada', 13)),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.text('Não foi possível abrir a SPEC-003: Permissão negada'),
        findsOneWidget,
      );
      expect(find.byType(CodeEditor), findsNothing);
      expect(skeleton, findsNothing);

      specs.gates.remove('SPEC-003');
      await tester.tap(retry);
      await settleIo(
        tester,
        until: () => find.byType(CodeEditor).evaluate().isNotEmpty,
      );
      expect(openError, findsNothing);
      expect(editorText(tester), contains('# Segunda'));
    });

    testWidgets('a file gone from the folder is a failure too', (tester) async {
      await pump(tester);
      File('${tmp.path}/specs/SPEC-003-doc.md').deleteSync();
      await open(tester, 'SPEC-003');
      await settleIo(tester, until: () => openError.evaluate().isNotEmpty);
      expect(
        find.text(
          'Não foi possível abrir a SPEC-003: o arquivo não está mais na '
          'pasta de specs.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('another spec still opens, without the old document coming '
        'back in between', (tester) async {
      final (_, specs) = await pump(tester);
      final gate = specs.gate('SPEC-003');
      await open(tester, 'SPEC-003');
      gate.complete(null);
      await tester.pump();
      await tester.pump();
      expect(openError, findsOneWidget);

      final next = specs.gate('SPEC-004');
      await open(tester, 'SPEC-004');
      await tester.pump();
      expect(openError, findsNothing);
      expect(find.byType(CodeEditor), findsNothing);
      next.complete(specText('SPEC-004', 'Terceira'));
      await tester.pump();
      await tester.pump();
      expect(editorText(tester), contains('# Terceira'));
    });
  });

  group('SpecSkeleton', () {
    Widget app({bool reduced = false, bool shown = true}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: shown ? const SpecSkeleton() : const SizedBox(),
      ),
    );

    final shine = find.byType(SlideTransition);

    testWidgets('has the shape of the document: title, section, line, '
        'section, line', (tester) async {
      await tester.pumpWidget(app());
      final bars = find.byType(FractionallySizedBox);
      expect(bars, findsNWidgets(5));
      expect(
        tester.getSize(bars.first).height,
        greaterThan(tester.getSize(bars.last).height),
      );
      expect(
        tester.getSemantics(find.byType(SpecSkeleton)),
        matchesSemantics(label: 'Carregando a spec', isLiveRegion: true),
      );
    });

    testWidgets('the shine moves only while it is on screen', (tester) async {
      motionOn();
      await tester.pumpWidget(app());
      final pass = tester.widget<SlideTransition>(shine.first).position;
      expect(tester.hasRunningAnimations, isTrue);
      final start = pass.value;
      await tester.pump(SpecSkeleton.shinePeriod ~/ 4);
      expect(pass.value, isNot(start));

      await tester.pumpWidget(app(shown: false));
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('R11 · with reduced motion it stands still', (tester) async {
      motionOn();
      await tester.pumpWidget(app(reduced: true));
      expect(shine, findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('reduced motion turned on stops a shine in progress', (
      tester,
    ) async {
      motionOn();
      await tester.pumpWidget(app());
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(app(reduced: true));
      expect(shine, findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('SpecTextFade', () {
    Widget app(int turn, {bool reduced = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SpecTextFade(turn: turn, child: const SizedBox()),
      ),
    );

    testWidgets('R11 · with reduced motion the text is there at once', (
      tester,
    ) async {
      motionOn();
      await tester.pumpWidget(app(0, reduced: true));
      await tester.pumpWidget(app(1, reduced: true));
      expect(fadeOf(tester), 1);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('R12 · a new turn during the fade carries on from the current '
        'opacity', (tester) async {
      motionOn();
      await tester.pumpWidget(app(0));
      await tester.pumpWidget(app(1));
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(AppMotion.base ~/ 2);
      final mid = fadeOf(tester);
      expect(mid, inExclusiveRange(0, 1));
      await tester.pumpWidget(app(2));
      expect(fadeOf(tester), mid);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(AppMotion.base);
      expect(fadeOf(tester), 1);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
