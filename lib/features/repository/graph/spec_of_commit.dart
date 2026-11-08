import 'commit_log.dart';
import 'lane_layout.dart';
import 'spec_branch.dart';

final _specInText = RegExp(r'\bSPEC-(\d{1,4})\b');

/// The spec of a commit (SPEC-045 R2; the Atividade of SPEC-046 uses it
/// too):
///
/// 1. the branch that contains it first, [track] (from [layoutLanes]):
///    `spec/042-t4-…` → SPEC-042 T4;
/// 2. on another branch (the default one), the branch its merge brought in
///    (`Merge pull request #94 from o/spec/042-sprints` → SPEC-042);
/// 3. the `SPEC-NNN` in the [subject] (a squash merge, a docs commit);
/// 4. no spec.
SpecBranch? specOfCommit({required String? track, required String subject}) {
  final fromTrack = parseSpecBranch(track);
  if (fromTrack != null) return fromTrack;
  final merged = parseSpecBranch(branchFromMergeSubject(subject));
  if (merged != null) return SpecBranch(merged.number);
  final m = _specInText.firstMatch(subject);
  return m == null ? null : SpecBranch(int.parse(m.group(1)!));
}

/// The spec of every commit of [commits] (in the log order), sha → spec;
/// commits without a spec are left out. For the views that have no lanes
/// of their own (SPEC-046).
Map<String, SpecBranch> specsOfLog(
  List<CommitRow> commits, {
  required String defaultBranch,
}) {
  final rows = layoutLanes(commits, defaultBranch: defaultBranch).rows;
  return {
    for (final (i, c) in commits.indexed)
      c.sha: ?specOfCommit(track: rows[i].track, subject: c.subject),
  };
}
