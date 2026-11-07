import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/data/repos/specs_repo.dart';
import 'package:promptorium/data/repos/sprints_repo.dart';
import 'package:promptorium/data/repos/workspaces_repo.dart';

import '../helpers/test_db.dart';

void main() {
  late AppDatabase db;
  late SprintsRepo sprints;
  late SpecsRepo specs;
  late int ws;

  setUp(() async {
    db = memoryDatabase();
    sprints = SprintsRepo(db);
    specs = SpecsRepo(db);
    ws = (await WorkspacesRepo(db).add(path: '/r', name: 'r')).id;
  });
  tearDown(() => db.close());

  Future<Spec> spec(String code) => specs.insert(
    workspaceId: ws,
    code: code,
    title: code,
    path: 'specs/$code.md',
  );

  test('a primeira sprint nasce Ativa e as seguintes, Planejadas', () async {
    final a = await sprints.create(workspaceId: ws, name: 'Sprint 1');
    final b = await sprints.create(
      workspaceId: ws,
      name: 'Sprint 2',
      goal: 'Entregar',
    );
    expect(a.state, SprintState.active);
    expect(b.state, SprintState.planned);
    expect(b.goal, 'Entregar');
    expect(b.position, greaterThan(a.position));
  });

  test('um workspace não fica com duas Ativas', () async {
    final a = await sprints.create(workspaceId: ws, name: 'Sprint 1');
    final b = await sprints.create(workspaceId: ws, name: 'Sprint 2');
    await sprints.activate(b.id);
    final all = await sprints.byWorkspace(ws);
    expect(all.where((s) => s.state == SprintState.active).single.id, b.id);
    expect(all.firstWhere((s) => s.id == a.id).state, SprintState.planned);
    expect((await sprints.active(ws))?.id, b.id);
  });

  test('a sprint Ativa de um workspace não mexe na de outro', () async {
    final other = (await WorkspacesRepo(db).add(path: '/o', name: 'o')).id;
    final a = await sprints.create(workspaceId: other, name: 'Sprint 1');
    final b = await sprints.create(workspaceId: ws, name: 'Sprint 1');
    await sprints.activate(b.id);
    expect((await sprints.active(other))?.id, a.id);
  });

  test('uma sprint concluída não volta a ser Ativa', () async {
    final a = await sprints.create(workspaceId: ws, name: 'Sprint 1');
    await sprints.complete(a.id);
    await sprints.activate(a.id);
    expect(await sprints.active(ws), isNull);
  });

  test('excluir deixa as specs em Sem sprint, sem apagar nenhuma', () async {
    final a = await sprints.create(workspaceId: ws, name: 'Sprint 1');
    final s = await spec('SPEC-001');
    await sprints.moveSpecs([s.id], a.id);
    await sprints.delete(a.id);
    final after = await specs.getById(s.id);
    expect(after, isNotNull);
    expect(after!.sprintId, isNull);
  });

  test('mover não altera coluna nem etapas', () async {
    final a = await sprints.create(workspaceId: ws, name: 'Sprint 1');
    final s = await spec('SPEC-001');
    await specs.setStage(s.id, SpecStage.running);
    await sprints.moveSpecs([s.id], a.id);
    final after = (await specs.getById(s.id))!;
    expect(after.sprintId, a.id);
    expect(after.stage, SpecStage.running);
    await sprints.moveSpecs([s.id], null);
    expect((await specs.getById(s.id))!.sprintId, isNull);
  });

  test('concluir move só o que não foi feito e não ativa a próxima', () async {
    final a = await sprints.create(workspaceId: ws, name: 'Sprint 1');
    final b = await sprints.create(workspaceId: ws, name: 'Sprint 2');
    final feita = await spec('SPEC-001');
    final rodando = await spec('SPEC-002');
    await specs.setStage(feita.id, SpecStage.done);
    await specs.setStage(rodando.id, SpecStage.running);
    await sprints.moveSpecs([feita.id, rodando.id], a.id);

    await sprints.complete(a.id, moveTo: b.id);

    expect((await specs.getById(feita.id))!.sprintId, a.id);
    final moved = (await specs.getById(rodando.id))!;
    expect(moved.sprintId, b.id);
    expect(moved.stage, SpecStage.running);
    final all = await sprints.byWorkspace(ws);
    expect(all.first.state, SprintState.done);
    expect(all.first.closedAt, isNotNull);
    expect(all.last.state, SprintState.planned);
    expect(await sprints.active(ws), isNull);
  });

  test('concluir pode mandar para Sem sprint e ativar a próxima', () async {
    final a = await sprints.create(workspaceId: ws, name: 'Sprint 1');
    final b = await sprints.create(workspaceId: ws, name: 'Sprint 2');
    final s = await spec('SPEC-001');
    await sprints.moveSpecs([s.id], a.id);
    await sprints.complete(a.id, activate: b.id);
    expect((await specs.getById(s.id))!.sprintId, isNull);
    expect((await sprints.active(ws))?.id, b.id);
  });

  test('atualizar o arquivo da spec não tira ela da sprint', () async {
    final a = await sprints.create(workspaceId: ws, name: 'Sprint 1');
    final s = await spec('SPEC-001');
    await sprints.moveSpecs([s.id], a.id);
    await specs.setStage(s.id, SpecStage.review);
    expect((await specs.getById(s.id))!.sprintId, a.id);
  });
}
