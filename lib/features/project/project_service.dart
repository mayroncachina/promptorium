import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/git_root.dart';
import '../../core/git/git_service.dart';
import '../../core/git/repo_setup.dart';
import '../../data/providers.dart';
import '../prompt/conversation_manager.dart';
import '../review/review_host.dart' show detectReviewHost, remoteHost;
import '../sessions/session_manager.dart';
import '../specs/spec_service.dart';
import 'cost_estimate.dart';
import 'project_config.dart';
import 'project_plan.dart';
import 'project_templates.dart';
import 'spec_auto_planner.dart';
import 'stack_commands.dart';

class ProjectException implements Exception {
  const ProjectException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Folder names accepted by "Novo projeto" (no separators, no leading dot).
final projectNamePattern = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9._-]*$');

/// Commit message of the plan files.
const planCommitMessage = 'Plano inicial do projeto';

/// Outcome of "Criar projeto".
@immutable
class MaterializeOutcome {
  const MaterializeOutcome({
    required this.specs,
    required this.files,
    this.firstSpec,
    this.commitError,
  });

  final List<Spec> specs;

  /// Paths written, relative to the workspace (`CLAUDE.md`, `specs/…`).
  final List<String> files;

  /// Spec of [Roadmap.firstSpec], as saved.
  final Spec? firstSpec;

  /// The commit failed (files and specs were created anyway).
  final String? commitError;
}

/// "Novo projeto" (folder + repository) and "Criar projeto" (plan files,
/// specs and commit).
class ProjectService {
  ProjectService(this._ref);

  final Ref _ref;

  /// Creates `<parent>/<name>`, runs `git init` on [branch] (with a first
  /// commit and, optionally, `origin`), adds it as the active workspace and
  /// starts its plan. An existing empty folder is reused.
  ///
  /// The config.yml of the first commit always has `branch-base:` (SPEC-072
  /// R6, P5) and, for a GitHub / GitLab remote, `hospedagem:` (R22).
  Future<Workspace> createProject({
    required String parent,
    required String name,
    String? remoteUrl,
    ProjectTemplate? template,
    bool plan = true,
    String branch = 'main',
    int customStackCalls = 0,
  }) async {
    final n = name.trim();
    if (n.isEmpty) throw const ProjectException('Informe o nome da pasta.');
    if (!projectNamePattern.hasMatch(n)) {
      throw const ProjectException(
        'Use só letras, números, ponto, hífen e sublinhado no nome da pasta.',
      );
    }
    final base = expandHome(parent.trim());
    if (base.isEmpty || !Directory(base).isAbsolute) {
      throw const ProjectException('Escolha onde criar a pasta.');
    }
    if (!await Directory(base).exists()) {
      throw ProjectException('A pasta $base não existe.');
    }
    final path = base.endsWith('/') ? '$base$n' : '$base/$n';
    final dir = Directory(path);
    final setup = _ref.read(repoSetupProvider);
    final b = branch.trim().isEmpty ? 'main' : branch.trim();
    if (await setup.checkBranchName(b) case final why?) {
      throw ProjectException(why);
    }
    final kind = await FileSystemEntity.type(path);
    if (kind != FileSystemEntityType.notFound &&
        kind != FileSystemEntityType.directory) {
      throw ProjectException('Já existe um arquivo em $path.');
    }
    // A folder left by a failed creation (.git without commits, template
    // files) is accepted, so "Criar" can be retried (R21).
    if (kind == FileSystemEntityType.directory &&
        !await setup.isCreationLeftover(path)) {
      throw ProjectException('$path já existe e não está vazia.');
    }
    // The first commit needs a git identity: checked before anything is
    // created (R21).
    try {
      await setup.checkIdentity(base);
    } catch (e) {
      throw ProjectException(repoSetupError(e));
    }
    if (kind == FileSystemEntityType.notFound) await dir.create();
    // Template files first: the initial commit carries them (UX v2, U7).
    final t = template;
    await ProjectConfig.save(
      path,
      initialConfig(t?.config ?? const ProjectConfig(), b, remoteUrl),
    );
    if (t != null && !t.isEmpty) {
      if (t.claudeMd case final md?) {
        await File('$path/CLAUDE.md').writeAsString(md);
      }
    }
    try {
      await setup.init(path, remoteUrl: remoteUrl, branch: b);
    } catch (e) {
      throw ProjectException(repoSetupError(e));
    }
    final ws = await _ref.read(workspaceActionsProvider).addFolder(path);
    // The proposals of the "Outro…" modal count in the cost (SPEC-072 R19).
    await recordPlannerCalls(_ref, ws.id, 'outro', customStackCalls);
    if (plan) {
      await _ref.read(projectPlansRepoProvider).start(ws.id);
      final commands = t == null
          ? const StackCommands()
          : commandsOfConfig(t.config);
      if (t != null && (t.decisions.isNotEmpty || !commands.isEmpty)) {
        // The planner keeps pinned choices and commands (SPEC-072 R11).
        await _ref
            .read(projectPlansRepoProvider)
            .update(
              ws.id,
              ProjectPlansCompanion(
                data: Value(
                  ProjectPlanData(
                    stack: StackPlan(
                      decisions: t.decisions,
                      commands: commands,
                      scaffold: t.scaffold,
                    ),
                  ).encode(),
                ),
              ),
            );
      }
    }
    return ws;
  }

