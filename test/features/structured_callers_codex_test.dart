import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_cli.dart';
import 'package:promptorium/core/claude/run_extensions.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/providers/provider_preferences.dart';
import 'package:promptorium/core/providers/structured_run.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/project/custom_stack.dart';
import 'package:promptorium/features/project/project_planner.dart';
import 'package:promptorium/features/prompt/split_specs.dart';
import 'package:promptorium/features/specs/prototype/prototype_service.dart';
import 'package:promptorium/features/specs/spec_answers.dart';
import 'package:promptorium/features/specs/spec_file.dart';
import 'package:promptorium/features/specs/spec_verifier.dart';
import 'package:promptorium/features/vibe/vibe_guard.dart';
import 'package:promptorium/features/skills/skill_writer.dart';

import '../core/codex/fake_codex.dart';
import '../helpers/test_db.dart';
import 'sessions/session_test_utils.dart' show FakeCli, until;

/// SPEC-100 R8: each flow of the table runs on the provider of "Planner e
/// assistentes" — here the Codex — with the schema in `outputSchema` and a
/// read-only thread; the flows Só Claude Code stay on the Claude Code.
void main() {
  late Directory tmp;
  late FakeCli cli;
  late List<FakeCodex> servers;
  late ProviderContainer c;
  late Workspace ws;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('promptorium-callers-');
    cli = FakeCli();
    servers = [];
    c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        claudeProcessStarterProvider.overrideWithValue(cli.start),
        runSettingsDirProvider.overrideWithValue('${tmp.path}/run'),
        codexProcessStarterProvider.overrideWithValue((
          exe,
          args, {
          workingDirectory,
          environment,
        }) async {
          final s = FakeCodex(threadId: 'th-${servers.length}');
          servers.add(s);
          return s;
        }),
      ],
    );
    await c.read(appSettingsProvider.notifier).load();
    await c
        .read(appSettingsProvider.notifier)
        .set(ProviderKind.planner.settingKey, 'codex');
    ws = await c.read(workspacesRepoProvider).add(path: tmp.path, name: 'w');
  });

  tearDown(() async {
    c.dispose();
    for (final s in servers) {
      await s.finish();
    }
    tmp.deleteSync(recursive: true);
  });

  /// Waits for the Codex turn, answers [answer] and checks the read-only
  /// thread and the schema sent.
  Future<Map<String, dynamic>> answerTurn(
    String answer, {
    bool schema = true,
  }) async {
    await until(
      () async =>
          servers.isNotEmpty &&
          servers.last.writtenJson.any((m) => m['method'] == 'turn/start'),
    );
    final s = servers.last;
    final thread = s.writtenJson.lastWhere(
      (m) => m['method'] == 'thread/start' || m['method'] == 'thread/resume',
    );
    expect(thread['params']['sandbox'], 'read-only');
    expect(thread['params']['approvalPolicy'], 'never');
    final turn = s.writtenJson.lastWhere((m) => m['method'] == 'turn/start');
    if (schema) {
      expect(codexSchemaProblems(turn['params']['outputSchema']), isEmpty);
    } else {
      expect(turn['params']['outputSchema'], isNull);
    }
    s.answer(answer);
    s.completeTurn();
    return turn['params'] as Map<String, dynamic>;
  }

  test('Dividir em specs', () async {
    final out = c.read(splitSpecsRunnerProvider)(ws, 'Divida');
    await answerTurn('### SPEC-001 · A', schema: false);
    expect(await out, '### SPEC-001 · A');
  });

  test('Verificar spec', () async {
    final out = c.read(verificationAgentProvider)(
      ws,
      'Spec SPEC-001:\n<spec>x</spec>',
      'codex',
      VerificationCancellation(),
    );
    await answerTurn(jsonEncode({'items': <Object>[]}));
    expect(await out, {'items': <Object>[]});
  });

  test('Stack própria (sem o Claude Code fixo)', () async {
    final out = c.read(customStackRunProvider)(cwd: tmp.path, prompt: 'Go');
    final stack = {
      'name': 'Go',
      'decisions': <Object>[],
      'claudeMd': '# Go',
      'commands': {
        for (final k in ['install', 'run', 'dev', 'test', 'lint', 'format'])
          k: '',
      },
      'scaffold': '',
    };
    await answerTurn(jsonEncode(stack));
    expect(structuredOutput(await out), stack);
    expect(cli.processes, isEmpty);
  });

  test('Perguntas e respostas da spec', () async {
    final out = c
        .read(specQuestionOptionsProvider)
        .generate(ws, 'Spec SPEC-001', const OpenQuestion(id: 'P1', text: '?'));
    await answerTurn(
      jsonEncode({
        'options': [
          {'title': 'A', 'consequence': 'mais simples'},
        ],
      }),
    );
    expect((await out).single.title, 'A');
  });

  test('Nova skill', () async {
    final out = c
        .read(skillWriterProvider)
        .write(workspace: ws, scope: AgentScope.project, request: 'lint');
    await answerTurn(
      jsonEncode({
        'name': 'lint',
        'description': 'Roda o lint.',
        'allowedTools': '',
        'body': '# Lint',
      }),
    );
    expect(await out, contains('lint'));
  });

  test('Projeto (planner)', () async {
    final done = c.read(projectPlannerProvider.notifier).sendVision(ws, 'App');
    await answerTurn(
      jsonEncode({
        'reply': 'Ok',
        'plan': {
          'name': 'App',
          'summary': 's',
          'audience': 'a',
          'mvp': <String>[],
          'outOfScope': <String>[],
          'openQuestions': <String>[],
        },
        'suggestions': <String>[],
      }),
    );
    await done;
    final row = await c.read(projectPlansRepoProvider).start(ws.id);
    expect(row.data, contains('"name":"App"'));
  });

  test(
    'checagem da VIBE: segue o provedor da conversa, perfil rápido',
    () async {
      final vibe = Spec(
        issueCommentPending: false,
        hasPlan: false,
        inTray: false,
        kind: SpecKind.vibe,
        id: 1,
        workspaceId: ws.id,
        code: 'VIBE-001',
        title: 'Botão',
        path: 'v.md',
        status: SpecStatus.review,
        stage: SpecStage.backlog,
        requirements: const [],
        dependsOn: const [],
        autoAdvance: false,
        reviewRounds: 0,
        gateResends: 0,
        rejectedHunks: 0,
        worktreePath: tmp.path,
      );
      final out = c.read(unrelatedRequestProvider)(
        vibe: vibe,
        changed: const [],
        accepted: const [],
        request: 'e o checkout',
        provider: 'codex',
      );
      await answerTurn(
        jsonEncode({'outro_assunto': true, 'confianca': 0.9, 'motivo': 'x'}),
      );
      expect((await out).unrelated, isTrue);
    },
  );

  test('Só Claude Code: o Protótipo de telas fica no Claude Code', () async {
    final out = c.read(prototypeAgentProvider)(
      cwd: tmp.path,
      options: prototypeOptions('docs/mockups/spec-001'),
      prompt: 'gere',
    );
    await until(() async => cli.processes.isNotEmpty);
    expect(servers, isEmpty);
    cli.last.emit(
      jsonEncode({
        'type': 'result',
        'subtype': 'success',
        'structured_output': {'telas': <Object>[], 'resposta': ''},
      }),
    );
    await out;
  });

  test('Só Claude Code: Executar spec fica no Claude Code até a SPEC-101; '
      'o revisor segue o projeto (SPEC-102)', () {
    final settings = {providerPreferenceKey(ws.id): 'codex'};
    expect(
      providerForKind(settings, ProviderKind.reviewer, workspaceId: ws.id),
      'codex',
    );
    expect(
      providerForKind(settings, ProviderKind.runSpec, workspaceId: ws.id),
      'claude',
    );
    expect(
      providerForKind(settings, ProviderKind.planner, workspaceId: ws.id),
      'codex',
    );
  });
}
