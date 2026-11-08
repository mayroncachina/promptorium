import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/gh_cli.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/features/repository/releases/release_timeline.dart';
import 'package:promptorium/features/repository/releases/semver.dart';

import '../../core/git/git_test_utils.dart';
import 'fake_gh.dart';

Future<void> commit(String repo, String file, String message) async {
  File('$repo/$file').writeAsStringSync('$message\n');
  await gitIn(repo, ['add', '.']);
  await gitIn(repo, ['commit', '-q', '-m', message]);
}

void main() {
  group('versions', () {
    test('only what looks like a version is a version tag', () {
      for (final t in ['v1.2.3', '1.2.3', 'v0.12.0-beta.1', '2.0.0+build.7']) {
        expect(isVersionTag(t), isTrue, reason: t);
      }
      for (final t in ['release-1', 'v1.2', 'latest', 'v01.2.3', 'nightly']) {
        expect(isVersionTag(t), isFalse, reason: t);
      }
    });

    test('order: a pre-release is lower than its version', () {
      final v = SemVer.tryParse;
      expect(v('0.12.0')! > v('0.11.9')!, isTrue);
      expect(v('1.0.0')! > v('1.0.0-rc.1')!, isTrue);
      expect(v('v1.0.0')!.compareTo(v('1.0.0')!), 0);
    });
  });

  group('R2 · timeline', () {
    test('joins tags and releases by tag, with the four states, newest '
        'first', () {
      final entries = mergeTimeline(
        tags: [
          LocalTag('v0.12.0', date: DateTime.utc(2026, 11, 8)),
          LocalTag('v0.11.0', date: DateTime.utc(2026, 11, 7)),
          LocalTag('v0.9.0', date: DateTime.utc(2026, 11, 5)),
          const LocalTag('nightly'),
        ],
        releases: GhCli.parseReleases([
          releaseRow('v0.12.0', draft: true),
          releaseRow(
            'v0.11.0',
            publishedAt: '2026-11-07T13:41:53Z',
            assets: [('a.deb', 10), ('b.zip', 20)],
          ),
          releaseRow(
            'v0.10.0',
            publishedAt: '2026-11-06T12:52:02Z',
            prerelease: true,
          ),
          releaseRow('preview', publishedAt: '2026-11-01T00:00:00Z'),
        ]),
      );
      expect(entries.map((e) => e.tag), [
        'v0.12.0',
        'v0.11.0',
        'v0.10.0',
        'v0.9.0',
      ]);
      expect(entries.map((e) => e.state), [
        ReleaseState.draft,
        ReleaseState.published,
        ReleaseState.prerelease,
        ReleaseState.tagOnly,
      ]);
      expect(entries.map((e) => e.state.label), [
        'Rascunho',
        'Publicada',
        'Pré-release',
        'Só tag',
      ]);
      // The latest is the newest published one that is not a pre-release.
      expect(entries[1].isLatest, isTrue);
      expect(entries.where((e) => e.isLatest), hasLength(1));
      expect(entries[1].assets.map((a) => a.size), [10, 20]);
      expect(entries[1].hasLocalTag, isTrue);
      expect(entries[2].hasLocalTag, isFalse);
      expect(entries[3].date, DateTime.utc(2026, 11, 5));
    });

    test('the commits of each version count from the previous local tag', () {
      final entries = mergeTimeline(
        tags: const [LocalTag('v0.2.0'), LocalTag('v0.1.0')],
        releases: GhCli.parseReleases([releaseRow('v0.3.0', draft: true)]),
      );
      expect(commitRanges(entries), [('v0.2.0', 'v0.1.0'), ('v0.1.0', null)]);
    });

    test('notes: git-cliff groups when they follow its format, else the '
        'whole text', () {
      final cliff = mergeTimeline(
        tags: const [],
        releases: GhCli.parseReleases([
          releaseRow(
            'v0.11.0',
            body:
                '## [0.11.0] - 2026-11-07\n\n### Funcionalidades\n'
                '- **sessions:** Ditado por voz (abc1234)\n\n'
                '### Documentação\n- docs (def5678)\n',
          ),
        ]),
      ).single.section;
      expect(cliff.groups.single.title, 'Funcionalidades');
      expect(cliff.groups.single.items, ['Ditado por voz']);
      final plain = mergeTimeline(
        tags: const [],
        releases: GhCli.parseReleases([
          releaseRow('v1.0.0', body: 'Primeira versão estável.'),
        ]),
      ).single.section;
      expect(plain.rawText, 'Primeira versão estável.');
    });

    test(
      'with real git: tags in the timeline and their commit counts',
      () async {
        final tmp = Directory.systemTemp.createTempSync('promptorium-tl-');
        addTearDown(() => tmp.deleteSync(recursive: true));
        final repo = await createRepo(tmp);
        await gitIn(repo, ['tag', 'v0.1.0']);
        await commit(repo, 'b.txt', 'feat: b');
        await commit(repo, 'c.txt', 'fix: c');
        await gitIn(repo, ['tag', '-a', 'v0.2.0', '-m', 'v0.2.0']);
        await commit(repo, 'd.txt', 'feat: d');
        await gitIn(repo, ['tag', 'not-a-version']);
        final git = GitService(repo);
        final tags = await readLocalTags(git);
        expect(tags.map((t) => t.name).toSet(), {'v0.1.0', 'v0.2.0'});
        final entries = await loadTimeline(
          git,
          tags: tags,
          releases: GhCli.parseReleases([
            releaseRow('v0.2.0', assets: [('x.deb', 1)]),
          ]),
        );
        expect(entries.map((e) => (e.tag, e.commits, e.previousTag)), [
          ('v0.2.0', 2, 'v0.1.0'),
          ('v0.1.0', 1, null),
        ]);
        expect(entries.first.state, ReleaseState.published);
        expect(entries.last.state, ReleaseState.tagOnly);
      },
    );
  });
}
