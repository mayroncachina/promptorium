import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/project/project_plan.dart';
import 'package:promptorium/features/project/widgets/roadmap_editors.dart';

const roadmap = Roadmap(
  specs: [
    RoadmapSpec(
      title: 'Esqueleto',
      phase: RoadmapPhase.foundation,
      tasks: [RoadmapTask(code: 'T1', title: 'Criar')],
    ),
    RoadmapSpec(
      title: 'Receitas',
      phase: RoadmapPhase.mvp,
      tasks: [
        RoadmapTask(code: 'T2', title: 'CRUD', dependsOn: ['T1']),
        RoadmapTask(code: 'T3', title: 'Fotos', dependsOn: ['T2']),
      ],
    ),
  ],
);

List<String> codes(Roadmap r, int spec) => [
  for (final t in r.specs[spec].tasks) t.code,
];

void main() {
  test('withTask replaces in place or moves to the end of another spec', () {
    var r = withTask(
      roadmap,
      1,
      const RoadmapTask(code: 'T2', title: 'CRUD de receitas'),
    );
    expect(codes(r, 1), ['T2', 'T3']);
    expect(r.specs[1].tasks.first.title, 'CRUD de receitas');

    r = withTask(roadmap, 0, const RoadmapTask(code: 'T2', title: 'CRUD'));
    expect(codes(r, 0), ['T1', 'T2']);
    expect(codes(r, 1), ['T3']);

    r = withTask(
      roadmap,
      1,
      RoadmapTask(code: roadmap.nextTaskCode(), title: 'Nova'),
    );
    expect(codes(r, 1), ['T2', 'T3', 'T4']);
  });

  test('withoutTask drops it and the references to it', () {
    final r = withoutTask(roadmap, 'T2');
    expect(codes(r, 1), ['T3']);
    expect(r.specs[1].tasks.single.dependsOn, isEmpty);
    // normalized: the MVP task left without dependencies waits for the
    // foundation again.
    expect(r.normalized().specs[1].tasks.single.dependsOn, ['T1']);
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
}
