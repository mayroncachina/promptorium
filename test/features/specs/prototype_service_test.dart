import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/specs/prototype/prototype_files.dart';
import 'package:promptorium/features/specs/prototype/prototype_service.dart';
import 'package:promptorium/features/specs/spec_action.dart';
import 'package:promptorium/core/claude/readonly_run.dart'
    show PlannerException;

import 'dart:async';

import 'dart:convert';

import 'package:promptorium/core/claude/claude_cli.dart';
import 'package:promptorium/core/claude/run_extensions.dart';

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';
import 'prototype_files_test.dart' show spec;

/// What the fake agent was called with.
class AgentCall {
  AgentCall(this.cwd, this.options, this.prompt, [this.cancelled]);
  final String cwd;
  final ClaudeOptions options;
  final String prompt;
  final Future<void>? cancelled;
}

Spec specRow(String path) => Spec(
  hasPlan: false,
  inTray: false,
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
          cancelled,
        }) {
          final call = AgentCall(cwd, options, prompt, cancelled);
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

  test('SPEC-025 R9: cancelling "Gerar telas" stops the agent, puts back '
      'what it changed and throws SpecActionCancelled', () async {
    Directory(dir()).createSync(recursive: true);
    File('${dir()}/R1-lista.html').writeAsStringSync('<p>antes</p>');
    final started = Completer<void>();
    behave = (call) async {
      File('${dir()}/R1-lista.html').writeAsStringSync('<p>meio</p>');
      started.complete();
      await call.cancelled;
      // The real run fails like this once `cancelled` completes.
      throw const PlannerException('Verificação cancelada.');
    };
    final cancel = Completer<void>();
    final run = c
        .read(prototypeServiceProvider)
        .generate(ws, specRow('specs/x.md'), spec, cancelled: cancel.future);
    final rejected = expectLater(run, throwsA(isA<SpecActionCancelled>()));
    await started.future;
    expect(calls.single.cancelled, isNotNull);
    expect(c.read(prototypeJobsProvider), isNotEmpty);
    cancel.complete();
    await rejected;
    expect(c.read(prototypeJobsProvider), isEmpty);
    expect(File('${dir()}/R1-lista.html').readAsStringSync(), '<p>antes</p>');
    final index = await PrototypeIndex.read(dir());
    expect(index.history.single.failed, isTrue);
    expect(index.history.single.answer, 'Geração cancelada.');
  });

  test('SPEC-025 R9: the real agent stops the CLI when "cancelled" '
      'completes', () async {
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
    final cancel = Completer<void>();
    final run = real.read(prototypeAgentProvider)(
      cwd: tmp.path,
      options: prototypeOptions('docs/mockups/spec-022'),
      prompt: 'gere',
      cancelled: cancel.future,
    );
    final rejected = expectLater(run, throwsA(isA<PlannerException>()));
    await until(() async => cli.processes.isNotEmpty);
    cancel.complete();
    await rejected;
    expect(cli.last.signals, isNotEmpty);
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

  test('SPEC-027 R6 R7: removeAll deletes files and index entries, marks the '
      'emptied requirement; restore puts everything back; generating only R1 '
      'asks just that requirement and clears the mark', () async {
    Directory(dir()).createSync(recursive: true);
    File('${dir()}/R1-lista.html').writeAsStringSync('<p>1</p>');
    File('${dir()}/R2-detalhe.html').writeAsStringSync('<p>2</p>');
    File('${dir()}/R2-detalhe.b.html').writeAsStringSync('<p>2b</p>');
    final at = DateTime(2026, 11, 1, 9, 30);
    await PrototypeIndex(
      screens: {
        'R1-lista.html': ScreenMeta(description: 'lista', createdAt: at),
        'R2-detalhe.b.html': ScreenMeta(description: 'denso', createdAt: at),
      },
    ).write(dir());
    final service = c.read(prototypeServiceProvider);
    final row = specRow('specs/SPEC-022.md');
    final r1 = parseMockupName('R1-lista.html')!;
    final r2b = parseMockupName('R2-detalhe.b.html')!;

    final removed = await service.removeAll(
      ws,
      row,
      [r1, r2b],
      approved: {'R1-lista.html'},
    );
    expect(File('${dir()}/R1-lista.html').existsSync(), isFalse);
    expect(File('${dir()}/R2-detalhe.b.html').existsSync(), isFalse);
    expect(File('${dir()}/R2-detalhe.html').existsSync(), isTrue);
    var index = await PrototypeIndex.read(dir());
    expect(index.screens.keys, isEmpty);
    // R1 has no screen left; R2 still has A.
    expect(index.emptied.keys, ['R1']);
    expect(index.emptied['R1']!.title, 'Lista');
    expect(index.emptied['R1']!.hadApproval, isTrue);
    expect(removed.emptied, {'R1'});
    expect(
      removed.files.keys,
      unorderedEquals(['R1-lista.html', 'R2-detalhe.b.html']),
    );

    await service.restore(ws, row, removed);
    expect(File('${dir()}/R1-lista.html').readAsStringSync(), '<p>1</p>');
    expect(File('${dir()}/R2-detalhe.b.html').readAsStringSync(), '<p>2b</p>');
    index = await PrototypeIndex.read(dir());
    expect(index.screens['R1-lista.html']!.description, 'lista');
    expect(index.screens['R2-detalhe.b.html']!.createdAt, at);
    expect(index.emptied, isEmpty);

    // Emptied again, then "Gerar tela do R1".
    await service.removeAll(ws, row, [r1]);
    expect((await PrototypeIndex.read(dir())).emptied.keys, ['R1']);
    behave = (call) async {
      File('${dir()}/R1-lista.html').writeAsStringSync('<p>novo</p>');
      return {'telas': [], 'resposta': 'ok'};
    };
    await service.generate(ws, row, spec, only: {'R1'});
    expect(calls.last.prompt, contains('Gere somente a tela de R1'));
    index = await PrototypeIndex.read(dir());
    expect(index.emptied, isEmpty);
    expect(index.history.last.request, 'Gerar tela do R1');
    expect(index.history.last.requirements, ['R1']);
  });
}
