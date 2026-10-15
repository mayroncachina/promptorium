import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_cli.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/app_settings_repo.dart';
import 'package:promptorium/features/project/project_plan.dart';
import 'package:promptorium/features/project/project_screen.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import '../../ui/preferences_test.dart' show unmount;
import '../sessions/session_test_utils.dart' show FakeCli;

const vision = VisionPlan(
  name: 'Receitas da família',
  summary: 'App de receitas.',
  audience: 'Seis pessoas.',
  mvp: ['Cadastro de receitas', 'Lista de compras'],
  outOfScope: ['Modo offline'],
  openQuestions: ['Como entram no app?'],
);

const stack = StackPlan(
  decisions: [
    StackDecision(
      area: 'Banco',
      choice: 'PostgreSQL',
      why: 'Relações simples.',
      alternatives: ['SQLite'],
    ),
    StackDecision(
      area: 'Deploy',
      choice: StackDecision.undecided,
      alternatives: ['VPS'],
    ),
  ],
  claudeMd: '# Receitas',
);

const roadmap = Roadmap(
  specs: [
    RoadmapSpec(
      title: 'Esqueleto',
      phase: RoadmapPhase.foundation,
      tasks: [RoadmapTask(code: 'T1', title: 'Criar o projeto')],
    ),
    RoadmapSpec(
      title: 'Receitas',
      phase: RoadmapPhase.mvp,
      tasks: [
        RoadmapTask(code: 'T2', title: 'CRUD', dependsOn: ['T1']),
        RoadmapTask(code: 'T3', title: 'Fotos', dependsOn: ['T1']),
      ],
    ),
  ],
  later: ['App nativo'],
);

/// Projeto screen on workspace `/r` with [data] at [step] (no plan when
/// [data] is null).
Future<(ProviderContainer, AppDatabase)> pumpProject(
  WidgetTester tester, {
  ProjectPlanData? data,
  ProjectStep step = ProjectStep.vision,
  bool materialized = false,
  bool withWorkspace = true,
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = memoryDatabase();
  addTearDown(db.close);
  final cli = FakeCli();
  final c = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      currentBranchProvider.overrideWith((ref, root) async => 'main'),
      claudeProcessStarterProvider.overrideWithValue(cli.start),
    ],
  );
  if (withWorkspace) {
    final ws = await db
        .into(db.workspaces)
        .insertReturning(WorkspacesCompanion.insert(path: '/r', name: 'r'));
    await AppSettingsRepo(db).setInt(AppSettingKeys.activeWorkspace, ws.id);
    if (data != null) {
      await db
          .into(db.projectPlans)
          .insert(
            ProjectPlansCompanion.insert(
              workspaceId: Value(ws.id),
              step: Value(step.name),
              data: Value(data.encode()),
              materializedAt: Value(materialized ? DateTime(2026) : null),
            ),
          );
    }
  }
  await c.read(appSettingsProvider.notifier).load();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: ProjectScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (c, db);
}

Future<ProjectPlanData> stored(AppDatabase db) async {
  final row = await db.select(db.projectPlans).getSingle();
  return ProjectPlanData.decode(row.data);
}