  Future<DeleteSummary> deleteSummary(Workspace ws) async {
    final sessions = await _ref
        .read(sessionsRepoProvider)
        .watchByWorkspace(ws.id)
        .first;
    final tasks = await _ref
        .read(tasksRepoProvider)
        .watchByWorkspace(ws.id)
        .first;
    final specs = await _ref
        .read(specsRepoProvider)
        .watchByWorkspace(ws.id)
        .first;
    return (
      sessions: sessions.length,
      tasks: tasks.length,
      specs: specs.length,
      worktrees: sessions.where((s) => s.worktreePath != ws.path).length,
    );
  }

  /// "Apagar projeto": stops its live sessions and conversations, removes the
  /// session worktrees, moves the project folder to the trash and removes
  /// the workspace with everything the app keeps about it (plan, specs,
  /// tasks, sessions, conversations — database cascade). Nothing is removed
  /// from the app when the folder cannot be trashed.
  Future<void> deleteProject(Workspace ws) async {
    if (isUnsafeProjectPath(ws.path)) {
      throw ProjectException('Por segurança, ${ws.path} não pode ser apagada.');
    }
    _ref.read(specAutoPlannerProvider.notifier).forget(ws.id);
    final sessions = await _ref
        .read(sessionsRepoProvider)
        .watchByWorkspace(ws.id)
        .first;
    final manager = _ref.read(sessionManagerProvider.notifier);
    for (final s in sessions) {
      await manager.release(s.id);
    }
    final conversations = await _ref
        .read(conversationsRepoProvider)
        .watchByWorkspace(ws.id)
        .first;
    final chats = _ref.read(conversationManagerProvider.notifier);
    for (final c in conversations) {
      await chats.stop(c.id);
    }
    final git = _ref.read(gitServiceFactoryProvider)(ws.path);
    for (final s in sessions) {
      final wt = s.worktreePath;
      if (wt == ws.path || !await Directory(wt).exists()) continue;
      try {
        await git.removeWorktree(wt, force: true);
      } catch (_) {
        // Not a worktree of this repository any more: delete only folders
        // the app created (under its worktrees base).
        if (wt.startsWith('${git.worktreesBase}/')) {
          await Directory(wt).delete(recursive: true);
        }
      }
    }
    if (await Directory(ws.path).exists()) {
      await _ref.read(trashFolderProvider)(ws.path);
    }
    await _ref.read(workspaceActionsProvider).remove(ws.id);
  }

  /// Whether the workspace already has a `CLAUDE.md`.
  bool hasClaudeMd(Workspace ws) => File('${ws.path}/CLAUDE.md').existsSync();

  /// Whether that `CLAUDE.md` is still the template's minimal one (R23).
  bool hasTemplateClaudeMd(Workspace ws) => templateClaudeMd(ws.path) != null;

