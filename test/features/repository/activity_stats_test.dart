import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/git/git_service.dart' show CommitOriginKind;
import 'package:promptorium/features/repository/activity/activity_log.dart';
import 'package:promptorium/features/repository/activity/activity_stats.dart';
import 'package:promptorium/features/repository/graph/commit_log.dart'
    show ChangedFile;
import 'package:promptorium/features/repository/releases/unreleased.dart';

import 'activity_fixtures.dart';

void main() {
  group('R1 · períodos e comparação', () {
    final log = logOf([
      ac('c5', ['c4'], 1, 'feat: a'),
      ac('c4', ['c3'], 2, 'feat: b'),
      ac('c3', ['c2'], 3, 'fix: c'),
      ac('c2', ['c1'], 35, 'feat: d'),
      ac('c1', ['c0'], 40, 'feat: e'),
      ac('c0', [], 200, 'inicial'),
    ]);
    final r = reportsOf(log);

    test('30 dias: o período e os 30 anteriores', () {
      final s = r[ActivityPeriod.days30].summary;
      expect(s.commits, 3);
      expect(s.prevCommits, 2);
      expect(changeLabel(s.commits, s.prevCommits), '+50%');
    });

    test('90 dias e 1 ano: cada um com o seu anterior', () {
      expect(r[ActivityPeriod.days90].summary.commits, 5);
      expect(r[ActivityPeriod.days90].summary.prevCommits, 0);
      expect(r[ActivityPeriod.year].summary.commits, 6);
      expect(r[ActivityPeriod.year].summary.prevCommits, 0);
      expect(changeLabel(6, 0), isNull);
      expect(changeLabel(3, 4), '−25%');
    });

    test('o período começa à meia-noite de N−1 dias atrás', () {
      final p = r[ActivityPeriod.days30];
      expect(p.from, DateTime(2026, 10, 10));
      expect(p.to, activityNow);
    });

    test('specs mergeadas e ciclo mediano com o período anterior', () {
      final s = reportsOf(logOf(specHistory()))[ActivityPeriod.days30].summary;
      expect(s.specsMerged, 2);
      expect(s.prevSpecsMerged, 0);
      expect(s.medianCycle, closeTo(4.5, .01));
      expect(s.prevMedianCycle, isNull);
    });
  });

  group('R2 · mapa por dia', () {
    test('conta os commits do dia, sem merges, com as specs do dia', () {
      final r = reportsOf(logOf(specHistory()))[ActivityPeriod.days30];
      final day3 = dayOf(daysAgo(3));
      expect(r.days[day3]!.commits, 1);
      expect(r.days[day3]!.specs, ['SPEC-043']);
      // The merge days have no commit of their own.
      expect(r.days[dayOf(daysAgo(5))], isNull);
      expect(r.days[dayOf(daysAgo(12))]!.specs, ['SPEC-042']);
      expect(r.level(0), 0);
      expect(r.level(r.maxDay), 4);
    });

    test('dias de release vêm das tags; sem tags não há marca (R7)', () {
      final commits = specHistory();
      final withTags = reportsOf(
        logOf(
          commits,
          tags: [
            ActivityTag('v0.1.0', daysAgo(5)),
            ActivityTag('v0.2.0', daysAgo(2)),
            ActivityTag('rascunho', daysAgo(1)),
            ActivityTag('v0.0.1', daysAgo(50)),
          ],
        ),
      )[ActivityPeriod.days30];
      expect(withTags.hasTags, isTrue);
      expect(withTags.releaseDays[dayOf(daysAgo(5))], ['v0.1.0']);
      expect(withTags.releaseDays[dayOf(daysAgo(1))], isNull);
      expect(withTags.summary.releases, 2);
      expect(withTags.summary.prevReleases, 1);
      expect(withTags.summary.firstRelease, 'v0.1.0');
      expect(withTags.summary.lastRelease, 'v0.2.0');

      final none = reportsOf(logOf(commits))[ActivityPeriod.days30];
      expect(none.hasTags, isFalse);
      expect(none.releaseDays, isEmpty);
      expect(none.summary.releases, isNull);
    });
  });

  group('R3 · commits por tipo', () {
    test('os grupos do cliff.toml, em ordem, e "Outros"', () {
      final r = reportsOf(
        logOf([
          ac('c4', ['c3'], 1, 'Atualiza coisas'),
          ac('c3', ['c2'], 1, 'docs: guia'),
          ac('c2', ['c1'], 2, 'fix(x): y'),
          ac('c1', ['c0'], 9, 'feat(x): y'),
          ac('c0', [], 10, 'feat: z'),
        ]),
      )[ActivityPeriod.days30];
      expect(r.typeGroups, [
        'Funcionalidades',
        'Correções',
        'Documentação',
        otherGroup,
      ]);
      final last = r.typeWeeks.last;
      expect(last.week, weekOf(activityNow));
      expect(last.counts, {otherGroup: 1, 'Documentação': 1, 'Correções': 1});
      expect(r.typeWeeks.fold(0, (n, w) => n + w.total), 5);
    });

    test('um cliff.toml do projeto troca os grupos', () {
      final cliff = CliffRules.parse('''
commit_parsers = [
  { message = "^feat", group = "<!-- 0 -->Novidades" },
  { message = "^fix", group = "Consertos" },
]
''');
      final r = reportsOf(
        logOf([
          ac('c2', ['c1'], 1, 'fix: a'),
          ac('c1', ['c0'], 2, 'docs: b'),
          ac('c0', [], 3, 'feat: c'),
        ]),
        cliff: cliff,
      )[ActivityPeriod.days30];
      expect(r.typeGroups, ['Novidades', 'Consertos', otherGroup]);
    });

    test('mais de $maxTypeGroups grupos: os menores vão para "Outros"', () {
      final subjects = [
        for (var i = 0; i < 6; i++) 'feat: $i',
        for (var i = 0; i < 5; i++) 'fix: $i',
        for (var i = 0; i < 4; i++) 'docs: $i',
        for (var i = 0; i < 3; i++) 'test: $i',
        for (var i = 0; i < 3; i++) 'ci: $i',
        for (var i = 0; i < 2; i++) 'chore: $i',
        'perf: 1',
      ];
      final commits = [
        for (final (i, s) in subjects.indexed)
          ac('c$i', i == subjects.length - 1 ? [] : ['c${i + 1}'], 1, s),
      ];
      final r = reportsOf(logOf(commits))[ActivityPeriod.days30];
      expect(r.typeGroups.length, maxTypeGroups + 1);
      expect(r.typeGroups, isNot(contains('Desempenho')));
      expect(r.typeGroups.last, otherGroup);
      expect(r.typeWeeks.last.counts[otherGroup], 1);
    });
  });

  group('R4 · ciclo das specs', () {
    final reports = reportsOf(logOf(specHistory()));
    final c = reports[ActivityPeriod.days30].cycle;

    test('do primeiro commit da branch ao merge; filhas dentro da pai', () {
      expect(c.hasSpecBranches, isTrue);
      expect([for (final s in c.cycles) s.code], ['SPEC-042', 'SPEC-043']);
      // The daughter started first: 12 days ago, merge 5 days ago.
      expect(c.cycles.first.days, closeTo(7, .01));
      expect(c.cycles.last.days, closeTo(2, .01));
      // The docs commit of SPEC-044 on main is no spec branch.
      expect(reports.cycles.map((s) => s.code), isNot(contains('SPEC-044')));
    });

    test('mediana, p90 e as cinco mais longas', () {
      expect(c.median, closeTo(4.5, .01));
      expect(c.p90, closeTo(6.5, .01));
      expect(median([1, 5, 2]), 2);
      expect(
        percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 90),
        closeTo(9.1, .01),
      );
      expect(c.longest.length, 2);
    });

    test('a mediana por sprint concluída no período, em ordem', () {
      final r = reportsOf(logOf(specHistory()))[ActivityPeriod.days30];
      final out = sprintCycles(
        doneSprints: [
          (id: 2, name: 'Sprint 2', position: 2, closedAt: daysAgo(1)),
          (id: 1, name: 'Sprint 1', position: 1, closedAt: daysAgo(4)),
          (id: 3, name: 'Antiga', position: 0, closedAt: daysAgo(80)),
        ],
        specSprint: {'SPEC-042': 1, 'SPEC-043': 2},
        cycles: reports.cycles,
        from: r.from,
        to: r.to,
      );
      expect([for (final s in out) s.name], ['Sprint 1', 'Sprint 2']);
      expect(out.first.median, closeTo(7, .01));
      expect(out.last.median, closeTo(2, .01));
    });

    test('sem branches spec/* o ciclo diz que não há fonte (R7)', () {
      final r = reportsOf(
        logOf([
          ac('c1', ['c0'], 1, 'feat: SPEC-042 a'),
          ac('c0', [], 3, 'inicial'),
        ]),
      )[ActivityPeriod.days30];
      expect(r.cycle.hasSpecBranches, isFalse);
      expect(r.summary.medianCycle, isNull);
    });
  });

  group('R5 · arquivos mais alterados', () {
    test('sem gerados, com linhas e as specs de cada um', () {
      final r = reportsOf(logOf(specHistory()))[ActivityPeriod.days30];
      expect(r.files.map((f) => f.path), ['lib/a.dart']);
      final f = r.files.single;
      expect(f.commits, 2);
      expect(f.added, 15);
      expect(f.removed, 3);
      expect(f.lines, 18);
      expect(f.specs, ['SPEC-043', 'SPEC-042']);
      expect(f.history.map((h) => h.sha), ['s43b', 't1']);
      expect(isIgnoredFile('a/b/c.freezed.dart'), isTrue);
      expect(isIgnoredFile('lib/pubspec.dart'), isFalse);
    });

    test('no máximo 15, por commits', () {
      final commits = [
        for (var i = 0; i < 20; i++)
          ac(
            'c$i',
            i == 19 ? [] : ['c${i + 1}'],
            1,
            'feat: $i',
            files: [for (var k = 0; k <= i; k++) ChangedFile('f$k.dart', 1, 0)],
          ),
      ];
      final r = reportsOf(logOf(commits))[ActivityPeriod.days30];
      expect(r.files.length, 15);
      expect(r.files.first.path, 'f0.dart');
      expect(r.files.first.commits, 20);
    });
  });

  group('R8 · quem fez os commits', () {
    final log = logOf([
      ac('c5', ['c4'], 1, 'feat: a', trailers: 'sonnet · SPEC-042 R2'),
      ac('c4', ['c3'], 2, 'feat: b', trailers: 'app · SPEC-042 R2'),
      ac('c3', ['c2'], 3, 'fix: c'),
      ac('c2', ['c1'], 4, 'feat: d', trailers: 'opus · sessão x'),
      ac('c1', ['c0'], 20, 'feat: e'),
      ac('c0', [], 40, 'feat: f'),
    ]);

    test('pessoa, agentes e app, por modelo; antes da marca é sem marca', () {
      final o = reportsOf(log)[ActivityPeriod.days30].origins;
      expect(o.person, 1);
      expect(o.agent, 2);
      expect(o.app, 1);
      expect(o.unmarked, 1);
      expect(o.marked, 4);
      expect(o.models, [('opus', 1), ('sonnet', 1)]);
      expect(o.since, daysAgo(4));
      final early = o.weeks.firstWhere((w) => w.week == weekOf(daysAgo(20)));
      expect(early.unmarked, 1);
      expect(early.person, 0);
      expect(o.weeks.fold(0, (n, w) => n + w.total), 5);
    });

    test('nunca marcado: tudo sem marca, nada conta como pessoa', () {
      final o = reportsOf(
        logOf([
          ac('c1', ['c0'], 1, 'feat: a'),
          ac('c0', [], 2, 'feat: b'),
        ]),
      )[ActivityPeriod.days30].origins;
      expect(o.since, isNull);
      expect(o.person, 0);
      expect(o.unmarked, 2);
    });

    test('a classificação é a da SPEC-048 (CommitOrigin)', () {
      final p = PreparedActivity(
        ActivityInput(
          log: log,
          defaultBranch: 'main',
          now: activityNow,
          cliff: CliffRules.promptorium,
        ),
      );
      expect(p.origins.map((o) => o.kind), [
        CommitOriginKind.agent,
        CommitOriginKind.app,
        CommitOriginKind.person,
        CommitOriginKind.agent,
        CommitOriginKind.unmarked,
        CommitOriginKind.unmarked,
      ]);
      expect(
        p.origins.first.trailer,
        'Promptorium-Agente: sonnet · SPEC-042 R2',
      );
    });
  });
}