void main() {
  testWidgets('without a workspace offers a new project; without a plan '
      'starts one', (tester) async {
    var (c, _) = await pumpProject(tester, withWorkspace: false);
    expect(find.byKey(const ValueKey('project-new')), findsOneWidget);
    await unmount(tester, c);

    (c, _) = await pumpProject(tester);
    expect(find.text('Planejar r'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('project-start')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('project-step-vision')), findsOneWidget);
    expect(find.text('Conte a ideia'), findsOneWidget);
    // Only Visão can be opened while the plan is empty.
    await tester.tap(find.byKey(const ValueKey('project-stepper-roadmap')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('project-step-vision')), findsOneWidget);
    await unmount(tester, c);
  });

  testWidgets('Visão shows the conversation, the plan and the quick replies '
      'of the last answer; Próximo opens Stack', (tester) async {
    final (c, db) = await pumpProject(
      tester,
      data: const ProjectPlanData(
        messages: [
          PlanMessage(fromUser: true, text: 'Quero um app de receitas'),
          PlanMessage(
            fromUser: false,
            text: 'Como as pessoas entram?',
            note: 'Plano atualizado · MVP +2',
            suggestions: ['Link mágico', 'Google'],
          ),
        ],
        vision: vision,
        stack: stack,
      ),
    );
    expect(find.text('Quero um app de receitas'), findsOneWidget);
    expect(find.text('Plano atualizado · MVP +2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('project-suggestion-Link mágico')),
      findsOneWidget,
    );
    expect(find.text('Receitas da família'), findsOneWidget);
    expect(find.text('Lista de compras'), findsOneWidget);
    expect(find.text('Em aberto · 1'), findsOneWidget);
    expect(find.text('MVP com 2 funcionalidades'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('project-vision-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('project-step-stack')), findsOneWidget);
    final row = await db.select(db.projectPlans).getSingle();
    expect(row.step, 'stack');
    await unmount(tester, c);
  });

  testWidgets('Stack: an alternative becomes the choice and marks the '
      'CLAUDE.md as stale', (tester) async {
    final (c, db) = await pumpProject(
      tester,
      data: const ProjectPlanData(vision: vision, stack: stack),
      step: ProjectStep.stack,
    );
    expect(find.text('decidir'), findsOneWidget);
    expect(find.text('# Receitas'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('project-stack-alt-Banco-SQLite')),
    );
    await tester.pumpAndSettle();
    expect(find.text('sua escolha'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('project-stack-alt-Banco-PostgreSQL')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('project-claudemd-refresh')), findsOne);
    final s = (await stored(db)).stack;
    expect(s.decisions.first.choice, 'SQLite');
    expect(s.claudeMdStale, isTrue);
    await unmount(tester, c);
  });

  testWidgets('Roadmap shows the phases and the order; Revisar e criar lists '
      'what will be written; a created project shows the summary', (
    tester,
  ) async {
    var (c, _) = await pumpProject(
      tester,
      data: const ProjectPlanData(
        vision: vision,
        stack: stack,
        roadmap: roadmap,
      ),
      step: ProjectStep.roadmap,
    );
    expect(find.textContaining('2 specs · 3 tarefas'), findsWidgets);
    expect(find.byKey(const ValueKey('project-roadmap-task-T3')), findsOne);
    expect(find.text('App nativo'), findsOneWidget);
    expect(find.text('T1 sozinha · Criar o projeto'), findsOneWidget);
    expect(find.text('T2, T3 lado a lado'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('project-roadmap-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('project-step-create')), findsOneWidget);
    expect(find.text('A  CLAUDE.md'), findsOneWidget);
    expect(find.text('A  specs/SPEC-…-esqueleto.md'), findsOneWidget);
    expect(find.byKey(const ValueKey('project-create')), findsOneWidget);
    expect(find.byKey(const ValueKey('project-run-first')), findsOneWidget);
    await unmount(tester, c);

    (c, _) = await pumpProject(
      tester,
      data: const ProjectPlanData(
        vision: vision,
        stack: stack,
        roadmap: roadmap,
      ),
      step: ProjectStep.create,
      materialized: true,
    );
    expect(find.text('Projeto criado'), findsOneWidget);
    expect(find.byKey(const ValueKey('project-create')), findsNothing);
    expect(find.byKey(const ValueKey('project-go-tasks')), findsOneWidget);
    await unmount(tester, c);
  });

  testWidgets('Roadmap edits: task title, dependencies and spec; new task; '
      'delete a spec; regenerating asks after edits', (tester) async {
    final (c, db) = await pumpProject(
      tester,
      data: const ProjectPlanData(
        vision: vision,
        stack: stack,
        roadmap: roadmap,
      ),
      step: ProjectStep.roadmap,
    );
    Future<Roadmap> saved() async => (await stored(db)).roadmap;

    // Edit T3: new title, depends on T2 too.
    await tester.tap(find.byKey(const ValueKey('project-roadmap-task-T3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('roadmap-task-editor')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('roadmap-task-title')),
      'Upload de fotos',
    );
    await tester.tap(find.byKey(const ValueKey('roadmap-task-dep-T2')));
    await tester.tap(find.byKey(const ValueKey('roadmap-editor-save')));
    await tester.pumpAndSettle();
    var r = await saved();
    expect(r.edited, isTrue);
    final t3 = r.tasks.firstWhere((t) => t.code == 'T3');
    expect(t3.title, 'Upload de fotos');
    expect(t3.dependsOn, ['T1', 'T2']);
    expect(find.text('Upload de fotos'), findsOneWidget);
    expect(find.textContaining('editado por você'), findsWidgets);

    // New task in the MVP spec ("+ Tarefa" of the second card).
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('roadmap-spec-1')),
        matching: find.byKey(const ValueKey('roadmap-add-task')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('roadmap-editor-save')));
    await tester.pumpAndSettle();
    expect(find.text('Informe o título da tarefa.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('roadmap-task-title')),
      'Busca por ingrediente',
    );
    await tester.tap(find.byKey(const ValueKey('roadmap-editor-save')));
    await tester.pumpAndSettle();
    r = await saved();
    final added = r.specs[1].tasks.last;
    expect(added.code, 'T4');
    expect(added.dependsOn, ['T1']); // MVP: waits for the foundation

    // Spec: rename + requirements, then delete the MVP spec (and its tasks).
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('roadmap-spec-0')),
        matching: find.byKey(const ValueKey('roadmap-spec-edit')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('roadmap-spec-title')),
      'Esqueleto do app',
    );
    await tester.enterText(
      find.byKey(const ValueKey('roadmap-spec-requirements')),
      'R1 · Projeto roda\nTestes rodam',
    );
    await tester.tap(find.byKey(const ValueKey('roadmap-editor-save')));
    await tester.pumpAndSettle();
    r = await saved();
    expect(r.specs[0].title, 'Esqueleto do app');
    expect(r.specs[0].requirements.map((q) => q.id), ['R1', 'R2']);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('roadmap-spec-1')),
        matching: find.byKey(const ValueKey('roadmap-spec-edit')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Excluir spec e 3 tarefas'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('roadmap-editor-delete')));
    await tester.pumpAndSettle();
    r = await saved();
    expect(r.specs.map((s) => s.title), ['Esqueleto do app']);
    expect(r.tasks.map((t) => t.code), ['T1']);

    // Regenerate after edits: asks first (cancel keeps everything).
    await tester.tap(find.byKey(const ValueKey('project-roadmap-again')));
    await tester.pumpAndSettle();
    expect(find.text('Regerar o roadmap?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect((await saved()).tasks, hasLength(1));
    await unmount(tester, c);
  });

  testWidgets('every step fits the minimum window (1100×700)', (tester) async {
    for (final step in ProjectStep.values) {
      final (c, _) = await pumpProject(
        tester,
        data: const ProjectPlanData(
          messages: [
            PlanMessage(fromUser: true, text: 'Quero um app de receitas'),
            PlanMessage(
              fromUser: false,
              text: 'Como as pessoas entram?',
              suggestions: ['Link mágico', 'Google', 'Senha da família'],
            ),
          ],
          vision: vision,
          stack: stack,
          roadmap: roadmap,
        ),
        step: step,
        size: const Size(1100 - 56, 700 - 72),
      );
      expect(find.byKey(ValueKey('project-step-${step.name}')), findsOne);
      expect(tester.takeException(), isNull, reason: step.name);
      await unmount(tester, c);
    }
  });

  testWidgets('Descartar plano asks first and removes only the draft', (
    tester,
  ) async {
    final (c, db) = await pumpProject(
      tester,
      data: const ProjectPlanData(vision: vision),
    );
    await tester.tap(find.byKey(const ValueKey('project-discard')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('project-discard-confirm')));
    await tester.pumpAndSettle();
    expect(await db.select(db.projectPlans).get(), isEmpty);
    expect(find.text('Planejar r'), findsOneWidget);
    await unmount(tester, c);
  });
}
