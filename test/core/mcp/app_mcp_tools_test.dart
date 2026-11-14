import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/mcp/app_mcp_config.dart';
import 'package:promptorium/core/mcp/app_mcp_server.dart';
import 'package:promptorium/core/mcp/app_mcp_tools.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/specs/spec_service.dart';

import '../../helpers/test_db.dart';
import 'mcp_test_utils.dart';

String _spec(
  String code, {
  String status = 'aprovada',
  List<String> deps = const [],
}) =>
    '---\nid: $code\nstatus: $status\n'
    '${deps.isEmpty ? '' : 'depende-de: [${deps.join(', ')}]\n'}---\n'
    '# Título de $code\n\n## Objetivo\n\nx\n\n## Requisitos\n\n'
    '- R1 · O app deve fazer a.\n- R2 · O app deve fazer b.\n\n'
    '## Critérios de aceite\n\n- [ ] a [R1]\n- [ ] b [R2]\n';

const _newSpec = '''
---
id: SPEC-999
status: aprovada
arquivo: /etc/passwd
---

# Exportar o relatório do Review em PDF

## Objetivo

Gerar um PDF.

## Requisitos

- R1 · O Review deve oferecer "Exportar PDF".
- R2 · Capa com o logo do projeto.

## Critérios de aceite

- [ ] Exporta [R1]
''';

