import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/process/process_runner.dart';
import '../../data/providers.dart';
import '../agents/agent_file.dart';
import '../agents/agent_repository.dart' show agentHomeProvider;
import 'skill_repository.dart';

/// Skill catalogs: GitHub repositories with one folder per skill
/// (`<name>/SKILL.md` or `skills/<name>/SKILL.md`, + support files). Each one is cloned to
/// `~/.promptorium/catalogs/<owner>__<name>` (a cache the app owns: reset to
/// the remote on every sync) — plain git, so private repositories use the
/// user's credentials and there is no API rate limit. Catalogs are
/// read-only for the app: it only downloads and updates skills from them.

/// `owner/name` of a GitHub repository.
@immutable
class CatalogRepo {
  const CatalogRepo(this.owner, this.name);

  final String owner;
  final String name;

  String get slug => '$owner/$name';
  String get cloneUrl => 'https://github.com/$slug.git';
  String get webUrl => 'https://github.com/$slug';

  static final _part = RegExp(r'^[A-Za-z0-9._-]+$');

  /// `owner/name`, `https://github.com/owner/name(.git)` or
  /// `git@github.com:owner/name.git` (null when not a GitHub repository).
  static CatalogRepo? parse(String input) {
    var s = input.trim();
    for (final p in [
      'https://github.com/',
      'http://github.com/',
      'git@github.com:',
      'github.com/',
    ]) {
      if (s.startsWith(p)) s = s.substring(p.length);
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('.git')) s = s.substring(0, s.length - 4);
    final parts = s.split('/');
    if (parts.length != 2) return null;
    final (o, n) = (parts[0], parts[1]);
    if (!_part.hasMatch(o) || !_part.hasMatch(n) || n == '.' || n == '..') {
      return null;
    }
    return CatalogRepo(o, n);
  }

  @override
  bool operator ==(Object other) =>
      other is CatalogRepo &&
      other.owner.toLowerCase() == owner.toLowerCase() &&
      other.name.toLowerCase() == name.toLowerCase();

  @override
  int get hashCode => Object.hash(owner.toLowerCase(), name.toLowerCase());

  @override
  String toString() => slug;
}

/// The catalog the app starts with.
const defaultCatalog = CatalogRepo('mayroncachina', 'promptorium-skills');

/// A skill of a catalog.
@immutable
class CatalogSkill {
  const CatalogSkill({
    required this.name,
    required this.description,
    required this.dir,
    required this.files,
    required this.hash,
    required this.commit,
    String? path,
  }) : path = path ?? 'skills/$name';

  final String name;
  final String description;

  /// Absolute folder in the clone.
  final String dir;
  final List<String> files;
  final String hash;

  /// Short commit that last touched the folder.
  final String commit;

  /// Folder in the repository: `<name>` or `skills/<name>`.
  final String path;
}

/// What the clone holds.
@immutable
class CatalogSnapshot {
  const CatalogSnapshot({
    required this.repo,
    required this.cloned,
    this.empty = false,
    this.head,
    this.skills = const [],
    this.syncedAt,
  });

  final CatalogRepo repo;

  /// The repository was cloned (synced at least once).
  final bool cloned;

  /// The remote has no commits yet.
  final bool empty;

  /// Short commit of the default branch.
  final String? head;
  final List<CatalogSkill> skills;
  final DateTime? syncedAt;
}

