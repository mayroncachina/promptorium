import 'package:flutter/foundation.dart';

/// A branch of a spec (SPEC-045 R2, R3): `spec/042-sprints` is the spec
/// (the mother) and `spec/042-t4-conclusao` its task 4 (a daughter).
@immutable
class SpecBranch {
  const SpecBranch(this.number, {this.task});

  final int number;

  /// Task of a big spec (`-tN-`); null on the mother.
  final int? task;

  bool get isTask => task != null;

  /// `SPEC-042`.
  String get code => specCode(number);

  /// `SPEC-042 T4` (the task) or `SPEC-042`.
  String get label => task == null ? code : '$code T$task';

  @override
  bool operator ==(Object other) =>
      other is SpecBranch && other.number == number && other.task == task;

  @override
  int get hashCode => Object.hash(number, task);

  @override
  String toString() => label;
}

/// `SPEC-042` of the number 42.
String specCode(int number) => 'SPEC-${number.toString().padLeft(3, '0')}';

final _specBranch = RegExp(r'(?:^|/)spec/(\d{1,4})(?:-t(\d+))?(?=-|$)');

/// The spec of a branch name (`spec/042-…`, `origin/spec/042-…`); null for
/// the other branches.
SpecBranch? parseSpecBranch(String? branch) {
  if (branch == null) return null;
  final m = _specBranch.firstMatch(branch);
  if (m == null) return null;
  return SpecBranch(
    int.parse(m.group(1)!),
    task: m.group(2) == null ? null : int.parse(m.group(2)!),
  );
}

final _mergePr = RegExp(r'^Merge pull request #(\d+) from [^/\s]+/(\S+)');
final _mergeBranch = RegExp(r"^Merge (?:remote-tracking )?branch '([^']+)'");

/// The branch a merge commit brought in, read from its subject: `Merge pull
/// request #94 from owner/spec/042-sprints`, `Merge branch 'x' into y`,
/// `Merge remote-tracking branch 'origin/x'` (the remote is dropped).
String? branchFromMergeSubject(String subject) {
  final pr = _mergePr.firstMatch(subject);
  if (pr != null) return pr.group(2);
  final b = _mergeBranch.firstMatch(subject);
  if (b == null) return null;
  final name = b.group(1)!;
  final remote = RegExp(r'^(?:origin|upstream)/(.+)$').firstMatch(name);
  return remote?.group(1) ?? name;
}

/// Number of the PR of a GitHub merge subject (`Merge pull request #94 …`).
int? prFromMergeSubject(String subject) {
  final m = _mergePr.firstMatch(subject);
  return m == null ? null : int.parse(m.group(1)!);
}
