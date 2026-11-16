import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/dev/dev_server.dart' show DevServerStatus;
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/activities/activity.dart';
import 'package:promptorium/features/project/project_planner.dart';
import 'package:promptorium/features/prompt/conversation_manager.dart';
import 'package:promptorium/features/repository/releases/release_dispatcher.dart';
import 'package:promptorium/features/review/ci_fixer.dart';
import 'package:promptorium/features/review/pr_babysitter.dart';
import 'package:promptorium/features/sessions/session_manager.dart';

Spec spec(
  int id,
  String code, {
  SpecStage stage = SpecStage.running,
  int steps = 3,
  SpecKind kind = SpecKind.spec,
}) => Spec(
  hasPlan: false,
  inTray: false,
  kind: kind,
  id: id,
  workspaceId: 1,
  code: code,
  title: 'Título $code',
  status: SpecStatus.approved,
  path: 'docs/specs/$code.md',
  stage: stage,
  requirements: [for (var i = 1; i <= steps; i++) (id: 'R$i', text: 't$i')],
  dependsOn: const [],
  autoAdvance: false,
  reviewRounds: 0,
  gateResends: 0,
  rejectedHunks: 0,
  issueCommentPending: false,
);

Session session(
  String id, {
  int? specId,
  String? steps,
  SessionStatus status = SessionStatus.running,
  DateTime? startedAt,
  DateTime? endedAt,
  String? prUrl,
}) => Session(
  provider: 'claude',
  id: id,
  workspaceId: 1,
  worktreePath: '/wt/$id',
  branch: 'spec/$id',
  model: 'opus',
  permissionMode: 'acceptEdits',
  status: status,
  specId: specId,
  steps: steps,
  startedAt: startedAt ?? DateTime(2026, 11, 15, 10),
  endedAt: endedAt,
  prUrl: prUrl,
  costUsd: 0,
  tokensIn: 0,
  tokensOut: 0,
);

SpecStep step(int specId, String id, StepStatus status, {String? sessionId}) =>
    SpecStep(
      specId: specId,
      step: id,
      status: status,
      sessionId: sessionId,
      gateAttempts: 0,
      userPicked: false,
      escalations: 0,
    );

LiveTool tool(String name, Map<String, dynamic> input, {bool done = false}) =>
    LiveTool(
      id: 'tu-$name',
      name: name,
      input: input,
      at: DateTime(2026, 11, 15, 10, 30),
      done: done,
    );

PendingApproval approval(
  String sessionId,
  String tool, {
  String input = '{}',
}) => PendingApproval(
  sessionId: sessionId,
  sessionTitle: 'Sessão',
  request:
      ClaudeEvent.parseLine(
            '{"type":"control_request","request_id":"r-$sessionId",'
            '"request":{"subtype":"can_use_tool","tool_name":"$tool",'
            '"input":$input}}',
          ).single
          as PermissionRequest,
  receivedAt: DateTime(2026, 11, 15, 10, 40),
);

final now = DateTime(2026, 11, 15, 11);

List<Activity> build(ActivityWorkspace ws, ActivityLive live) =>
    buildActivities([ws], live, now: now);

