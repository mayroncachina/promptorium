import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/instructions/instructions_view.dart';
import 'package:promptorium/features/project/project_plan.dart';
import 'package:promptorium/ui/shell/navigation.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import '../../ui/preferences_test.dart' show unmount;
import 'project_screen_test.dart' show pumpProject;

/// SPEC-113 T3: Projeto › Instruções as a tab, as a dialog in the planning
/// flow (R6), and Ferramentas › Instruções as a shortcut (R7).
void main() {
  Future<void> settleIo(WidgetTester tester, bool Function() until) async {
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    for (var i = 0; DateTime.now().isBefore(deadline); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (i >= 2 && until()) return;
    }
    fail('não apareceu');
  }

  bool shows(String k) => find.byKey(ValueKey(k)).evaluate().isNotEmpty;

  testWidgets('R6: a repository with code has the Instruções tab next to '
      'Configuração; a request from outside opens it (R7)', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('promptorium-instr-tab-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File('${tmp.path}/pubspec.yaml').writeAsStringSync('name: x\n');
    File('${tmp.path}/AGENTS.md').writeAsStringSync('# x\n');
    File('${tmp.path}/CLAUDE.md').writeAsStringSync('@AGENTS.md\n');
    final (c, _) = await pumpProject(tester, path: tmp.path);
    await settleIo(tester, () => shows('project-tab-instructions'));
    final tabs = tester.widget<TabBar>(
      find.byKey(const ValueKey('project-tabs')),
    );
    final labels = [for (final t in tabs.tabs) (t as Tab).text];
    expect(labels, [
      'Saúde',
      'Configuração',
      'Instruções',
      'Memória',
      'Métricas',
    ]);
    expect(shows('instructions-detail'), isFalse);

    c.read(projectInstructionsRequestProvider.notifier).request();
    await settleIo(tester, () => shows('instructions-editor-AGENTS.md'));
    expect(c.read(projectInstructionsRequestProvider), isFalse);
    expect(tester.takeException(), isNull);
    await unmount(tester, c);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('R6: in the planning flow Instruções opens in a dialog, by the '
      'button and by a request from outside', (tester) async {
    final (c, _) = await pumpProject(tester, data: const ProjectPlanData());
    expect(
      find.byKey(const ValueKey('project-instructions-open')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('project-instructions-open')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('instructions-dialog')), findsOneWidget);
    Navigator.of(
      tester.element(find.byKey(const ValueKey('instructions-dialog'))),
    ).pop();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('instructions-dialog')), findsNothing);

    c.read(projectInstructionsRequestProvider.notifier).request();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('instructions-dialog')), findsOneWidget);
    expect(c.read(projectInstructionsRequestProvider), isFalse);
    await unmount(tester, c);
  });

  testWidgets('R7: Ferramentas › Instruções is a shortcut to Projeto › '
      'Instruções', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = memoryDatabase();
    addTearDown(db.close);
    final c = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    await tester.runAsync(() => c.read(appSettingsProvider.notifier).load());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: InstructionsShortcut()),
        ),
      ),
    );
    expect(find.text('As instruções agora ficam no Projeto'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('instructions-shortcut-open')));
    await tester.pump();
    expect(c.read(navigationProvider), AppSection.project);
    expect(c.read(projectInstructionsRequestProvider), isTrue);
    await unmount(tester, c);
  });
}
