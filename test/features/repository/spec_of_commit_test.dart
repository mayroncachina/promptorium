import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/repository/graph/commit_log.dart';
import 'package:promptorium/features/repository/graph/graph_painter.dart';
import 'package:promptorium/features/repository/graph/spec_branch.dart';
import 'package:promptorium/features/repository/graph/spec_of_commit.dart';
import 'package:promptorium/ui/theme/tokens.dart';

CommitRow row(
  String sha,
  List<String> parents,
  String subject, {
  List<CommitRef> refs = const [],
}) => CommitRow(
  sha: sha,
  parents: parents,
  author: 'Teste',
  time: DateTime(2026, 11, 7),
  subject: subject,
  refs: refs,
);

void main() {
  group('R2 · the spec of a commit', () {
    test('a commit on a spec branch', () {
      expect(
        specOfCommit(track: 'spec/042-sprints', subject: 'docs: sprints'),
        const SpecBranch(42),
      );
    });

    test('a commit on a daughter is the task of the spec', () {
      expect(
        specOfCommit(track: 'spec/042-t4-conclusao', subject: 'fix: x')?.label,
        'SPEC-042 T4',
      );
    });

    test('the merge of the PR on the default branch', () {
      expect(
        specOfCommit(
          track: 'main',
          subject: 'Merge pull request #94 from o/spec/042-sprints',
        ),
        const SpecBranch(42),
      );
      expect(
        specOfCommit(
          track: 'main',
          subject: 'Merge pull request #98 from o/spec/042-t4-conclusao',
        ),
        const SpecBranch(42),
      );
    });

    test('SPEC-NNN in the message (squash, docs)', () {
      expect(
        specOfCommit(
          track: 'main',
          subject: 'docs: SPEC-039, nova spec com mini planejamento (#88)',
        ),
        const SpecBranch(39),
      );
    });

    test('a commit without a spec', () {
      expect(
        specOfCommit(
          track: 'main',
          subject: 'Merge pull request #84 from o/chore/remover-hook',
        ),
        isNull,
      );
      expect(specOfCommit(track: null, subject: 'fix: x'), isNull);
    });

    test('the specs of a whole log, by the branch that contains each commit '
        'first', () {
      final specs = specsOfLog([
        row(
          'M',
          ['A', 'S2'],
          'Merge pull request #2 from o/spec/043-conflito',
          refs: const [CommitRef(RefKind.local, 'main')],
        ),
        row('S2', ['S1'], 'docs: decisões'),
        row('S1', ['A'], 'docs: conflito'),
        row('A', [], 'chore: inicial'),
      ], defaultBranch: 'main');
      expect(specs, {
        'M': const SpecBranch(43),
        'S2': const SpecBranch(43),
        'S1': const SpecBranch(43),
      });
    });
  });

  group('R2 · colours', () {
    test('the default branch light grey, a spec in its colour, its tasks '
        'lighter, the others neutral', () {
      expect(trackColor('main', 'main'), SpecColors.defaultBranch);
      expect(trackColor('origin/main', 'main'), SpecColors.defaultBranch);
      expect(trackColor('spec/042-sprints', 'main'), SpecColors.of(42));
      final task = trackColor('spec/042-t4-conclusao', 'main');
      expect(task, SpecColors.task(42));
      expect(
        HSLColor.fromColor(task).lightness,
        greaterThan(HSLColor.fromColor(SpecColors.of(42)).lightness),
      );
      expect(trackColor('chore/x', 'main'), SpecColors.other);
      expect(trackColor(null, 'main'), SpecColors.other);
    });

    test('neighbouring specs never share a colour', () {
      for (var n = 1; n < 60; n++) {
        expect(SpecColors.of(n), isNot(SpecColors.of(n + 1)));
      }
    });
  });
}
