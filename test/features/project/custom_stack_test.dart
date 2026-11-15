import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/readonly_run.dart';
import 'package:promptorium/core/providers/agent_event.dart';
import 'package:promptorium/features/project/custom_stack.dart';
import 'package:promptorium/features/project/project_plan.dart';
import 'package:promptorium/features/project/project_planner.dart';
import 'package:promptorium/features/project/project_templates.dart';

/// The `result` event of a modal answer.
Result customResult(Map<String, Object?> output) => AgentEvent.fromJson(
  jsonDecode(
    jsonEncode({
      'type': 'result',
      'subtype': 'success',
      'is_error': false,
      'total_cost_usd': 0.02,
      'structured_output': output,
    }),
  ) as Map<String, dynamic>,
) as Result;

/// A Go · Fiber proposal ([name] changes on an adjustment).
Map<String, Object?> goFiber({
  String name = 'Go · Fiber',
  String migrations = 'GORM',
}) => {
  'name': name,
  'decisions': [
    {
      'area': 'Linguagem',
      'choice': 'Go 1.23',
      'why': 'Binário único.',
      'alternatives': <String>[],
    },
    {
      'area': 'Framework',
      'choice': 'Fiber v2',
      'why': 'Como você pediu.',
      'alternatives': ['chi'],
    },
    {
      'area': 'Migrations',
      'choice': migrations,
      'why': '',
      'alternatives': <String>[],
    },
  ],
  'claudeMd': '# Loja\n\n## Comandos\n- Testes: go test ./...\n',
  'commands': {
    'install': 'test ! -f go.mod || go mod download',
    'run': 'go run ./cmd/api',
    'dev': 'air',
    'test': 'go test ./...',
    'lint': 'golangci-lint run',
    'format': 'gofmt -w {arquivo}',
  },
  'scaffold': 'go mod init loja && go get github.com/gofiber/fiber/v2',
};

/// Records the calls and answers each with the next of [answers].
class FakeCustomRun {
  FakeCustomRun(this.answers);

  final List<Object> answers;
  final calls = <({String prompt, String? sessionId, String? resumeId})>[];
  Completer<void>? hold;

  Future<Result> call({
    required String cwd,
    required String prompt,
    String? sessionId,
    String? resumeId,
    Future<void>? cancelled,
  }) async {
    calls.add((prompt: prompt, sessionId: sessionId, resumeId: resumeId));
    if (hold case final h?) {
      await Future.any([
        h.future,
        if (cancelled != null)
          cancelled.then(
            (_) => throw const PlannerException('Verificação cancelada.'),
          ),
      ]);
    }
    final a = answers.removeAt(0);
    if (a is Exception) throw a;
    return customResult(a as Map<String, Object?>);
  }
}

