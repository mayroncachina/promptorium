import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';

void main() {
  testWidgets(
    'opening directly on Board discovers concluded files in Feito and the Canvas',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final root = Directory.systemTemp.createTempSync('board-discovery-');
      Directory('${root.path}/specs').createSync();
      File('${root.path}/specs/SPEC-001.md').writeAsStringSync(
        '---\nid: SPEC-001\nstatus: concluida\n---\n# Já entregue\n',
      );
      File('${root.path}/specs/SPEC-002.md').writeAsStringSync(
        '---\nid: SPEC-002\nstatus: feita\n---\n# Também entregue\n',
      );
      File('${root.path}/specs/SPEC-003.md').writeAsStringSync(
        '---\nid: SPEC-003\nstatus: arquivada\n---\n# Arquivada\n',
      );
      final db = memoryDatabase();
      late ProviderContainer c;
      await tester.runAsync(() async {
        final ws = await db
            .into(db.workspaces)
            .insertReturning(
              WorkspacesCompanion.insert(path: root.path, name: 'ws'),
            );
        c = ProviderContainer(
          overrides: [
            ...sessionOverrides(
              db: db,
              cli: FakeCli(),
              notifier: FakeNotifier(),
            ),
            activeWorkspaceProvider.overrideWithValue(ws),
          ],
        );
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: BoardScreen()),
          ),
        ),
      );
      try {
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
          if (find.text('Também entregue').evaluate().isNotEmpty &&
              find.text('Já entregue').evaluate().isNotEmpty) {
            break;
          }
        }
        final done = find.byKey(const ValueKey('board-column-done'));
        for (final title in ['Já entregue', 'Também entregue']) {
          expect(
            find.descendant(of: done, matching: find.text(title)),
            findsOneWidget,
          );
        }
        expect(find.text('Arquivada'), findsNothing);
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('board-column-count-done')),
              )
              .data,
          '2',
        );
        expect(find.byKey(const ValueKey('specs-sync')), findsOneWidget);
        expect(find.text('Pasta de specs: specs/'), findsOneWidget);
        await tester.runAsync(() async {
          final rows = await db.select(db.specs).get();
          expect(rows.map((s) => s.stage), everyElement(SpecStage.done));
          expect(await db.select(db.sessions).get(), isEmpty);
          expect(await db.select(db.specSteps).get(), isEmpty);
        });
        // Canvas: the same specs show the "Feito" stage.
        c.read(boardGraphViewProvider.notifier).set(true);
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        for (final code in ['SPEC-001', 'SPEC-002']) {
          final node = find.byKey(ValueKey('board-open-$code'));
          expect(node, findsOneWidget);
          expect(
            find.descendant(of: node, matching: find.text('Feito')),
            findsOneWidget,
          );
        }
        expect(find.byKey(const ValueKey('board-open-SPEC-003')), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 400));
        root.deleteSync(recursive: true);
      }
    },
  );
}
