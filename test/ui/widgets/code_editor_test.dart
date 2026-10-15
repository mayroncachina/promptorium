import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/app_settings_repo.dart';
import 'package:promptorium/ui/shell/editor_zoom.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/ui/widgets/code_editor/app_code_editor.dart';
import 'package:promptorium/ui/widgets/zoom_control.dart';
import 'package:re_editor/re_editor.dart' show CodeEditor, CodeShortcutType;

import '../../helpers/test_db.dart';

/// Container over [db] that does not close it (to "reopen the app").
ProviderContainer _container(AppDatabase db) =>
    ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);

Future<void> _pumpEditor(
  WidgetTester tester,
  ProviderContainer c,
  CodeLineEditingController controller,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Column(
            children: [
              const ZoomControl(editorKey: 'specs'),
              Expanded(
                child: AppCodeEditor(
                  controller: controller,
                  editorKey: 'specs',
                  language: CodeLanguage.markdown,
                  baseFontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

double _fontSize(WidgetTester tester) =>
    tester.widget<CodeEditor>(find.byType(CodeEditor)).style!.fontSize!;

void main() {
  test('editorFontSize = base × zoom; language by extension', () {
    expect(editorFontSize(12, 100), 12);
    expect(editorFontSize(12, 150), 18);
    expect(editorFontSize(13, 70), closeTo(9.1, 1e-9));
    expect(CodeLanguage.forPath('specs/SPEC-001-a.md'), CodeLanguage.markdown);
    expect(CodeLanguage.forPath('lib/main.dart'), CodeLanguage.dart);
    expect(CodeLanguage.forPath('pubspec.yaml'), CodeLanguage.yaml);
    expect(CodeLanguage.forPath('a/.mcp.json'), CodeLanguage.json);
    expect(CodeLanguage.forPath('Makefile'), CodeLanguage.makefile);
    expect(CodeLanguage.forPath('linux/CMakeLists.txt'), CodeLanguage.cmake);
    expect(CodeLanguage.forPath('tool/run.sh'), CodeLanguage.shell);
    expect(CodeLanguage.forPath('notas.xyz'), CodeLanguage.plaintext);
  });

  testWidgets('zoom control changes the editor fontSize and persists per '
      'editor across restarts', (tester) async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final controller = CodeLineEditingController.fromText('# Título\n\ntexto');
    addTearDown(controller.dispose);

    var c = _container(db);
    await c.read(appSettingsProvider.notifier).load();
    await _pumpEditor(tester, c, controller);
    expect(_fontSize(tester), 12);
    expect(find.text('100%'), findsOneWidget);

    await tester.tap(find.text('+'));
    await tester.pump();
    await tester.tap(find.text('+'));
    await tester.pump();
    expect(find.text('120%'), findsOneWidget);
    expect(_fontSize(tester), closeTo(14.4, 1e-9));
    // Another editor key is independent.
    expect(c.read(editorZoomProvider('code')), 100);

    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.pump(Duration.zero);
    expect(
      (await AppSettingsRepo(db).getAll())[AppSettingKeys.editorZoom('specs')],
      '120',
    );

    // "Reopen the app".
    c = _container(db);
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    await _pumpEditor(tester, c, controller);
    expect(find.text('120%'), findsOneWidget);
    expect(_fontSize(tester), closeTo(14.4, 1e-9));
    await tester.tap(find.text('120%')); // reset
    await tester.pump();
    expect(_fontSize(tester), 12);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });

  test('find locates matches and replace all rewrites them', () async {
    final controller = CodeLineEditingController.fromText(
      '- R1 · worktree\n- R2 · sqlite\nworktree de novo\n',
    );
    final find = CodeFindController(controller);
    addTearDown(() {
      find.dispose();
      controller.dispose();
    });

    Future<void> waitResult(bool Function() done) async {
      for (var i = 0; i < 200 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    find.replaceMode(); // Ctrl+H
    find.findInputController.text = 'worktree';
    await waitResult(() => find.value?.result?.matches.length == 2);
    expect(find.value!.result!.matches, hasLength(2));
    expect(find.value!.replaceMode, isTrue);

    find.replaceInputController.text = 'git worktree';
    find.replaceAllMatches();
    await waitResult(() => controller.text.contains('git worktree de novo'));
    expect(
      controller.text,
      '- R1 · git worktree\n- R2 · sqlite\ngit worktree de novo\n',
    );
  });

  test('Ctrl+H is bound to replace, Ctrl+F to find', () {
    const s = AppCodeShortcuts();
    expect(
      s
          .build(CodeShortcutType.replace)!
          .whereType<SingleActivator>()
          .map((a) => (a.trigger.keyLabel, a.control, a.alt)),
      contains(('H', true, false)),
    );
    expect(
      s
          .build(CodeShortcutType.find)!
          .whereType<SingleActivator>()
          .map((a) => (a.trigger.keyLabel, a.control)),
      contains(('F', true)),
    );
  });
}
