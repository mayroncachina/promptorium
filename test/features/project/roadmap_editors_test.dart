import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/project/project_plan.dart';
import 'package:promptorium/features/project/project_planner.dart';
import 'package:promptorium/features/project/widgets/roadmap_editors.dart';

const roadmap = Roadmap(
  specs: [
    RoadmapSpec(
      code: 'S1',
      title: 'Esqueleto',
      phase: RoadmapPhase.foundation,
      requirements: [(id: 'R1', text: 'Criar')],
    ),
    RoadmapSpec(
      code: 'S2',
      title: 'Receitas',
      phase: RoadmapPhase.mvp,
      requirements: [(id: 'R1', text: 'CRUD')],
      dependsOn: ['S1'],
    ),
    RoadmapSpec(
      code: 'S3',
      title: 'Fotos',
      phase: RoadmapPhase.mvp,
      requirements: [(id: 'R1', text: 'Upload')],
      dependsOn: ['S1', 'S2'],
    ),
  ],
);

void main() {
  test('withoutSpec drops it and the references to it', () {
    final r = withoutSpec(roadmap, 1);
    expect(r.specs.map((s) => s.code), ['S1', 'S3']);
    expect(r.specs[1].dependsOn, ['S1']);
    // A spec of the MVP left without dependencies waits for the foundation.
    final only = withoutSpec(withoutSpec(roadmap, 0), 0);
    expect(only.specs.single.dependsOn, isEmpty);
    expect(only.normalized().specs.single.dependsOn, isEmpty); // no foundation
    expect(withoutSpec(roadmap, 0).normalized().specs.first.dependsOn, isEmpty);
  });

  test('requirement lines: ids kept, made up when missing or repeated', () {
    expect(
      parseRequirementLines(
        'R1 · Cadastrar\n- R3: Buscar\n\nSem id\nR1 · repetido',
      ),
      [
        (id: 'R1', text: 'Cadastrar'),
        (id: 'R3', text: 'Buscar'),
        (id: 'R2', text: 'Sem id'),
        (id: 'R4', text: 'repetido'),
      ],
    );
    expect(
      requirementLines(const [(id: 'R1', text: 'a'), (id: 'R2', text: 'b')]),
      'R1 · a\nR2 · b',
    );
  });

  test('edited survives encode/decode and normalization', () {
    final data = ProjectPlanData(roadmap: roadmap.copyWith(edited: true));
    final back = ProjectPlanData.decode(data.encode()).roadmap;
    expect(back.edited, isTrue);
    expect(back.normalized().edited, isTrue);
    expect(
      ProjectPlanData.decode(const ProjectPlanData(roadmap: roadmap).encode())
          .roadmap
          .edited,
      isFalse,
    );
  });

  test('idea spec: a taken code is replaced, the idea leaves "Depois", an '
      'MVP spec without dependencies waits for the foundation', () {
    final r = addIdeaSpec(
      roadmap.copyWith(later: ['Modo offline', 'App nativo']),
      const RoadmapSpec(
        code: 'S2', // taken
        title: 'Modo offline',
        phase: RoadmapPhase.mvp,
        requirements: [(id: 'R1', text: 'Cache local')],
        dependsOn: ['S2', 'S9'],
      ),
      'Modo offline',
    );
    expect(r.later, ['App nativo']);
    expect(r.edited, isTrue);
    final spec = r.specs.last;
    expect(spec.title, 'Modo offline');
    expect(spec.code, 'S4');
    // Existing S2 stays a valid dependency; unknown S9 is dropped.
    expect(spec.dependsOn, ['S2']);

    final free = addIdeaSpec(
      roadmap,
      const RoadmapSpec(
        title: 'Notificações',
        phase: RoadmapPhase.mvp,
        requirements: [(id: 'R1', text: 'Avisar')],
      ),
      'x',
    ).specs.last;
    expect(free.code, 'S4');
    expect(free.dependsOn, ['S1']); // the foundation
  });
}
