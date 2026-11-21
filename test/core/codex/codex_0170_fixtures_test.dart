import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_provider.dart';
import 'package:promptorium/core/providers/agent_event.dart';
import 'package:promptorium/core/providers/agent_provider.dart';

import 'fake_codex.dart';

/// SPEC-093 R18: the current `CodexRun` reads real 0.170 transcripts
/// (`test/fixtures/codex/0.170/`) without breaking. What it gets wrong is
/// pinned here as the current behaviour and listed in
/// `docs/pesquisa/codex-0170.md` ("Divergências"); fixing it belongs to
/// SPEC-094/095/096, not to this probe.
const _dir = 'test/fixtures/codex/0.170';

Map<String, Map<String, dynamic>> _handshake() {
  final t = readCodexTranscript('$_dir/handshake.jsonl');
  Map<String, dynamic> resultOf(String method) {
    final id = t
        .firstWhere((l) => l.dir == 'send' && l.msg['method'] == method)
        .msg['id'];
    return t
            .firstWhere(
              (l) =>
                  l.dir == 'recv' &&
                  l.msg['method'] == null &&
                  l.msg['id'] == id,
            )
            .msg['result']
        as Map<String, dynamic>;
  }

  return {
    'account/read': resultOf('account/read'),
    'model/list': resultOf('model/list'),
  };
}

class _Replay {
  _Replay(this.fake, this.run);
  final FakeCodex fake;
  final CodexRun run;
  final events = <AgentEvent>[];

  List<T> of<T>() => events.whereType<T>().toList();
}

Future<_Replay> _start(
  String fixture,
  AgentStartOptions options, {
  bool approve = false,
}) async {
  final fake = FakeCodex.replay(
    readCodexTranscript('$_dir/$fixture.jsonl'),
    fallback: _handshake(),
  );
  final run = await CodexProvider(
    starter: (exe, args, {workingDirectory, environment}) async => fake,
  ).start(options) as CodexRun;
  final r = _Replay(fake, run);
  run.events.listen((e) {
    r.events.add(e);
    if (approve && e is PermissionRequest) unawaited(run.approve(e.requestId));
  });
  addTearDown(() async {
    await run.stop(timeout: const Duration(milliseconds: 50));
    await fake.finish();
  });
  return r;
}

