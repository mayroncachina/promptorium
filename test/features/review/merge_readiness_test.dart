import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/board/step_gate.dart';
import 'package:promptorium/features/review/conflict_resolution.dart';
import 'package:promptorium/features/review/merge_readiness.dart';

void main() {
  test('all eight checks classify service blockers and advisory facts', () {
    final result = evaluateReadiness(
      const ReadinessInputs(
        hasSpec: true,
        reviewing: true,
        pendingCriteria: ['a'],
        failedGates: ['R1'],
        openComments: 3,
        stackedOn: 'SPEC-001',
        rootProblem: 'branch errada',
        prProblem: 'check pendente',
        uncommitted: 1,
      ),
    );
    expect(result.items, hasLength(8));
    expect(result.blockers.map((i) => i.id), [
      'revisor',
      'criterios',
      'empilhada',
      'raiz',
    ]);
    expect(result.warnings.map((i) => i.id), [
      'verificacoes',
      'comentarios',
      'pr',
      'worktree',
    ]);
    expect(result.blockers.first.origin, ReadinessOrigin.tela);
    expect(result.canOverride, isFalse);
  });
  test('unknown blocking facts never produce ready or criteria override', () {
    final result = evaluateReadiness(
      const ReadinessInputs(
        hasSpec: true,
        unknown: {'criterios': 'erro', 'raiz': 'git falhou', 'pr': 'offline'},
      ),
    );
    expect(result.level, ReadinessLevel.bloqueio);
    expect(result.blockers, hasLength(2));
    expect(result.warnings, hasLength(1));
    expect(result.canOverride, isFalse);
  });
  test(
    'criteria alone allow a reasoned override; no-spec omits spec facts',
    () {
      expect(
        evaluateReadiness(
          const ReadinessInputs(hasSpec: true, pendingCriteria: ['a']),
        ).canOverride,
        isTrue,
      );
      final result = evaluateReadiness(const ReadinessInputs());
      expect(result.items.map((i) => i.id), [
        'pr',
        'empilhada',
        'raiz',
        'worktree',
      ]);
      expect(result.level, ReadinessLevel.ok);
    },
  );

  test('a source that failed is "não verificado": blocking in raiz, '
      'empilhada and worktree, a warning in pr, verificacoes and comentarios, '
      'never ok', () {
    final result = evaluateReadiness(
      const ReadinessInputs(
        hasSpec: true,
        unknown: {
          'empilhada': 'git falhou',
          'worktree': 'git falhou',
          'verificacoes': 'banco',
          'comentarios': 'banco',
        },
      ),
    );
    ReadinessItem item(String id) => result.items.firstWhere((i) => i.id == id);
    for (final id in ['empilhada', 'worktree', 'verificacoes', 'comentarios']) {
      expect(item(id).level, ReadinessLevel.naoVerificado, reason: id);
    }
    expect(result.blockers.map((i) => i.id), ['empilhada', 'worktree']);
    expect(result.warnings.map((i) => i.id), ['verificacoes', 'comentarios']);
    expect(result.level, ReadinessLevel.bloqueio);
  });

  test('a failed reviewer is a warning with no blocker; the worst item sets '
      'the level; failing steps are the action targets', () {
    final failed = evaluateReadiness(
      const ReadinessInputs(hasSpec: true, reviewerFailed: true),
    );
    expect(failed.level, ReadinessLevel.aviso);
    expect(failed.warnings.single.id, 'revisor');
    expect(failed.warnings.single.detail, contains('passou para você'));

    final gates = evaluateReadiness(
      const ReadinessInputs(hasSpec: true, failedGates: ['R2', 'R3']),
    );
    expect(gates.items.firstWhere((i) => i.id == 'verificacoes').targets, [
      'R2',
      'R3',
    ]);
    expect(gates.level, ReadinessLevel.aviso);

    // Reviewing still blocks even if an older round failed.
    expect(
      evaluateReadiness(
        const ReadinessInputs(
          hasSpec: true,
          reviewing: true,
          reviewerFailed: true,
        ),
      ).blockers.single.id,
      'revisor',
    );
  });

  group('SPEC-043 R5, R7: Resolução do conflito', () {
    ConflictResolution res(
      ResolutionState state, {
      String? checked = 'aaaaaaa111',
    }) => ConflictResolution(
      state: state,
      workspaceId: 1,
      base: 'main',
      checkedSha: checked,
      baseSha: 'bbbbbbb222',
      report: GateReport(
        at: DateTime(2026),
        checks: const [GateCheck(name: 'testes', ok: false)],
      ),
    );

    MergeReadiness of(String? problem) => evaluateReadiness(
      ReadinessInputs(
        hasSpec: true,
        hasResolution: true,
        resolutionProblem: problem,
      ),
    );

    String? problem(
      ConflictResolution r, {
      String? head,
      bool contains = true,
    }) {
      final p = resolutionProblem(
        r,
        head: head,
        baseTip: 'ccccccc333',
        containsBase: contains,
      );
      return p == null ? null : '${p.$1} · ${p.$2}';
    }

    test('in progress, failed or outdated block the merge', () {
      for (final state in [
        ResolutionState.resolvendo,
        ResolutionState.conferindo,
        ResolutionState.reprovada,
        ResolutionState.desatualizada,
      ]) {
        final r = of(problem(res(state)));
        final item = r.items.firstWhere((i) => i.id == 'resolucao');
        expect(item.label, 'Resolução do conflito');
        expect(item.effective, ReadinessLevel.bloqueio, reason: '$state');
        expect(r.level, ReadinessLevel.bloqueio);
      }
      expect(
        problem(res(ResolutionState.reprovada)),
        startsWith('reprovada · O gate reprovou a resolução em testes'),
      );
      final stale = problem(res(ResolutionState.desatualizada))!;
      expect(stale, startsWith('desatualizada'));
      expect(stale, contains('aaaaaaa'));
      expect(stale, contains('ccccccc'));
      expect(
        of(problem(res(ResolutionState.reprovada))).items
            .firstWhere((i) => i.id == 'resolucao')
            .action,
        'Corrigir e verificar',
      );
      expect(
        of(stale).items.firstWhere((i) => i.id == 'resolucao').action,
        'Resolver de novo',
      );
    });

    test('approved only on the current tip of the branch and of the base', () {
      final ok = res(ResolutionState.aprovada);
      expect(problem(ok, head: 'aaaaaaa111'), isNull);
      expect(of(null).level, ReadinessLevel.ok);
      expect(
        of(null).items.firstWhere((i) => i.id == 'resolucao').level,
        ReadinessLevel.ok,
      );
      // R7: the base moved after the gate.
      expect(problem(ok, contains: false), startsWith('desatualizada'));
      // New commits after the gate.
      expect(problem(ok, head: 'ddddddd444'), startsWith('desatualizada'));
      // Without a resolution there is no item.
      expect(
        evaluateReadiness(const ReadinessInputs(hasSpec: true)).items
            .any((i) => i.id == 'resolucao'),
        isFalse,
      );
    });

    test('"Mergear mesmo assim…" stays available, alone or with criteria', () {
      expect(of(problem(res(ResolutionState.reprovada))).canOverride, isTrue);
      expect(
        evaluateReadiness(
          ReadinessInputs(
            hasSpec: true,
            pendingCriteria: const ['a'],
            hasResolution: true,
            resolutionProblem: problem(res(ResolutionState.desatualizada)),
          ),
        ).canOverride,
        isTrue,
      );
      expect(
        evaluateReadiness(
          ReadinessInputs(
            hasSpec: true,
            stackedOn: 'SPEC-001',
            hasResolution: true,
            resolutionProblem: problem(res(ResolutionState.reprovada)),
          ),
        ).canOverride,
        isFalse,
      );
      expect(
        evaluateReadiness(
          const ReadinessInputs(
            hasSpec: true,
            hasResolution: true,
            unknown: {'resolucao': 'git falhou'},
          ),
        ).canOverride,
        isFalse,
      );
    });
  });

  group('SPEC-050 R6 · PR sem spec', () {
    test('só checks, conflitos, decisão do PR, base e gate do projeto', () {
      final r = evaluateReadiness(
        const ReadinessInputs(
          imported: true,
          baseProblem:
              'Desatualizada · 2 commits do autor e 1 local não publicado',
          prReview: 'Aguardando aprovação',
          gateCommands: 'flutter test e flutter analyze',
          unknown: {'gate': 'Não verificado neste commit'},
        ),
      );
      expect(r.items.map((i) => i.id), [
        'base',
        'decisao',
        'gate',
        'checks',
        'conflitos',
        'worktree',
      ]);
      for (final id in [
        'revisor',
        'criterios',
        'verificacoes',
        'comentarios',
        'empilhada',
        'raiz',
        'pr',
      ]) {
        expect(r.items.where((i) => i.id == id), isEmpty, reason: id);
      }
      expect(r.blockers.map((i) => i.id), ['base']);
      expect(r.warnings.map((i) => i.id), ['decisao', 'gate']);
      final gate = r.items.firstWhere((i) => i.id == 'gate');
      expect(gate.level, ReadinessLevel.naoVerificado);
      expect(gate.label, 'Gate do projeto · flutter test e flutter analyze');
      expect(gate.action, 'Verificar');
      expect(r.items.firstWhere((i) => i.id == 'base').action, 'Atualizar…');
      // A branch behind the author's commits can still be merged, with a
      // reason (the mockup's "Mergear mesmo assim…").
      expect(r.canOverride, isTrue);
    });

    test('conflito do PR bloqueia; tudo certo fica pronto', () {
      expect(
        evaluateReadiness(
          const ReadinessInputs(
            imported: true,
            prConflict: 'O PR tem conflito',
          ),
        ).blockers.map((i) => i.id),
        ['conflitos'],
      );
      final ok = evaluateReadiness(const ReadinessInputs(imported: true));
      expect(ok.level, ReadinessLevel.ok);
      expect(ok.summary, 'Pronto para merge');
    });
  });
}