  /// Writes the CLAUDE.md (when [writeClaudeMd]) and one approved spec file
  /// per roadmap spec (`depende-de` translated to `SPEC-NNN`) and, when
  /// [commit], commits those files on the current branch. The specs show up
  /// in the Quadro. Marks the plan as done.
  Future<MaterializeOutcome> materialize(
    Workspace ws, {
    bool writeClaudeMd = true,
    bool commit = true,
  }) async {
    final plans = _ref.read(projectPlansRepoProvider);
    final row = await plans.get(ws.id);
    if (row == null) throw const ProjectException('Não há plano.');
    if (row.materializedAt != null) {
      throw const ProjectException('O projeto já foi criado.');
    }
    final data = ProjectPlanData.decode(row.data);
    final roadmap = data.roadmap.normalized();
    if (!roadmap.isReady) {
      throw const ProjectException('Gere o roadmap antes de criar.');
    }

    final files = <String>[];
    final claudeMd = data.stack.claudeMd.trim();
    if (writeClaudeMd && claudeMd.isNotEmpty) {
      await File('${ws.path}/CLAUDE.md').writeAsString('$claudeMd\n');
      files.add('CLAUDE.md');
    }

    // The stack's commands fill the empty keys of the config.yml
    // (SPEC-072 R13).
    final merge = mergeStackCommands(
      ProjectConfig.loadSync(ws.path),
      data.stack.commands,
    );
    if (merge.changed) {
      await ProjectConfig.save(ws.path, merge.config);
      _ref.invalidate(projectConfigProvider(ws.path));
      files.add(ProjectConfig.filePath);
    }

    final specService = _ref.read(specServiceProvider);
    final specsRepo = _ref.read(specsRepoProvider);
    final specs = <Spec>[];
    // Specs of an earlier try that failed halfway are reused, not
    // duplicated (R22); new ones are recorded on the plan as they are
    // written.
    final created = {...data.created};
    for (final s in roadmap.specs) {
      final previous = created[s.code];
      var spec = previous == null
          ? null
          : await specsRepo.getByCode(ws.id, previous);
      if (spec != null && !File('${ws.path}/${spec.path}').existsSync()) {
        spec = null;
      }
      if (spec != null && spec.inTray) {
        await specsRepo.setInTray([spec.id], false);
        spec = await specsRepo.getById(spec.id) ?? spec;
      }
      if (spec == null) {
        // On the Quadro's Backlog, not in the Bandeja (R22).
        spec = await specService.create(
          ws,
          title: s.title,
          render: (code) => roadmapSpecMarkdown(s, code: code),
          inTray: false,
        );
        created[s.code] = spec.code;
        await plans.update(
          ws.id,
          ProjectPlansCompanion(
            data: Value(data.copyWith(created: created).encode()),
          ),
        );
      }
      specs.add(spec);
      files.add(spec.path);
    }
    // Dependencies need the final codes: a second pass writes `depende-de`.
    final codeOf = {
      for (var i = 0; i < roadmap.specs.length; i++)
        roadmap.specs[i].code: specs[i].code,
    };
    for (var i = 0; i < roadmap.specs.length; i++) {
      final deps = [
        for (final d in roadmap.specs[i].dependsOn)
          if (codeOf[d] != null) codeOf[d]!,
      ];
      if (deps.isEmpty) continue;
      final text = await specService.read(ws, specs[i]);
      if (text == null) continue;
      specs[i] = await specService.save(
        ws,
        specs[i],
        SpecDocument.parse(text).withMeta(dependsOn: deps),
      );
    }

    String? commitError;
    if (commit && files.isNotEmpty) {
      final git = _ref.read(gitServiceFactoryProvider)(ws.path);
      try {
        await git.git(['add', '--', ...files]);
        await git.git([
          'commit',
          '-q',
          '-m',
          planCommitMessage,
          '--',
          ...files,
        ]);
      } catch (e) {
        commitError = repoSetupError(e);
      }
    }

    await plans.update(
      ws.id,
      ProjectPlansCompanion(
        step: Value(ProjectStep.create.name),
        materializedAt: Value(DateTime.now()),
      ),
    );
    final first = roadmap.firstSpec;
    return MaterializeOutcome(
      specs: specs,
      files: files,
      firstSpec: first == null ? null : specs[roadmap.specs.indexOf(first)],
      commitError: commitError,
    );
  }
}

/// The config.yml of a new project: [base] (the template's) with
/// `branch-base:` (SPEC-072 R6) and, when [remoteUrl] is on GitHub or
/// GitLab, `hospedagem: {host, tipo}` (R22). Local and unrecognized hosts
/// write no `hospedagem:`.
ProjectConfig initialConfig(
  ProjectConfig base,
  String branch,
  String? remoteUrl,
) {
  var c = base.copyWith(baseBranch: () => branch);
  final url = remoteUrl?.trim() ?? '';
  if (url.isEmpty) return c;
  final type = detectReviewHost(url, base);
  final host = remoteHost(url);
  if (type != null && host != null) {
    c = c.copyWith(host: host, hostType: type);
  }
  return c;
}

/// Moves a folder to the desktop trash (recoverable). Overridden in tests.
typedef TrashFolder = Future<void> Function(String path);

Future<void> _gioTrash(String path) async {
  final ProcessResult r;
  try {
    r = await Process.run('gio', ['trash', '--', path]);
  } on ProcessException catch (e) {
    throw ProjectException(
      'Não foi possível mover para a lixeira (gio não encontrado): '
      '${e.message}',
    );
  }
  if (r.exitCode != 0) {
    throw ProjectException(
      'Não foi possível mover para a lixeira: ${'${r.stderr}'.trim()}',
    );
  }
}

final trashFolderProvider = Provider<TrashFolder>((ref) => _gioTrash);

/// Folders "Apagar projeto" refuses to trash: `/`, the home folder and its
/// parents, and relative paths.
bool isUnsafeProjectPath(String path, {String? home}) {
  final p = path.endsWith('/') && path.length > 1
      ? path.substring(0, path.length - 1)
      : path;
  if (!p.startsWith('/') || p == '/') return true;
  final h = home ?? Platform.environment['HOME'];
  if (h != null && h.isNotEmpty) {
    if (p == h || h.startsWith('$p/')) return true;
  }
  return p.split('/').where((x) => x.isNotEmpty).length < 2;
}

/// What "Apagar projeto" removes (shown in the confirmation).
typedef DeleteSummary = ({int sessions, int tasks, int specs, int worktrees});

final projectServiceProvider = Provider(ProjectService.new);
