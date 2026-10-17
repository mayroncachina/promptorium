import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/autopilot.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/features/board/spec_runner.dart';
import 'package:promptorium/features/board/widgets/card_extras.dart';
import 'package:promptorium/features/board/widgets/wave_graph.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';
import 'board_screen_test.dart' show pumpBoard, pumpFor, text;
import 'spec_runner_test.dart' show resultLine;

Spec spec(int id, String code, List<String> deps, {SpecStage? stage}) => Spec(
  id: id,
  workspaceId: 1,
  code: code,
  title: code,
  status: SpecStatus.approved,
  path: 'specs/$code.md',
  stage: stage ?? SpecStage.backlog,
  requirements: const [],
  dependsOn: deps,
  autoAdvance: true,
  reviewRounds: 0,
  gateResends: 0,
  rejectedHunks: 0,
);

void main() {
  group('pure', () {
    test('dependency waves and the next wave', () {
      final specs = [
        spec(1, 'S1', [], stage: SpecStage.done),
        spec(2, 'S2', ['S1']),
        spec(3, 'S3', ['S1', 'S2']),
        spec(4, 'S4', []),
        spec(5, 'S5', ['S6']), // cycle
        spec(6, 'S6', ['S5']),
      ];
      final w = dependencyWaves(specs);
      expect([for (final s in specs.take(4)) w[s.id]], [0, 1, 2, 0]);
      // A cycle ends (any finite wave).
      expect(w[5], isNotNull);
      expect(w[6], isNotNull);
      expect(nextWave(specs, w), 0); // S4 is not done
      expect(nextWave([specs[0], specs[1]], w), 1);
    });

    test('suggestions marker, live tool line, saved order', () {
      expect(
        parseSuggestions(
          'ok\nSPEC SUGESTÃO: dividir R3 em dois\nspec sugestao: R5 sobra\n',
        ),
        ['dividir R3 em dois', 'R5 sobra'],
      );
      expect(parseSuggestions(null), isEmpty);
      final t = ToolItem(
        id: '1',
        name: 'Bash',
        input: {'command': 'flutter test'},
      );
      expect(lastToolLine([NoticeItem('x'), t]), 'Bash · flutter test');
      expect(lastToolLine([NoticeItem('x')]), isNull);
      SpecCardData d(Spec s) => SpecCardData(
        spec: s,
        steps: const [],
        sessions: const [],
        blockers: const [],
      );
      final ordered = orderedCards([
        d(spec(1, 'S1', []).copyWith(boardOrder: const Value(2))),
        d(spec(2, 'S2', [])),
        d(spec(3, 'S3', []).copyWith(boardOrder: const Value(0))),
      ]);
      expect(ordered.map((x) => x.spec.code), ['S3', 'S1', 'S2']);
    });
  });

  group('autopilot limits (temporary repo, fake CLI)', () {
    late Directory tmp;
    late String repo;
    late FakeCli cli;
    late FakeNotifier notifier;
    late ProviderContainer c;
    late Workspace ws;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('promptorium-pilot-');
      repo = await createRepo(tmp);
      Directory('$repo/specs').createSync();
      for (final n in [1, 2, 3]) {
        File('$repo/specs/SPEC-00$n-x.md').writeAsStringSync(
          '---\nid: SPEC-00$n\nstatus: aprovada\n---\n\n# S$n\n\n'
          '## Requisitos\n\n- R1 · a\n',
        );
      }
      await gitIn(repo, ['add', '.']);
      await gitIn(repo, ['commit', '-q', '-m', 'specs']);
      Directory('$repo/.promptorium').createSync();
      cli = FakeCli();
      notifier = FakeNotifier();
      c = sessionContainer(
        sessionOverrides(
          db: memoryDatabase(),
          cli: cli,
          notifier: notifier,
          worktreesBase: '${tmp.path}/wt',
        ),
      );
      await c.read(appSettingsProvider.notifier).load();
      ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'r');
      await c.read(specServiceProvider).sync(ws);
    });

    tearDown(() {
      c.dispose();
      tmp.deleteSync(recursive: true);
    });

    test('paralelo: at most N specs at once; the next starts when one '
        'reaches Review', () async {
      File('$repo/.promptorium/config.yml')
          .writeAsStringSync('autopilot:\n  paralelo: 2\n');
      await c.read(autopilotProvider.notifier).start(ws.id);
      await settle();
      expect(cli.processes, hasLength(2));
      cli.processes.first.emit(resultLine('ETAPA CONCLUÍDA: R1'));
      for (var i = 0; i < 50 && cli.processes.length < 3; i++) {
        await settle();
      }
      expect(cli.processes, hasLength(3));
    });

    test('orcamento-dia: spent → off with a notification; nothing new '
        'starts', () async {
      File(
        '$repo/.promptorium/config.yml',
      ).writeAsStringSync('autopilot:\n  paralelo: 1\n  orcamento-dia: 0.05\n');
      await c.read(autopilotProvider.notifier).start(ws.id);
      await settle();
      expect(cli.processes, hasLength(1));
      cli.last.emit(resultLine('ETAPA CONCLUÍDA: R1', cost: 0.06));
      for (var i = 0; i < 20; i++) {
        await settle();
      }
      expect(c.read(autopilotProvider), isEmpty);
      expect(cli.processes, hasLength(1));
      expect(notifier.shown.map((n) => n.$1), contains('Autopilot parado'));
      expect(
        await c.read(autopilotProvider.notifier).spentToday(ws.id),
        closeTo(0.06, 1e-9),
      );
    });

    test('a crashed session leaves its step waiting for the user', () async {
      final spec = (await c
          .read(specsRepoProvider)
          .getByCode(ws.id, 'SPEC-001'))!;
      await c.read(specRunnerProvider).runNext(spec.id);
      await settle();
      await cli.last.finish(1);
      for (var i = 0; i < 10; i++) {
        await settle();
      }
      final rows = await c.read(specStepsRepoProvider).bySpec(spec.id);
      expect(rows.single.status, StepStatus.needsInput);
    });
  });

  testWidgets('Grafo view, suggestion banner (Ignorar) and column order', (
    tester,
  ) async {
    final (c, db) = await pumpBoard(tester);
    await tester.runAsync(
      () => c
          .read(specSuggestionsRepoProvider)
          .add(specId: 2, body: 'dividir R3', steps: 'R2'),
    );
    await pumpFor(tester, 20);
    expect(
      find.byKey(const ValueKey('board-suggestion-SPEC-002')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('board-suggestion-ignore-SPEC-002')),
    );
    await pumpFor(tester, 20);
    expect(
      find.byKey(const ValueKey('board-suggestion-SPEC-002')),
      findsNothing,
    );

    // Backlog: SPEC-003, SPEC-004 → move SPEC-004 up.
    await tester.tap(find.byKey(const ValueKey('board-menu-SPEC-004')));
    await pumpFor(tester, 20);
    await tester.tap(find.text('Subir na coluna'));
    await pumpFor(tester, 20);
    final order = {
      for (final s
          in await tester.runAsync(
                () => c.read(specsRepoProvider).watchByWorkspace(1).first,
              ) ??
              const <Spec>[])
        s.code: s.boardOrder,
    };
    expect(order['SPEC-004'], 0);
    expect(order['SPEC-003'], 1);

    await tester.tap(find.byKey(const ValueKey('board-view-graph')));
    await pumpFor(tester, 10);
    expect(find.byKey(const ValueKey('board-graph')), findsOneWidget);
    expect(find.byKey(const ValueKey('board-wave-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('board-wave-1')), findsOneWidget);
    expect(text(tester, 'board-progress-SPEC-002'), '1/3');
    expect(db, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('applySuggestionPrompt names the spec and the steps', (_) async {
    final s = SpecSuggestion(
      id: 1,
      specId: 1,
      body: 'dividir R3',
      steps: 'R2',
      state: 'pendente',
      createdAt: DateTime(2026),
    );
    final p = applySuggestionPrompt(spec(1, 'SPEC-001', []), s);
    expect(p, contains('@specs/SPEC-001.md'));
    expect(p, contains('das etapas R2'));
    expect(p, contains('"dividir R3"'));
    expect(AppTheme.dark(), isNotNull);
  });
}