class CatalogException implements Exception {
  const CatalogException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SkillCatalog {
  SkillCatalog({
    required this.baseDir,
    ProcessRunner? run,
    String Function(CatalogRepo)? urlFor,
  }) : _run = run ?? _defaultRun,
       _urlFor = urlFor ?? ((r) => r.cloneUrl);

  /// `~/.promptorium/catalogs`.
  final String baseDir;
  final ProcessRunner _run;

  /// Clone URL of a repository (tests point it to a local bare repo).
  final String Function(CatalogRepo) _urlFor;

  /// Never waits on a username/password prompt.
  static Future<ProcessResult> _defaultRun(String exe, List<String> args) =>
      Process.run(exe, args, environment: const {'GIT_TERMINAL_PROMPT': '0'});

  String cloneDir(CatalogRepo r) => '$baseDir/${r.owner}__${r.name}';

  Future<ProcessResult> _exec(String exe, List<String> args) async {
    try {
      return await _run(exe, args);
    } on ProcessException catch (e) {
      throw CatalogException('$exe não encontrado: ${e.message}');
    }
  }

  /// `git -C <clone> …`; throws [CatalogException] with git's last line.
  Future<String> _git(CatalogRepo r, List<String> args) async {
    final res = await _exec('git', ['-C', cloneDir(r), ...args]);
    if (res.exitCode != 0) throw CatalogException(_lastLine(res));
    return '${res.stdout}'.trim();
  }

  Future<bool> _gitOk(CatalogRepo r, List<String> args) async =>
      (await _exec('git', ['-C', cloneDir(r), ...args])).exitCode == 0;

  static String _lastLine(ProcessResult r) {
    final err = '${r.stderr}'.trim().isEmpty ? '${r.stdout}' : '${r.stderr}';
    final lines = err.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return 'falhou (código ${r.exitCode})';
    final l = lines.last.trim();
    if (l.contains('terminal prompts disabled') ||
        l.contains('could not read Username')) {
      return 'O GitHub pediu usuário e senha (repositório privado?). '
          'Configure um credential helper do git (ex.: gh auth setup-git) e '
          'tente de novo.';
    }
    return l;
  }

  /// Default branch of the remote (`origin/HEAD`), `main` when unknown.
  Future<String> defaultBranch(CatalogRepo r) async {
    final res = await _exec('git', [
      '-C',
      cloneDir(r),
      'symbolic-ref',
      '--short',
      'refs/remotes/origin/HEAD',
    ]);
    final s = '${res.stdout}'.trim();
    if (res.exitCode == 0 && s.startsWith('origin/')) {
      return s.substring('origin/'.length);
    }
    return 'main';
  }

  Future<bool> _remoteHas(CatalogRepo r, String branch) =>
      _gitOk(r, ['rev-parse', '-q', '--verify', 'refs/remotes/origin/$branch']);

  /// Clones the repository or resets the clone to the remote's default
  /// branch (any local leftover is discarded: the clone is a cache).
  Future<void> sync(CatalogRepo r) async {
    final dir = cloneDir(r);
    if (!await Directory('$dir/.git').exists()) {
      await Directory(baseDir).create(recursive: true);
      final res = await _exec('git', ['clone', '-q', '--', _urlFor(r), dir]);
      if (res.exitCode != 0) {
        throw CatalogException(
          'Não foi possível clonar ${r.slug}: ${_lastLine(res)}',
        );
      }
    } else {
      await _git(r, ['fetch', '-q', '--prune', 'origin']);
      // origin/HEAD may be missing (repository was empty when cloned).
      await _gitOk(r, ['remote', 'set-head', 'origin', '--auto']);
    }
    final branch = await defaultBranch(r);
    if (await _remoteHas(r, branch)) {
      await _git(r, ['checkout', '-q', '-B', branch, 'origin/$branch']);
      await _git(r, ['reset', '-q', '--hard', 'origin/$branch']);
      await _git(r, ['clean', '-q', '-fd']);
    }
    await File('$dir/.git/promptorium-synced')
        .writeAsString(DateTime.now().toUtc().toIso8601String());
  }

  /// What the clone holds now (no network).
  Future<CatalogSnapshot> read(CatalogRepo r) async {
    final dir = cloneDir(r);
    if (!await Directory('$dir/.git').exists()) {
      return CatalogSnapshot(repo: r, cloned: false);
    }
    DateTime? synced;
    final mark = File('$dir/.git/promptorium-synced');
    if (await mark.exists()) {
      synced = DateTime.tryParse((await mark.readAsString()).trim());
    }
    final headRes = await _exec('git', [
      '-C',
      dir,
      'rev-parse',
      '--short',
      'HEAD',
    ]);
    if (headRes.exitCode != 0) {
      return CatalogSnapshot(
        repo: r,
        cloned: true,
        empty: true,
        syncedAt: synced,
      );
    }
    final skills = <CatalogSkill>[];
    // `skills/<name>/` first, then `<name>/` at the root; a name already
    // seen is skipped.
    final seen = <String>{};
    for (final base in ['skills', '']) {
      final root = Directory(base.isEmpty ? dir : '$dir/$base');
      if (!await root.exists()) continue;
      await for (final d in root.list()) {
        if (d is! Directory) continue;
        final name = d.path.split('/').last;
        if (name.startsWith('.') || (base.isEmpty && name == 'skills')) {
          continue;
        }
        final md = File('${d.path}/SKILL.md');
        if (!await md.exists() || seen.contains(name)) continue;
        AgentFile file;
        try {
          file = AgentFile.parse(await md.readAsString());
        } catch (_) {
          continue;
        }
        seen.add(name);
        final path = base.isEmpty ? name : '$base/$name';
        final commit = await _exec('git', [
          '-C',
          dir,
          'log',
          '-1',
          '--format=%h',
          '--',
          path,
        ]);
        skills.add(
          CatalogSkill(
            name: name,
            description: file.description ?? '',
            path: path,
            dir: d.path,
            files: await skillFiles(d.path),
            hash: await skillHash(d.path),
            commit: '${commit.stdout}'.trim(),
          ),
        );
      }
    }
    skills.sort((a, b) => a.name.compareTo(b.name));
    return CatalogSnapshot(
      repo: r,
      cloned: true,
      head: '${headRes.stdout}'.trim(),
      skills: skills,
      syncedAt: synced,
    );
  }

  /// Copies [s] into [scope] and records where it came from. [overwrite]
  /// replaces an installed copy ("Atualizar").
  Future<String> install(
    CatalogSkill s,
    CatalogRepo r,
    SkillRepository dest,
    AgentScope scope, {
    bool overwrite = false,
  }) async {
    final target = dest.folderFor(s.name, scope);
    if (await Directory(target).exists()) {
      if (!overwrite) throw SkillException('Já existe uma skill em $target.');
      await Directory(target).delete(recursive: true);
    }
    await copySkillFolder(s.dir, target);
    await dest.writeOrigin(
      target,
      SkillOrigin(
        repo: r.slug,
        path: s.path,
        commit: s.commit,
        hash: s.hash,
        installedAt: DateTime.now(),
      ),
    );
    return target;
  }
}

// --- state ---------------------------------------------------------------------

final skillCatalogProvider = Provider<SkillCatalog>((ref) {
  final home = ref.watch(agentHomeProvider) ?? Directory.systemTemp.path;
  return SkillCatalog(baseDir: '$home/.promptorium/catalogs');
});

/// Key of the registered catalogs in `app_settings` (JSON list of slugs).
const catalogsSettingKey = 'skills.catalogs';

/// Registered catalog repositories (the default one first).
class CatalogRepos extends Notifier<List<CatalogRepo>> {
  @override
  List<CatalogRepo> build() {
    final raw = ref.watch(
      appSettingsProvider.select((m) => m[catalogsSettingKey]),
    );
    final out = <CatalogRepo>[defaultCatalog];
    if (raw != null) {
      try {
        final list = jsonDecode(raw);
        if (list is List) {
          for (final s in list) {
            final r = CatalogRepo.parse('$s');
            if (r != null && !out.contains(r)) out.add(r);
          }
        }
      } on FormatException {
        // keep the default
      }
    }
    return out;
  }

  Future<void> _store(List<CatalogRepo> repos) => ref
      .read(appSettingsProvider.notifier)
      .set(
        catalogsSettingKey,
        jsonEncode([
          for (final r in repos)
            if (r != defaultCatalog) r.slug,
        ]),
      );

  /// Adds `owner/name` (or a GitHub URL). Throws [CatalogException].
  Future<CatalogRepo> add(String input) async {
    final r = CatalogRepo.parse(input);
    if (r == null) {
      throw const CatalogException(
        'Use owner/nome ou o endereço do repositório no GitHub.',
      );
    }
    if (!state.contains(r)) await _store([...state, r]);
    return r;
  }

  Future<void> remove(CatalogRepo r) => _store([
    for (final x in state)
      if (x != r) x,
  ]);
}

final catalogReposProvider = NotifierProvider<CatalogRepos, List<CatalogRepo>>(
  CatalogRepos.new,
);

/// The clone of a catalog as it is on disk. Invalidate after a sync.
final catalogSnapshotProvider =
    FutureProvider.family<CatalogSnapshot, CatalogRepo>(
      (ref, repo) => ref.watch(skillCatalogProvider).read(repo),
    );
