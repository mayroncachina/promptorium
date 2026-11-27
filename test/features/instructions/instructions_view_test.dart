import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/capabilities.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/core/providers/workspace_assets.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/app_settings_repo.dart';
import 'package:promptorium/features/instructions/instructions_view.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../helpers/test_db.dart';
import '../../ui/preferences_test.dart' show unmount;

/// SPEC-104 T3: Ferramentas → Instruções (R2, R3, R4, R5).
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('instructions-view-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  void write(String rel, String text) {
    final f = File('${tmp.path}/$rel');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(text);
  }

  const noFallback = ProviderCapabilities(
    providerId: 'codex',
    displayName: 'Codex',
    values: {},
  );

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    InstructionsProof? proof,
    ProviderAvailability codex = const ProviderAvailability(
      ProviderStatus.ready,
      'ok',
    ),
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = memoryDatabase();
    addTearDown(db.close);
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        providerAvailabilityProvider.overrideWith((ref, id) async => codex),
        instructionsProofProvider.overrideWith((ref, id) async => proof),
        instructionsInventoryProvider.overrideWith(
          (ref, root) => scanInstructions(root),
        ),
        ...overrides,
      ],
    );
    await tester.runAsync(() async {
      final ws = await db
          .into(db.workspaces)
          .insertReturning(
            WorkspacesCompanion.insert(path: tmp.path, name: 'vitrine'),
          );
      await AppSettingsRepo(db).setInt(AppSettingKeys.activeWorkspace, ws.id);
      await c.read(appSettingsProvider.notifier).load();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: InstructionsView()),
        ),
      ),
    );
    await waitFor(tester, find.byKey(const ValueKey('instructions-detail')));
    await settle(tester);
    addTearDown(() => unmount(tester, c));
    return c;
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  Finder inRow(String provider, String text) => find.descendant(
    of: key('instructions-row-$provider'),
    matching: find.text(text),
  );

  test('rows: "previsto" without a run, "carregado" only with the proof', () {
    final inv = InstructionsInventory(
      root: '/r',
      claude: InstructionFile(
        path: 'CLAUDE.md',
        size: 10,
        modified: DateTime(2026),
        lines: 1,
      ),
      claudeText: '# a\n',
    );
    final none = instructionsRows(inv, null, fallback: true);
    expect(none[1].state, 'previsto');
    expect(none[1].reads, 'CLAUDE.md via override');
    final proof = InstructionsProof(
      sources: const ['CLAUDE.md'],
      at: DateTime.now(),
      where: 'sessão “Corrigir cache”',
    );
    final loaded = instructionsRows(inv, proof, fallback: true);
    expect(loaded[1].state, startsWith('carregado na sessão de '));
    expect(loaded[1].tone, InstructionsTone.loaded);
    // A run that did not load it: the override stopped working (R3).
    final broken = InstructionsProof(
      sources: const [],
      at: DateTime.now(),
      where: 'sessão',
    );
    final rows = instructionsRows(inv, broken, fallback: true);
    expect(rows[1].state, 'não carregado');
    expect(codexReadsClaudeMd(inv, broken, fallback: true), isFalse);
  });

  testWidgets('R2/R5: without a Codex run the row says "previsto"; the '
      'source, one row per provider and the nested files show', (tester) async {
    write(
      'CLAUDE.md',
      '# vitrine\n- Rode `flutter analyze` antes de commitar.\n',
    );
    write('packages/api/CLAUDE.md', 'x\n');
    write('lib/ui/AGENTS.md', 'y\n');
    await pump(tester);
    expect(find.text('ARQUIVOS'), findsOneWidget);
    expect(key('instructions-file-CLAUDE.md'), findsOneWidget);
    expect(key('instructions-file-packages/api/CLAUDE.md'), findsOneWidget);
    expect(key('instructions-file-lib/ui/AGENTS.md'), findsOneWidget);
    expect(inRow('Claude Code', 'carregado'), findsOneWidget);
    expect(inRow('Codex', 'CLAUDE.md via override'), findsOneWidget);
    expect(inRow('Codex', 'previsto'), findsOneWidget);
    expect(inRow('Codex', 'nenhuma execução Codex ainda'), findsOneWidget);
    expect(find.textContaining('carregado na'), findsNothing);
    expect(key('instructions-mechanism'), findsOneWidget);
    expect(find.textContaining('flutter analyze'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('R2: with the instructionSources of a run the row says '
      '"carregado" and names the run', (tester) async {
    write('CLAUDE.md', '# a\n');
    final at = DateTime.now();
    await pump(
      tester,
      proof: InstructionsProof(
        sources: const ['CLAUDE.md'],
        at: at,
        where: 'sessão “Corrigir cache”',
      ),
    );
    final hm =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    expect(inRow('Codex', 'carregado na sessão de $hm'), findsOneWidget);
    expect(
      inRow(
        'Codex',
        'instructionSources da sessão “Corrigir cache” · hoje $hm',
      ),
      findsOneWidget,
    );
  });

  testWidgets('R5: with the Codex unavailable the row stays and says why', (
    tester,
  ) async {
    write('CLAUDE.md', '# a\n');
    await pump(
      tester,
      codex: const ProviderAvailability(
        ProviderStatus.incompatible,
        'versão 0.150 abaixo da mínima',
      ),
    );
    expect(key('instructions-row-Codex'), findsOneWidget);
    expect(inRow('Codex', 'indisponível'), findsOneWidget);
    expect(
      inRow('Codex', 'Codex incompatível: versão 0.150 abaixo da mínima'),
      findsOneWidget,
    );
  });

  testWidgets('R4: an AGENTS.md of the person: "duas fontes" on the Codex '
      'row and only the "Unificar" card, no write action', (tester) async {
    write('CLAUDE.md', '# a\n');
    write('AGENTS.md', '# meu\n');
    await pump(tester);
    expect(key('instructions-two-sources'), findsNothing);
    expect(key('instructions-unify-card'), findsOneWidget);
    expect(inRow('Codex', 'duas fontes'), findsOneWidget);
    expect(inRow('Codex', 'AGENTS.md (no lugar do CLAUDE.md)'), findsOneWidget);
    expect(key('instructions-open-both'), findsNothing);
    expect(key('instructions-update-agents'), findsNothing);
    expect(key('instructions-generate-agents'), findsNothing);
  });

  testWidgets('SPEC-113 R1: CLAUDE.md importing a person\'s AGENTS.md is the '
      'single source, never "duas fontes"', (tester) async {
    write('CLAUDE.md', '@AGENTS.md\n\n# só Claude\n');
    write('AGENTS.md', '# meu\n');
    await pump(tester);
    expect(key('instructions-single-source'), findsOneWidget);
    expect(key('instructions-two-sources'), findsNothing);
    expect(find.textContaining('Duas fontes'), findsNothing);
    expect(inRow('Codex', 'duas fontes'), findsNothing);
    expect(inRow('Codex', 'AGENTS.md (fonte única)'), findsOneWidget);
    expect(inRow('Codex', 'previsto'), findsOneWidget);
    expect(key('instructions-generate-agents'), findsNothing);
    expect(key('instructions-update-agents'), findsNothing);
  });

  test('SPEC-113 R1: single source is "carregado" only with the proof', () {
    final file = InstructionFile(
      path: 'AGENTS.md',
      size: 6,
      modified: DateTime(2026),
      lines: 1,
    );
    final inv = InstructionsInventory(
      root: '/r',
      claude: file,
      claudeText: '@AGENTS.md\n',
      agents: file,
      agentsText: '# meu\n',
    );
    expect(instructionsRows(inv, null, fallback: true)[1].state, 'previsto');
    final proof = InstructionsProof(
      sources: const ['AGENTS.md'],
      at: DateTime.now(),
      where: 'sessão',
    );
    final rows = instructionsRows(inv, proof, fallback: true);
    expect(rows[1].state, 'carregado');
    expect(rows[0].reads, 'CLAUDE.md + AGENTS.md (import)');
  });

  testWidgets('R4: a generated, stale AGENTS.md shows the diff before '
      '"Atualizar AGENTS.md" writes', (tester) async {
    write('CLAUDE.md', '# a\n- Testes só nas telas principais.\n');
    await tester.runAsync(() => writeGeneratedAgentsMd(tmp.path));
    write('CLAUDE.md', '# a\n- Testes de widget para toda tela nova.\n');
    await pump(tester);
    expect(inRow('Codex', 'desatualizado'), findsOneWidget);
    expect(key('instructions-diff'), findsOneWidget);
    expect(find.text('- Testes só nas telas principais.'), findsWidgets);
    expect(find.text('- Testes de widget para toda tela nova.'), findsWidgets);
    // Not written before the button.
    expect(
      agentsMdBody(File('${tmp.path}/AGENTS.md').readAsStringSync()),
      '# a\n- Testes só nas telas principais.\n',
    );
    await tester.ensureVisible(key('instructions-update-agents'));
    await tester.pump();
    await tester.tap(key('instructions-update-agents'));
    await waitFor(tester, key('instructions-fresh'));
    expect(
      agentsMdBody(File('${tmp.path}/AGENTS.md').readAsStringSync()),
      '# a\n- Testes de widget para toda tela nova.\n',
    );
    expect(key('instructions-fresh'), findsOneWidget);
  });

  testWidgets('R3: plano B offers "Gerar AGENTS.md" and the nested CLAUDE.md '
      'is "Só Claude Code"', (tester) async {
    write('CLAUDE.md', '# a\n');
    write('packages/api/CLAUDE.md', 'x\n');
    await pump(
      tester,
      overrides: [codexCapabilitiesProvider.overrideWithValue(noFallback)],
    );
    expect(inRow('Codex', 'nada (não lê o CLAUDE.md)'), findsOneWidget);
    expect(key('instructions-mechanism'), findsNothing);
    expect(find.text('Só Claude Code'), findsOneWidget);
    await tester.ensureVisible(key('instructions-generate-agents'));
    await tester.pump();
    await tester.tap(key('instructions-generate-agents'));
    await waitFor(tester, key('instructions-fresh'));
    final agents = File('${tmp.path}/AGENTS.md').readAsStringSync();
    expect(agentsMdMarker(agents), claudeMdHash('# a\n'));
    expect(File('${tmp.path}/packages/api/AGENTS.md').existsSync(), isFalse);
    expect(key('instructions-fresh'), findsOneWidget);
  });
}

/// Lets real IO run until [f] shows (up to 15 s).
Future<void> waitFor(WidgetTester tester, Finder f) async {
  final end = DateTime.now().add(const Duration(seconds: 15));
  while (f.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) fail('não apareceu: $f');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Lets real IO run (the scan, the write) between frames.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}
