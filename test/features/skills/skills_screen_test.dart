import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/app_settings_repo.dart';
import 'package:promptorium/features/agents/agent_file.dart';
import 'package:promptorium/features/mcp/mcp_state.dart';
import 'package:promptorium/features/sessions/widgets/session_style.dart';
import 'package:promptorium/features/skills/skill_catalog.dart';
import 'package:promptorium/features/skills/skill_repository.dart';
import 'package:promptorium/features/skills/skills_screen.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import '../../ui/preferences_test.dart' show unmount;

final commit = SkillEntry(
  scope: AgentScope.project,
  dir: '/r/.claude/skills/commit-convencional',
  file: AgentFile.create(
    name: 'commit-convencional',
    description: 'Mensagens de commit no padrão Conventional Commits.',
    body: '# Commit\n',
  ).withValue('allowed-tools', 'Bash(git diff *)'),
  files: const ['SKILL.md', 'exemplos.md'],
  hash: 'h1',
  origin: SkillOrigin(
    repo: defaultCatalog.slug,
    path: 'skills/commit-convencional',
    commit: 'a1b2c3d',
    hash: 'h1',
    installedAt: DateTime(2026, 10, 12),
  ),
);

final resumo = SkillEntry(
  scope: AgentScope.global,
  dir: '/home/x/.claude/skills/resumo-pr',
  file: AgentFile.create(
    name: 'resumo-pr',
    description: 'Resume um branch em descrição de PR.',
    body: '# PR\n',
  ),
  files: const ['SKILL.md'],
  hash: 'h9',
);

CatalogSkill catalogSkill(String name, String hash) => CatalogSkill(
  name: name,
  description: 'Descrição de $name.',
  dir: '/nao-existe/$name',
  files: const ['SKILL.md'],
  hash: hash,
  commit: '9f8e7d1',
);

Future<ProviderContainer> pumpSkills(
  WidgetTester tester, {
  bool emptyCatalog = false,
  List<SkillEntry>? entries,
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = memoryDatabase();
  addTearDown(db.close);
  final c = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      skillEntriesProvider.overrideWith(
        (ref, path) async => entries ?? [commit, resumo],
      ),
      catalogSnapshotProvider.overrideWith(
        (ref, repo) async => CatalogSnapshot(
          repo: repo,
          cloned: true,
          empty: emptyCatalog,
          head: emptyCatalog ? null : '9f8e7d1',
          skills: emptyCatalog
              ? const []
              : [
                  catalogSkill('commit-convencional', 'h3'),
                  catalogSkill('escrever-testes', 'h4'),
                ],
          syncedAt: DateTime(2026, 10, 15, 14),
        ),
      ),
      mcpInventoryProvider.overrideWith(
        (ref, cwd) async => McpInventory(
          toolsByServer: const {},
          servers: const [],
          at: DateTime(2026),
          skills: const ['code-review', 'simplify', 'commit-convencional'],
        ),
      ),
    ],
  );
  final ws = await db
      .into(db.workspaces)
      .insertReturning(WorkspacesCompanion.insert(path: '/r', name: 'r'));
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
  await tester.pumpAndSettle();
  return c;
}

bool enabled(WidgetTester tester, String key) =>
    tester.widget<AmberButton>(find.byKey(ValueKey(key))).onTap != null;

