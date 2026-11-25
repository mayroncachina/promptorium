import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_args.dart';
import 'package:promptorium/core/codex/codex_cli.dart';
import 'package:promptorium/core/providers/capabilities.dart';
import 'package:promptorium/core/providers/provider_availability.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/sessions/handoff/continue_controller.dart';
import 'package:promptorium/features/sessions/handoff/continue_link.dart';
import 'package:promptorium/features/sessions/session_composer_draft.dart';
import 'package:promptorium/features/sessions/session_manager.dart';
import 'package:promptorium/features/sessions/timeline.dart';
import 'package:promptorium/features/sessions/timeline_provider.dart';

import '../../../core/codex/fake_codex.dart';
import '../../../core/git/git_test_utils.dart';
import '../../../helpers/test_db.dart';
import '../session_test_utils.dart';

Session _session({
  String provider = 'claude',
  int? specId,
  String status = 'completed',
  String? agent,
  String path = '/wt/a',
}) => Session(
  id: 's1',
  workspaceId: 1,
  provider: provider,
  title: 'Parser de front-matter',
  worktreePath: path,
  branch: 'spec/parser-linhas',
  status: SessionStatus.values.byName(status),
  model: 'opus',
  costUsd: 0,
  tokensIn: 0,
  tokensOut: 0,
  startedAt: DateTime(2026, 11, 20, 11),
  specId: specId,
  agentName: agent,
);

const _ready = ProviderAvailability(ProviderStatus.ready, 'ok');
const _missing = ProviderAvailability(ProviderStatus.missing, 'x');
const _login = ProviderAvailability(ProviderStatus.loginRequired, 'x');

