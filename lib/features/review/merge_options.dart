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

class ConflictPrediction {
  const ConflictPrediction({this.files = const [], this.error});
  final List<String> files;
  final String? error;
}