void main() {
  test('the modal uses the Stack schema plus name and scaffold (R17)', () {
    final props = customStackSchema['properties'] as Map;
    expect(
      props.keys,
      containsAll(['name', 'decisions', 'claudeMd', 'commands', 'scaffold']),
    );
    expect(customStackSchema['required'], containsAll(['name', 'scaffold']));

    final s = parseCustomStackResult(customResult(goFiber()));
    expect(s.name, 'Go · Fiber');
    expect(s.decisions.map((d) => d.choice), ['Go 1.23', 'Fiber v2', 'GORM']);
    expect(s.commands.test, 'go test ./...');
    expect(s.scaffold, startsWith('go mod init'));
    expect(
      () => parseCustomStackResult(customResult({...goFiber(), 'name': ''})),
      throwsA(isA<PlannerException>()),
    );
  });

  test('propose, adjust in the same conversation, cancel and retry (R17, '
      'R19)', () async {
    final run = FakeCustomRun([
      goFiber(),
      goFiber(migrations: 'goose'),
      const PlannerException('O planner terminou com erro (error).'),
      goFiber(name: 'Go · chi'),
    ]);
    var ids = 0;
    final chat = CustomStackChat(
      run: run.call,
      newSessionId: () => 'sessao-${++ids}',
      cwd: () => '/tmp',
    );
    addTearDown(chat.dispose);

    await chat.propose('API em Go com Fiber e Postgres, testes com go test');
    expect(chat.proposal?.name, 'Go · Fiber');
    expect(chat.calls, 1);
    expect(run.calls.single.sessionId, 'sessao-1');
    expect(run.calls.single.prompt, contains('API em Go com Fiber'));

    await chat.adjust('migrations com goose, não com o GORM');
    expect(run.calls.last.resumeId, 'sessao-1');
    expect(run.calls.last.sessionId, isNull);
    expect(run.calls.last.prompt, startsWith('Ajuste pedido:'));
    expect(chat.proposal?.decisions.last.choice, 'goose');
    expect(chat.calls, 2);
    expect(chat.messages.map((m) => m.adjust), [false, true]);

    // An error stays in the modal, with "Tentar de novo".
    await chat.adjust('trocar o Fiber pelo chi');
    expect(chat.error, contains('erro'));
    expect(chat.proposal?.name, 'Go · Fiber'); // the last preview stays
    await chat.retry();
    expect(chat.error, isNull);
    expect(chat.proposal?.name, 'Go · chi');
    expect(chat.calls, 4);
    expect(chat.messages, hasLength(3));

    // Cancelar ends the call; nothing changes.
    run
      ..hold = Completer()
      ..answers.add(goFiber(name: 'nunca'));
    final f = chat.adjust('outra coisa');
    await Future<void>.delayed(Duration.zero);
    expect(chat.busy, isTrue);
    chat.cancel();
    await f;
    expect(chat.busy, isFalse);
    expect(chat.error, isNull);
    expect(chat.proposal?.name, 'Go · chi');
    expect(chat.messages, hasLength(3));

    // A command edited in the preview.
    chat.editCommand('dev', '');
    expect(chat.proposal?.commands.dev, '');
  });

  test('the chosen stack is a template: commands to the config.yml, pinned '
      'decisions, the CLAUDE.md base with the scaffold (R18)', () {
    final s = parseCustomStackResult(customResult(goFiber()));
    final t = ProjectTemplate.fromStack(s);
    expect(t.isCustom, isTrue);
    expect(t.label, 'Go · Fiber');
    expect(t.config.testCommand, 'go test ./...');
    expect(t.config.dev?.command, 'air');
    expect(t.config.worktree.prepare, 'test ! -f go.mod || go mod download');
    expect(t.decisions.every((d) => d.pinned), isTrue);
    expect(
      t.summary,
      'Go 1.23 · Fiber v2 · GORM · testes: go test ./... · '
      'CLAUDE.md base',
    );
    // The scaffold goes in the commands section.
    expect(
      t.claudeMd,
      contains('## Comandos\n- Esqueleto (scaffold): `go mod init loja'),
    );
    expect(isCustomClaudeMd(t.claudeMd!), isTrue);
    expect(isCustomClaudeMd('${t.claudeMd!}editado'), isFalse);

    final tmp = Directory.systemTemp.createTempSync('promptorium-custom-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File('${tmp.path}/CLAUDE.md').writeAsStringSync(t.claudeMd!);
    final base = templateClaudeMd(tmp.path);
    expect(base, startsWith('# Loja'));
    File('${tmp.path}/CLAUDE.md').writeAsStringSync('${t.claudeMd!}\nminha');
    expect(templateClaudeMd(tmp.path), isNull);

    // The roadmap planner gets the scaffold for the first Fundação spec.
    final prompt = roadmapPrompt(
      const VisionPlan(),
      StackPlan(decisions: t.decisions, scaffold: t.scaffold),
    );
    expect(prompt, contains('scaffold): go mod init loja'));
    expect(prompt, contains('primeira spec da Fundação'));
  });
}
