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
}