void main() {
  testWidgets('Instaladas: groups, badges, plugin skills, update banner and '
      'the editor', (tester) async {
    final c = await pumpSkills(tester);
    expect(find.text('Instaladas · 2'), findsOneWidget);
    expect(find.text('Catálogo · 2'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('skill-item-project-commit-convencional')),
      findsOneWidget,
    );
    expect(find.text('atualizar'), findsOneWidget);
    expect(find.text('local'), findsOneWidget);
    // Plugins / built-in: listed once, installed names left out.
    expect(find.byKey(const ValueKey('skill-builtin-code-review')), findsOne);
    expect(
      find.byKey(const ValueKey('skill-builtin-commit-convencional')),
      findsNothing,
    );

    // First skill open: origin, update a1b2c3d → 9f8e7d1.
    expect(
      find.text('/r/.claude/skills/commit-convencional/SKILL.md'),
      findsOne,
    );
    expect(find.byKey(const ValueKey('skill-update-banner')), findsOneWidget);
    expect(
      find.text('Há uma versão nova no catálogo (a1b2c3d → 9f8e7d1).'),
      findsOne,
    );
    expect(find.text('Bash(git diff *)'), findsOneWidget);
    expect(enabled(tester, 'skill-save'), isFalse);

    await tester.enterText(
      find.byKey(const ValueKey('skill-description')),
      'Nova descrição.',
    );
    await tester.pump();
    expect(enabled(tester, 'skill-save'), isTrue);
    // Testing waits for the save.
    expect(
      tester
          .widget<SmallButton>(find.byKey(const ValueKey('skill-test')))
          .onTap,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('skill-item-global-resumo-pr')));
    await tester.pumpAndSettle();
    expect(find.text('Criada aqui (não veio de um catálogo).'), findsOneWidget);
    expect(find.byKey(const ValueKey('skill-update-banner')), findsNothing);
    expect(find.text('Copiar para o projeto'), findsOneWidget);

    // Filter.
    await tester.enterText(find.byKey(const ValueKey('skills-filter')), 'pr');
    await tester.pump();
    expect(
      find.byKey(const ValueKey('skill-item-project-commit-convencional')),
      findsNothing,
    );
    await unmount(tester, c);
  });

  testWidgets('Catálogo: cards with their state, details and Instalar', (
    tester,
  ) async {
    final c = await pumpSkills(tester);
    await tester.tap(find.byKey(const ValueKey('skills-tab-catalog')));
    await tester.pumpAndSettle();
    expect(find.text(defaultCatalog.slug), findsWidgets);
    expect(find.text('atualização'), findsOneWidget);
    expect(find.text('não instalada'), findsOneWidget);
    // First card selected: the installed copy can be updated.
    expect(find.text('Atualizar a cópia instalada'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('catalog-card-escrever-testes')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Instalar'), findsOneWidget);
    expect(find.byKey(const ValueKey('catalog-target-project')), findsOne);
    expect(
      tester
          .widget<AmberButton>(find.byKey(const ValueKey('catalog-install')))
          .onTap,
      isNotNull,
    );

    await tester.enterText(
      find.byKey(const ValueKey('catalog-search')),
      'nada-assim',
    );
    await tester.pump();
    expect(find.text('Nada encontrado'), findsOneWidget);
    await unmount(tester, c);
  });

  testWidgets('empty catalog: no skills yet, nothing to publish', (
    tester,
  ) async {
    final c = await pumpSkills(tester, emptyCatalog: true);
    // The catalog is read-only: no publish action on installed skills.
    expect(find.byKey(const ValueKey('skill-publish')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('skills-tab-catalog')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('catalog-empty')), findsOneWidget);
    await unmount(tester, c);
  });

  testWidgets('both tabs fit the minimum window (1100×700)', (tester) async {
    final c = await pumpSkills(tester, size: const Size(1100 - 56, 700 - 72));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('skills-tab-catalog')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await unmount(tester, c);
  });

  testWidgets('no skills: empty state; Nova skill validates the blank name', (
    tester,
  ) async {
    final c = await pumpSkills(tester, entries: const []);
    expect(find.byKey(const ValueKey('skills-empty')), findsOneWidget);
    await tester.tap(find.text('Nova skill'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('new-skill-dialog')), findsOneWidget);
    expect(find.text('Gerar rascunho'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('new-skill-mode-blank')));
    await tester.pump();
    expect(find.text('Criar'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('new-skill-create')));
    await tester.pumpAndSettle();
    expect(find.text('Informe o nome.'), findsOneWidget);
    await unmount(tester, c);
  });
}