void main() {
  group('sources (R1, R2)', () {
    test('a running spec session follows its tool and its step', () {
      final s = spec(1, 'SPEC-075');
      final list = build(
        ActivityWorkspace(
          id: 1,
          name: 'promptorium',
          specs: [s],
          stepRows: [
            step(1, 'R1', StepStatus.done),
            step(1, 'R2', StepStatus.running, sessionId: 'a'),
          ],
          sessions: [session('a', specId: 1, steps: 'R2')],
        ),
        ActivityLive(
          sessions: SessionManagerState(
            live: {
              'a': LiveSession(
                busySince: DateTime(2026, 11, 15, 10, 20),
                tool: tool('Edit', {'file_path': '/wt/a/lib/x.dart'}),
                calls: 38,
                files: 7,
              ),
            },
          ),
        ),
      );
      final a = list.single;
      expect(a.kind, ActivityKind.spec);
      expect(a.column, ActivityColumn.running);
      expect(a.pose, ActivityPose.edit);
      expect(a.status, 'Editando · R2');
      expect(a.lastAction, 'Edit lib/x.dart');
      expect(a.calls, 38);
      expect(a.progress?.label, 'etapa 2 de 3');
      expect(a.action, ActivityAction.stop);
      expect(a.seed, specSeed(1, 'SPEC-075'));
      expect(a.tasks.map((t) => (t.id, t.done, t.current)), [
        ('R1', true, false),
        ('R2', false, true),
        ('R3', false, false),
      ]);
      expect(a.needsYou, isFalse);
    });

    test('the tool gives the pose: read, run, think between tools', () {
      expect(poseOfTool(tool('Grep', {})), ActivityPose.read);
      expect(poseOfTool(tool('Glob', {})), ActivityPose.read);
      expect(poseOfTool(tool('Write', {})), ActivityPose.edit);
      expect(poseOfTool(tool('Bash', {})), ActivityPose.run);
      expect(poseOfTool(tool('Bash', {}, done: true)), ActivityPose.think);
      expect(poseOfTool(null), ActivityPose.think);
      expect(
        poseLabel(
          ActivityPose.run,
          tool: tool('Bash', {'command': 'flutter test'}),
        ),
        'Rodando testes',
      );
    });

    test('an approval waits for you: wave, Responder, the request', () {
      final list = build(
        ActivityWorkspace(
          id: 1,
          name: 'w',
          specs: [spec(1, 'SPEC-073', stage: SpecStage.review)],
          sessions: [session('a', specId: 1, steps: 'R1')],
        ),
        ActivityLive(
          sessions: SessionManagerState(
            live: {
              'a': LiveSession(
                busySince: DateTime(2026, 11, 15, 10),
                approvals: [
                  approval('a', 'Bash', input: '{"command":"flutter test"}'),
                ],
              ),
            },
          ),
        ),
      );
      final a = list.single;
      expect(a.needsYou, isTrue);
      expect(a.pose, ActivityPose.wave);
      expect(a.column, ActivityColumn.review);
      expect(a.status, 'quer executar');
      expect(a.lastAction, 'Bash flutter test');
      expect(a.action, ActivityAction.respond);
    });

    test('an idle live session and a finished one are not activities', () {
      final list = build(
        ActivityWorkspace(
          id: 1,
          name: 'w',
          sessions: [
            session('idle'),
            session('done', status: SessionStatus.completed),
          ],
        ),
        const ActivityLive(
          sessions: SessionManagerState(live: {'idle': LiveSession()}),
        ),
      );
      expect(list, isEmpty);
    });

    test('a failed session of a spec is an error with Retomar; an old free '
        'one is history', () {
      final s = spec(1, 'SPEC-003');
      final list = build(
        ActivityWorkspace(
          id: 1,
          name: 'w',
          specs: [s],
          stepRows: [step(1, 'R1', StepStatus.needsInput, sessionId: 'a')],
          sessions: [
            session('a', specId: 1, steps: 'R1', status: SessionStatus.failed),
            session(
              'old',
              status: SessionStatus.failed,
              endedAt: DateTime(2026, 11, 10),
            ),
          ],
        ),
        const ActivityLive(),
      );
      final a = list.single;
      expect(a.error, isTrue);
      expect(a.needsYou, isTrue);
      expect(a.pose, ActivityPose.error);
      expect(a.action, ActivityAction.resume);
      expect(a.sessionId, 'a');
    });

    test('a step refused by the gate needs you without an error', () {
      final list = build(
        ActivityWorkspace(
          id: 1,
          name: 'w',
          specs: [spec(1, 'SPEC-004')],
          stepRows: [step(1, 'R2', StepStatus.needsInput)],
        ),
        const ActivityLive(),
      );
      expect(list.single.needsYou, isTrue);
      expect(list.single.error, isFalse);
      expect(list.single.pose, ActivityPose.wave);
    });

    test('gate, PR, CI fix: Review with their poses', () {
      final s = spec(1, 'SPEC-074', stage: SpecStage.review);
      final list = build(
        ActivityWorkspace(
          id: 1,
          name: 'w',
          specs: [s],
          sessions: [
            session(
              'a',
              specId: 1,
              status: SessionStatus.completed,
              prUrl: 'https://github.com/o/r/pull/246',
            ),
          ],
        ),
        ActivityLive(
          gates: const {1},
          watchedPrs: const {'a'},
          ci: {
            'a': CiFixState(
              phase: CiFixPhase.running,
              since: DateTime(2026, 11, 15, 10),
              round: 1,
            ),
          },
        ),
      );
      final byKind = {for (final a in list) a.kind: a};
      expect(byKind.keys, {
        ActivityKind.gate,
        ActivityKind.pr,
        ActivityKind.ciFix,
      });
      expect(byKind[ActivityKind.gate]!.pose, ActivityPose.gate);
      expect(byKind[ActivityKind.pr]!.pose, ActivityPose.watch);
      expect(byKind[ActivityKind.pr]!.title, '#246 · Acompanhar PR');
      expect(byKind[ActivityKind.pr]!.action, ActivityAction.now);
      expect(byKind[ActivityKind.ciFix]!.pose, ActivityPose.watch);
      for (final a in list) {
        expect(a.column, ActivityColumn.review);
        expect(a.seed, specSeed(1, 'SPEC-074'));
      }
    });

    test('a running CI fix turn is one row: the fix, not the session', () {
      final list = build(
        ActivityWorkspace(
          id: 1,
          name: 'w',
          specs: [spec(1, 'SPEC-073', stage: SpecStage.review)],
          sessions: [session('a', specId: 1)],
        ),
        ActivityLive(
          sessions: SessionManagerState(
            live: {'a': LiveSession(busySince: DateTime(2026, 11, 15, 10))},
          ),
          ci: {
            'a': CiFixState(
              phase: CiFixPhase.fixing,
              since: DateTime(2026, 11, 15, 10),
              round: 1,
            ),
          },
        ),
      );
      expect(list.single.kind, ActivityKind.ciFix);
      expect(list.single.pose, ActivityPose.fix);
    });

    test('a watched PR with failing checks needs you', () {
      final status = parsePrView(
        '{"state":"OPEN","mergeable":"MERGEABLE","reviewDecision":"",'
        '"comments":[],"reviews":[],"headRefOid":"abc",'
        '"statusCheckRollup":[{"name":"build","conclusion":"FAILURE",'
        '"status":"COMPLETED"}]}',
      );
      final list = build(
        ActivityWorkspace(
          id: 1,
          name: 'w',
          sessions: [session('a', status: SessionStatus.completed)],
        ),
        ActivityLive(
          watchedPrs: const {'a'},
          prs: {'a': PrWatch(status: status)},
        ),
      );
      expect(list.single.needsYou, isTrue);
      expect(list.single.status, 'CI falhou');
    });

    test('a VIBE with a plan ready: Ver plano; a busy Prompt thinks', () {
      final vibe = spec(5, 'VIBE-001', kind: SpecKind.vibe);
      Conversation conv(int id, {int? specId}) => Conversation(
        id: id,
        workspaceId: 1,
        title: 'Conversa $id',
        provider: 'claude',
        model: 'sonnet',
        createdAt: DateTime(2026, 11, 15, 9),
        mode: 'plan',
        tokensIn: 0,
        tokensOut: 0,
        costUsd: 0,
        messageCount: 0,
        specId: specId,
      );
      final list = build(
        ActivityWorkspace(
          id: 1,
          name: 'w',
          specs: [vibe],
          conversations: [conv(1, specId: 5), conv(2), conv(3)],
        ),
        ActivityLive(
          conversations: ConversationManagerState(
            live: {
              1: LiveConversation(
                busy: true,
                approvals: [approval('c1', 'ExitPlanMode')],
              ),
              2: const LiveConversation(busy: true),
              3: const LiveConversation(),
            },
          ),
        ),
      );
      expect(list, hasLength(2));
      final v = list.firstWhere((a) => a.kind == ActivityKind.vibe);
      expect(v.status, 'plano pronto');
      expect(v.action, ActivityAction.viewPlan);
      expect(v.needsYou, isTrue);
      final p = list.firstWhere((a) => a.kind == ActivityKind.prompt);
      expect(p.pose, ActivityPose.think);
      expect(p.seed, 'conv:2');
    });

    test('release and dev server: icons, not robots (R12); a finished '
        'release leaves', () {
      ReleaseRun run(ReleaseRunStatus st) => ReleaseRun(
        workspaceId: 1,
        repoPath: '/r',
        version: '0.19.0',
        tag: 'v0.19.0',
        branch: 'main',
        dispatchedAt: DateTime(2026, 11, 15, 10),
        workflowName: 'Release',
        status: st,
      );
      List<Activity> with_(ReleaseRunStatus st) => build(
        ActivityWorkspace(
          id: 1,
          name: 'w',
          release: run(st),
          devServers: [
            (
              worktree: '/r',
              status: DevServerStatus.running,
              port: 5173,
              command: 'npm run dev',
              startedAt: DateTime(2026, 11, 15, 9),
              lastLog: 'GET / 200',
            ),
          ],
        ),
        const ActivityLive(),
      );
      final running = with_(ReleaseRunStatus.running);
      expect(running.map((a) => a.kind), [
        ActivityKind.release,
        ActivityKind.dev,
      ]);
      expect(running.every((a) => !a.hasRobot), isTrue);
      expect(running.last.subtitle, 'Servidor · localhost:5173');
      expect(with_(ReleaseRunStatus.success).map((a) => a.kind), [
        ActivityKind.dev,
      ]);
      expect(with_(ReleaseRunStatus.failure).first.error, isTrue);
    });

    test('the planner thinks; the Autopilot queue sleeps in Backlog', () {
      final s = spec(9, 'SPEC-009', stage: SpecStage.backlog);
      final list = build(
        ActivityWorkspace(
          id: 1,
          name: 'w',
          planner: const PlannerActivity(busy: 'Propondo a stack…'),
          queue: [(spec: s, label: 'próxima do Autopilot')],
        ),
        const ActivityLive(),
      );
      final planner = list.firstWhere((a) => a.kind == ActivityKind.planner);
      expect(planner.pose, ActivityPose.think);
      expect(planner.status, 'Propondo a stack…');
      final q = list.firstWhere((a) => a.kind == ActivityKind.queued);
      expect(q.column, ActivityColumn.backlog);
      expect(q.pose, ActivityPose.sleep);
      expect(q.robotLabel, 'na fila');
      expect(q.seed, specSeed(1, 'SPEC-009'));
    });
  });

  group('tabs and order (R6, R17)', () {
    Activity a(
      String id,
      int ws, {
      ActivityColumn column = ActivityColumn.running,
      bool needsYou = false,
      bool error = false,
      DateTime? at,
    }) => Activity(
      id: id,
      workspaceId: ws,
      workspaceName: 'ws$ws',
      kind: ActivityKind.spec,
      column: column,
      pose: ActivityPose.think,
      title: id,
      subtitle: '',
      status: '',
      needsYou: needsYou,
      error: error,
      startedAt: at ?? DateTime(2026, 11, 15, 10),
    );

    test('groups with a request or an error go up; inside, needs you first, '
        'then running, review, backlog, oldest first', () {
      final all = [
        a('x1', 1),
        a('y-backlog', 2, column: ActivityColumn.backlog),
        a('y-review', 2, column: ActivityColumn.review),
        a('y-new', 2, at: DateTime(2026, 11, 15, 10, 30)),
        a('y-old', 2, at: DateTime(2026, 11, 15, 9)),
        a('y-ask', 2, column: ActivityColumn.review, needsYou: true),
        a('z-err', 3, needsYou: true, error: true),
      ];
      final groups = groupActivities(all, ActivityTab.all, order: [1, 2, 3]);
      expect(groups.map((g) => g.workspaceId), [2, 3, 1]);
      expect(groups.first.items.map((x) => x.id), [
        'y-ask',
        'y-old',
        'y-new',
        'y-review',
        'y-backlog',
      ]);
      expect(groups.first.needsYou, 1);
      final counts = activityTabCounts(all);
      expect(counts[ActivityTab.all], 7);
      expect(counts[ActivityTab.needsYou], 2);
      expect(counts[ActivityTab.backlog], 1);
      expect(counts[ActivityTab.review], 2);
      expect(counts[ActivityTab.running], 4);
      expect(
        groupActivities(all, ActivityTab.backlog).single.items.single.id,
        'y-backlog',
      );
      expect(flatActivities(all, ActivityTab.needsYou).map((x) => x.id), [
        'y-ask',
        'z-err',
      ]);
    });
  });
}