void main() {
  late Directory root;
  late AppDatabase db;
  late Workspace ws;
  late ProviderContainer c;
  late AppMcpTools tools;
  late List<(McpGrant, String)> notes;

  McpGrant grant({
    String token = 't1',
    int? workspaceId,
    String sessionId = 'sessao-1',
    int limit = 10,
    int created = 0,
    bool skipApproval = false,
  }) => McpGrant(
    token: token,
    workspaceId: workspaceId ?? ws.id,
    sessionId: sessionId,
    access: McpAccess.write,
    limit: limit,
    created: created,
    skipApproval: skipApproval,
  );

  void write(String code, {String status = 'aprovada', List<String>? deps}) {
    final f = File('${root.path}/specs/$code-x.md');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(_spec(code, status: status, deps: deps ?? const []));
  }

  List<String> files() => [
    for (final f in Directory('${root.path}/specs').listSync())
      f.uri.pathSegments.last,
  ]..sort();

  setUp(() async {
    root = Directory.systemTemp.createTempSync('mcp-tools-');
    db = memoryDatabase();
    notes = [];
    c = ProviderContainer(
      overrides: [
        databaseOverride(db),
        appMcpToolsProvider.overrideWith(
          (ref) => AppMcpTools(ref, onCreated: (g, t) => notes.add((g, t))),
        ),
      ],
    );
    ws = await c.read(workspacesRepoProvider).add(path: root.path, name: 'w');
    write('SPEC-001', status: 'concluida');
    write('SPEC-002', deps: ['SPEC-001']);
    write('SPEC-003', status: 'rascunho');
    await c.read(specServiceProvider).sync(ws);
    tools = c.read(appMcpToolsProvider) as AppMcpTools;
  });
  tearDown(() async {
    c.dispose();
    await db.close();
    root.deleteSync(recursive: true);
  });

  Future<McpToolOutcome> call(
    String tool, [
    Map<String, Object?> args = const {},
    McpGrant? g,
  ]) => tools.call(g ?? grant(), tool, args);

  group('R3 · reads', () {
    test('listar_specs: code, title, status, column, sprint and '
        'depende-de, with filters', () async {
      final all = await call('listar_specs');
      final specs = all.data!['specs'] as List;
      expect(
        [for (final s in specs) (s as Map)['codigo']],
        ['SPEC-001', 'SPEC-002', 'SPEC-003'],
      );
      final two = specs[1] as Map;
      expect(two['status'], 'aprovada');
      expect(two['coluna'], 'backlog');
      expect(two['depende_de'], ['SPEC-001']);
      expect(all.text, contains('SPEC-002 · Título de SPEC-002 · aprovada'));

      final drafts = await call('listar_specs', {'status': 'rascunho'});
      expect((drafts.data!['specs'] as List).single['codigo'], 'SPEC-003');
      final done = await call('listar_specs', {'coluna': 'concluida'});
      expect((done.data!['specs'] as List).single['codigo'], 'SPEC-001');
    });

    test('ler_spec: the text and the steps; another workspace does not see '
        'it', () async {
      final r = await call('ler_spec', {'codigo': 'spec-002'});
      expect(r.error, isFalse);
      expect(r.text, contains('# Título de SPEC-002'));
      final steps = r.data!['etapas'] as List;
      expect([for (final s in steps) (s as Map)['etapa']], ['R1', 'R2']);
      expect((steps.first as Map)['status'], 'pending');

      final other = await call('ler_spec', {
        'codigo': 'SPEC-002',
      }, grant(workspaceId: ws.id + 99));
      expect(other.error, isTrue);
    });

    test('estado_do_quadro: the columns, live sessions and what waits for '
        'the person', () async {
      final r = await call('estado_do_quadro');
      final cols = r.data!['colunas'] as Map;
      expect(cols['concluida'], ['SPEC-001 · Título de SPEC-001']);
      expect(r.data!['sessoes_vivas'], isEmpty);
      expect(r.text, contains('Precisa de você (0)'));
    });

    test('spec_atual: the spec and steps of the session, or none', () async {
      final none = await call('spec_atual');
      expect(none.text, 'Esta execução não trabalha numa spec.');
      final spec = (await c
          .read(specsRepoProvider)
          .getByCode(ws.id, 'SPEC-002'))!;
      await c
          .read(sessionsRepoProvider)
          .insert(
            id: 'sessao-1',
            workspaceId: ws.id,
            worktreePath: root.path,
            branch: 'main',
            model: 'inherit',
            title: 'SPEC-002 · R2',
            specId: spec.id,
            steps: 'R2',
          );
      final r = await call('spec_atual');
      expect(r.data!['spec'], 'SPEC-002');
      expect(r.data!['etapas_da_execucao'], ['R2']);
    });

    test('the reads are not write tools (no approval)', () {
      for (final n in [
        'listar_specs',
        'ler_spec',
        'estado_do_quadro',
        'spec_atual',
      ]) {
        expect(isAppMcpWriteTool(appMcpToolId(n)), isFalse);
        expect(appMcpReadToolIds, contains(appMcpToolId(n)));
      }
    });
  });

  group('R4, R6 · criar_spec and criar_filhas', () {
    test('criar_spec writes a draft at the next code, with depende-de and '
        'the origin, and returns the lint warnings', () async {
      final r = await call('criar_spec', {
        'texto': _newSpec,
        'depende_de': ['SPEC-002'],
      });
      expect(r.error, isFalse, reason: r.text);
      expect(r.created, 1);
      expect(r.data!['codigo'], 'SPEC-004');
      expect(r.text, startsWith('SPEC-004 criada como rascunho em specs/'));
      // R2 has no "deve": the lint says so.
      expect(r.data!['avisos'], isNotEmpty);
      final spec = (await c
          .read(specsRepoProvider)
          .getByCode(ws.id, 'SPEC-004'))!;
      expect(spec.status, SpecStatus.draft);
      expect(spec.dependsOn, ['SPEC-002']);
      expect(spec.agentSession, 'sessao-1');
      final text = File('${root.path}/${spec.path}').readAsStringSync();
      final doc = SpecDocument.parse(text);
      expect(doc.id, 'SPEC-004');
      expect(doc.status, SpecStatus.draft);
      expect(doc.frontmatter['origem'], 'agente');
      expect(doc.frontmatter['sessao'], 'sessao-1');
      // The agent's frontmatter (and its path) is gone.
      expect(text, isNot(contains('/etc/passwd')));
      expect(notes.single.$2, contains('SPEC-004'));
    });

    test('criar_filhas creates up to 6 children with depende-de: <pai>, in '
        'one call', () async {
      final r = await call('criar_filhas', {
        'pai': 'SPEC-002',
        'filhas': [
          {'texto': '# Gerar o PDF\n\n## Requisitos\n\n- R1 · Deve gerar.\n'},
          {'texto': '# Botão Exportar\n\n## Requisitos\n\n- R1 · Deve ter.\n'},
        ],
      });
      expect(r.error, isFalse, reason: r.text);
      expect(r.created, 2);
      final repo = c.read(specsRepoProvider);
      for (final code in ['SPEC-004', 'SPEC-005']) {
        final s = (await repo.getByCode(ws.id, code))!;
        expect(s.dependsOn, ['SPEC-002']);
        expect(s.status, SpecStatus.draft);
      }
      expect(notes.single.$2, contains('filhas da SPEC-002'));
    });

    test('more than 6 children, an unknown parent or a spec without a '
        'title write nothing', () async {
      final seven = [
        for (var i = 0; i < 7; i++) {'texto': '# F$i\n'},
      ];
      final before = files();
      expect(
        (await call('criar_filhas', {
          'pai': 'SPEC-002',
          'filhas': seven,
        })).error,
        isTrue,
      );
      expect(
        (await call('criar_filhas', {
          'pai': 'SPEC-777',
          'filhas': [
            {'texto': '# F\n'},
          ],
        })).error,
        isTrue,
      );
      expect(
        (await call('criar_filhas', {
          'pai': 'SPEC-002',
          'filhas': [
            {'texto': '# Boa\n'},
            {'texto': 'sem título'},
          ],
        })).error,
        isTrue,
      );
      expect((await call('criar_spec', {'texto': 'sem título'})).error, isTrue);
      expect(
        (await call('criar_spec', {
          'texto': '# X\n',
          'depende_de': ['SPEC-404'],
        })).error,
        isTrue,
      );
      expect(files(), before);
    });

    test('"sem perguntar" marks the creation in the timeline', () async {
      await call('criar_spec', {'texto': '# X\n'}, grant(skipApproval: true));
      expect(notes.single.$2, contains('sem aprovação'));
    });
  });

  group('R5 · never', () {
    test('no tool changes status, column or steps, overwrites a file or '
        'takes a path', () async {
      final repo = c.read(specsRepoProvider);
      Future<List<String>> snapshot() async => [
        for (final s in await repo.watchByWorkspace(ws.id).first)
          '${s.code}|${s.status}|${s.stage}|${s.path}',
      ];
      final before = await snapshot();
      final texts = {
        for (final f in files())
          f: File('${root.path}/specs/$f').readAsStringSync(),
      };
      await call('listar_specs');
      await call('ler_spec', {'codigo': 'SPEC-002'});
      await call('estado_do_quadro');
      await call('spec_atual');
      await call('criar_spec', {
        'texto': _spec('SPEC-002'),
        'caminho': '${root.path}/specs/SPEC-002-x.md',
        'status': 'concluida',
      });
      // The existing specs are as they were (the new one is SPEC-004).
      expect((await snapshot()).take(3), before);
      for (final MapEntry(:key, :value) in texts.entries) {
        expect(File('${root.path}/specs/$key').readAsStringSync(), value);
      }
      final created = (await repo.getByCode(ws.id, 'SPEC-004'))!;
      expect(created.status, SpecStatus.draft);
      expect(created.path, startsWith('specs/SPEC-004-'));
      expect(c.read(specStepsRepoProvider), isNotNull);
      expect(await c.read(specStepsRepoProvider).bySpec(created.id), isEmpty);
      // No tool takes a path in its schema.
      for (final t in appMcpCatalog) {
        final props = (t.inputSchema['properties'] as Map).keys;
        expect(props.any((k) => '$k'.contains('caminho')), isFalse);
        expect(t.inputSchema['additionalProperties'], isFalse);
      }
    });
  });

  group('R9 · limit', () {
    late AppMcpServer server;
    late int port;
    setUp(() async {
      server = AppMcpServer(tools);
      port = await server.start();
    });
    tearDown(() => server.stop());

    test('above the limit the creation is refused with the reason and '
        'nothing is written', () async {
      server.issue(grant(limit: 2));
      final a = await mcpCall(port, 't1', 'criar_spec', {'texto': '# A\n'});
      expect(a['isError'], isNull);
      expect(server.grantOf('t1')!.created, 1);
      final before = files();
      final over = await mcpCall(port, 't1', 'criar_filhas', {
        'pai': 'SPEC-002',
        'filhas': [
          {'texto': '# B\n'},
          {'texto': '# C\n'},
        ],
      });
      expect(over['isError'], isTrue);
      final reason = (over['content'] as List).single['text'] as String;
      expect(reason, contains('Limite de 2 specs por execução'));
      expect(reason, contains('Nada foi gravado'));
      expect(files(), before);
      final b = await mcpCall(port, 't1', 'criar_spec', {'texto': '# B\n'});
      expect(b['isError'], isNull);
      final c3 = await mcpCall(port, 't1', 'criar_spec', {'texto': '# C\n'});
      expect(c3['isError'], isTrue);
      expect(server.grantOf('t1')!.created, 2);
    });

    test('two calls at once do not pass the limit together', () async {
      server.issue(grant(limit: 1));
      final both = await Future.wait([
        mcpCall(port, 't1', 'criar_spec', {'texto': '# A\n'}),
        mcpCall(port, 't1', 'criar_spec', {'texto': '# B\n'}),
      ]);
      expect(both.where((r) => r['isError'] == true), hasLength(1));
      expect(files().where((f) => f.startsWith('SPEC-004')), hasLength(1));
      expect(files().where((f) => f.startsWith('SPEC-005')), isEmpty);
    });
  });
}
