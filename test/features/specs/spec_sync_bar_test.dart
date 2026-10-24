import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/project/project_config.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/features/specs/spec_verifier.dart';
import 'package:promptorium/features/specs/widgets/spec_sync_bar.dart';
import 'package:promptorium/features/specs/workspace_watcher.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import 'spec_verifier_test.dart' show specText, answer;

/// Watcher that never delivers events: only the button can synchronize.
class _SilentWatcher extends WorkspaceWatcher {
  @override
  Set<int> build() => const {};
}

/// Mounts a [SpecSyncBar] over a git repository with `specs/SPEC-001.md`.
Future<({ProviderContainer c, AppDatabase db, Workspace ws, Directory tmp})>
_mount(WidgetTester tester, VerificationAgent agent) async {
  final tmp = Directory.systemTemp.createTempSync('spec-sync-ui-');
  final db = memoryDatabase();
  late ProviderContainer c;
  late Workspace ws;
  late Spec spec;
  await tester.runAsync(() async {
    final root = await createRepo(tmp);
    ws = await db
        .into(db.workspaces)
        .insertReturning(WorkspacesCompanion.insert(path: root, name: 'ws'));
    c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        activeWorkspaceProvider.overrideWithValue(ws),
        workspaceWatcherProvider.overrideWith(_SilentWatcher.new),
        verificationAgentProvider.overrideWithValue(agent),
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
  return (c: c, db: db, ws: ws, tmp: tmp);
}

Future<void> _unmount(
  WidgetTester tester,
  ({ProviderContainer c, AppDatabase db, Workspace ws, Directory tmp}) m,
) async {
  await tester.pumpWidget(const SizedBox());
  m.c.dispose();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await m.db.close();
  });
  await tester.pump(const Duration(milliseconds: 400));
  m.tmp.deleteSync(recursive: true);
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 500; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (done()) return;
  }
  fail('UI did not update');
}

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
            // The real watcher reacts to the verifier rewriting the spec and
            // races the UI under the full suite.
            workspaceWatcherProvider.overrideWith(_SilentWatcher.new),
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
        for (var i = 0; i < 500; i++) {
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
        await until(
          () => find.text('SPEC-001: concluída').evaluate().isNotEmpty,
        );
        await tester.tap(find.text('Fechar'));
        await tester.pumpAndSettle();
        await until(() => find.text('Reabrir').evaluate().isNotEmpty);
        await tester.tap(find.text('Relatório / origem'));
        await until(
          () => find
              .textContaining('Conclusão verificada pelo agente.')
              .evaluate()
              .isNotEmpty,
        );
        expect(find.textContaining('R1 · implementado'), findsOneWidget);
        expect(
          find.textContaining(RegExp(r'Revisão: [0-9a-f]{12} · ')),
          findsOneWidget,
        );
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

  testWidgets('"Sincronizar specs" imports files the watcher did not deliver', (
    tester,
  ) async {
    final m = await _mount(tester, (ws, prompt, provider, token) async => null);
    try {
      await tester.runAsync(() async {
        File(
          '${m.ws.path}/specs/SPEC-002.md',
        ).writeAsStringSync('---\nid: SPEC-002\nstatus: feita\n---\n# Nova\n');
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(
          await m.c.read(specsRepoProvider).getByCode(m.ws.id, 'SPEC-002'),
          isNull,
        );
      });
      await tester.tap(find.byKey(const ValueKey('specs-sync')));
      Spec? found;
      for (var i = 0; i < 500 && found == null; i++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          found = await m.c
              .read(specsRepoProvider)
              .getByCode(m.ws.id, 'SPEC-002');
        });
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(found!.stage, SpecStage.done);
      await _until(
        tester,
        () => find.text('Sincronizar specs').evaluate().isNotEmpty,
      );
      expect(find.text('Pasta de specs: specs/'), findsOneWidget);
      await tester.runAsync(
        () => ProjectConfig.save(
          m.ws.path,
          const ProjectConfig(specsDir: 'docs/specs'),
        ),
      );
      m.c.invalidate(projectConfigProvider(m.ws.path));
      await _until(
        tester,
        () => find.text('Pasta de specs: docs/specs/').evaluate().isNotEmpty,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester, m);
    }
  });

  testWidgets('agent failure shows the error and keeps the spec open', (
    tester,
  ) async {
    final m = await _mount(
      tester,
      (ws, prompt, provider, token) async =>
          throw const SpecException('Agente indisponível.'),
    );
    try {
      await tester.tap(find.byKey(const ValueKey('specs-verify')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verificar e concluir comprovadas'));
      await _until(
        tester,
        () => find.text('Resultado da verificação').evaluate().isNotEmpty,
      );
      expect(find.text('SPEC-001: Agente indisponível.'), findsOneWidget);
      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();
      expect(find.text('Reabrir'), findsNothing);
      await tester.runAsync(() async {
        final spec = (await m.c
            .read(specsRepoProvider)
            .getByCode(m.ws.id, 'SPEC-001'))!;
        expect(spec.stage, SpecStage.backlog);
        expect(
          File('${m.ws.path}/specs/SPEC-001.md').readAsStringSync(),
          specText,
        );
        expect(await m.c.read(specVerifierProvider).report(m.ws, spec), isNull);
      });
      expect(tester.takeException(), isNull);
    } finally {
      await _unmount(tester, m);
    }
  });
}
