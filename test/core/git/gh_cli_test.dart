import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/gh_cli.dart';

import '../../features/repository/fake_gh.dart';

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
}
