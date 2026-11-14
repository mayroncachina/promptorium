import 'dart:io';

import 'package:drift/drift.dart' show Value;

import '../../core/git/git_service.dart';
import '../../data/db/app_database.dart';
import '../../data/repos/specs_repo.dart';

/// Renumbering at the merge (SPEC-069 R12): a VIBE, or the spec it became,
/// is written in its own worktree with a number reserved in this machine's
/// database. When the base already has a file with that number (written
/// elsewhere), the file and its references move to the next free number
/// before the merge, in a commit of the worktree. Returns the new code, or
/// null when nothing changed.
Future<String?> renumberIfTaken({
  required SpecsRepo repo,
  required Workspace ws,
  required Spec spec,
  required GitService main,
  required GitService worktree,
  required String base,
}) async {
  final kind = SpecKind.ofCode(spec.code);
  final wt = spec.worktreePath;
  if (kind == null || wt == null) return null;
  // A file that already is in the workspace is not new to the base.
  if (File('${ws.path}/${spec.path}').existsSync()) return null;
  final own = File('$wt/${spec.path}');
  if (!own.existsSync()) return null;
  final slash = spec.path.lastIndexOf('/');
  final dir = slash < 0 ? '' : spec.path.substring(0, slash);
  final name = spec.path.substring(slash + 1);
  final List<String> inBase;
  try {
    inBase = (await main.git(['ls-tree', '--name-only', base, '--', '$dir/']))
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  } on GitException {
    return null;
  }
  String baseName(String p) => p.substring(p.lastIndexOf('/') + 1);
  final code = spec.code;
  final taken = inBase.any((p) {
    final n = baseName(p);
    return p != spec.path && (n.startsWith('$code-') || n == '$code.md');
  });
  if (!taken) return null;
  var max = await repo.maxNumber(ws.id, kind: kind);
  final re = RegExp('^${kind.prefix}-(\\d+)');
  for (final p in inBase) {
    final m = re.firstMatch(baseName(p));
    if (m != null) {
      final n = int.parse(m.group(1)!);
      if (n > max) max = n;
    }
  }
  final next = '${kind.prefix}-${(max + 1).toString().padLeft(3, '0')}';
  final rel = '${dir.isEmpty ? '' : '$dir/'}${name.replaceFirst(code, next)}';
  final text = own.readAsStringSync().replaceAll(
    RegExp('\\b${RegExp.escape(code)}\\b'),
    next,
  );
  File('$wt/$rel').writeAsStringSync(text);
  own.deleteSync();
  await worktree.git(['add', '-A', '--', spec.path, rel]);
  await worktree.git([
    'commit',
    '-q',
    '-m',
    '$next: renumerada ($code já existia em $base)',
    '--',
    spec.path,
    rel,
  ]);
  await repo.update(
    spec.id,
    SpecsCompanion(code: Value(next), path: Value(rel)),
  );
  await repo.reserve(ws.id, next);
  return next;
}
