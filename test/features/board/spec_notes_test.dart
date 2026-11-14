import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/mcp/app_mcp_config.dart';
import 'package:promptorium/core/mcp/app_mcp_server.dart';
import 'package:promptorium/core/mcp/app_mcp_tools.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/widgets/spec_notes.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';

const _text =
    '---\nid: SPEC-047\nstatus: aprovada\n---\n# Higiene do repositório\n\n'
    '## Requisitos\n\n- R1 · Deve listar.\n- R2 · Deve limpar.\n'
    '- R3 · Deve guardar.\n';

/// `anotar_andamento` (SPEC-052 R7): the card shows the newest note, the
/// history keeps all of them, and no step is concluded.
void main() {
  late Directory root;
  late AppDatabase db;
  late Workspace ws;
  late Spec spec;
  late ProviderContainer c;

  McpGrant grant({int? conversationId}) => McpGrant(
    token: 't',
    workspaceId: ws.id,
    sessionId: conversationId == null ? 'sessao-r3' : 'claude-sid',
    conversationId: conversationId,
    access: McpAccess.write,
  );

  Future<McpToolOutcome> note(String text, {int? conversationId}) =>
      (c.read(appMcpToolsProvider) as AppMcpTools).call(
        grant(conversationId: conversationId),
        AppMcpToolNames.note,
        {'nota': text},
      );

  setUp(() async {
    root = Directory.systemTemp.createTempSync('spec-notes-');
    File('${root.path}/specs/SPEC-047-higiene.md')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(_text);
    db = memoryDatabase();
    c = ProviderContainer(
      overrides: [
        databaseOverride(db),
        appMcpToolsProvider.overrideWith((ref) => AppMcpTools(ref)),
      ],
    );
    ws = await c.read(workspacesRepoProvider).add(path: root.path, name: 'w');
    await c.read(specServiceProvider).sync(ws);
    spec = (await c.read(specsRepoProvider).getByCode(ws.id, 'SPEC-047'))!;
    await c
        .read(specStepsRepoProvider)
        .set(spec.id, 'R3', StepStatus.running, sessionId: 'sessao-r3');
    await c
        .read(sessionsRepoProvider)
        .insert(
          id: 'sessao-r3',
          workspaceId: ws.id,
          worktreePath: root.path,
          branch: 'spec/047',
          model: 'inherit',
          title: 'SPEC-047 · R3',
          specId: spec.id,
          steps: 'R3',
        );
  });
  tearDown(() async {
    c.dispose();
    await db.close();
    root.deleteSync(recursive: true);
  });

  test('the note goes to the history of the spec, with the hour and the '
      'session, and does not conclude the step', () async {
    final before = await c.read(specStepsRepoProvider).bySpec(spec.id);
    final r = await note('Comecei pela tabela: a limpeza precisa guardar.');
    expect(r.error, isFalse, reason: r.text);
    expect(r.text, contains('não conclui a etapa'));
    await note('Migração da tabela pronta. Faltam os testes.');

    final notes = await c.read(specNotesRepoProvider).bySpec(spec.id);
    expect(notes.map((n) => n.note), [
      'Migração da tabela pronta. Faltam os testes.',
      'Comecei pela tabela: a limpeza precisa guardar.',
    ]);
    expect(notes.first.sessionId, 'sessao-r3');
    expect(notes.first.steps, 'R3');

    // Steps, status and stage as they were; the file too.
    final after = await c.read(specStepsRepoProvider).bySpec(spec.id);
    expect(
      [for (final s in after) '${s.step}:${s.status.name}'],
      [for (final s in before) '${s.step}:${s.status.name}'],
    );
    final row = (await c.read(specsRepoProvider).getById(spec.id))!;
    expect((row.status, row.stage), (spec.status, spec.stage));
    expect(
      File('${root.path}/specs/SPEC-047-higiene.md').readAsStringSync(),
      _text,
    );
  });

  test('a note over 280 characters, an empty one or one from a run '
      'without a spec is refused and nothing is written', () async {
    expect((await note('x' * 281)).error, isTrue);
    expect((await note('   ')).error, isTrue);
    expect((await note('oi', conversationId: 9)).error, isTrue);
    expect(await c.read(specNotesRepoProvider).bySpec(spec.id), isEmpty);
  });

  testWidgets('the card shows the newest note and the panel the history', (
    tester,
  ) async {
    final repo = c.read(specNotesRepoProvider);
    final now = DateTime.now();
    await tester.runAsync(() async {
      await repo.add(
        specId: spec.id,
        note: 'Comecei pela tabela.',
        sessionId: 'sessao-r3',
        steps: 'R3',
        at: now.subtract(const Duration(minutes: 30)),
      );
      await repo.add(
        specId: spec.id,
        note: 'Migração da tabela pronta.',
        sessionId: 'sessao-r3',
        steps: 'R3',
        at: now.subtract(const Duration(minutes: 2)),
      );
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Column(
              children: [
                SpecNoteLine(spec: spec),
                SpecNotesHistory(spec: spec),
              ],
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('board-note-SPEC-047')),
        matching: find.text('Migração da tabela pronta. · há 2 min'),
      ),
      findsOneWidget,
    );
    expect(find.text('Andamento'), findsOneWidget);
    expect(find.text('Comecei pela tabela.'), findsOneWidget);
    expect(find.text('Migração da tabela pronta.'), findsOneWidget);
    expect(find.text('SPEC-047 · R3'), findsNWidgets(2));
    expect(find.textContaining('não concluem a etapa'), findsOneWidget);
  });

  test('noteAge', () {
    final now = DateTime(2026, 11, 13, 16, 40);
    expect(noteAge(now, now: now), 'agora');
    expect(noteAge(DateTime(2026, 11, 13, 16, 26), now: now), 'há 14 min');
    expect(noteAge(DateTime(2026, 11, 13, 13, 40), now: now), 'há 3 h');
  });
}
