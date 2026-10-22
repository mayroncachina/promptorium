import 'dart:async';
import 'dart:io';

/// Watches [dirs] (each one non-recursive: recursive watching does not
/// report sub-folders on Linux) and calls [onChange] with the paths touched,
/// [debounce] after the last event. Folders that do not exist (yet) are
/// skipped; [update] replaces the set.
class DirWatcher {
  DirWatcher(
    Iterable<String> dirs, {
    required this.onChange,
    this.debounce = const Duration(milliseconds: 300),
  }) {
    update(dirs);
  }

  final void Function(Set<String> paths) onChange;
  final Duration debounce;

  final Map<String, StreamSubscription<FileSystemEvent>> _subs = {};
  final Set<String> _pending = {};
  Timer? _timer;
  bool _closed = false;

  Set<String> get watching => _subs.keys.toSet();

  void update(Iterable<String> dirs) {
    if (_closed) return;
    final want = dirs.toSet();
    for (final d in _subs.keys.toList()) {
      if (!want.contains(d)) _subs.remove(d)?.cancel();
    }
    for (final d in want) {
      if (_subs.containsKey(d)) continue;
      final dir = Directory(d);
      if (!dir.existsSync()) continue;
      try {
        _subs[d] = dir.watch().listen((e) {
          _event(e.path);
          // git writes HEAD and refs as `x.lock` renamed to `x`.
          if (e is FileSystemMoveEvent && e.destination != null) {
            _event(e.destination!);
          }
        }, onError: (_) => _subs.remove(d)?.cancel());
      } on FileSystemException {
        // too many watches / no permission: the folder is skipped
      }
    }
  }

  void _event(String path) {
    if (_closed) return;
    _pending.add(path);
    _timer?.cancel();
    _timer = Timer(debounce, () {
      final paths = Set.of(_pending);
      _pending.clear();
      if (!_closed) onChange(paths);
    });
  }

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    await Future.wait([for (final s in _subs.values) s.cancel()]);
    _subs.clear();
  }
}
