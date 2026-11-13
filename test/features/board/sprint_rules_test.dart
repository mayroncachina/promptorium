import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/features/board/board_rules.dart';
import 'package:promptorium/features/board/sprint_rules.dart';

Spec spec(
  int id, {
  int? sprint,
  SpecStage stage = SpecStage.backlog,
  List<String> deps = const [],
}) => Spec(
  hasPlan: false,
  inTray: false,
  kind: SpecKind.spec,
  id: id,
  workspaceId: 1,
  code: 'SPEC-${id.toString().padLeft(3, '0')}',
  title: 't$id',
  status: SpecStatus.approved,
  path: 'p',
  stage: stage,
  requirements: const [],
  dependsOn: deps,
  autoAdvance: false,
  reviewRounds: 0,
  gateResends: 0,
  rejectedHunks: 0,
  sprintId: sprint,
);

Sprint sprint(
  int id, {
  SprintState state = SprintState.planned,
  int? position,
  String? name,
}) => Sprint(
  id: id,
  workspaceId: 1,
  name: name ?? 'Sprint $id',
  state: state,
  position: position ?? id,
);

void main() {
  group('SprintFilter', () {
    test('Todas mostra tudo, Sem sprint e a sprint filtram', () {
      final a = spec(1, sprint: 1), b = spec(2);
      expect(const SprintFilter.all().matches(a), isTrue);
      expect(const SprintFilter.all().matches(b), isTrue);
      expect(const SprintFilter.none().matches(a), isFalse);
      expect(const SprintFilter.none().matches(b), isTrue);
      expect(const SprintFilter.sprint(1).matches(a), isTrue);
      expect(const SprintFilter.sprint(1).matches(b), isFalse);
    });

    test('igualdade e valor salvo', () {
      expect(const SprintFilter.sprint(1), const SprintFilter.sprint(1));
      expect(const SprintFilter.all() == const SprintFilter.none(), isFalse);
      expect(const SprintFilter.all().stored, 'all');
      expect(const SprintFilter.none().stored, 'none');
      expect(const SprintFilter.sprint(7).stored, '7');
    });

    test('sprintFilterOf aponta para onde a spec está', () {
      expect(sprintFilterOf(spec(1, sprint: 4)), const SprintFilter.sprint(4));
      expect(sprintFilterOf(spec(1)), const SprintFilter.none());
    });
  });

  group('R2: seleção padrão', () {
    final sprints = [sprint(1), sprint(2, state: SprintState.active)];

    test('sem escolha salva abre a Ativa', () {
      expect(resolveSprintFilter(null, sprints), const SprintFilter.sprint(2));
    });

    test('sem Ativa abre Todas', () {
      expect(resolveSprintFilter(null, [sprint(1)]), const SprintFilter.all());
    });

    test('sem nenhuma sprint abre Todas', () {
      expect(resolveSprintFilter(null, const []), const SprintFilter.all());
      expect(resolveSprintFilter('none', const []), const SprintFilter.all());
    });

    test('respeita a escolha salva', () {
      expect(resolveSprintFilter('1', sprints), const SprintFilter.sprint(1));
      expect(resolveSprintFilter('all', sprints), const SprintFilter.all());
      expect(resolveSprintFilter('none', sprints), const SprintFilter.none());
    });

    test('sprint salva que sumiu cai na Ativa', () {
      expect(resolveSprintFilter('9', sprints), const SprintFilter.sprint(2));
    });
  });

  test('R3: progresso conta feitas, total, em execução e aguardando', () {
    final p = sprintProgress([
      spec(1, stage: SpecStage.done),
      spec(2, stage: SpecStage.running),
      spec(3),
    ], waiting: (s) => s.id == 3);
    expect((p.done, p.total, p.running, p.waiting), (1, 3, 1, 1));
    expect(p.label, '1 de 3');
  });

  group('R4: nome sugerido', () {
    test('primeira e próximas', () {
      expect(nextSprintName(const []), 'Sprint 1');
      expect(nextSprintName([sprint(1), sprint(2)]), 'Sprint 3');
    });

    test('pula um número já usado depois de excluir', () {
      expect(nextSprintName([sprint(1, name: 'Sprint 5')]), 'Sprint 6');
    });

    test('nomes livres não atrapalham', () {
      expect(nextSprintName([sprint(1, name: 'Bandeja')]), 'Sprint 2');
    });
  });

  test('ordem do seletor: Ativa, Planejadas e concluídas à parte', () {
    final all = [
      sprint(1, state: SprintState.done),
      sprint(2),
      sprint(3, state: SprintState.active),
      sprint(4, state: SprintState.done),
    ];
    expect(openSprints(all).map((s) => s.id), [3, 2]);
    expect(closedSprints(all).map((s) => s.id), [4, 1]);
  });

  group('R10: sugestão ao concluir', () {
    test('a próxima Planejada da lista', () {
      final a = sprint(2, state: SprintState.active);
      expect(nextPlannedSprint(a, [sprint(1), a, sprint(3)])?.id, 3);
    });

    test('sem próxima, volta a uma anterior; sem nenhuma, null', () {
      final a = sprint(2, state: SprintState.active);
      expect(nextPlannedSprint(a, [sprint(1), a])?.id, 1);
      expect(nextPlannedSprint(a, [a]), isNull);
    });
  });

  test('R7: dependências fora da seleção', () {
    final dep = spec(1, sprint: 2);
    final other = spec(3, sprint: 1);
    final s = spec(2, sprint: 1, deps: ['SPEC-001', 'SPEC-003', 'SPEC-099']);
    final byCode = specsByCode([dep, other, s]);
    expect(externalDependencies(s, byCode, const SprintFilter.sprint(1)), [
      dep,
    ]);
    expect(externalDependencies(s, byCode, const SprintFilter.all()), isEmpty);
  });

  group('R12: aviso ao mover', () {
    final sprints = [sprint(1), sprint(2)];

    List<String> warn(Spec s, List<Spec> others, Sprint? target) =>
        moveWarnings([s], target, specsByCode([s, ...others]), sprints);

    test('dependência não feita em sprint posterior avisa', () {
      final dep = spec(2, sprint: 2);
      final s = spec(1, deps: ['SPEC-002']);
      expect(warn(s, [dep], sprints.first), [
        'SPEC-001 depende de SPEC-002, na Sprint 2',
      ]);
    });

    test('dependência em Sem sprint avisa', () {
      final dep = spec(2);
      final s = spec(1, deps: ['SPEC-002']);
      expect(warn(s, [dep], sprints.first), [
        'SPEC-001 depende de SPEC-002, que fica em Sem sprint',
      ]);
    });

    test('não avisa se a dependência foi feita, vem antes ou é da mesma', () {
      final s = spec(1, deps: ['SPEC-002']);
      expect(
        warn(s, [spec(2, sprint: 2, stage: SpecStage.done)], sprints.first),
        isEmpty,
      );
      expect(warn(s, [spec(2, sprint: 1)], sprints.last), isEmpty);
      expect(warn(s, [spec(2, sprint: 2)], sprints.last), isEmpty);
    });

    test('não avisa se a dependência vai junto', () {
      final dep = spec(2);
      final s = spec(1, deps: ['SPEC-002']);
      expect(
        moveWarnings([s, dep], sprints.first, specsByCode([s, dep]), sprints),
        isEmpty,
      );
    });

    test('mover para Sem sprint nunca avisa', () {
      final s = spec(1, deps: ['SPEC-002']);
      expect(warn(s, [spec(2, sprint: 2)], null), isEmpty);
    });
  });

  group('R11: Autopilot', () {
    final specs = [spec(1, sprint: 1), spec(2, sprint: 2), spec(3)];

    test('com sprint Ativa, só as specs dela', () {
      expect(autopilotScope(specs, sprint(1)).map((s) => s.id), [1]);
    });

    test('sem sprint Ativa, todas', () {
      expect(autopilotScope(specs, null), specs);
    });

    test('dependência fora da sprint continua bloqueando', () {
      final s = spec(1, sprint: 1, deps: ['SPEC-002']);
      final byCode = specsByCode([s, spec(2, sprint: 2)]);
      expect(isSpecBlocked(s, byCode), isTrue);
    });
  });
}
