import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/git/git_root.dart';
import '../../core/git/git_service.dart';
import '../../core/git/repo_setup.dart';
import '../../data/providers.dart';
import '../../data/repos/tasks_repo.dart';
import '../specs/spec_service.dart';
import 'project_plan.dart';

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
    required this.tasks,
    required this.files,
    this.firstTask,
    this.commitError,
  });

  final List<Spec> specs;
  final List<Task> tasks;

  /// Paths written, relative to the workspace (`CLAUDE.md`, `specs/…`).
  final List<String> files;

  /// Task of [Roadmap.firstTask], as saved.
  final Task? firstTask;

  /// The commit failed (files, specs and tasks were created anyway).
  final String? commitError;
}

/// "Novo projeto" (folder + repository) and "Criar projeto" (plan files,
/// specs, tasks and commit).
class ProjectService {
  ProjectService(this._ref);

  final Ref _ref;

  /// Creates `<parent>/<name>`, runs `git init` (with an empty first commit
  /// and, optionally, `origin`), adds it as the active workspace and starts
  /// its plan. An existing empty folder is reused.
  Future<Workspace> createProject({
    required String parent,
    required String name,
    String? remoteUrl,
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
    switch (await FileSystemEntity.type(path)) {
      case FileSystemEntityType.notFound:
        await dir.create();
      case FileSystemEntityType.directory:
        if (!await dir.list().isEmpty) {
          throw ProjectException('$path já existe e não está vazia.');
        }
      default:
        throw ProjectException('Já existe um arquivo em $path.');
    }
    try {
      await _ref.read(repoSetupProvider).init(path, remoteUrl: remoteUrl);
    } catch (e) {
      throw ProjectException(repoSetupError(e));
    }
    final ws = await _ref.read(workspaceActionsProvider).addFolder(path);
    await _ref.read(projectPlansRepoProvider).start(ws.id);
    return ws;
  }

  /// Whether the workspace already has a `CLAUDE.md`.
  bool hasClaudeMd(Workspace ws) => File('${ws.path}/CLAUDE.md').existsSync();

  /// Writes the CLAUDE.md (when [writeClaudeMd]) and one approved spec file
  /// per roadmap spec, inserts the tasks (`TASK-NNN`, dependencies
  /// translated) and, when [commit], commits those files on the current
  /// branch. Marks the plan as done.
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

    final specService = _ref.read(specServiceProvider);
    final specs = <Spec>[];
    for (final s in roadmap.specs) {
      final spec = await specService.create(
        ws,
        title: s.title,
        render: (code) => roadmapSpecMarkdown(s, code: code),
      );
      specs.add(spec);
      files.add(spec.path);
    }

    final repo = _ref.read(tasksRepoProvider);
    final saved = await repo.transaction(() async {
      final first = await repo.maxNumber(ws.id) + 1;
      final codes = <String, String>{};
      var i = 0;
      for (final t in roadmap.tasks) {
        codes[t.code] = TasksRepo.codeFor(first + i++);
      }
      final out = <String, Task>{};
      for (var s = 0; s < roadmap.specs.length; s++) {
        for (final t in roadmap.specs[s].tasks) {
          out[t.code] = await repo.insert(
            workspaceId: ws.id,
            specId: specs[s].id,
            code: codes[t.code]!,
            title: t.title.length > 120 ? t.title.substring(0, 120) : t.title,
            body: t.description.isEmpty ? null : t.description,
            requirement: t.requirement.isEmpty ? null : t.requirement,
            dependsOn: [
              for (final d in t.dependsOn)
                if (codes[d] != null) codes[d]!,
            ],
          );
        }
      }
      return out;
    });

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
    final first = roadmap.firstTask;
    return MaterializeOutcome(
      specs: specs,
      tasks: saved.values.toList(),
      files: files,
      firstTask: first == null ? null : saved[first.code],
      commitError: commitError,
    );
  }
}

final projectServiceProvider = Provider(ProjectService.new);
