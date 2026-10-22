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
    'opening directly on Board discovers a concluded file without visiting Specs',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final root = Directory.systemTemp.createTempSync('board-discovery-');
      Directory('${root.path}/specs').createSync();
      File('${root.path}/specs/SPEC-001.md').writeAsStringSync(
        '---\nid: SPEC-001\nstatus: concluida\n---\n# Já entregue\n',
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
          if (find.text('Já entregue').evaluate().isNotEmpty) break;
        }
        expect(find.text('Já entregue'), findsOneWidget);
        expect(find.byKey(const ValueKey('specs-sync')), findsOneWidget);
        expect(find.text('Pasta de specs: specs/'), findsOneWidget);
        await tester.runAsync(() async {
          final rows = await db.select(db.specs).get();
          expect(rows.single.stage, SpecStage.done);
          expect(await db.select(db.sessions).get(), isEmpty);
        });
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
