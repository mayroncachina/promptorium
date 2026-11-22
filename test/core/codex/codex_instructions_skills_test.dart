import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/codex/codex_provider.dart';
import 'package:promptorium/core/providers/agent_provider.dart';
import 'package:promptorium/core/providers/capabilities.dart';
import 'package:promptorium/core/providers/workspace_assets.dart';

import 'fake_codex.dart';

/// SPEC-104 on the adapter (R1, R2, R6) and on the short `skills/list`
/// query (R7–R9, R12), with the fake and the `skills.jsonl` recording of
/// the real Codex 0.170 (no turn).
void main() {
  const fixture = 'test/fixtures/codex/0.170/skills.jsonl';

  test('capabilities: the Codex reads CLAUDE.md and the extra skill roots, '
      'proved without a turn', () {
    const codex = ProviderCapabilities.codex;
    expect(codex.supports(ProviderCapability.instructionsFallback), isTrue);
    expect(codex.supports(ProviderCapability.skillsExtraRoots), isTrue);
    expect(
      ProviderCapabilities.claude.supports(
        ProviderCapability.instructionsFallback,
      ),
      isTrue,
    );
  });

  test('R1/R2: every run passes the CLAUDE.md override and keeps the '
      'instructionSources of thread/start as the proof', () async {
    final tmp = Directory.systemTemp.createTempSync('codex-instr-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final fake = FakeCodex()
      ..instructionSources = ['${tmp.path}/CLAUDE.md', '/fora/AGENTS.md'];
    late List<String> seen;
    final run =
        await CodexProvider(
              starter: (exe, args, {workingDirectory, environment}) async {
                seen = args;
                return fake;
              },
            ).start(
              AgentStartOptions(
                workingDirectory: tmp.path,
                mode: PromptMode.edit,
                environment: {'HOME': '${tmp.path}/home'},
              ),
            )
            as CodexRun;
    final events = <ClaudeEvent>[];
    run.events.listen(events.add);
    addTearDown(() async {
      await run.stop(timeout: const Duration(milliseconds: 50));
      await fake.finish();
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(seen, [
      'app-server',
      '-c',
      'project_doc_fallback_filenames=["CLAUDE.md"]',
    ]);
    expect(run.instructionSources, ['CLAUDE.md', '/fora/AGENTS.md']);
    final init = events.whereType<SystemInit>().single;
    expect(init.json['instruction_sources'], ['CLAUDE.md', '/fora/AGENTS.md']);
    // No skill folder: no extraRoots request, nothing written anywhere.
    expect(
      fake.writtenJson.any((m) => m['method'] == 'skills/extraRoots/set'),
      isFalse,
    );
    expect(tmp.listSync(), isEmpty);
  });

  test('R2: a server that does not report instructionSources leaves the '
      'proof empty (never "carregado")', () async {
    final fake = FakeCodex();
    final run =
        await CodexProvider(
              starter: (exe, args, {workingDirectory, environment}) async =>
                  fake,
            ).start(
              const AgentStartOptions(
                workingDirectory: '/w',
                mode: PromptMode.ask,
              ),
            )
            as CodexRun;
    run.events.listen((_) {});
    addTearDown(() async {
      await run.stop(timeout: const Duration(milliseconds: 50));
      await fake.finish();
    });
    expect(run.instructionSources, isNull);
  });

  test('R6: the Claude skill folders go to skills/extraRoots/set before the '
      'thread, without copy nor link', () async {
    final tmp = Directory.systemTemp.createTempSync('codex-roots-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final repo = '${tmp.path}/repo';
    final home = '${tmp.path}/home';
    Directory('$repo/.claude/skills/gerar-release').createSync(recursive: true);
    Directory('$home/.claude/skills/commit-pt').createSync(recursive: true);
    final before = tmp
        .listSync(recursive: true, followLinks: false)
        .map((e) => e.path)
        .toSet();
    final fake = FakeCodex();
    final run =
        await CodexProvider(
              starter: (exe, args, {workingDirectory, environment}) async =>
                  fake,
            ).start(
              AgentStartOptions(
                workingDirectory: repo,
                mode: PromptMode.edit,
                environment: {'HOME': home},
              ),
            )
            as CodexRun;
    run.events.listen((_) {});
    addTearDown(() async {
      await run.stop(timeout: const Duration(milliseconds: 50));
      await fake.finish();
    });
    final methods = [for (final m in fake.writtenJson) m['method']];
    final roots = fake.writtenJson.singleWhere(
      (m) => m['method'] == 'skills/extraRoots/set',
    )['params']['extraRoots'];
    expect(roots, ['$repo/.claude/skills', '$home/.claude/skills']);
    expect(
      methods.indexOf('skills/extraRoots/set'),
      lessThan(methods.indexOf('thread/start')),
    );
    expect(run.skillRootsApplied, isTrue);
    expect(
      tmp
          .listSync(recursive: true, followLinks: false)
          .map((e) => e.path)
          .toSet(),
      before,
    );
    expect(
      tmp.listSync(recursive: true, followLinks: false).whereType<Link>(),
      isEmpty,
    );
  });

  group('skills/list (recorded from Codex 0.170, no turn)', () {
    const repo = '<sonda>/repo';
    final roots = ['$repo/.claude/skills', '<sonda>/home/.claude/skills'];

    Future<(CodexSkillsInventory, FakeCodex)> read() async {
      late FakeCodex fake;
      final inv = await readCodexSkills(
        executable: 'codex',
        workspacePath: repo,
        roots: roots,
        starter: (exe, args, {workingDirectory, environment}) async {
          expect(args, ['app-server']);
          return fake = FakeCodex.replay(readCodexTranscript(fixture));
        },
      );
      return (inv, fake);
    }

    test('R6: a skill of .claude/skills is listed by the Codex through the '
        'extra root', () async {
      final (inv, fake) = await read();
      expect(fake.unmatched, isEmpty);
      final status = inv.statusOf('$repo/.claude/skills/gerar-release');
      expect(status.state, CodexSkillState.active);
      expect(status.detail, 'via pasta extra · ativa');
      expect(
        inv.statusOf('<sonda>/home/.claude/skills/commit-pt').visible,
        isTrue,
      );
    });

    test('R9: the errors land on their skill', () async {
      final (inv, _) = await read();
      final status = inv.statusOf('$repo/.claude/skills/sem-front');
      expect(status.state, CodexSkillState.error);
      expect(status.detail, contains('frontmatter'));
      expect(status.badge, 'Codex · erro');
    });

    test('R8: the Codex own skills (system, repo .agents/.codex) are apart '
        'from the Claude ones', () async {
      final (inv, _) = await read();
      final own = {for (final s in inv.own) s.name};
      expect(own, containsAll(['openai-docs', 'imagegen', 'nativa-agents']));
      expect(own, isNot(contains('gerar-release')));
      final docs = inv.own.firstWhere((s) => s.name == 'openai-docs');
      expect(docs.scope, 'system');
      expect(docs.origin, 'sistema · vem com o Codex');
    });

    test('R12: one App Server, only initialize + extraRoots + skills/list — '
        'no thread, no turn', () async {
      final (_, fake) = await read();
      final methods = [
        for (final m in fake.writtenJson)
          if (m['id'] != null) m['method'],
      ];
      expect(methods, ['initialize', 'skills/extraRoots/set', 'skills/list']);
    });
  });

  test('R9: fields the Codex ignores', () {
    expect(
      codexIgnoredFields(['name', 'description', 'allowed-tools', 'model']),
      ['allowed-tools', 'model'],
    );
  });

  test('statusOf: missing and disabled skills', () {
    final inv = CodexSkillsInventory.parse(
      {
        'data': [
          {
            'cwd': '/r',
            'skills': [
              {
                'name': 'off',
                'description': '',
                'path': '/r/.claude/skills/off/SKILL.md',
                'scope': 'user',
                'enabled': false,
              },
            ],
            'errors': [],
          },
        ],
      },
      extraRoots: ['/r/.claude/skills'],
    );
    expect(
      inv.statusOf('/r/.claude/skills/off').state,
      CodexSkillState.disabled,
    );
    expect(
      inv.statusOf('/r/.claude/skills/nada').state,
      CodexSkillState.missing,
    );
    expect(inv.own, isEmpty);
  });
}