Future<Result> _turn(_Replay r, String text) async {
  final before = r.of<Result>().length;
  await r.run.send(text);
  for (var i = 0; i < 400 && r.of<Result>().length == before; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(r.of<Result>().length, before + 1, reason: 'turn/completed chegou');
  return r.of<Result>().last;
}

List<ToolUseBlock> _tools(_Replay r) => [
  for (final m in r.of<AssistantMessage>())
    ...m.blocks.whereType<ToolUseBlock>(),
];

void main() {
  test('handshake 0.170: the fallback catalog keeps the probe model', () {
    final models = _handshake()['model/list']!['data'] as List;
    expect(models.map((m) => m['id']), contains('gpt-5.6-luna'));
    for (final m in models) {
      expect(m['inputModalities'], containsAll(['text', 'image']));
    }
  });

  test('R5 read-only: refusal arrives only as agent text, no item', () async {
    final r = await _start(
      'leitura',
      const AgentStartOptions(
        workingDirectory: '/w',
        mode: PromptMode.ask,
        model: 'gpt-5.6-luna',
      ),
    );
    final res = await _turn(r, 'Crie o arquivo ola.txt com o texto oi.');
    expect(res.isSuccess, isTrue);
    expect(res.result, contains('somente leitura'));
    // The rejected apply_patch ran inside code mode: no fileChange item.
    expect(_tools(r), isEmpty);
    expect(r.fake.unmatched, containsAll(['account/read', 'model/list']));
  });

  test('R6 fileChange + approval: kind is an object, not a string', () async {
    final r = await _start(
      'edicao',
      const AgentStartOptions(
        workingDirectory: '/w',
        mode: PromptMode.edit,
        model: 'gpt-5.6-luna',
      ),
      approve: true,
    );
    final res = await _turn(r, 'Crie nota.txt e altere base.txt.');
    expect(res.isSuccess, isTrue);
    final ask = r.of<PermissionRequest>().single;
    expect(ask.toolName, 'Edit');
    expect(ask.description, 'command failed; retry without sandbox?');
    // The adapter answers `accept`; the probe sent `acceptForSession`.
    expect(r.fake.appAnswers.values.single['result'], {'decision': 'accept'});
    expect(r.fake.recordedAnswers.values.single['result'], {
      'decision': 'acceptForSession',
    });
    final edit = _tools(r).singleWhere((t) => t.name == 'Edit');
    final changes = edit.input['changes'] as List;
    expect(changes.first['kind'], {'type': 'add'});
    expect(edit.input.containsKey('file_path'), isFalse);
  });

  test(
    'R4/D1 safe thread (read-only, policy per turn) fails the current check',
    () async {
      // The probe opened the thread read-only and raised the sandbox on
      // turn/start, which keeps ~/.codex/config.toml untouched. The current
      // adapter asks for workspace-write on thread/start and rejects the
      // read-only answer: SPEC-096 changes both sides.
      final t = readCodexTranscript('$_dir/edicao-turno.jsonl');
      final turn = t.firstWhere((l) => l.msg['method'] == 'turn/start');
      expect(turn.msg['params']['sandboxPolicy'], {'type': 'workspaceWrite'});
      expect(turn.msg['params']['approvalPolicy'], 'on-request');
      final update = t
          .where((l) => l.msg['method'] == 'item/completed')
          .map((l) => l.msg['params']['item'] as Map)
          .firstWhere((i) => i['type'] == 'fileChange');
      expect((update['changes'] as List).first['kind'], {
        'type': 'update',
        'move_path': null,
      });
      await expectLater(
        _start(
          'edicao-turno',
          const AgentStartOptions(
            workingDirectory: '/w',
            mode: PromptMode.edit,
            model: 'gpt-5.6-luna',
          ),
        ),
        throwsA(isA<AgentUnavailable>()),
      );
    },
  );

  test('remote-control payloads keep the machine name redacted', () {
    for (final l in readCodexTranscript('$_dir/handshake.jsonl')) {
      if (l.msg['method'] != 'remoteControl/status/changed') continue;
      expect(l.msg['params']['serverName'], '[redigido]');
      expect(l.msg['params']['installationId'], '[redigido]');
    }
  });

  test(
    'R7/R9 untrusted: three command approvals, env reaches the shell',
    () async {
      final r = await _start(
        'comando',
        const AgentStartOptions(
          workingDirectory: '/w',
          mode: PromptMode.refine,
          model: 'gpt-5.6-luna',
        ),
        approve: true,
      );
      final res = await _turn(r, 'Rode ls, cat nao-existe.txt e echo.');
      expect(res.isSuccess, isTrue);
      expect(r.of<PermissionRequest>().map((p) => p.toolName), [
        'Bash',
        'Bash',
        'Bash',
      ]);
      final results = r.of<ToolResult>();
      expect(results.map((t) => t.isError), [false, true, false]);
      expect(results.last.content, contains('agente=codex'));
      expect(r.fake.appAnswers.length, 3);
    },
  );

  test(
    'R8 worktree, never: the failed fileChange is an error result',
    () async {
      final r = await _start(
        'worktree-com_roots_never',
        const AgentStartOptions(
          workingDirectory: '/w',
          mode: PromptMode.edit,
          model: 'gpt-5.6-luna',
          extras: CodexExtras(approval: 'never'),
        ),
      );
      final res = await _turn(r, 'Crie o arquivo e rode git commit.');
      expect(res.isSuccess, isTrue);
      expect(r.of<ToolResult>().single.isError, isTrue);
    },
  );

  test(
    'R8 worktree, on-request: bwrap failure reaches only the text',
    () async {
      final r = await _start(
        'worktree-sem_roots_on_request',
        const AgentStartOptions(
          workingDirectory: '/w',
          mode: PromptMode.edit,
          model: 'gpt-5.6-luna',
        ),
        approve: true,
      );
      final res = await _turn(r, 'Crie o arquivo e rode git commit.');
      expect(res.result, contains('bwrap'));
      expect(r.of<PermissionRequest>(), hasLength(1));
    },
  );

  test('R10/R12/R14 CLAUDE.md, outputSchema and usage per turn', () async {
    final r = await _start(
      'contexto',
      const AgentStartOptions(
        workingDirectory: '/w',
        mode: PromptMode.ask,
        model: 'gpt-5.6-luna',
        jsonSchema: '{"type":"object","properties":{"ok":{"type":"boolean"}},"required":["ok"]}',
      ),
    );
    final first = await _turn(r, 'Qual é a palavra-senha?');
    expect(first.result, 'LARANJA-42');
    // Per-turn usage = delta of `total`, minus cached input.
    expect(first.usage.inputTokens, 12393 - 10112);
    expect(first.usage.cacheReadInputTokens, 10112);
    expect(first.usage.outputTokens, 10);
    final second = await _turn(r, 'Responda se 2+2=4.');
    expect(second.result, '{"ok":true}');
    expect(second.usage.inputTokens, 26430 - 12393);
    expect(second.usage.cacheReadInputTokens, 0);
    final sent = r.fake.writtenJson
        .where((m) => m['method'] == 'turn/start')
        .toList();
    expect(sent.last['params']['outputSchema'], isNotNull);
  });

  test('R11 image turn replays with an image-capable model', () async {
    final r = await _start(
      'imagem',
      const AgentStartOptions(
        workingDirectory: '/w',
        mode: PromptMode.ask,
        model: 'gpt-5.6-luna',
      ),
    );
    final res = await _turn(r, 'Diga a cor de cada imagem.');
    expect(res.result, contains('Vermelho'));
    expect(r.run.supportsImages, isTrue);
  });

  test('R13 interrupt: status interrupted becomes an error result', () async {
    final r = await _start(
      'interromper',
      const AgentStartOptions(
        workingDirectory: '/w',
        mode: PromptMode.ask,
        model: 'gpt-5.6-luna',
      ),
    );
    final res = await _turn(r, 'Escreva os números de 1 a 300.');
    expect(res.subtype, 'interrupted');
    expect(res.isError, isTrue);
    expect(res.usage.outputTokens, 98);
  });

  test('R15 YOLO + untrusted -c hook: rm runs, nothing is denied', () async {
    final r = await _start(
      'hook_turno',
      const AgentStartOptions(
        workingDirectory: '/w',
        mode: PromptMode.edit,
        model: 'gpt-5.6-luna',
        yolo: true,
      ),
    );
    final res = await _turn(r, 'Rode rm apagar.txt.');
    expect(res.isSuccess, isTrue);
    final bash = _tools(r).singleWhere((t) => t.name == 'Bash');
    expect(bash.input['command'], contains('rm apagar.txt'));
    expect(r.of<ToolResult>().single.isError, isFalse);
  });

  test('transcripts carry no credentials or personal paths', () {
    for (final name in [
      'handshake',
      'leitura',
      'edicao',
      'edicao-turno',
      'comando',
      'worktree-com_roots_never',
      'worktree-sem_roots_on_request',
      'contexto',
      'imagem',
      'interromper',
      'hook_turno',
      'sandbox',
      'hooks-por_c',
    ]) {
      for (final l in readCodexTranscript('$_dir/$name.jsonl')) {
        final s = l.msg.toString();
        expect(s, isNot(contains('/home/')), reason: name);
        expect(s, isNot(matches(RegExp(r'[\w.+-]+@[\w-]+\.\w'))), reason: name);
        expect(s, isNot(matches(RegExp(r'\bsk-[A-Za-z0-9]'))), reason: name);
        expect(
          s,
          isNot(matches(RegExp(r'eyJ[A-Za-z0-9_-]{10,}\.'))),
          reason: name,
        );
      }
    }
  });
}
