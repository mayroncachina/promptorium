import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/core/providers/agent_provider.dart' show PromptMode;
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/review/review_service.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/specs/spec_service.dart';
import 'package:promptorium/features/vibe/vibe_service.dart';

import '../../core/git/git_test_utils.dart';
import '../../helpers/test_db.dart';
import '../prompt/prompt_test_utils.dart';
import '../sessions/session_test_utils.dart' show settle;

/// Começar e conversar (SPEC-069 R1, R4, R7).
void main() {
  late Directory tmp;
  late String repo;
  late AppDatabase db;
  late FakeAgentProvider provider;
  late ProviderContainer c;
  late Workspace ws;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('vibe-service-');
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

  VibeService service() => c.read(vibeServiceProvider);

  test('preview: the next VIBE number, its branch and the base', () async {
    final p = await service().preview(ws, 'Deixa o botão Comprar verde');
    expect(p.code, 'VIBE-001');
    expect(p.branch, startsWith('vibe/001-deixa-o-botao'));
    expect(p.base, 'main');
  });

  test('Começar VIBE: number reserved, worktree and branch created, card in '
      'Em execução and the agent in the worktree, never in the main '
      'checkout', () async {
    final r = await service().start(ws, 'Deixa o botão Comprar verde.');
    final spec = (await c.read(specsRepoProvider).getById(r.spec.id))!;
    expect(spec.code, 'VIBE-001');
    expect(spec.kind, SpecKind.vibe);
    expect(spec.stage, SpecStage.running);
    expect(spec.inTray, isFalse);
    expect(spec.branch, startsWith('vibe/001-'));
    expect(spec.baseBranch, 'main');
    final wt = spec.worktreePath!;
    expect(wt, isNot(repo));
    expect(Directory(wt).existsSync(), isTrue);
    expect(await gitIn(wt, ['branch', '--show-current']), contains('vibe/'));
    // The VIBE file is committed in the worktree, not in the checkout.
    expect(File('$wt/${spec.path}').existsSync(), isTrue);
    expect(File('$repo/${spec.path}').existsSync(), isFalse);
    expect(spec.path, startsWith('docs/vibe/VIBE-001-'));
    expect(await gitIn(wt, ['status', '--porcelain']), isEmpty);
    expect(await gitIn(repo, ['status', '--porcelain']), isEmpty);

    final run = provider.last;
    expect(run.options.workingDirectory, wt);
    expect(run.options.workingDirectory, isNot(repo));
    expect(run.options.mode, PromptMode.edit);
    expect(run.sent, ['Deixa o botão Comprar verde.']);
    final conv = await c
        .read(conversationsRepoProvider)
        .getById(r.conversationId);
    expect(conv!.specId, spec.id);

    // R3: the number is reserved; the next VIBE takes the following one.
    expect(
      await nextSpecCode(c.read(specsRepoProvider), ws, kind: SpecKind.vibe),
      'VIBE-002',
    );
    expect(await nextSpecCode(c.read(specsRepoProvider), ws), 'SPEC-001');
  });

  test('R4: the next requests stay in the same VIBE and worktree, also after '
      'the process restarts', () async {
    final r = await service().start(ws, 'Botão verde');
    final m = c.read(conversationManagerProvider.notifier);
    provider.last.emit(initLine(provider.last.options.sessionId!));
    provider.last.emit(resultLine());
    await settle();
    await m.stop(r.conversationId);
    await m.send(r.conversationId, 'Arredonda os cantos');
    expect(provider.runs, hasLength(2));
    expect(
      provider.last.options.workingDirectory,
      provider.runs.first.options.workingDirectory,
    );
    expect(provider.last.options.workingDirectory, isNot(repo));
  });

  test(
    'a VIBE without its worktree never falls back to the main checkout',
    () async {
      final r = await service().start(ws, 'Botão verde');
      final m = c.read(conversationManagerProvider.notifier);
      await m.stop(r.conversationId);
      final specs = c.read(specsRepoProvider);
      // The worktree is gone…
      await specs.update(
        r.spec.id,
        const SpecsCompanion(worktreePath: Value('/nao/existe')),
      );
      await expectLater(
        m.send(r.conversationId, 'mais um ajuste'),
        throwsA(isA<ConversationException>()),
      );
      // …or points at the checkout itself.
      await specs.update(r.spec.id, SpecsCompanion(worktreePath: Value(repo)));
      await expectLater(
        m.send(r.conversationId, 'mais um ajuste'),
        throwsA(isA<ConversationException>()),
      );
      expect(provider.runs, hasLength(1));
      expect(
        provider.runs.every((x) => x.options.workingDirectory != repo),
        isTrue,
      );
    },
  );

  test('R7: "Enviar para Review" runs the gate and moves the card; a request '
      'after that brings it back with "o Review recomeça"; the Review talks '
      'to the same conversation', () async {
    final r = await service().start(ws, 'Botão verde');
    final run = provider.last;
    run.emit(initLine(run.options.sessionId!));
    run.emit(resultLine());
    await settle();
    final spec = (await c.read(specsRepoProvider).getById(r.spec.id))!;
    // The agent's edit.
    File('${spec.worktreePath}/a.txt').writeAsStringSync('verde\n');

    final report = await service().sendToReview(spec.id);
    expect(report.ok, isTrue, reason: report.encode());
    var now = (await c.read(specsRepoProvider).getById(spec.id))!;
    expect(now.stage, SpecStage.review);
    expect(
      await gitIn(spec.worktreePath!, ['log', '-1', '--format=%s']),
      contains('VIBE-001 R1'),
    );
    final sessions = await c.read(sessionsRepoProvider).bySpec(spec.id);
    final review = sessions.single;
    expect(review.id, startsWith(vibeSessionPrefix));
    expect(review.worktreePath, spec.worktreePath);
    expect(review.status, SessionStatus.completed);

    // The Review's comments go to the conversation.
    await c
        .read(sessionManagerProvider.notifier)
        .send(review.id, 'Ajuste: verde mais escuro');
    expect(run.sent.last, 'Ajuste: verde mais escuro');
    now = (await c.read(specsRepoProvider).getById(spec.id))!;
    expect(now.stage, SpecStage.running);
    final notes =
        (await c.read(conversationsRepoProvider).events(r.conversationId))
            .map((e) => e.json)
            .join('\n');
    expect(notes, contains('o Review recomeça'));
    expect(notes, contains('Verificação aprovada'));
    expect(
      ReviewService.mergeGuard(
        branch: spec.branch!,
        base: 'main',
        worktreePath: spec.worktreePath!,
        workspacePath: repo,
        worktreesBase: '${tmp.path}/wt',
      ),
      isNull,
    );
  });

  test('a VIBE with nothing done does not pass the gate and stays in Em '
      'execução', () async {
    final r = await service().start(ws, 'Botão verde');
    provider.last.emit(resultLine());
    await settle();
    final report = await service().sendToReview(r.spec.id);
    expect(report.ok, isFalse);
    final now = (await c.read(specsRepoProvider).getById(r.spec.id))!;
    expect(now.stage, SpecStage.running);
  });
}
