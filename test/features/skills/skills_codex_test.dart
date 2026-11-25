import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/providers/capabilities.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/app_settings_repo.dart';
import 'package:promptorium/features/agents/agent_file.dart';
import 'package:promptorium/features/mcp/mcp_state.dart';
import 'package:promptorium/features/skills/skill_catalog.dart';
import 'package:promptorium/features/skills/skill_repository.dart';
import 'package:promptorium/features/sessions/widgets/session_style.dart';
import 'package:promptorium/features/skills/skills_screen.dart';
import 'package:promptorium/core/providers/workspace_assets.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../core/codex/fake_codex.dart';
import '../../helpers/test_db.dart';
import '../../ui/preferences_test.dart' show unmount;

/// SPEC-104 T4 on the Skills screen: badges per provider, the "Do Codex"
/// group, the errors of `skills/list`, "ignorado no Codex" (R7–R9), plano
/// B (R10) and one App Server per opening (R12). The `skills/list` answer
/// is the one recorded from the real Codex 0.170 (`skills.jsonl`).
void main() {
  const repo = '<sonda>/repo';
  const home = '<sonda>/home';

  /// The recorded `skills/list` after `skills/extraRoots/set`.
  final recorded = () {
    final t = readCodexTranscript('test/fixtures/codex/0.170/skills.jsonl');
    final lists = [
      for (final l in t)
        if (l.dir == 'send' && l.msg['method'] == 'skills/list') l.msg['id'],
    ];
    return t
            .firstWhere(
              (l) =>
                  l.dir == 'recv' &&
                  l.msg['method'] == null &&
                  l.msg['id'] == lists.last,
            )
            .msg['result']
        as Map<String, dynamic>;
  }();

  SkillEntry entry(
    String dir,
    String name, {
    AgentScope scope = AgentScope.project,
    String? tools,
  }) {
    var file = AgentFile.create(
      name: name,
      description: 'Descrição de $name.',
      body: '# $name\n',
    );
    if (tools != null) file = file.withValue('allowed-tools', tools);
    return SkillEntry(
      scope: scope,
      dir: dir,
      file: file,
      files: const ['SKILL.md'],
      hash: 'h-$name',
    );
  }

  final gerar = entry(
    '$repo/.claude/skills/gerar-release',
    'gerar-release',
    tools: 'Bash(git *), Read',
  );
  final semFront = entry('$repo/.claude/skills/sem-front', 'sem-front');
  final commitPt = entry(
    '$home/.claude/skills/commit-pt',
    'commit-pt',
    scope: AgentScope.global,
  );

  late List<int> builds;

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required String workspace,
    required List<SkillEntry> entries,
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    builds = [];
    final db = memoryDatabase();
    addTearDown(db.close);
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        skillEntriesProvider.overrideWith((ref, path) async => entries),
        catalogSnapshotProvider.overrideWith(
          (ref, r) async => CatalogSnapshot(
            repo: r,
            cloned: true,
            empty: true,
            head: null,
            skills: const [],
            syncedAt: DateTime(2026),
          ),
        ),
        mcpInventoryProvider.overrideWith(
          (ref, cwd) async => McpInventory(
            toolsByServer: const {},
            servers: const [],
            at: DateTime(2026),
            skills: const [],
          ),
        ),
        // Each build is one short App Server (proved below, R12): the
        // widget tests count builds and answer with the recorded list.
        codexSkillsProvider.overrideWith((ref, path) async {
          final reload = ref.watch(codexSkillsReloadProvider);
          builds.add(reload);
          return CodexSkillsReady(CodexSkillsInventory.parse(recorded));
        }),
        ...overrides,
      ],
    );
    final ws = await db
        .into(db.workspaces)
        .insertReturning(
          WorkspacesCompanion.insert(path: workspace, name: 'vitrine'),
        );
    await AppSettingsRepo(db).setInt(AppSettingKeys.activeWorkspace, ws.id);
    await c.read(appSettingsProvider.notifier).load();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: SkillsScreen()),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    addTearDown(() => unmount(tester, c));
    return c;
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  testWidgets('R7–R9: badges per provider, the "Do Codex" group, the error '
      'on its skill and "ignorado no Codex"', (tester) async {
    await pump(tester, workspace: repo, entries: [gerar, semFront, commitPt]);
    // R7: Claude + Codex badges, from skills/list.
    expect(
      find.descendant(
        of: key('skill-codex-project-gerar-release'),
        matching: find.text('Codex'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: key('skill-codex-global-commit-pt'),
        matching: find.text('Codex'),
      ),
      findsOneWidget,
    );
    expect(find.text('Claude'), findsNWidgets(3));
    // R9: the error of skills/list on the right skill.
    expect(
      find.descendant(
        of: key('skill-codex-project-sem-front'),
        matching: find.text('Codex · erro'),
      ),
      findsOneWidget,
    );
    expect(
      find.text('skills/list: missing YAML frontmatter delimited by ---'),
      findsOneWidget,
    );
    // R8: the Codex's own skills, read-only, without the Claude ones.
    expect(find.text('DO CODEX'), findsOneWidget);
    expect(key('skill-codex-own-openai-docs'), findsOneWidget);
    expect(key('skill-codex-own-nativa-agents'), findsOneWidget);
    expect(key('skill-codex-own-gerar-release'), findsNothing);
    expect(find.text('sistema · vem com o Codex'), findsWidgets);
    // The panel of the selected skill (gerar-release).
    expect(
      find.text('No Codex: via pasta extra · ativa · sem cópia'),
      findsOneWidget,
    );
    expect(key('skill-tools-codex-ignored'), findsOneWidget);
    expect(find.text('allowed-tools ignorado no Codex'), findsOneWidget);
    // R9: marked, but the save is not blocked.
    await tester.enterText(key('skill-tools'), 'Read');
    await tester.pump();
    expect(tester.widget<AmberButton>(key('skill-save')).onTap, isNotNull);
    // The error skill offers "Abrir SKILL.md".
    await tester.tap(key('skill-item-project-sem-front'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(key('skill-open-skillmd'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R12: typing in the filter never queries; "Atualizar" queries '
      'again (forceReload)', (tester) async {
    await pump(tester, workspace: repo, entries: [gerar, commitPt]);
    expect(builds, [0]);
    for (final ch in ['g', 'ge', 'ger']) {
      await tester.enterText(key('skills-filter'), ch);
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(builds, [0]);
    await tester.tap(key('skills-refresh'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(builds, [0, 1]);
  });

  test('R12: one query = one short App Server with initialize, extraRoots '
      'and skills/list only — no thread, no turn, no prompt; "Atualizar" '
      'passes forceReload', () async {
    final tmp = Directory.systemTemp.createTempSync('skills-r12-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    Directory('${tmp.path}/.claude/skills/x').createSync(recursive: true);
    final servers = <FakeCodex>[];
    final c = ProviderContainer(
      overrides: [
        codexProcessStarterProvider.overrideWithValue((
          exe,
          args, {
          workingDirectory,
          environment,
        }) async {
          expect(args, ['app-server']);
          final fake = FakeCodex()..skillsList = recorded;
          servers.add(fake);
          return fake;
        }),
      ],
    );
    addTearDown(c.dispose);
    final sub = c.listen(codexSkillsProvider(tmp.path), (_, _) {});
    addTearDown(sub.close);
    final first = await c.read(codexSkillsProvider(tmp.path).future);
    expect(first, isA<CodexSkillsReady>());
    // Reading again (another widget, a rebuild) reuses the answer.
    await c.read(codexSkillsProvider(tmp.path).future);
    expect(servers, hasLength(1));
    c.read(codexSkillsReloadProvider.notifier).bump();
    await c.read(codexSkillsProvider(tmp.path).future);
    expect(servers, hasLength(2));
    for (final s in servers) {
      expect(
        [
          for (final m in s.writtenJson)
            if (m['id'] != null) m['method'],
        ],
        ['initialize', 'skills/extraRoots/set', 'skills/list'],
      );
    }
    expect(
      servers.first.writtenJson.singleWhere(
        (m) => m['method'] == 'skills/extraRoots/set',
      )['params']['extraRoots'],
      contains('${tmp.path}/.claude/skills'),
    );
    expect(
      servers.last.writtenJson.singleWhere(
        (m) => m['method'] == 'skills/list',
      )['params']['forceReload'],
      isTrue,
    );
    expect(
      servers.first.writtenJson
          .singleWhere((m) => m['method'] == 'skills/list')['params']
          .containsKey('forceReload'),
      isFalse,
    );
  });

  testWidgets('R10: without extraRoots the skill is "Só Claude Code"; '
      '"Disponibilizar no Codex" links only after the confirmation, only in '
      'the repository', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('skills-plan-b-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final dir = '${tmp.path}/.claude/skills/gerar-release';
    Directory(dir).createSync(recursive: true);
    File('$dir/SKILL.md')
        .writeAsStringSync('---\nname: gerar-release\ndescription: x\n---\n');
    await pump(
      tester,
      workspace: tmp.path,
      entries: [entry(dir, 'gerar-release')],
      overrides: [
        codexCapabilitiesProvider.overrideWithValue(
          const ProviderCapabilities(
            providerId: 'codex',
            displayName: 'Codex',
            values: {},
          ),
        ),
      ],
    );
    expect(
      find.descendant(
        of: key('skill-codex-project-gerar-release'),
        matching: find.text('Só Claude Code'),
      ),
      findsOneWidget,
    );
    final link = Link('${tmp.path}/.agents/skills/gerar-release');
    // Cancel: nothing is created.
    await tester.tap(key('skill-expose-codex'));
    await tester.pumpAndSettle();
    expect(find.textContaining('aparece no git status'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(link.existsSync(), isFalse);
    // Confirm: the relative link inside the repository.
    await tester.tap(key('skill-expose-codex'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Criar o link'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(link.existsSync(), isTrue);
    expect(link.targetSync(), '../../.claude/skills/gerar-release');
    expect(Directory('${tmp.path}/.agents').listSync().length, 1);
  });
}
