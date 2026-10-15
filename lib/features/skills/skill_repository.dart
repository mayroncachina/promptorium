import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/enums.dart';
import '../agents/agent_file.dart';
import '../agents/agent_repository.dart' show agentHomeProvider;

export '../../data/db/enums.dart' show AgentScope;

/// Skills on disk: `~/.claude/skills/<name>/SKILL.md` (global) and
/// `<workspace>/.claude/skills/<name>/SKILL.md` (project). The SKILL.md is
/// read and written with [AgentFile] (same YAML frontmatter + body, unknown
/// fields kept).

class SkillException implements Exception {
  const SkillException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Skill names (folder names): lowercase letters, digits and hyphens.
final skillNamePattern = RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$');

/// Limit of the `description` field.
const skillDescriptionMax = 1024;

/// File the Promptorium keeps inside an installed skill folder: where it
/// came from (catalog repository, path, commit) and the content hash at
/// install time, to tell updates and local changes apart.
const skillOriginFile = '.promptorium-origin.json';

@immutable
class SkillOrigin {
  const SkillOrigin({
    required this.repo,
    required this.path,
    required this.commit,
    required this.hash,
    required this.installedAt,
  });

  /// `owner/name` of the catalog repository.
  final String repo;

  /// Folder in the repository (`skills/<name>`).
  final String path;

  /// Short commit of the folder when installed.
  final String commit;

  /// [skillHash] of the files when installed.
  final String hash;
  final DateTime installedAt;

