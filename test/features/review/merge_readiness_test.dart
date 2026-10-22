import 'package:flutter_test/flutter_test.dart';
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
}