void main() {
  group('R1 · availability', () {
    ContinueAvailability of(
      Session s, {
      bool busy = false,
      int approvals = 0,
      ProviderAvailability? target = _ready,
      ProviderFlows flows = ProviderFlows.defaults,
    }) => continueAvailability(
      session: s,
      busy: busy,
      approvals: approvals,
      origin: _ready,
      target: target,
      flows: flows,
      workspacePath: '/repo',
    );

    test('ready with both providers and the target on in Sessões', () {
      final a = of(_session());
      expect(a.visible, isTrue);
      expect(a.enabled, isTrue);
      expect(continueLabel(a.target!), 'Continuar no Codex');
      expect(
        continueLabel(of(_session(provider: 'codex')).target!),
        'Continuar no Claude',
      );
    });

    test('disabled while it works or waits for an approval', () {
      expect(of(_session(), busy: true).reason, ContinueReasons.busy);
      expect(of(_session(), approvals: 1).reason, ContinueReasons.busy);
      expect(
        ContinueReasons.busy,
        'Espere o turno acabar ou pare a sessão',
      );
    });

    test('disabled when the target is off in Sessões or not logged in', () {
      expect(
        of(_session(), flows: ProviderFlows.defaults.turnOff('codex')).reason,
        'Codex não está ligado nas Sessões',
      );
      expect(of(_session(), target: _login).reason, ContinueReasons.targetOff('codex'));
    });

    test('hidden without the other provider installed and in step sessions '
        '(P4)', () {
      expect(of(_session(), target: _missing).visible, isFalse);
      expect(of(_session(), target: null).visible, isFalse);
      expect(of(_session(specId: 3)).visible, isFalse);
      expect(of(_session(provider: 'gemini')).visible, isFalse);
      expect(of(_session(status: 'merged')).visible, isFalse);
    });
  });

  group('R3 · conversion', () {
    test('decision 3: Perguntar stays read-only, Editar writes with '
        'confirmation, YOLO only in a worktree', () {
      expect(
        convertAccess('plan', target: 'codex', worktree: true),
        ClaudePermissionMode.plan,
      );
      expect(
        convertAccess('acceptEdits', target: 'codex', worktree: true),
        ClaudePermissionMode.acceptEdits,
      );
      expect(
        convertAccess('bypassPermissions', target: 'codex', worktree: true),
        ClaudePermissionMode.skipPermissions,
      );
      expect(
        convertAccess('bypassPermissions', target: 'claude', worktree: false),
        ClaudePermissionMode.acceptEdits,
      );
      // Claude-only modes become Editar.
      expect(
        convertAccess('auto', target: 'codex', worktree: true),
        ClaudePermissionMode.acceptEdits,
      );
      // Decision 15: without the sandbox, full access only in a worktree.
      expect(
        convertAccess(
          'acceptEdits',
          target: 'codex',
          worktree: true,
          noSandbox: true,
        ),
        ClaudePermissionMode.skipPermissions,
      );
      expect(
        convertAccess(
          'acceptEdits',
          target: 'codex',
          worktree: false,
          noSandbox: true,
        ),
        isNull,
      );
      expect(
        accessWords(ClaudePermissionMode.acceptEdits),
        'Editar · escreve com confirmação',
      );
    });

    test('title, what stays behind and the first message', () {
      expect(
        continuedTitle('Parser de front-matter', 'codex'),
        'Parser de front-matter (Codex)',
      );
      expect(
        continuedTitle('Parser de front-matter (Codex)', 'claude'),
        'Parser de front-matter (Claude)',
      );
      final behind = leftBehind(_session(agent: 'revisor'), budgetUsd: 2);
      expect(behind.map((b) => b.kind), ['agente', 'orçamento']);
      expect(behind.first.value, 'revisor');
      expect(behind.every((b) => b.tag == 'Só Claude Code'), isTrue);
      expect(leftBehind(_session(provider: 'codex', agent: 'x')), isEmpty);
      expect(
        continueMessage(
          originTitle: 'Parser',
          originProvider: 'claude',
          path: ContinuePath.summary,
          summary: 'RESUMO',
        ),
        'RESUMO',
      );
    });
  });

  group('R3, R8, R9, R11, P1 · the controller', () {
    late Directory tmp;
    late String root;
    late List<FakeCodex> servers;
    late FakeCli cli;
    late ProviderContainer c;
    late Workspace ws;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('continue-099-');
      root = await createRepo(tmp);
      servers = [];
      cli = FakeCli();
      c = sessionContainer([
        ...sessionOverrides(
          db: memoryDatabase(),
          cli: cli,
          notifier: FakeNotifier(),
          worktreesBase: '${tmp.path}/wt',
        ),
        providerAvailabilityProvider.overrideWith((ref, id) async => _ready),
        codexProcessStarterProvider.overrideWithValue((
          exe,
          args, {
          workingDirectory,
          environment,
        }) async {
          final fake = FakeCodex(threadId: 'thread-${servers.length}');
          servers.add(fake);
          return fake;
        }),
      ]);
      await c.read(appSettingsProvider.notifier).load();
      ws = await c.read(workspacesRepoProvider).add(path: root, name: 'r');
    });

    tearDown(() async {
      await c.read(sessionManagerProvider.notifier).shutdown();
      c.dispose();
      tmp.deleteSync(recursive: true);
    });

    Future<ContinuationLinks> linksOf() async {
      final rows = await c
          .read(sessionsRepoProvider)
          .watchEventsOfType(ws.id, AppEventTypes.handoff)
          .first;
      return ContinuationLinks({
        for (final e in rows.entries)
          e.key: ContinuationRecord.decode(e.value)!,
      });
    }

    Future<Session> claudeSession() async {
      final id = await c
          .read(sessionManagerProvider.notifier)
          .create(
            NewSessionRequest(
              workspace: ws,
              title: 'Parser de front-matter',
              prompt: 'troque o parser',
              provider: 'claude',
              permissionMode: ClaudePermissionMode.acceptEdits,
            ),
          );
      await settle();
      cli.last.emit(fixtureLines().last); // result: idle
      await settle();
      return (await c.read(sessionsRepoProvider).getById(id))!;
    }

    test('the new session opens in the same worktree and branch, without '
        '`git worktree add` and without stash, idle with the message in its '
        'field; the origin is "Concluída" and both are linked', () async {
      final o = await claudeSession();
      File('${o.worktreePath}/novo.txt').writeAsStringSync('x');
      final before = await gitIn(root, ['worktree', 'list']);
      final controller = c.read(continueControllerProvider);
      expect(await controller.uncommitted(o.worktreePath), ['novo.txt']);
      final id = await controller.start(
        ContinueRequest(
          origin: o,
          target: 'codex',
          title: continuedTitle(o.title!, 'codex'),
          model: 'inherit',
          effort: 'default',
          mode: convertAccess(
            o.permissionMode,
            target: 'codex',
            worktree: true,
          )!,
          path: ContinuePath.summary,
          message: 'Continuação da sessão "Parser de front-matter".',
        ),
      );
      await settle();
      final n = (await c.read(sessionsRepoProvider).getById(id))!;
      expect(n.provider, 'codex');
      expect(n.title, 'Parser de front-matter (Codex)');
      expect(n.worktreePath, o.worktreePath);
      expect(n.branch, o.branch);
      expect(n.baseBranch, o.baseBranch);
      expect(n.parentSessionId, o.id);
      expect(n.permissionMode, 'acceptEdits');
      // No new worktree, no stash: the file is still there, uncommitted.
      expect(await gitIn(root, ['worktree', 'list']), before);
      expect(await gitIn(root, ['stash', 'list']), isEmpty);
      expect(File('${o.worktreePath}/novo.txt').existsSync(), isTrue);
      // P1: idle, nothing sent; the message waits in the field.
      final m = c.read(sessionManagerProvider);
      expect(m.isAlive(id), isTrue);
      expect(n.status, SessionStatus.completed);
      expect(
        servers.single.writtenJson.where((j) => j['method'] == 'turn/start'),
        isEmpty,
      );
      expect(
        c.read(sessionComposerDraftProvider)[id],
        'Continuação da sessão "Parser de front-matter".',
      );
      // The origin ended cleanly and is "Concluída".
      final origin = (await c.read(sessionsRepoProvider).getById(o.id))!;
      expect(m.isAlive(o.id), isFalse);
      expect(origin.status, SessionStatus.completed);
      // R9: the link both ways.
      final links = await linksOf();
      expect(links.of(id)?.fromId, o.id);
      expect(links.of(id)?.path, ContinuePath.summary);
      expect(links.continuedInto(o.id), id);
      expect(links.newestOfChain(o.id), id);
      // R8: the note at the top of the timeline.
      final items = c.read(sessionTimelineProvider(id)).timeline.items;
      final first = items.whereType<HandoffItem>().first;
      expect(first.text, startsWith('Continuada de "Parser de front-matter" · '
          'Claude Code · '));
      expect(first.text, endsWith('· mesmo worktree'));
      // R11: the journal.
      final journal = await c
          .read(activityEventsRepoProvider)
          .since(DateTime(2000));
      expect(
        journal.map((e) => '${e.title} · ${e.detail}'),
        contains(
          'Parser de front-matter · Trabalho passado do Claude Code para o '
          'Codex',
        ),
      );
      // The first message goes when the person sends it.
      await c.read(sessionManagerProvider.notifier).send(id, 'vai');
      await settle();
      expect(
        servers.single.writtenJson.where((j) => j['method'] == 'turn/start'),
        hasLength(1),
      );
    });

    test('R9: deleting one session keeps the other; the link goes away', () async {
      final o = await claudeSession();
      final id = await c
          .read(continueControllerProvider)
          .start(
            ContinueRequest(
              origin: o,
              target: 'codex',
              title: 'X (Codex)',
              model: 'inherit',
              effort: null,
              mode: ClaudePermissionMode.acceptEdits,
              path: ContinuePath.summary,
              message: 'm',
            ),
          );
      await settle();
      await c.read(sessionManagerProvider.notifier).shutdown();
      await c.read(sessionsRepoProvider).delete(o.id);
      final n = await c.read(sessionsRepoProvider).getById(id);
      expect(n, isNotNull);
      expect(n!.parentSessionId, isNull);
    });

    test('P1: a continued Claude session whose message was never sent starts '
        'again as new (no --resume of a session the CLI never saw)', () async {
      final ctrl = c.read(continueControllerProvider);
      final o = await claudeSession();
      final codexId = await ctrl.start(
        ContinueRequest(
          origin: o,
          target: 'codex',
          title: 'X (Codex)',
          model: 'inherit',
          effort: null,
          mode: ClaudePermissionMode.acceptEdits,
          path: ContinuePath.summary,
          message: 'm',
        ),
      );
      await settle();
      final codex = (await c.read(sessionsRepoProvider).getById(codexId))!;
      // R10: and back to Claude.
      final back = await ctrl.start(
        ContinueRequest(
          origin: codex,
          target: 'claude',
          title: continuedTitle(codex.title!, 'claude'),
          model: 'inherit',
          effort: null,
          mode: ClaudePermissionMode.acceptEdits,
          path: ContinuePath.summary,
          message: 'volta',
        ),
      );
      await settle();
      expect(cli.args.last, containsAllInOrder(['--session-id', back]));
      await c.read(sessionManagerProvider.notifier).release(back);
      await c.read(sessionManagerProvider.notifier).send(back, 'volta');
      await settle();
      expect(cli.args.last, isNot(contains('--resume')));
      expect(cli.args.last, containsAllInOrder(['--session-id', back]));
      final links = await linksOf();
      // R9: a chain shows only the immediate link of each side.
      expect(links.continuedInto(codexId), back);
      expect(links.of(codexId)?.fromId, o.id);
      expect(links.newestOfChain(o.id), back);
    });
  });
}
