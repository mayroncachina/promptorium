import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/features/specs/spec_verifier.dart';
import 'package:promptorium/features/specs/widgets/spec_sync_bar.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import 'spec_verifier_test.dart' show specText, answer;

void main() {
  testWidgets(
    'user selects a spec, verifies it and sees report and reopening controls',
    (tester) async {
      final tmp = Directory.systemTemp.createTempSync('spec-sync-ui-');
      final db = memoryDatabase();
      late ProviderContainer c;
      late Workspace ws;
      late Spec spec;
      await tester.runAsync(() async {
        final root = await createRepo(tmp);
        ws = await db
            .into(db.workspaces)
            .insertReturning(
              WorkspacesCompanion.insert(path: root, name: 'ws'),
            );
        c = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            activeWorkspaceProvider.overrideWithValue(ws),
            verificationAgentProvider.overrideWithValue(
              (ws, prompt, provider, token) async => answer(),
            ),
          ],
        );
        Directory('$root/specs').createSync();
        File('$root/specs/SPEC-001.md').writeAsStringSync(specText);
        await c.read(specServiceProvider).sync(ws);
        spec = (await c.read(specsRepoProvider).getByCode(ws.id, 'SPEC-001'))!;
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  final specs = ref.watch(specsProvider(ws.id)).value ?? [spec];
                  return SpecSyncBar(
                    workspace: ws,
                    specs: specs,
                    selected: specs.first,
                  );
                },
              ),
            ),
          ),
        ),
      );
      Future<void> until(bool Function() done) async {
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 20));
          if (done()) return;
        }
        fail('UI did not update');
      }

      try {
        await tester.tap(find.byKey(const ValueKey('specs-verify')));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('serão marcadas como concluídas'),
          findsOneWidget,
        );
        await tester.tap(find.text('Verificar e concluir comprovadas'));
        await until(
          () => find.text('Resultado da verificação').evaluate().isNotEmpty,
        );
        expect(find.text('SPEC-001: concluída'), findsOneWidget);
        await tester.tap(find.text('Fechar'));
        await tester.pumpAndSettle();
        expect(find.text('Reabrir'), findsOneWidget);
        await tester.tap(find.text('Relatório / origem'));
        await until(
          () => find
              .textContaining('Conclusão verificada pelo agente.')
              .evaluate()
              .isNotEmpty,
        );
        expect(find.textContaining('R1 · implementado'), findsOneWidget);
        await tester.tap(find.text('Fechar'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reabrir'));
        await until(() => find.text('Reabrir').evaluate().isEmpty);
        await tester.runAsync(() async {
          expect(
            (await c.read(specsRepoProvider).getById(spec.id))!.stage,
            SpecStage.backlog,
          );
        });
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await db.close();
        });
        await tester.pump(const Duration(milliseconds: 400));
        tmp.deleteSync(recursive: true);
      }
    },
  );
}
