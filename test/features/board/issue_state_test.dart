import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/gh_cli.dart' show cliRunnerProvider;
import 'package:promptorium/core/git/gh_issues.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/board_screen.dart';
import 'package:promptorium/features/issues/issue_availability.dart';
import 'package:promptorium/features/issues/issue_state_watcher.dart';

import '../../core/git/fake_issues.dart';
import '../../helpers/test_db.dart';
import 'canvas_fixture.dart';

/// The state of the linked issues (SPEC-074 R9): the badge changes, the
/// spec never moves.
void main() {
  Spec spec({IssueState? state, String? by, DateTime? at}) => Spec(
    id: 1,
    workspaceId: 1,
    code: 'SPEC-019',
    title: 'Tema escuro',
    path: 'x',
    status: SpecStatus.draft,
    stage: SpecStage.backlog,
    requirements: const [],
    dependsOn: const [],
    hasPlan: false,
    autoAdvance: false,
    reviewRounds: 0,
    gateResends: 0,
    rejectedHunks: 0,
    inTray: true,
    kind: SpecKind.spec,
    issueCommentPending: false,
    issueNumber: 198,
    issueState: state,
    issueClosedBy: by,
    issueClosedAt: at,
  );

  test('closed, reopened, not found; nothing when it is the same', () {
    final at = DateTime.utc(2026, 11, 14);
    final closed = issueStateChange(
      spec(),
      GhIssueState(
        number: 198,
        found: true,
        closed: true,
        closedAt: at,
        closedBy: 'à mão',
      ),
    )!;
    expect(closed.issueState.value, IssueState.closed);
    expect(closed.issueClosedBy.value, 'à mão');
    // Only the issue columns: status, stage and the Bandeja stay.
    expect(closed.status.present, isFalse);
    expect(closed.stage.present, isFalse);
    expect(closed.inTray.present, isFalse);
    final reopened = issueStateChange(
      spec(state: IssueState.closed, by: 'à mão', at: at),
      const GhIssueState(number: 198, found: true),
    )!;
    expect(reopened.issueState.value, IssueState.open);
    expect(reopened.issueClosedBy.value, isNull);
    expect(
      issueStateChange(
        spec(),
        const GhIssueState(number: 198, found: false),
      )!.issueState.value,
      IssueState.notFound,
    );
    expect(
      issueStateChange(
        spec(state: IssueState.open),
        const GhIssueState(number: 198, found: true),
      ),
      isNull,
    );
  });

  test('one query for the workspace: a closed issue changes the badge and '
      'does not move the spec; reopened goes back; 404 is "não '
      'encontrada"', () async {
    final db = memoryDatabase();
    final gh = FakeIssuesGh()
      ..add(188, 'Login', state: 'closed', closedAt: '2026-11-14T12:00:00Z')
      ..add(198, 'Tema', state: 'closed', closedAt: '2026-11-13T12:00:00Z')
      ..add(226, 'Pix');
    gh.closedByPr[188] = 205;
    final c = ProviderContainer(
      overrides: [
        databaseOverride(db),
        cliRunnerProvider.overrideWithValue(gh.call),
        issueAvailabilityProvider.overrideWith(
          (ref, _) async =>
              const IssueAvailability.ok(repo: 'ana-souza/loja-da-ana'),
        ),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    final ws = await c
        .read(workspacesRepoProvider)
        .add(path: '/tmp/nao-existe-074', name: 'loja');
    final repo = c.read(specsRepoProvider);
    Future<Spec> add(
      String code,
      int? issue, {
      SpecStage stage = SpecStage.backlog,
      bool tray = false,
    }) => repo.insert(
      workspaceId: ws.id,
      code: code,
      title: code,
      path: 'specs/$code.md',
      status: SpecStatus.approved,
      stage: stage,
      inTray: tray,
      issueNumber: issue,
    );
    final login = await add('SPEC-015', 188, stage: SpecStage.done);
    final tema = await add('SPEC-019', 198, tray: true);
    final pix = await add('SPEC-023', 226, stage: SpecStage.running);
    final gone = await add('SPEC-030', 404);
    await add('SPEC-031', null);

    final watcher = c.read(issueStateWatcherProvider);
    expect(await watcher.check(ws.id), 4);
    expect(
      gh.ghCalls.where((a) => a.length > 1 && a[1] == 'graphql'),
      hasLength(1),
    );
    Future<Spec> row(Spec s) async => (await repo.getById(s.id))!;
    final l = await row(login);
    expect(l.issueState, IssueState.closed);
    expect(l.issueClosedBy, 'PR #205');
    expect(l.stage, SpecStage.done);
    final t = await row(tema);
    expect(t.issueState, IssueState.closed);
    expect(t.issueClosedBy, 'à mão');
    expect(
      (t.stage, t.status, t.inTray),
      (SpecStage.backlog, SpecStatus.approved, true),
    );
    expect((await row(pix)).issueState, IssueState.open);
    expect((await row(pix)).stage, SpecStage.running);
    expect((await row(gone)).issueState, IssueState.notFound);

    // Reopened on GitHub: back to the normal badge.
    gh.issues[198]!['state'] = 'open';
    expect(await watcher.check(ws.id), 1);
    expect((await row(tema)).issueState, IssueState.open);
    expect((await row(tema)).issueClosedBy, isNull);
    // Nothing changed: nothing written.
    expect(await watcher.check(ws.id), 0);
    expect(gh.writes, isEmpty);
  });

  testWidgets('the card of the Quadro says "#N fechada" in text; the spec '
      'stays in its column', (tester) async {
    final r = await pumpCanvas(tester, const [
      CanvasSpec('SPEC-015', title: 'Login com Google', stage: SpecStage.done),
    ], view: BoardView.columns);
    final (_, db) = r;
    await (db.update(db.specs)..where((s) => s.code.equals('SPEC-015'))).write(
      SpecsCompanion(
        issueNumber: const Value(188),
        issueState: const Value(IssueState.closed),
        issueClosedBy: const Value('PR #205'),
        issueClosedAt: Value(DateTime(2026, 11, 14, 12)),
      ),
    );
    await pumpFor(tester, 20);
    expect(find.text('#188 fechada'), findsOneWidget);
    expect(byKey('board-card-SPEC-015'), findsOneWidget);
    final tip = tester.widget<Tooltip>(
      find
          .ancestor(
            of: byKey('issue-badge-SPEC-015'),
            matching: find.byType(Tooltip),
          )
          .first,
    );
    expect(tip.message, startsWith('Fechada no GitHub em 14/11, pelo PR #205'));
  });
}