  static SkillOrigin? fromJson(Object? j) {
    if (j is! Map) return null;
    final repo = j['repo'], path = j['path'], hash = j['hash'];
    if (repo is! String || path is! String || hash is! String) return null;
    return SkillOrigin(
      repo: repo,
      path: path,
      commit: '${j['commit'] ?? ''}',
      hash: hash,
      installedAt:
          DateTime.tryParse('${j['installedAt']}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, Object?> toJson() => {
    'repo': repo,
    'path': path,
    'commit': commit,
    'hash': hash,
    'installedAt': installedAt.toUtc().toIso8601String(),
  };
}

/// An installed skill.
@immutable
class SkillEntry {
  const SkillEntry({
    required this.scope,
    required this.dir,
    required this.file,
    required this.files,
    required this.hash,
    this.origin,
  });

  final AgentScope scope;

  /// Absolute path of the skill folder.
  final String dir;
  final AgentFile file;

  /// Files of the folder, relative and sorted (the origin file excluded).
  final List<String> files;

  /// [skillHash] of the folder now.
  final String hash;
  final SkillOrigin? origin;

  String get name => file.name ?? dir.split('/').last;
  String get description => file.description ?? '';
  String get skillMdPath => '$dir/SKILL.md';
  bool get isProject => scope == AgentScope.project;

  /// Installed from a catalog and changed here since.
  bool get hasLocalChanges => origin != null && origin!.hash != hash;
}

/// Relative paths of the files of [dir] (recursive, sorted), skipping the
/// origin file and dot folders (`.git`).
Future<List<String>> skillFiles(String dir) async {
  final root = Directory(dir);
  if (!await root.exists()) return const [];
  final out = <String>[];
  await for (final e in root.list(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final rel = e.path.substring(dir.length + 1);
    if (rel == skillOriginFile) continue;
    if (rel.split('/').any((p) => p.startsWith('.') && p != '.')) {
      // .git, .DS_Store… (dot files at any level)
      continue;
    }
    out.add(rel);
  }
  out.sort();
  return out;
}

/// Content hash of a skill folder (FNV-1a 64 over the sorted relative paths
/// and bytes). Same files = same hash, wherever the folder is.
Future<String> skillHash(String dir) async {
  // 64-bit arithmetic wraps on the Dart VM (the offset basis is negative
  // as an int64; only the bits matter).
  var h = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  void add(List<int> bytes) {
    for (final b in bytes) {
      h ^= b;
      h *= prime;
    }
  }

  for (final rel in await skillFiles(dir)) {
    add(utf8.encode(rel));
    add(const [0]);
    add(await File('$dir/$rel').readAsBytes());
    add(const [0]);
  }
  String half(int v) => (v & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  return '${half(h >> 32)}${half(h)}';
}

/// Copies [from] into [to] (created), skipping the origin file and dot
/// folders unless [keepOrigin].
Future<void> copySkillFolder(
  String from,
  String to, {
  bool keepOrigin = false,
}) async {
  await Directory(to).create(recursive: true);
  for (final rel in await skillFiles(from)) {
    final target = File('$to/$rel');
    await target.parent.create(recursive: true);
    await File('$from/$rel').copy(target.path);
  }
  if (keepOrigin) {
    final o = File('$from/$skillOriginFile');
    if (await o.exists()) await o.copy('$to/$skillOriginFile');
  }
}

/// Reads and writes the skills of `~/.claude/skills` and
/// `<workspace>/.claude/skills`. [home] is injectable for tests.
class SkillRepository {
  SkillRepository({required this.home, this.workspacePath});

  final String? home;
  final String? workspacePath;

  String? get globalDir => home == null ? null : '$home/.claude/skills';
  String? get projectDir =>
      workspacePath == null ? null : '$workspacePath/.claude/skills';

  String? dirFor(AgentScope scope) =>
      scope == AgentScope.global ? globalDir : projectDir;

  /// `<base>/<name>`.
  String folderFor(String name, AgentScope scope) {
    final base = dirFor(scope);
    if (base == null) {
      throw SkillException(
        scope == AgentScope.project
            ? 'Selecione um workspace para salvar skills de projeto.'
            : 'Diretório HOME desconhecido.',
      );
    }
    return '$base/$name';
  }

  /// Project skills first, then global; each sorted by name. Folders without
  /// a readable SKILL.md are skipped (the CLI ignores them too).
  Future<List<SkillEntry>> list() async => [
    ...await _scan(AgentScope.project),
    ...await _scan(AgentScope.global),
  ];

  Future<List<SkillEntry>> _scan(AgentScope scope) async {
    final base = dirFor(scope);
    if (base == null || !await Directory(base).exists()) return const [];
    final out = <SkillEntry>[];
    await for (final d in Directory(base).list(followLinks: true)) {
      if (d is! Directory) continue;
      final e = await load(d.path, scope);
      if (e != null) out.add(e);
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  /// The skill in [dir] (null when it has no valid SKILL.md).
  Future<SkillEntry?> load(String dir, AgentScope scope) async {
    final md = File('$dir/SKILL.md');
    if (!await md.exists()) return null;
    final AgentFile file;
    try {
      file = AgentFile.parse(await md.readAsString());
    } catch (_) {
      return null;
    }
    SkillOrigin? origin;
    final o = File('$dir/$skillOriginFile');
    if (await o.exists()) {
      try {
        origin = SkillOrigin.fromJson(jsonDecode(await o.readAsString()));
      } catch (_) {
        origin = null;
      }
    }
    return SkillEntry(
      scope: scope,
      dir: dir,
      file: file,
      files: await skillFiles(dir),
      hash: await skillHash(dir),
      origin: origin,
    );
  }

  static void validate(AgentFile file) {
    final name = file.name ?? '';
    if (!skillNamePattern.hasMatch(name)) {
      throw const SkillException(
        'Nome inválido: use letras minúsculas, números e hífens '
        '(ex.: revisar-migration).',
      );
    }
    final d = (file.description ?? '').trim();
    if (d.isEmpty) {
      throw const SkillException(
        'Informe o que a skill faz e quando usar (description).',
      );
    }
    if (d.length > skillDescriptionMax) {
      throw const SkillException(
        'A description passa de $skillDescriptionMax caracteres.',
      );
    }
  }

  /// Writes [file] as `<scope>/<name>/SKILL.md`. With [previousDir] (the
  /// skill being edited) a new name or scope moves the whole folder.
  /// Returns the folder.
  Future<String> save(
    AgentFile file,
    AgentScope scope, {
    String? previousDir,
  }) async {
    validate(file);
    final target = folderFor(file.name!, scope);
    if (previousDir != null && previousDir != target) {
      if (await Directory(target).exists()) {
        throw SkillException('Já existe uma skill em $target.');
      }
      await Directory(target).parent.create(recursive: true);
      try {
        await Directory(previousDir).rename(target);
      } on FileSystemException {
        // Other file system (e.g. ~ and the workspace on different disks).
        await copySkillFolder(previousDir, target, keepOrigin: true);
        await Directory(previousDir).delete(recursive: true);
      }
    } else if (previousDir == null && await Directory(target).exists()) {
      throw SkillException('Já existe uma skill em $target.');
    }
    await Directory(target).create(recursive: true);
    final md = File('$target/SKILL.md');
    final tmp = File('${md.path}.promptorium-tmp');
    await tmp.writeAsString(file.serialize(), flush: true);
    await tmp.rename(md.path);
    return target;
  }

  /// Copies the skill to the other scope ("Copiar para Global/Projeto").
  Future<String> copy(SkillEntry e, AgentScope to) async {
    final target = folderFor(e.name, to);
    if (await Directory(target).exists()) {
      throw SkillException('Já existe uma skill em $target.');
    }
    await copySkillFolder(e.dir, target, keepOrigin: true);
    return target;
  }

  /// Deletes the whole folder (the UI asks first).
  Future<void> delete(String dir) async {
    final d = Directory(dir);
    if (await d.exists()) await d.delete(recursive: true);
  }

  Future<void> writeOrigin(String dir, SkillOrigin origin) => File(
    '$dir/$skillOriginFile',
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(origin.toJson()));
}

/// Body of a new blank skill.
String blankSkillBody(String name) =>
    '''
# $name

## Quando usar

## Passo a passo

1.
''';

// --- providers -----------------------------------------------------------------

final skillRepositoryProvider = Provider.family<SkillRepository, String?>(
  (ref, workspacePath) => SkillRepository(
    home: ref.watch(agentHomeProvider),
    workspacePath: workspacePath,
  ),
);

/// Installed skills of a workspace (null = global only). Invalidate after
/// changes.
final skillEntriesProvider = FutureProvider.family<List<SkillEntry>, String?>(
  (ref, workspacePath) =>
      ref.watch(skillRepositoryProvider(workspacePath)).list(),
);
