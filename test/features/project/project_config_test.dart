import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/project/widgets/project_config_view.dart';
import 'package:promptorium/features/sessions/agent_names.dart';
import 'package:promptorium/ui/theme/app_theme.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/sessions_repo.dart';
import 'package:promptorium/data/repos/specs_repo.dart';
import 'package:promptorium/features/board/spec_runner.dart';
import 'package:promptorium/features/project/project_config.dart';
import 'package:promptorium/features/specs/spec_service.dart';

import '../../helpers/test_db.dart';

void main() {
  test('merge and self-hosted GitLab configuration round trips', () {
    const config = ProjectConfig(
      mergeMethod: 'squash',
      host: 'git.exemplo.com',
      hostType: 'gitlab',
      testCommand: 'flutter test',
    );
    final parsed = ProjectConfig.parse(config.toYaml());
    expect(parsed.mergeMethod, 'squash');
    expect(parsed.host, 'git.exemplo.com');
    expect(parsed.hostType, 'gitlab');
    expect(parsed.testCommand, 'flutter test');
  });

  test('without merge.metodo the default is merge (--no-ff) and it is not '
      'written', () {
    expect(ProjectConfig.parse('').mergeMethod, 'merge');
    expect(const ProjectConfig().toYaml(), isNot(contains('metodo')));
    expect(
      ProjectConfig.parse('merge:\n  metodo: rebase\n').mergeMethod,
      'rebase',
    );
  });

  test('validateSpecsDir', () {
    expect(ProjectConfig.validateSpecsDir('specs'), isNull);
    expect(ProjectConfig.validateSpecsDir('docs/specs'), isNull);
    for (final bad in [
      '',
      '../x',
      '/abs',
      'a/../b',
      '.git/x',
      '.promptorium',
      'com espaço',
      './a',
    ]) {
      expect(ProjectConfig.validateSpecsDir(bad), isNotNull, reason: bad);
    }
  });

  test('relativeDir: subfolder of the workspace only', () {
    expect(
      ProjectConfig.relativeDir('/r/app', '/r/app/docs/specs'),
      'docs/specs',
    );
    expect(ProjectConfig.relativeDir('/r/app/', '/r/app/docs/'), 'docs');
    expect(ProjectConfig.relativeDir('/r/app', '/r/app'), isNull);
    expect(ProjectConfig.relativeDir('/r/app', '/r/outro/docs'), isNull);
    expect(ProjectConfig.relativeDir('/r/app', '/r/application/x'), isNull);
  });

  test('round trip: only non-default values are written', () {
    expect(const ProjectConfig().isDefault, isTrue);
    const c = ProjectConfig(
      specsDir: 'docs/specs',
      testCommand: 'pytest -q && ruff check',
      baseBranch: 'develop',
      agent: 'implementer',
      subagents: [
        SpecSubagent(
          agent: 'spec-reviewer',
          when: SubagentWhen.specEnd,
          instruction: 'foco em testes',
        ),
      ],
    );
    final back = ProjectConfig.parse(c.toYaml());
    expect(back, c);
    expect(back.subagents.single.instruction, 'foco em testes');
    final onlyTests = ProjectConfig.parse(
      const ProjectConfig(testCommand: 'make test').toYaml(),
    );
    expect(onlyTests.specsDir, 'specs');
    expect(onlyTests.testCommand, 'make test');
    // Garbage falls back to the defaults.
    expect(ProjectConfig.parse('specs: ../fora'), const ProjectConfig());
    expect(ProjectConfig.parse(': : :'), const ProjectConfig());
  });

  test('round trip of the gate, hooks, worktree, reviewer and autopilot '
      'keys; invalid values fall back', () {
    const c = ProjectConfig(
      testCommand: 'flutter test',
      lintCommand: 'flutter analyze',
      buildCommand: 'flutter build linux',
      formatCommand: 'dart format {arquivo}',
      verification: VerificationConfig(
        attempts: 2,
        timeoutSeconds: 300,
        requireCleanTree: false,
      ),
      blockedCommands: ['git push --force*', 'rm -rf "x"'],
      worktree: WorktreeConfig(
        copy: ['.env', '.env.local'],
        prepare: 'flutter pub get',
        basePort: 4000,
      ),
      reviewer: ReviewerConfig(enabled: true, budgetUsd: 0.5, rounds: 3),
      autopilot: AutopilotConfig(parallel: 3, dailyBudgetUsd: 10),
    );
    final back = ProjectConfig.parse(c.toYaml());
    expect(back, c);
    expect(back.gate.attempts, 2);
    expect(back.gate.requireCommit, isTrue);
    expect(back.blockedCommands.last, 'rm -rf "x"');
    expect(back.worktree.copy, ['.env', '.env.local']);
    expect(back.reviewer.model, 'haiku');
    expect(back.autopilot.dailyBudgetUsd, 10);
    final odd = ProjectConfig.parse('''
verificacao:
  tentativas: muitas
  timeout: 0
  exigir-commit: nao
worktree:
  copiar: [../fora, /etc/passwd, .env]
  porta-base: -1
revisor: sim
autopilot:
  paralelo: 0
''');
    expect(odd.gate.attempts, 1);
    expect(odd.gate.timeoutSeconds, 600);
    expect(odd.gate.requireCommit, isFalse);
    expect(odd.worktree.copy, ['.env']);
    expect(odd.worktree.basePort, isNull);
    expect(odd.reviewer.enabled, isFalse);
    expect(odd.autopilot.parallel, isNull);
    // Only the specs folder differs: still not "default" for saving.
    expect(const ProjectConfig(specsDir: 'docs').isDefault, isFalse);
  });

  test('contar-testes (SPEC-023 R5): on by default, "nao" turns it off and '
      'toYaml keeps it', () {
    expect(const ProjectConfig().gate.countTests, isTrue);
    expect(
      ProjectConfig.parse('verificacao:\n  tentativas: 2\n').gate.countTests,
      isTrue,
    );
    final off = ProjectConfig.parse(
      'testes: flutter test\nverificacao:\n  contar-testes: nao\n',
    );
    expect(off.gate.countTests, isFalse);
    expect(off.gate.attempts, 1);
    expect(off.toYaml(), contains('  contar-testes: nao'));
    expect(ProjectConfig.parse(off.toYaml()), off);
    expect(
      const ProjectConfig(verification: VerificationConfig(attempts: 2))
          .toYaml(),
      isNot(contains('contar-testes')),
    );
  });

  test('save / load / remove when back to the defaults', () async {
    final tmp = Directory.systemTemp.createTempSync('promptorium-config-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    expect(ProjectConfig.loadSync(tmp.path).isDefault, isTrue);
    await ProjectConfig.save(
      tmp.path,
      const ProjectConfig(testCommand: 'npm test'),
    );
    expect(File('${tmp.path}/.promptorium/config.yml').existsSync(), isTrue);
    expect(ProjectConfig.loadSync(tmp.path).testCommand, 'npm test');
    await ProjectConfig.save(tmp.path, const ProjectConfig());
    expect(File('${tmp.path}/.promptorium/config.yml').existsSync(), isFalse);
  });

  test(
    'specs go to the configured folder; older ones stay reachable',
    () async {
      final tmp = Directory.systemTemp.createTempSync('promptorium-config-');
      final db = memoryDatabase();
      addTearDown(() async {
        await db.close();
        tmp.deleteSync(recursive: true);
      });
      final ws = await db
          .into(db.workspaces)
          .insertReturning(
            WorkspacesCompanion.insert(path: tmp.path, name: 'w'),
          );
      final service = SpecService(SpecsRepo(db), sessions: SessionsRepo(db));
      final first = await service.create(ws, title: 'Antiga');
      expect(first.path, startsWith('specs/SPEC-001'));
      await ProjectConfig.save(
        tmp.path,
        const ProjectConfig(specsDir: 'docs/specs'),
      );
      final second = await service.create(ws, title: 'Nova');
      expect(second.path, startsWith('docs/specs/SPEC-002'));
      expect(File('${tmp.path}/${second.path}').existsSync(), isTrue);
      // The old one is still readable and `sync` of the new folder keeps it.
      await service.sync(ws);
      expect(await service.read(ws, first), isNotNull);
      expect((await SpecsRepo(db).getByCode(ws.id, 'SPEC-001')), isNotNull);
    },
  );

  test('mergeSubagents adds the project defaults once', () {
    const own = [SpecSubagent(agent: 'a', when: SubagentWhen.specEnd)];
    const defaults = [
      SpecSubagent(agent: 'a', when: SubagentWhen.specEnd),
      SpecSubagent(agent: 'b', when: SubagentWhen.afterEach),
    ];
    expect(mergeSubagents(own, defaults).map((s) => s.agent), ['a', 'b']);
  });

  testWidgets('the form edits and saves .promptorium/config.yml', (
    tester,
  ) async {
    final tmp = Directory.systemTemp.createTempSync('promptorium-config-');
    final db = memoryDatabase();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final ws = (await tester.runAsync(
      () => db
          .into(db.workspaces)
          .insertReturning(
            WorkspacesCompanion.insert(path: tmp.path, name: 'meu-app'),
          ),
    ))!;
    String? picked;
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          agentListProvider.overrideWith((ref, path) async => const []),
          directoryPickerProvider.overrideWithValue(
            ({initialDirectory}) async =>
                picked ?? '${tmp.path}/docs/especificacoes',
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: ProjectConfigView(workspace: ws)),
        ),
      ),
    );
    expect(find.text('Configuração de meu-app'), findsOneWidget);

    // Folder chooser: a subfolder fills the field; one outside is refused.
    await tester.tap(find.byKey(const ValueKey('config-specs-pick')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('config-specs')))
          .controller!
          .text,
      'docs/especificacoes',
    );
    picked = '/outro/lugar';
    await tester.tap(find.byKey(const ValueKey('config-specs-pick')));
    await tester.pump();
    expect(find.byKey(const ValueKey('config-error')), findsOneWidget);
    picked = null;
    await tester.enterText(
      find.byKey(const ValueKey('config-specs')),
      'docs/specs',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('config-specs-warning')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('config-tests')),
      'make test',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('config-save')));
    await tester.tap(find.byKey(const ValueKey('config-save')));
    // Real file IO (several awaits): alternate real time and the fake clock
    // until it is saved and shown (the suite may run under load).
    for (var i = 0; i < 300; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (i >= 12 &&
          ProjectConfig.loadSync(tmp.path).specsDir == 'docs/specs' &&
          find
              .byKey(const ValueKey('config-specs-warning'))
              .evaluate()
              .isEmpty) {
        break;
      }
    }
    final saved = ProjectConfig.loadSync(tmp.path);
    expect(saved.specsDir, 'docs/specs');
    expect(saved.testCommand, 'make test');
    // Saved: the "specs already existing stay" warning is gone.
    expect(find.byKey(const ValueKey('config-specs-warning')), findsNothing);

    // Invalid folder: error, nothing written.
    await tester.enterText(
      find.byKey(const ValueKey('config-specs')),
      '../fora',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('config-save')));
    await tester.tap(find.byKey(const ValueKey('config-save')));
    await tester.pump();
    expect(find.byKey(const ValueKey('config-error')), findsOneWidget);
    expect(ProjectConfig.loadSync(tmp.path).specsDir, 'docs/specs');
  });
}
