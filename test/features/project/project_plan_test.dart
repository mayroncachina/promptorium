import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/enums.dart';
import 'package:promptorium/features/project/project_plan.dart';
import 'package:promptorium/features/specs/spec_file.dart';

RoadmapSpec spec(
  String code, {
  RoadmapPhase phase = RoadmapPhase.mvp,
  List<String> deps = const [],
  int steps = 2,
}) => RoadmapSpec(
  code: code,
  title: 'Spec $code',
  phase: phase,
  requirements: [for (var i = 1; i <= steps; i++) (id: 'R$i', text: 'Req $i')],
  dependsOn: deps,
);

void main() {
  test('normalized: foundation first, unique codes, only known deps, MVP '
      'waits for the foundation', () {
    final r = Roadmap(
      specs: [
        spec('S3'),
        spec('S3', deps: ['S3', 'X9', 'S1', 'S1']), // repeated code
        spec('S1', phase: RoadmapPhase.foundation),
        spec('', phase: RoadmapPhase.foundation, deps: ['S1', 'S1']),
      ],
      later: const ['Offline'],
    ).normalized();

    // Foundation first (file order kept inside a phase).
    expect(r.specs.map((s) => s.phase), [
      RoadmapPhase.foundation,
      RoadmapPhase.foundation,
      RoadmapPhase.mvp,
      RoadmapPhase.mvp,
    ]);
    final codes = r.specs.map((s) => s.code).toList();
    expect(codes.toSet(), hasLength(4));
    expect(codes.take(2), ['S1', 'S2']); // the empty code got a fresh one
    expect(r.specs[1].dependsOn, ['S1']); // duplicates dropped
    final first = r.specs[2], second = r.specs[3];
    expect(first.code, 'S3');
    // MVP spec without dependencies waits for every foundation spec.
    expect(first.dependsOn, ['S1', 'S2']);
    // The repeated code was renamed; its "S3" is the first spec now, the
    // unknown X9 and the repeats of S1 are dropped.
    expect(second.code, isNot('S3'));
    expect(second.dependsOn, ['S3', 'S1']);
    expect(r.later, ['Offline']);
    expect(r.firstSpec!.code, 'S1');
    expect(r.dependencyCount, 1 + 2 + 2);
    expect(r.stepCount, 8);
  });

  test('waves group specs by when they can start', () {
    final r = Roadmap(
      specs: [
        spec('S1'),
        spec('S2', deps: ['S1']),
        spec('S3', deps: ['S1']),
        spec('S4', deps: ['S2', 'S3']),
        // Cycle: lands in the last wave instead of looping.
        spec('S5', deps: ['S6']),
        spec('S6', deps: ['S5']),
      ],
    );
    final waves = r.waves().map((w) => w.map((s) => s.code).toList()).toList();
    expect(waves, [
      ['S1'],
      ['S2', 'S3'],
      ['S4'],
      ['S5', 'S6'],
    ]);
  });

  test('big specs are flagged; next code skips the used ones', () {
    final r = Roadmap(specs: [spec('S1', steps: 7), spec('S2', steps: 6)]);
    expect(r.oversized.map((s) => s.code), ['S1']);
    expect(r.nextSpecCode(), 'S3');
    expect(Roadmap(specs: [spec('S2')]).nextSpecCode(), 'S3');
    expect(const Roadmap().isReady, isFalse);
    expect(
      Roadmap(
        specs: [const RoadmapSpec(title: 'Vazia', phase: RoadmapPhase.mvp)],
      ).isReady,
      isFalse,
    );
  });

  test('drafts saved with tasks load as specs: codes by position, task '
      'dependencies across specs become spec dependencies', () {
    final r = Roadmap.fromJson({
      'specs': [
        {
          'title': 'Base',
          'phase': 'foundation',
          'requirements': [
            {'id': 'R1', 'text': 'a'},
          ],
          'tasks': [
            {'code': 'T1', 'title': 'x', 'dependsOn': <String>[]},
          ],
        },
        {
          'title': 'Telas',
          'phase': 'mvp',
          'requirements': [
            {'id': 'R1', 'text': 'b'},
          ],
          'tasks': [
            {
              'code': 'T2',
              'title': 'y',
              'dependsOn': ['T1', 'T3'],
            },
            {
              'code': 'T3',
              'title': 'z',
              'dependsOn': ['T2'],
            },
          ],
        },
      ],
    });
    expect(r.specs.map((s) => s.code), ['S1', 'S2']);
    expect(r.specs[0].dependsOn, isEmpty);
    expect(r.specs[1].dependsOn, ['S1']); // T2 → T1; T2 ↔ T3 are inside S2
    expect(r.toJson().toString(), isNot(contains('tasks')));
  });

  test('plan data survives encode/decode and tolerates bad JSON', () {
    final data = ProjectPlanData(
      messages: const [
        PlanMessage(fromUser: true, text: 'Quero um app'),
        PlanMessage(
          fromUser: false,
          text: 'Para quem?',
          suggestions: ['Família'],
          note: 'Plano atualizado · Resumo',
        ),
      ],
      vision: const VisionPlan(
        name: 'Receitas',
        summary: 'App de receitas',
        mvp: ['Cadastro'],
      ),
      stack: const StackPlan(
        decisions: [
          StackDecision(
            area: 'Banco',
            choice: 'PostgreSQL',
            alternatives: ['SQLite'],
            pinned: true,
          ),
        ],
        claudeMd: '# Receitas',
        claudeMdStale: true,
      ),
      roadmap: Roadmap(
        specs: [
          RoadmapSpec(
            code: 'S1',
            title: 'Esqueleto',
            phase: RoadmapPhase.foundation,
            requirements: const [(id: 'R1', text: 'Projeto criado')],
            dependsOn: const ['S0'],
          ),
        ],
      ),
    );
    final back = ProjectPlanData.decode(data.encode());
    expect(back.encode(), data.encode());
    expect(back.messages[1].suggestions, ['Família']);
    expect(back.stack.decisions.single.pinned, isTrue);
    expect(back.roadmap.specs.single.requirements.single.id, 'R1');
    expect(back.roadmap.specs.single.dependsOn, ['S0']);
    expect(back.reachable(ProjectStep.create), isTrue);

    final empty = ProjectPlanData.decode('não é json');
    expect(empty.messages, isEmpty);
    expect(empty.reachable(ProjectStep.vision), isTrue);
    expect(empty.reachable(ProjectStep.stack), isFalse);
  });

  test('vision changes and stack choices', () {
    const a = VisionPlan(summary: 'x', mvp: ['a']);
    const b = VisionPlan(
      name: 'App',
      summary: 'x',
      mvp: ['a', 'b', 'c'],
      openQuestions: ['?'],
    );
    expect(
      visionChanges(a, b),
      'Plano atualizado · Nome · MVP +2 · Em aberto +1',
    );
    expect(visionChanges(b, b), isNull);

    const d = StackDecision(
      area: 'Deploy',
      choice: StackDecision.undecided,
      alternatives: ['Vercel', 'VPS'],
    );
    expect(d.isUndecided, isTrue);
    final picked = d.choose('VPS');
    expect(picked.choice, 'VPS');
    expect(picked.alternatives, ['Vercel']); // undecided is not an option
    expect(picked.pinned, isTrue);
    expect(picked.choose('Vercel').alternatives, ['VPS']);
  });

  test('roadmap spec markdown is an approved spec with requirements', () {
    final md = roadmapSpecMarkdown(
      const RoadmapSpec(
        title: 'Lista de compras',
        phase: RoadmapPhase.mvp,
        objective: 'Somar ingredientes.',
        requirements: [(id: 'R1', text: 'Juntar iguais')],
        acceptance: ['Dois ovos + três ovos = cinco ovos'],
      ),
      code: 'SPEC-004',
      dependsOn: ['SPEC-001', 'SPEC-002'],
    );
    final doc = SpecDocument.parse(md);
    expect(doc.id, 'SPEC-004');
    expect(doc.dependsOn, ['SPEC-001', 'SPEC-002']);
    expect(doc.phase, 'mvp');
    expect(doc.status, SpecStatus.approved);
    expect(doc.title, 'Lista de compras');
    expect(doc.requirements.single, (id: 'R1', text: 'Juntar iguais'));
    expect(md, contains('- [ ] Dois ovos'));
  });
}
