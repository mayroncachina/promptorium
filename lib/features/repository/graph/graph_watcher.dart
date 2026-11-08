import 'dart:io';

import '../../../core/fs/dir_watcher.dart';

/// Watches HEAD, the refs and the tags of a repository (SPEC-045 R7) with
/// the [DirWatcher] of the Código screen: the git folder itself (HEAD,
/// packed-refs) and every folder under `refs/` (branch names with `/` live
/// in sub-folders, so the folders are listed again after each change).
class GraphRefsWatcher {
  GraphRefsWatcher(
    this.gitDir, {
    required void Function() onChange,
    Duration debounce = const Duration(milliseconds: 300),
  }) {
    _watcher = DirWatcher(
      dirs(),
      debounce: debounce,
      onChange: (paths) {
        if (!paths.any(isRefChange)) return;
        _watcher.update(dirs());
        onChange();
      },
    );
  }

  /// Absolute `.git` folder (`git rev-parse --absolute-git-dir`).
  final String gitDir;
  late final DirWatcher _watcher;

  /// Folders under `refs/` watched at most.
  static const maxDirs = 400;

  List<String> dirs() {
    final out = [gitDir];
    final refs = Directory('$gitDir/refs');
    if (!refs.existsSync()) return out;
    out.add(refs.path);
    try {
      for (final e in refs.listSync(recursive: true, followLinks: false)) {
        if (out.length >= maxDirs) break;
        if (e is Directory) out.add(e.path);
      }
    } on FileSystemException {
      // a folder removed while listing: the next change lists again
    }
    return out;
  }

  /// HEAD, packed-refs or a ref (not git's `.lock` files, the index, the
  /// logs or FETCH_HEAD, which change without moving a ref).
  bool isRefChange(String path) {
    if (path.endsWith('.lock')) return false;
    if (path == '$gitDir/HEAD' || path == '$gitDir/packed-refs') return true;
    if (!path.startsWith('$gitDir/refs/')) return false;
    // stash and the app's internal refs don't show in the graph
    final rel = path.substring(gitDir.length + 6);
    return !rel.startsWith('stash') && !rel.startsWith('promptorium');
  }

  Future<void> close() => _watcher.close();
}
