import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/specs/prototype/prototype_files.dart';
import 'package:promptorium/features/specs/prototype/prototype_service.dart';

import 'dart:convert';

import 'package:promptorium/core/claude/claude_cli.dart';
import 'package:promptorium/core/claude/run_extensions.dart';

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';
import 'prototype_files_test.dart' show spec;

/// What the fake agent was called with.
class AgentCall {
  AgentCall(this.cwd, this.options, this.prompt);
  final String cwd;
  final ClaudeOptions options;
  final String prompt;
}

Spec specRow(String path) => Spec(
  id: 7,
  workspaceId: 1,
  code: 'SPEC-022',
  title: 'Protótipo',
  path: path,
  status: SpecStatus.review,
  stage: SpecStage.backlog,
  requirements: const [],
  dependsOn: const [],
  autoAdvance: true,
  reviewRounds: 0,
  gateResends: 0,
  rejectedHunks: 0,
);

void main() {
  late Directory tmp;
  late Workspace ws;
  late List<AgentCall> calls;
  late Future<Object?> Function(AgentCall) behave;
  late ProviderContainer c;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('promptorium-proto-');
    ws = Workspace(
      id: 1,
      path: tmp.path,
      name: 'ws',
      createdAt: DateTime(2026),
    );
    calls = [];
    behave = (_) async => null;
    c = ProviderContainer(
      overrides: [
        prototypeWatchProvider.overrideWithValue(false),
        prototypeAgentProvider.overrideWithValue(({
          required cwd,
          required options,
          required prompt,
        }) {
          final call = AgentCall(cwd, options, prompt);
          calls.add(call);
          return behave(call);
        }),
      ],
    );
  });

  tearDown(() {
    c.dispose();
    tmp.deleteSync(recursive: true);
  });

  String dir() => '${tmp.path}/docs/mockups/spec-022';

  test('R2: "Gerar telas" asks one HTML per requirement in the folder and '
      'restricts writing to it', () async {
    behave = (call) async {
      File('${dir()}/R1-lista.html').writeAsStringSync('<p>1</p>');
      File('${dir()}/R2-detalhe.html').writeAsStringSync('<p>2</p>');
      return {
        'telas': [
          {
            'arquivo': 'R1-lista.html',
            'requisito': 'R1',
            'descricao': 'lista com busca',
          },
        ],
        'resposta': 'Duas telas.',
      };
    };
    final out = await c
        .read(prototypeServiceProvider)
        .generate(ws, specRow('specs/SPEC-022.md'), spec);
    final call = calls.single;
    expect(call.cwd, tmp.path);
    expect(call.prompt, contains('um arquivo HTML autocontido por requisito'));
    expect(call.prompt, contains('`docs/mockups/spec-022/`'));
    expect(call.prompt, contains('- R1 · Lista'));
    expect(call.prompt, contains('R<n>-<slug>.html'));
    final args = call.options.toArgs();
    // Only the folder may be written; no shell.
    expect(call.options.allowedTools, ['Edit(docs/mockups/spec-022/**)']);
    expect(call.options.tools, isNot(contains('Bash')));
    expect(call.options.tools, containsAll(['Write', 'Read']));
    expect(call.options.disallowedTools, contains('Bash'));
    expect(call.options.permissionMode, ClaudePermissionMode.defaultMode);
    expect(args, isNot(contains('--dangerously-skip-permissions')));
    expect(call.options.appendSystemPrompt, contains('SOMENTE dentro de'));
    // The Promptorium look comes from tokens.dart.
    expect(call.options.appendSystemPrompt, contains('#0E1014'));
    expect(call.options.appendSystemPrompt, contains('#F2A541'));
    expect(call.options.appendSystemPrompt, contains('IBM Plex Sans'));
    expect(out.created, ['R1-lista.html', 'R2-detalhe.html']);
    final index = await PrototypeIndex.read(dir());
    expect(index.screens['R1-lista.html']!.description, 'lista com busca');
    expect(index.history.single.request, 'Gerar telas da spec');
    expect(index.history.single.answer, 'Duas telas.');
    expect(c.read(prototypeJobsProvider), isEmpty);
  });

  test('R7: a request with R1 selected creates R1-<slug>.b.html and keeps '
      'the original (an overwrite is put back)', () async {
    Directory(dir()).createSync(recursive: true);
    File('${dir()}/R1-lista.html').writeAsStringSync('original');
    late bool runningDuring;
    behave = (call) async {
      runningDuring =
          c.read(prototypeJobsProvider)[7]?.targets.single == 'R1-lista.b.html';
      File('${dir()}/R1-lista.b.html').writeAsStringSync('nova');
      // Misbehaving agent: also overwrites the base.
      File('${dir()}/R1-lista.html').writeAsStringSync('estragado');
      return {
        'telas': [
          {
            'arquivo': 'R1-lista.b.html',
            'requisito': 'R1',
            'descricao': 'busca e filtros',
          },
        ],
        'resposta': 'Variação B.',
      };
    };
    final base = parseMockupName('R1-lista.html')!;
    final out = await c
        .read(prototypeServiceProvider)
        .vary(
          ws,
          specRow('specs/SPEC-022.md'),
          spec,
          selected: [base],
          request: 'mais denso',
        );
    expect(runningDuring, isTrue);
    expect(calls.single.prompt, contains('mais denso'));
    expect(
      calls.single.prompt,
      contains(
        'base `docs/mockups/spec-022/R1-lista.html` → novo '
        '`docs/mockups/spec-022/R1-lista.b.html`',
      ),
    );
    expect(calls.single.options.allowedTools, [
      'Edit(docs/mockups/spec-022/**)',
    ]);
    expect(out.created, ['R1-lista.b.html']);
    expect(out.restored, ['R1-lista.html']);
    expect(File('${dir()}/R1-lista.html').readAsStringSync(), 'original');
    expect(File('${dir()}/R1-lista.b.html').readAsStringSync(), 'nova');
    final index = await PrototypeIndex.read(dir());
    expect(index.history.single.requirements, ['R1']);
    expect(index.history.single.files, ['R1-lista.b.html']);
  });

  test('a failed run is recorded and clears the job', () async {
    behave = (_) async => throw Exception('sem rede');
    await expectLater(
      c
          .read(prototypeServiceProvider)
          .generate(ws, specRow('specs/SPEC-022.md'), spec),
      throwsException,
    );
    final index = await PrototypeIndex.read(dir());
    expect(index.history.single.failed, isTrue);
    expect(c.read(prototypeJobsProvider), isEmpty);
  });

  test('R2: the real run passes --tools without Bash and --allowedTools '
      'Edit(<pasta>/**); a write elsewhere is denied', () async {
    final cli = FakeCli();
    final real = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        claudeProcessStarterProvider.overrideWithValue(cli.start),
        runSettingsDirProvider.overrideWithValue('${tmp.path}/run'),
      ],
    );
    addTearDown(real.dispose);
    await real.read(appSettingsProvider.notifier).load();
    final done = real.read(prototypeAgentProvider)(
      cwd: tmp.path,
      options: prototypeOptions('docs/mockups/spec-022'),
      prompt: 'gere',
    );
    await until(() async => cli.args.isNotEmpty);
    final args = cli.args.single;
    expect(args[args.indexOf('--tools') + 1], 'Read,Glob,Grep,Write,Edit');
    expect(
      args[args.indexOf('--allowedTools') + 1],
      'Edit(docs/mockups/spec-022/**)',
    );
    expect(args[args.indexOf('--permission-mode') + 1], 'default');
    cli.last.emit(
      jsonEncode({
        'type': 'control_request',
        'request_id': 'req-1',
        'request': {
          'subtype': 'can_use_tool',
          'tool_name': 'Write',
          'input': {'file_path': '${tmp.path}/lib/x.dart', 'content': 'x'},
          'tool_use_id': 'toolu_1',
        },
      }),
    );
    await until(
      () async => cli.last.writtenJson.any(
        (j) => '$j'.contains('req-1') && '$j'.contains('deny'),
      ),
    );
    expect(
      cli.last.writtenJson
          .where((j) => '$j'.contains('req-1'))
          .single
          .toString(),
      contains('pasta de mockups'),
    );
    cli.last.emit(
      jsonEncode({
        'type': 'result',
        'subtype': 'success',
        'result': '{"telas":[],"resposta":"ok"}',
        'session_id': 's',
        'total_cost_usd': 0,
      }),
    );
    expect(await done, {'telas': <Object?>[], 'resposta': 'ok'});
  });
}
