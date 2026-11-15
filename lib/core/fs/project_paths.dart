import 'dart:io';

/// `~/workspace` when it exists, else `$HOME` (where "Novo projeto" creates
/// the folder by default).
String defaultProjectParent({String? home}) {
  final h = home ?? Platform.environment['HOME'] ?? '/';
  final ws = '$h/workspace';
  return Directory(ws).existsSync() ? ws : h;
}

/// `/home/x/workspace` → `~/workspace`.
String tildePath(String path, {String? home}) {
  final h = home ?? Platform.environment['HOME'];
  if (h == null || h.isEmpty) return path;
  if (path == h) return '~';
  return path.startsWith('$h/') ? '~${path.substring(h.length)}' : path;
}
