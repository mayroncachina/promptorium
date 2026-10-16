import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/board/spec_runner.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/specs/spec_service.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';

const specText = '''---
id: SPEC-001
status: aprovada
---

# Extração do schema

## Requisitos

- R1 · Extrair tabelas
- R2 · Extrair índices
- R3 · Extrair generators
- R4 · Ligar na CLI
''';

/// `result` line of the fixture with [text] as the final answer.
String resultLine(String text, {bool success = true, double cost = 0.01}) {
  final j = jsonDecode(
    fixtureLines().firstWhere((l) => l.contains('"result"')),
  ) as Map<String, dynamic>;
  j['result'] = text;
  j['total_cost_usd'] = cost;
  if (!success) {
    j['subtype'] = 'error_during_execution';
    j['is_error'] = true;
  }
  return jsonEncode(j);
}

void main() {
  group('pure', () {
    test('marker: last line wins; accents, case, "e" and lists', () {
      expect(parseStepMarker(null), isEmpty);
      expect(parseStepMarker('feito, sem marcador'), isEmpty);
      expect(parseStepMarker('ok\nETAPA CONCLUÍDA: R3'), {'R3'});
      expect(parseStepMarker('etapas concluidas: r1, R2 e R3.'), {
        'R1',
        'R2',
        'R3',
      });
      expect(
        parseStepMarker('ETAPA CONCLUÍDA: R1\n…depois…\nETAPA CONCLUÍDA: R2'),
        {'R2'},
      );
    });

    test('prompt: spec embedded, done / now / later, commit and marker', () {
      final spec = Spec(
        id: 1,
        workspaceId: 1,
        code: 'SPEC-001',
        title: 'Extração do schema',
        status: SpecStatus.approved,
        path: 'specs/SPEC-001-x.md',
        stage: SpecStage.running,
        requirements: const [],
        dependsOn: const [],
        autoAdvance: true,
      );
      const steps = [
        StepView(id: 'R1', text: 'Extrair tabelas', status: StepStatus.done),
        StepView(id: 'R2', text: 'Extrair índices'),
        StepView(id: 'R3', text: 'Extrair generators'),
      ];
      final p = specStepPrompt(
        spec: spec,
        specText: specText,
        steps: steps,
        todo: ['R2'],
      );
      expect(p, startsWith('Implemente a etapa R2 da spec SPEC-001'));
      expect(p, contains('- R2 · Extrair índices'));
      expect(p, contains('Já concluídas (commits nesta branch):\n- R1 ·'));
      expect(p, contains('(não implemente agora): R3.'));
      expect(p, contains('<spec>\n---\nid: SPEC-001'));
      expect(p, contains('"SPEC-001 R2: <resumo do que mudou>"'));
      expect(p, contains('linha exata: ETAPA CONCLUÍDA: R2'));
      expect(
        specSessionTitle(spec, steps, ['R2']),
        'SPEC-001 · R2 · Extrair índices',
      );
      expect(
        specSessionTitle(spec, steps, ['R1', 'R2', 'R3']),
        'SPEC-001 · R1–R3 · Extração do schema',
      );
    });
  });

  group('SpecRunner (temporary repo, fake CLI)', () {
    late Directory tmp;
    late String repo;
    late FakeCli cli;
    late ProviderContainer c;
    late Workspace ws;
    late Spec spec;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('promptorium-runner-');
      repo = await createRepo(tmp);
      Directory('$repo/specs').createSync();
      File('$repo/specs/SPEC-001-extracao.md').writeAsStringSync(specText);
      cli = FakeCli();
      c = sessionContainer(
        sessionOverrides(
          db: memoryDatabase(),
          cli: cli,
          notifier: FakeNotifier(),
          worktreesBase: '${tmp.path}/wt',
        ),
      );
      await c.read(appSettingsProvider.notifier).load();
      ws = await c.read(workspacesRepoProvider).add(path: repo, name: 'repo');
      await c.read(specServiceProvider).sync(ws);
      spec = (await c.read(specsRepoProvider).getByCode(ws.id, 'SPEC-001'))!;
    });

    tearDown(() {
      c.dispose();
      tmp.deleteSync(recursive: true);
    });

    Future<Map<String, StepStatus>> states() async {
      final s = (await c.read(specsRepoProvider).getById(spec.id))!;
      final rows = await c.read(specStepsRepoProvider).bySpec(spec.id);
      return {for (final v in stepsOf(s, rows)) v.id: v.status};
    }

    Future<SpecStage> stage() async =>
        (await c.read(specsRepoProvider).getById(spec.id))!.stage;

    test('step by step in the spec worktree: marker → done → next session; '
        'no marker → waits for the user; last step → Review', () async {
      final runner = c.read(specRunnerProvider);
      final first = await runner.runNext(
        spec.id,
        mode: ClaudePermissionMode.acceptEdits,
      );
      await settle();

      // Own worktree / branch, stored on the spec.
      var row = (await c.read(specsRepoProvider).getById(spec.id))!;
      expect(row.branch, startsWith('pr/spec-001-extracao-do-schema-'));
      expect(cli.cwds.single, row.worktreePath);
      expect(Directory(row.worktreePath!).existsSync(), isTrue);
      final s1 = (await c.read(sessionsRepoProvider).getById(first))!;
      expect(s1.specId, spec.id);
      expect(s1.steps, 'R1'); // 4 steps > 3: one per session
      expect(s1.title, 'SPEC-001 · R1 · Extrair tabelas');
      final sent = cli.last.writtenJson.single['message']['content'] as String;
      expect(sent, contains('<spec>'));
      expect(await states(), {
        'R1': StepStatus.running,
        'R2': StepStatus.pending,
        'R3': StepStatus.pending,
        'R4': StepStatus.pending,
      });
      expect(await stage(), SpecStage.running);

      // Busy: a second run is refused.
      await expectLater(
        runner.runNext(spec.id),
        throwsA(isA<SpecRunException>()),
      );

      // R1 done → its process is closed and R2 starts in the same worktree.
      cli.last.emit(resultLine('Pronto.\nETAPA CONCLUÍDA: R1'));
      await settle();
      await settle();
      expect((await states())['R1'], StepStatus.done);
      expect(cli.processes, hasLength(2));
      expect(cli.processes.first.signals, isNotEmpty);
      expect(cli.cwds.last, row.worktreePath);
      expect(
        cli.args.last,
        containsAllInOrder(['--permission-mode', 'acceptEdits']),
      );
      final sessions = await c.read(sessionsRepoProvider).bySpec(spec.id);
      expect(sessions.map((s) => s.steps), ['R1', 'R2']);
      final second = sessions.last.id;

      // R2 without the marker: waits for the user, no new session.
      cli.last.emit(resultLine('Qual banco devo usar?'));
      await settle();
      expect((await states())['R2'], StepStatus.needsInput);
      expect(cli.processes, hasLength(2));
      expect(await stage(), SpecStage.running);

      // The user answers in the same session; now it finishes.
      await c.read(sessionManagerProvider.notifier).send(second, 'O Postgres.');
      await settle();
      expect((await states())['R2'], StepStatus.running);
      cli.last.emit(resultLine('ETAPA CONCLUÍDA: R2'));
      await settle();
      await settle();
      expect(cli.processes, hasLength(3));

      // Turn off auto-advance: R3 done does not open R4.
      await c.read(specsRepoProvider).setAutoAdvance(spec.id, false);
      cli.last.emit(resultLine('ETAPA CONCLUÍDA: R3'));
      await settle();
      await settle();
      expect(cli.processes, hasLength(3));
      expect((await states())['R3'], StepStatus.done);

      await runner.runNext(spec.id);
      await settle();
      cli.last.emit(resultLine('ETAPA CONCLUÍDA: R4'));
      await settle();
      expect((await states()).values.toSet(), {StepStatus.done});
      expect(await stage(), SpecStage.review);
      row = (await c.read(specsRepoProvider).getById(spec.id))!;
      expect(
        (await c.read(sessionsRepoProvider).bySpec(spec.id))
            .map((s) => s.worktreePath),
        everyElement(row.worktreePath),
      );
    });

    test('small spec runs whole in one session; stop → pending; failure → '
        'waits; blocked spec is refused', () async {
      File(
        '$repo/specs/SPEC-001-extracao.md',
      ).writeAsStringSync(specText.replaceFirst('- R4 · Ligar na CLI\n', ''));
      final runner = c.read(specRunnerProvider);
      final id = await runner.runNext(spec.id);
      await settle();
      expect(
        (await c.read(sessionsRepoProvider).getById(id))!.steps,
        'R1,R2,R3',
      );
      expect(
        cli.last.writtenJson.single['message']['content'],
        contains('ETAPA CONCLUÍDA: R1, R2, R3'),
      );

      await c.read(sessionManagerProvider.notifier).stop(id);
      await settle();
      expect((await states()).values.toSet(), {StepStatus.pending});

      await runner.runNext(spec.id);
      await settle();
      cli.last.emit(resultLine('falhou', success: false));
      await settle();
      expect((await states()).values.toSet(), {StepStatus.needsInput});

      // Not untouched any more: one step per session from now on. A
      // marker naming another step does not count.
      await runner.runNext(spec.id);
      await settle();
      expect(
        (await c.read(sessionsRepoProvider).bySpec(spec.id)).last.steps,
        'R1',
      );
      cli.last.emit(resultLine('ETAPA CONCLUÍDA: R1, R2'));
      await settle();
      await settle();
      expect((await states())['R1'], StepStatus.done);
      // R2 (left waiting by the failure) is picked by the next session.
      expect((await states())['R2'], StepStatus.running);
      expect(
        (await c.read(sessionsRepoProvider).bySpec(spec.id)).last.steps,
        'R2',
      );

      // Dependencies.
      await c
          .read(specServiceProvider)
          .create(
            ws,
            title: 'Depois',
            body: specText
                .replaceFirst('SPEC-001', 'SPEC-002')
                .replaceFirst(
                  'status: aprovada',
                  'status: aprovada\ndepende-de: [SPEC-001]',
                ),
          );
      final s2 = (await c
          .read(specsRepoProvider)
          .getByCode(ws.id, 'SPEC-002'))!;
      await expectLater(
        runner.runNext(s2.id),
        throwsA(
          isA<SpecRunException>().having(
            (e) => e.message,
            'message',
            contains('depende de SPEC-001'),
          ),
        ),
      );
    });
  });
}
