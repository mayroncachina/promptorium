import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/gh_cli.dart';

import 'package:promptorium/core/git/gh_issues.dart';

import '../../features/repository/fake_gh.dart';
import 'fake_issues.dart';

void main() {
  test('auth: missing, logged out and logged in with the account', () async {
    expect(
      await GhCli(FakeGh(hasGh: false).call, cwd: '/r').ghAuthStatus(),
      const GhAuth.missing(),
    );
    expect(
      await GhCli(FakeGh(authed: false).call, cwd: '/r').ghAuthStatus(),
      const GhAuth.loggedOut(),
    );
    expect(
      await GhCli(FakeGh().call, cwd: '/r').ghAuthStatus(),
      const GhAuth.loggedIn('mayroncachina'),
    );
  });

  test('release list: files, sizes, drafts and the latest', () async {
    final fake = FakeGh()
      ..releases = [
        releaseRow('v0.12.0', draft: true),
        releaseRow(
          'v0.11.0',
          publishedAt: '2026-11-07T13:41:53Z',
          assets: [('a.deb', 13533822)],
        ),
        releaseRow('v0.10.0', publishedAt: '2026-11-06T12:52:02Z'),
      ];
    final list = await GhCli(fake.call, cwd: '/r').releaseList();
    expect(list.map((r) => (r.tagName, r.isDraft, r.isLatest)), [
      ('v0.12.0', true, false),
      ('v0.11.0', false, true),
      ('v0.10.0', false, false),
    ]);
    expect(list[1].assets.single.size, 13533822);
    expect(fake.calls.last.$2.first, 'api');
  });

  test('a failed gh is a GhException with stderr', () async {
    final fake = FakeGh()..releasesFail = true;
    expect(
      () => GhCli(fake.call, cwd: '/r').releaseList(),
      throwsA(
        isA<GhException>().having((e) => '$e', 'text', contains('HTTP 502')),
      ),
    );
  });

  test('run view: jobs and steps; --log-failed without the job columns', () {
    final v = GhCli.parseRunView(1, {
      'databaseId': 42,
      'status': 'in_progress',
      'conclusion': '',
      'url': 'https://github.com/o/r/actions/runs/42',
      'jobs': [
        {
          'name': 'prepare',
          'status': 'completed',
          'conclusion': 'success',
          'startedAt': '2026-11-07T13:29:11Z',
          'completedAt': '2026-11-07T13:29:22Z',
          'steps': [
            {'name': 'Versão', 'number': 5, 'status': 'completed'},
          ],
        },
      ],
    });
    expect(v.id, 42);
    expect(v.completed, isFalse);
    expect(v.jobs.single.steps.single.name, 'Versão');
    expect(
      v.jobs.single.completedAt!.difference(v.jobs.single.startedAt!),
      const Duration(seconds: 11),
    );
    final log = [
      for (var i = 1; i <= 50; i++) 'package\tBuild\t2026-11-07T13:30:00Z l$i',
    ].join('\n');
    final tail = GhCli.tailFailedLog(log, 40);
    expect(tail, hasLength(40));
    expect(tail.first, '2026-11-07T13:30:00Z l11');
    expect(tail.last, '2026-11-07T13:30:00Z l50');
  });

  group('issues (SPEC-074)', () {
    GhIssues issuesOf(FakeIssuesGh fake) =>
        GhIssues(GhCli(fake.call, cwd: '/r'), repo: fake.repo);

    test('list: the filters become the search query, newest first, and the '
        'PRs stay out', () async {
      final fake = FakeIssuesGh()
        ..add(212, 'Carrinho some', labels: ['bug', 'checkout'])
        ..add(215, 'Cupom não aplica', labels: ['bug', 'checkout'])
        ..add(220, 'PR do frete', labels: ['checkout'], pr: true)
        ..add(230, 'Tema escuro', labels: ['ui']);
      final page = await issuesOf(fake).list(
        labels: ['checkout'],
        milestone: 'v1.2',
        assignee: IssueAssigneeFilter.none,
        search: 'cupom',
      );
      final args = fake.ghCalls.last;
      expect(args.take(4), ['api', '-X', 'GET', 'search/issues']);
      expect(
        args,
        contains(
          'q=repo:ana-souza/loja-da-ana is:issue state:open label:checkout '
          'milestone:v1.2 no:assignee cupom in:title,body',
        ),
      );
      expect(args, containsAll(['per_page=50', 'page=1']));
      expect(page.issues.map((i) => i.number), [215]);

      final all = await issuesOf(fake).list(labels: ['checkout']);
      // The search still brought the PR (#220): it is dropped.
      expect(all.issues.map((i) => i.number), [215, 212]);
      expect(all.issues.first.labels.map((l) => l.name), ['bug', 'checkout']);
    });

    test('query: closed, all, me, a person and labels with spaces', () {
      final i = GhIssues(GhCli(FakeIssuesGh().call, cwd: '/r'), repo: 'o/r');
      expect(
        i.searchQuery(
          state: IssueStateFilter.closed,
          assignee: IssueAssigneeFilter.me,
          labels: ['good first issue'],
        ),
        'repo:o/r is:issue state:closed label:"good first issue" '
        'assignee:@me',
      );
      expect(
        i.searchQuery(
          state: IssueStateFilter.all,
          assignee: const IssueAssigneeFilter.person('lucas-andrade'),
        ),
        'repo:o/r is:issue assignee:lucas-andrade',
      );
    });

    test('list: pages of 50 with the total and "Carregar mais N"', () async {
      final fake = FakeIssuesGh();
      for (var n = 1; n <= 58; n++) {
        fake.add(n, 'Issue $n');
      }
      final first = await issuesOf(fake).list();
      expect(first.issues, hasLength(50));
      expect(first.total, 58);
      expect(first.hasMore, isTrue);
      expect(first.nextCount, 8);
      final second = await issuesOf(fake).list(page: 2);
      expect(second.issues, hasLength(8));
      expect(second.hasMore, isFalse);
      expect(fake.ghCalls.last, contains('page=2'));
    });

    test('view, hints and a PR is not an issue', () async {
      final fake = FakeIssuesGh()
        ..add(
          215,
          'Cupom',
          body:
              '- [ ] a\n- [x] b\n- [ ] c\n![print](https://x/a.png)\n'
              '<img src="b.png">',
          milestone: 'v1.2',
          assignees: ['ana-souza'],
        )
        ..add(220, 'PR', pr: true);
      final i = await issuesOf(fake).view(215);
      expect(fake.ghCalls.last, [
        'api',
        'repos/ana-souza/loja-da-ana/issues/215',
      ]);
      expect(i.milestone, 'v1.2');
      expect(i.assignees, ['ana-souza']);
      expect(i.checklistItems, 3);
      expect(i.images, 2);
      expect(i.updatedAt, DateTime.utc(2026, 11, 10, 10));
      expect(() => issuesOf(fake).view(220), throwsA(isA<GhException>()));
    });

    test('create: arguments and the number of the new issue', () async {
      final fake = FakeIssuesGh()..nextNumber = 251;
      final n = await issuesOf(fake).create(
        title: 'Exportar pedidos',
        body: 'Texto',
        labels: ['enhancement', 'admin'],
        milestone: 'v1.2',
        assignee: '@me',
      );
      expect(n, 251);
      expect(fake.ghCalls.last, [
        'issue',
        'create',
        '--repo',
        'ana-souza/loja-da-ana',
        '--title',
        'Exportar pedidos',
        '--body',
        'Texto',
        '--label',
        'enhancement',
        '--label',
        'admin',
        '--milestone',
        'v1.2',
        '--assignee',
        '@me',
      ]);
      fake.createFails = true;
      expect(
        () => issuesOf(fake).create(title: 'x', body: ''),
        throwsA(isA<GhException>()),
      );
    });

    test('states: one GraphQL query for all, closed by a PR or by hand, and '
        'a missing one', () async {
      final fake = FakeIssuesGh()
        ..add(188, 'a', state: 'closed', closedAt: '2026-11-14T12:00:00Z')
        ..add(198, 'b', state: 'closed', closedAt: '2026-11-13T12:00:00Z')
        ..add(226, 'c');
      fake.closedByPr[188] = 205;
      final states = await issuesOf(fake).states([226, 188, 198, 404, 226]);
      expect(fake.ghCalls.where((a) => a[1] == 'graphql'), hasLength(1));
      expect(states.map((s) => (s.number, s.found, s.closed, s.closedBy)), [
        (188, true, true, 'PR #205'),
        (198, true, true, 'à mão'),
        (226, true, false, null),
        (404, false, false, null),
      ]);
      expect(states.first.closedAt, DateTime.utc(2026, 11, 14, 12));
      expect(await issuesOf(fake).states([]), isEmpty);
    });

    test('upsertComment: creates the comment once, then edits the one with '
        'the marker', () async {
      final fake = FakeIssuesGh()..add(226, 'Pix');
      fake.comments[226] = [
        {'id': 1, 'body': 'Outro comentário'},
      ];
      const marker = '<!-- promptorium:SPEC-023 -->';
      final id = await issuesOf(fake).upsertComment(226, marker, 'v1');
      expect(fake.ghCalls.last, containsAll(['POST', 'body=$marker\nv1']));
      final again = await issuesOf(fake).upsertComment(226, marker, 'v2');
      expect(again, id);
      expect(
        fake.ghCalls.last,
        containsAll([
          'PATCH',
          'repos/ana-souza/loja-da-ana/issues/comments/$id',
          'body=$marker\nv2',
        ]),
      );
      expect(fake.comments[226], hasLength(2));
      expect(fake.comments[226]!.last['body'], '$marker\nv2');
    });

    test('labels, milestones, assignees and the repository', () async {
      final fake = FakeIssuesGh(issuesEnabled: false, defaultBranch: 'trunk');
      final i = issuesOf(fake);
      expect((await i.labels()).map((l) => l.name), contains('checkout'));
      expect(await i.milestones(), ['v1.2', 'v1.3']);
      expect(await i.assignees(), ['ana-souza', 'lucas-andrade']);
      final info = await i.info();
      expect(info.hasIssuesEnabled, isFalse);
      expect(info.defaultBranch, 'trunk');
    });
  });

  test('SPEC-073: the whole failed log and the rerun of only the failed '
      'jobs', () async {
    final fake = FakeGh()..failedLog = 'test\tRun\t2026-11-15T10:00:00Z erro\n';
    final gh = GhCli(fake.call, cwd: '/r');
    expect(await gh.runFailedLogRaw(42), contains('test\tRun\t'));
    expect(fake.calls.last.$2, ['run', 'view', '42', '--log-failed']);
    await gh.runRerunFailed(42);
    expect(fake.calls.last.$2, ['run', 'rerun', '42', '--failed']);
  });
}
