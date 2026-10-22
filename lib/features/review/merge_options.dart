enum MergeMethod { merge, squash, rebase }

class MergeOptions {
  const MergeOptions({
    this.method = MergeMethod.merge,
    this.switchBase = false,
    this.restoreBranch = true,
    this.stash = false,
    this.skipHooks = false,
  });
  final MergeMethod method;
  final bool switchBase, restoreBranch, stash, skipHooks;
}

/// Facts of the main repository shown by the merge dialog.
class MergeFacts {
  const MergeFacts({
    this.rootBranch,
    this.rootChanges = const [],
    this.published = false,
  });

  /// Null = detached HEAD.
  final String? rootBranch;
  final List<String> rootChanges;
  final bool published;
}

class ConflictPrediction {
  const ConflictPrediction({this.files = const [], this.error});
  final List<String> files;
  final String? error;
}
