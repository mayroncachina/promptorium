import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/specs/specs_screen.dart';
import 'package:promptorium/features/specs/workspace_watcher.dart';
import 'package:promptorium/features/board/widgets/spec_steps_panel.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:re_editor/re_editor.dart' show CodeEditor;

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';
import 'spec_file_test.dart' show sample;

/// Real file IO does not run under FakeAsync: let it run, then pump, until
/// [until] holds (bounded; the full suite runs files in parallel).
Future<void> settleIo(WidgetTester tester, {bool Function()? until}) async {
  for (var i = 0; i < 300; i++) {
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

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('promptorium-specs-ui-');
    Directory('${tmp.path}/specs').createSync();
    File('${tmp.path}/specs/SPEC-002-sessoes.md').writeAsStringSync(sample);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = memoryDatabase();
    final c = ProviderContainer(
      overrides: [
        ...sessionOverrides(db: db, cli: FakeCli(), notifier: FakeNotifier()),
        workspaceWatcherProvider.overrideWith(QuietWorkspaceWatcher.new),
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
    // (the button only acts once the file is loaded)
    final dialog = find.byKey(const ValueKey('spec-no-design-dialog'));
    for (var i = 0; i < 5 && dialog.evaluate().isEmpty; i++) {
      await tester.tap(find.byKey(const ValueKey('spec-approve')));
      await settleIo(tester, until: () => dialog.evaluate().isNotEmpty);
    }
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
}
