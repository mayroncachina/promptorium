import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/enums.dart';
import 'package:promptorium/features/project/project_plan.dart';
import 'package:promptorium/features/specs/spec_file.dart';

RoadmapTask task(String code, {List<String> deps = const []}) =>
    RoadmapTask(code: code, title: 'Tarefa $code', dependsOn: deps);

void main() {
  test('normalized: foundation first, unique codes, only known deps, MVP '
      'waits for the foundation', () {
    final r = const Roadmap(
      specs: [
        RoadmapSpec(
          title: 'Receitas',
          phase: RoadmapPhase.mvp,
          tasks: [
            RoadmapTask(code: 'T3', title: 'CRUD'),
            RoadmapTask(code: 'T3', title: 'Fotos', dependsOn: ['T3', 'X9']),
          ],
        ),
        RoadmapSpec(
          title: 'Esqueleto',
          phase: RoadmapPhase.foundation,
          tasks: [
            RoadmapTask(code: 'T1', title: 'Criar projeto'),
            RoadmapTask(code: '', title: 'CI', dependsOn: ['T1', 'T1']),
          ],
        ),
      ],
      later: ['Offline'],
    ).normalized();

    expect(r.specs.map((s) => s.title), ['Esqueleto', 'Receitas']);
    final codes = r.tasks.map((t) => t.code).toList();
    expect(codes.toSet(), hasLength(4));
    expect(codes.take(2), ['T1', 'T2']); // empty code got a fresh one
    final ci = r.specs.first.tasks[1];
    expect(ci.dependsOn, ['T1']); // duplicates dropped
    final crud = r.specs[1].tasks[0];
    final photos = r.specs[1].tasks[1];
    expect(crud.code, 'T3');
    // MVP task without dependencies waits for every foundation task.
    expect(crud.dependsOn, ['T1', 'T2']);
    // The repeated code was renamed; its reference to "T3" is the CRUD now,
    // the unknown X9 is dropped.
    expect(photos.code, isNot('T3'));
    expect(photos.dependsOn, ['T3']);
    expect(r.later, ['Offline']);
    expect(r.firstTask!.code, 'T1');
    expect(r.dependencyCount, 1 + 2 + 1);
  });

  test('waves group tasks by when they can start', () {
    final r = Roadmap(
      specs: [
        RoadmapSpec(
          title: 'A',
          phase: RoadmapPhase.foundation,
          tasks: [
            task('T1'),
            task('T2', deps: ['T1']),
            task('T3', deps: ['T1']),
            task('T4', deps: ['T2', 'T3']),
            // Cycle: lands in the last wave instead of looping.
            task('T5', deps: ['T6']),
            task('T6', deps: ['T5']),
          ],
        ),
      ],
    );
    final waves = r.waves().map((w) => w.map((t) => t.code).toList()).toList();
    expect(waves, [
      ['T1'],
      ['T2', 'T3'],
      ['T4'],
      ['T5', 'T6'],
    ]);
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
            title: 'Esqueleto',
            phase: RoadmapPhase.foundation,
            requirements: const [(id: 'R1', text: 'Projeto criado')],
            tasks: [task('T1')],
          ),
        ],
      ),
    );
    final back = ProjectPlanData.decode(data.encode());
    expect(back.encode(), data.encode());
    expect(back.messages[1].suggestions, ['Família']);
    expect(back.stack.decisions.single.pinned, isTrue);
    expect(back.roadmap.specs.single.requirements.single.id, 'R1');
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
    );
    final doc = SpecDocument.parse(md);
    expect(doc.id, 'SPEC-004');
    expect(doc.status, SpecStatus.approved);
    expect(doc.title, 'Lista de compras');
    expect(doc.requirements.single, (id: 'R1', text: 'Juntar iguais'));
    expect(md, contains('- [ ] Dois ovos'));
  });
}
