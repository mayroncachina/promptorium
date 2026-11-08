import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart';
import 'package:promptorium/features/repository/releases/semver.dart';
import 'package:promptorium/features/repository/releases/unreleased.dart';

import '../../core/git/git_test_utils.dart';
import 'fake_gh.dart';
import 'release_timeline_test.dart' show commit;

RawCommit c(String subject, {String body = '', int parents = 1}) => RawCommit(
  sha: '${subject.hashCode.abs()}abcdef0123',
  subject: subject,
  body: body,
  parents: parents,
);

List<GroupedCommit> grouped(List<String> subjects) => [
  for (final g in groupCommits([
    for (final s in subjects) c(s),
  ], CliffRules.promptorium))
    ...g.commits,
];

void main() {
  final cliffToml = File('cliff.toml').readAsStringSync();

  group('R3 · groups', () {
    test("the project's cliff.toml: groups in its order, the SPEC "
        'preprocessors, chore(release) and merges left out', () {
      final rules = CliffRules.parse(cliffToml);
      expect(rules.fromFile, isTrue);
      expect(rules.groupOrder.take(2), ['Funcionalidades', 'Correções']);
      // git log order: newest first.
      final groups = groupCommits([
        c('Merge pull request #98 from o/spec/042-t1-dados', parents: 2),
        c('chore(release): v0.11.0'),
        c('docs: guia'),
        c('SPEC-042 R3: concluir sprint'),
        c('fix(tray): sublinhado do rótulo'),
        c('feat(sprints): seletor'),
        c('wip sem padrão'),
      ], rules);
      expect(groups.map((g) => g.title), [
        'Funcionalidades',
        'Correções',
        'Documentação',
      ]);
      // Oldest first inside a group, as git-cliff sorts them.
      expect(groups.first.commits.map((x) => x.short), [
        'sprints: seletor',
        'SPEC-042: concluir sprint (R3)',
      ]);
      expect(
        groups.first.summary,
        'sprints: seletor · SPEC-042: concluir sprint (R3)',
      );
    });

    test('without cliff.toml: the groups of the Promptorium', () {
      final groups = groupCommits([
        c('test: board'),
        c('ci: cache'),
        c('perf: lista'),
        c('feat!: nova api'),
      ], CliffRules.promptorium);
      expect(groups.map((g) => g.title), [
        'Funcionalidades',
        'Desempenho',
        'Testes',
        'Build e CI',
      ]);
      expect(groups.first.commits.single.breaking, isTrue);
    });

    test('specs by the spec/NNN branch of a merge or SPEC-NNN in the '
        'subject', () {
      final specs = mergedSpecs(
        [
          c('Merge pull request #95 from o/spec/042-t1-dados', parents: 2),
          c('Merge pull request #96 from o/spec/042-t2-seletor', parents: 2),
          c("Merge branch 'spec/041-radar'", parents: 2),
          c('feat(SPEC-043): conflito no gate'),
          c('fix: a spec/099 citada num commit comum'),
        ],
        titles: {'SPEC-041': 'Radar na bandeja'},
      );
      expect(specs.map((s) => s.code), ['SPEC-041', 'SPEC-042', 'SPEC-043']);
      expect(specs.first.title, 'Radar na bandeja');
      expect(specs[1].title, isNull);
    });
  });

  group('R3 · nextVersion', () {
    final v = SemVer.tryParse;
    test('after 1.0: incompatible → major, feat → minor, rest → patch', () {
      expect('${nextVersion(grouped(['feat!: x']), v('1.4.2'))}', '2.0.0');
      expect(
        '${nextVersion(grouped(['fix: a', 'feat: b']), v('1.4.2'))}',
        '1.5.0',
      );
      expect('${nextVersion(grouped(['fix: a']), v('1.4.2'))}', '1.4.3');
      expect(
        '${nextVersion([
          ...grouped(['fix: a']),
          GroupedCommit(
            commit: c('refactor: x', body: 'BREAKING CHANGE: y'),
            type: 'refactor',
            description: 'x',
            breaking: true,
          ),
        ], v('1.4.2'))}',
        '2.0.0',
      );
    });

    test('before 1.0: incompatible → minor, feat → patch', () {
      expect('${nextVersion(grouped(['feat!: x']), v('0.11.0'))}', '0.12.0');
      expect('${nextVersion(grouped(['feat: x']), v('0.11.0'))}', '0.11.1');
      expect('${nextVersion(grouped(['docs: x']), v('0.11.0'))}', '0.11.1');
    });

    test("with a cliff.toml, its [bump] decides 0.x as git-cliff does "
        '(defaults: feat → minor)', () {
      final rules = CliffRules.parse(cliffToml);
      expect(
        '${nextVersion(grouped(['feat: x']), v('0.11.0'), cliff: rules)}',
        '0.12.0',
      );
      final off = CliffRules.parse(
        '$cliffToml\n[bump]\nfeatures_always_bump_minor = false\n',
      );
      expect(
        '${nextVersion(grouped(['feat: x']), v('0.11.0'), cliff: off)}',
        '0.11.1',
      );
    });

    test('a repository without tags suggests 0.1.0', () {
      expect('${nextVersion(grouped(['feat!: x']), null)}', '0.1.0');
      expect(bumpReason(const [], null), BumpReason.first);
    });
  });

  group('R4 · changelog', () {
    test("without git-cliff: git-cliff's format", () {
      final groups = groupCommits([
        c('fix(sprints): singular'),
        c('feat(tray): radar na bandeja'),
      ], CliffRules.promptorium);
      final text = renderChangelog(
        '0.12.0',
        groups,
        date: DateTime(2026, 11, 8),
      );
      expect(
        text,
        startsWith(
          '## [0.12.0] - 2026-11-08\n\n### Funcionalidades\n'
          '- **tray:** Radar na bandeja (',
        ),
      );
      expect(text, contains('\n### Correções\n- **sprints:** Singular ('));
    });

    group('loadUnreleased with real git', () {
      late Directory tmp;
      late String repo;
      setUp(() async {
        tmp = Directory.systemTemp.createTempSync('promptorium-unr-');
        repo = await createRepo(tmp);
      });
      tearDown(() => tmp.deleteSync(recursive: true));

      test('no tag: everything since the first commit, 0.1.0, the '
          "Promptorium's groups", () async {
        await commit(repo, 'b.txt', 'feat: b');
        final u = await loadUnreleased(
          root: repo,
          git: GitService(repo),
          branch: 'main',
          branchRef: 'refs/heads/main',
          lastTag: null,
          today: DateTime(2026, 11, 8),
        );
        expect(u.commitCount, 2);
        expect('${u.suggested}', '0.1.0');
        expect(u.suggestedTag, 'v0.1.0');
        expect(u.byGitCliff, isFalse);
        expect(u.groups.single.title, 'Funcionalidades');
        expect(u.changelog, startsWith('## [0.1.0] - 2026-11-08'));
      });

      test('after the last tag; git-cliff gives the version and the '
          'changelog when the project has it', () async {
        File('$repo/cliff.toml').writeAsStringSync(cliffToml);
        await gitIn(repo, ['add', '.']);
        await gitIn(repo, ['commit', '-q', '-m', 'chore: cliff']);
        await gitIn(repo, ['tag', 'v0.11.0']);
        await commit(repo, 'b.txt', 'feat(repo): releases');
        await commit(repo, 'c.txt', 'SPEC-044 R2: linha do tempo');
        final fake = FakeGh(hasCliff: true);
        final u = await loadUnreleased(
          root: repo,
          git: GitService(repo),
          branch: 'main',
          branchRef: 'refs/heads/main',
          lastTag: 'v0.11.0',
          cliff: fake.call,
        );
        expect(u.commitCount, 2);
        expect(u.byGitCliff, isTrue);
        expect('${u.suggested}', '0.12.0');
        expect(u.changelog, fake.cliffChangelog.trim());
        expect(u.specs.map((s) => s.code), ['SPEC-044']);
        expect(fake.calls.where((x) => x.$1 == 'git-cliff').map((x) => x.$2), [
          ['--bumped-version'],
          ['--unreleased', '--tag', 'v0.12.0', '--strip', 'all'],
        ]);

        // git-cliff missing: the app computes with the cliff.toml rules.
        final local = await loadUnreleased(
          root: repo,
          git: GitService(repo),
          branch: 'main',
          branchRef: 'refs/heads/main',
          lastTag: 'v0.11.0',
          cliff: FakeGh().call,
          today: DateTime(2026, 11, 8),
        );
        expect(local.byGitCliff, isFalse);
        expect('${local.suggested}', '0.12.0');
        expect(local.changelog, contains('### Funcionalidades'));
        expect(local.changelog, contains('**SPEC-044:** Linha do tempo (R2)'));
      });

      test('nothing new since the tag', () async {
        await gitIn(repo, ['tag', 'v1.0.0']);
        final u = await loadUnreleased(
          root: repo,
          git: GitService(repo),
          branch: 'main',
          branchRef: 'refs/heads/main',
          lastTag: 'v1.0.0',
        );
        expect(u.isEmpty, isTrue);
        expect(u.groups, isEmpty);
      });
    });
  });

  group('R5 · version validation', () {
    test('not semver, existing tag, not greater than the last', () {
      final last = SemVer.tryParse('0.11.0');
      String? check(String v) => validateNewVersion(
        v,
        last: last,
        existingTags: {'v0.11.0', 'v0.12.0'},
        lastTag: 'v0.11.0',
      );
      expect(check('0.12'), 'Use X.Y.Z (ex.: 0.12.0).');
      expect(check('abc'), isNotNull);
      expect(check('0.12.0'), 'A tag v0.12.0 já existe.');
      expect(check('v0.12.0'), 'A tag v0.12.0 já existe.');
      expect(check('0.10.5'), contains('maior que a última'));
      expect(check('0.11.0'), isNotNull);
      expect(check('0.13.0'), isNull);
      expect(tagFor('0.13.0', lastTag: '0.11.0'), '0.13.0');
      expect(tagFor('0.13.0', lastTag: null), 'v0.13.0');
    });
  });
}
