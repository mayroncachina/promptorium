import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/data/repos/specs_repo.dart';
import 'package:promptorium/features/board/autopilot.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/features/vibe/vibe_service.dart';
import 'package:promptorium/features/vibe/widgets/vibe_card.dart';
import 'package:promptorium/ui/theme/app_theme.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import '../prompt/prompt_test_utils.dart';
import '../sessions/session_test_utils.dart' show settle;

/// Quadro (SPEC-069 R9, R10, R11).
void main() {
  test('R9: "Executar tudo" and the Autopilot ignore the VIBEs', () async {
    final db = memoryDatabase();
    addTearDown(db.close);
    final ws = await addWorkspace(db, '/r');
    final repo = SpecsRepo(db);
    final spec = await repo.insert(
      workspaceId: ws.id,
      code: 'SPEC-001',
      title: 'Busca',
      path: 'specs/SPEC-001.md',
      status: SpecStatus.approved,
      requirements: const [(id: 'R1', text: 'x')],
    );
    await repo.insert(
      workspaceId: ws.id,
      code: 'VIBE-001',
      title: 'Botão',
      path: 'docs/vibe/VIBE-001.md',
      status: SpecStatus.approved,
      kind: SpecKind.vibe,
      stage: SpecStage.running,
    );
    await repo.insert(
      workspaceId: ws.id,
      code: 'VIBE-002',
      title: 'Fonte',
      path: 'docs/vibe/VIBE-002.md',
      status: SpecStatus.approved,
      kind: SpecKind.vibe,
    );
    final all = await repo.watchByWorkspace(ws.id).first;
    final plan = autopilotPlan(all, null, parallel: 1);
    expect(plan.start.map((s) => s.id), [spec.id]);
    expect(plan.wait, isEmpty);
    expect(plan.skip, isEmpty);
  });

  test('R11: parada after 7 days without a message', () {
    final now = DateTime(2026, 11, 13);
    expect(vibeStaleDays(now.subtract(const Duration(days: 6)), now), isNull);
    expect(vibeStaleDays(now.subtract(const Duration(days: 7)), now), 7);
    expect(vibeStaleDays(now.subtract(const Duration(days: 8)), now), 8);
  });

  group('R10: Descartar VIBE', () {
    late Directory tmp;
    late String repo;
    late AppDatabase db;
    late FakeAgentProvider provider;
    late ProviderContainer c;
    late Workspace ws;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('vibe-board-');
      repo = await createRepo(tmp);
      db = memoryDatabase();
      provider = FakeAgentProvider();
      c = ProviderContainer(
        overrides: [
          databaseOverride(db),
          ...fakeProviderOverrides(provider),
          gitServiceFactoryProvider.overrideWithValue(
            (root) => GitService(root, worktreesBase: '${tmp.path}/wt'),
          ),
        ],
      );
      c.listen(conversationManagerProvider, (_, _) {});
      ws = await addWorkspace(db, repo);
      await c.read(appSettingsProvider.notifier).load();
    });

    tearDown(() async {
      c.dispose();
      tmp.deleteSync(recursive: true);
    });

    test('removes the worktree, the branch and the conversation; the number '
        'does not come back', () async {
      final r = await c.read(vibeServiceProvider).start(ws, 'Testar fonte');
      provider.last.emit(resultLine());
      await settle();
      final spec = (await c.read(specsRepoProvider).getById(r.spec.id))!;
      await c.read(vibeServiceProvider).discard(spec.id);
      expect(Directory(spec.worktreePath!).existsSync(), isFalse);
      expect(await gitIn(repo, ['branch', '--list', spec.branch!]), isEmpty);
      expect(
        await c.read(conversationsRepoProvider).getById(r.conversationId),
        isNull,
      );
      expect(await c.read(specsRepoProvider).getById(spec.id), isNull);
      expect(
        await nextSpecCode(c.read(specsRepoProvider), ws, kind: SpecKind.vibe),
        'VIBE-002',
      );
      // The main checkout is untouched.
      expect(await gitIn(repo, ['status', '--porcelain']), isEmpty);
    });

    test('a merged VIBE cannot be discarded', () async {
      final r = await c.read(vibeServiceProvider).start(ws, 'Testar fonte');
      await c
          .read(specsRepoProvider)
          .update(
            r.spec.id,
            const SpecsCompanion(stage: Value(SpecStage.done)),
          );
      await expectLater(
        c.read(vibeServiceProvider).discard(r.spec.id),
        throwsA(isA<VibeException>()),
      );
      expect(await c.read(specsRepoProvider).getById(r.spec.id), isNotNull);
    });
  });

  testWidgets('R9, R11, R13: the card has the VIBE mark as text, the summary '
      'and the seal of a VIBE stopped for 8 days; the confirmation says what '
      'goes', (tester) async {
    final db = memoryDatabase();
    final ws = await addWorkspace(db, '/r');
    final now = DateTime(2026, 11, 13, 12);
    final spec = await SpecsRepo(db).insert(
      workspaceId: ws.id,
      code: 'VIBE-004',
      title: 'Testar outra fonte',
      path: 'docs/vibe/VIBE-004.md',
      status: SpecStatus.approved,
      kind: SpecKind.vibe,
      stage: SpecStage.running,
    );
    await SpecsRepo(db).update(
      spec.id,
      const SpecsCompanion(branch: Value('vibe/004-testar-outra-fonte')),
    );
    await db
        .into(db.conversations)
        .insert(
          ConversationsCompanion.insert(
            workspaceId: ws.id,
            title: 'Testar outra fonte',
            model: 'inherit',
            specId: Value(spec.id),
            updatedAt: Value(now.subtract(const Duration(days: 8))),
          ),
        );
    final c = ProviderContainer(overrides: [databaseOverride(db)]);
    addTearDown(c.dispose);
    final row = (await SpecsRepo(db).getById(spec.id))!;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: VibeCard(spec: row, now: now),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('VIBE'), findsOneWidget);
    expect(find.text('VIBE-004'), findsOneWidget);
    expect(find.text('Testar outra fonte'), findsOneWidget);
    expect(find.text('parada há 8 dias'), findsOneWidget);
    expect(find.text('última mensagem há 8 dias'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('board-menu-VIBE-004')));
    await tester.pumpAndSettle();
    expect(find.text('Descartar VIBE'), findsOneWidget);
    await tester.tap(find.text('Descartar VIBE'));
    await tester.pumpAndSettle();
    expect(find.text('Descartar a VIBE-004?'), findsOneWidget);
    final text = tester
        .widget<Text>(find.byKey(const ValueKey('vibe-discard-text')))
        .textSpan!
        .toPlainText();
    expect(
      text,
      'Apaga o worktree, a branch vibe/004-testar-outra-fonte e a conversa. '
      'O número VIBE-004 não é reutilizado. Não dá para desfazer.',
    );
    expect(find.textContaining('nunca foi para o Review'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(await SpecsRepo(db).getById(spec.id), isNotNull);
    await tester.pumpWidget(const SizedBox());
  });
}
