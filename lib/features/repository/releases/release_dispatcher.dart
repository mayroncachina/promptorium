import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaml/yaml.dart';

import '../../../core/git/gh_cli.dart';
import '../../../data/providers.dart';
import '../../project/project_config.dart';
import '../../sessions/app_notifier.dart';

/// A workflow of `.github/workflows/` as the app reads it (R6).
@immutable
class ReleaseWorkflow {
  const ReleaseWorkflow({
    required this.file,
    this.name = '',
    this.dispatch = false,
    this.inputs = const [],
  });

  /// File name in `.github/workflows/` (`create-release.yml`).
  final String file;

  /// `name:` of the workflow (the file when absent).
  final String name;

  /// Has `workflow_dispatch` (can be run by `gh workflow run`).
  final bool dispatch;

  /// Inputs of `workflow_dispatch`.
  final List<String> inputs;

  String get label => name.isEmpty ? file : name;

  /// Can be the release workflow: dispatchable, "release" in the name or
  /// the file.
  bool get isReleaseCandidate =>
      dispatch &&
      (name.toLowerCase().contains('release') ||
          file.toLowerCase().contains('release'));

  @override
  bool operator ==(Object other) =>
      other is ReleaseWorkflow && other.file == file;

  @override
  int get hashCode => file.hashCode;
}

/// Parses one workflow file (null = not YAML / not a workflow).
ReleaseWorkflow? parseWorkflow(String file, String text) {
  Object? y;
  try {
    y = loadYaml(text);
  } catch (_) {
    return null;
  }
  if (y is! Map) return null;
  // YAML 1.1 readers turn `on` into true; package:yaml keeps the string.
  final on = y['on'] ?? y[true];
  Object? dispatch;
  var has = false;
  if (on == 'workflow_dispatch') {
    has = true;
  } else if (on is List) {
    has = on.contains('workflow_dispatch');
  } else if (on is Map && on.containsKey('workflow_dispatch')) {
    has = true;
    dispatch = on['workflow_dispatch'];
  }
  final inputs = dispatch is Map && dispatch['inputs'] is Map
      ? [for (final k in (dispatch['inputs'] as Map).keys) '$k']
      : const <String>[];
  return ReleaseWorkflow(
    file: file,
    name: y['name'] is String ? y['name'] as String : '',
    dispatch: has,
    inputs: inputs,
  );
}

/// The workflows of [root] (`.github/workflows/*.yml|yaml`), by file name.
List<ReleaseWorkflow> readWorkflows(String root) {
  final dir = Directory('$root/.github/workflows');
  if (!dir.existsSync()) return const [];
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.yml') || f.path.endsWith('.yaml'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final f in files)
      ?parseWorkflow(f.uri.pathSegments.last, f.readAsStringSync()),
  ];
}

/// Where the path came from (R6).
enum ReleasePathKind {
  /// `releases: workflow:` of `.promptorium/config.yml`.
  configured,

  /// The only dispatchable workflow with "release" in it.
  discovered,

  /// More than one candidate and nothing configured: the user picks.
  ambiguous,

  /// No workflow: `gh release create --draft`.
  draft,
}

/// How the release will be made (R6).
@immutable
class ReleasePath {
  const ReleasePath._(
    this.kind, {
    this.workflow,
    this.input = 'version',
    this.candidates = const [],
  });

  final ReleasePathKind kind;

  /// The workflow that runs (null for [ReleasePathKind.draft] and
  /// [ReleasePathKind.ambiguous]).
  final ReleaseWorkflow? workflow;

  /// The input that gets the version.
  final String input;

  /// The candidates of [ReleasePathKind.ambiguous].
  final List<ReleaseWorkflow> candidates;

  bool get isWorkflow => workflow != null;

  /// [workflow] picked among the [candidates] (R6: the dialog asks).
  ReleasePath choose(ReleaseWorkflow w, {String? configuredInput}) =>
      ReleasePath._(
        ReleasePathKind.discovered,
        workflow: w,
        input: inputFor(w, configuredInput),
      );

  /// `gh workflow run create-release.yml --ref main -f version=0.12.0`.
  String command({required String branch, required String version}) =>
      workflow == null
      ? 'gh release create <tag> --target $branch --draft'
      : 'gh workflow run ${workflow!.file} --ref $branch -f $input=$version';

  /// Where the choice came from, for the dialog (`de .promptorium/config.yml`).
  String get origin => switch (kind) {
    ReleasePathKind.configured => 'de ${ProjectConfig.filePath}',
    ReleasePathKind.discovered => 'achado em .github/workflows',
    ReleasePathKind.ambiguous => 'escolha um',
    ReleasePathKind.draft => 'sem workflow de release',
  };
}

/// The input of [w] that gets the version: the configured one, `version`
/// when the workflow has it (or declares none), its only input otherwise.
String inputFor(ReleaseWorkflow w, String? configured) {
  if (configured != null && configured.isNotEmpty) return configured;
  if (w.inputs.isEmpty || w.inputs.contains('version')) return 'version';
  return w.inputs.length == 1 ? w.inputs.single : 'version';
}

/// The path of the release (R6): the config, then the only candidate, then
/// a draft. Two or more candidates without config = [ReleasePathKind.ambiguous].
ReleasePath resolveReleasePath(
  ReleasesConfig config,
  List<ReleaseWorkflow> workflows,
) {
  final configured = config.workflow?.trim();
  if (configured != null && configured.isNotEmpty) {
    final file = configured.split('/').last;
    final w =
        workflows.where((w) => w.file == file).firstOrNull ??
        ReleaseWorkflow(file: file, dispatch: true);
    return ReleasePath._(
      ReleasePathKind.configured,
      workflow: w,
      input: inputFor(w, config.input),
    );
  }
  final candidates = [
    for (final w in workflows)
      if (w.isReleaseCandidate) w,
  ];
  if (candidates.length == 1) {
    final w = candidates.single;
    return ReleasePath._(
      ReleasePathKind.discovered,
      workflow: w,
      input: inputFor(w, config.input),
    );
  }
  if (candidates.length > 1) {
    return ReleasePath._(ReleasePathKind.ambiguous, candidates: candidates);
  }
  return const ReleasePath._(ReleasePathKind.draft);
}

/// Where a followed release is.
enum ReleaseRunStatus {
  /// Dispatched; the run is not listed yet.
  finding,
  running,
  success,
  failure,
  cancelled,

  /// No workflow: the draft is on GitHub (R6.3).
  draftCreated;

  bool get done => index >= success.index;
}

/// A release dispatched from the app and followed until it ends (R7, R8).
@immutable
class ReleaseRun {
  const ReleaseRun({
    required this.workspaceId,
    required this.repoPath,
    required this.version,
    required this.tag,
    required this.branch,
    required this.dispatchedAt,
    this.workflowFile,
    this.workflowName = '',
    this.runId,
    this.runUrl,
    this.status = ReleaseRunStatus.finding,
    this.jobs = const [],
    this.failedJob,
    this.failedStep,
    this.failedLog = const [],
    this.prUrl,
    this.prNumber,
    this.releaseUrl,
    this.error,
    this.checkedAt,
  });

  final int workspaceId;
  final String repoPath;

  /// `0.12.0`.
  final String version;

  /// `v0.12.0`.
  final String tag;
  final String branch;
  final DateTime dispatchedAt;

  /// Null for a draft.
  final String? workflowFile;
  final String workflowName;
  final int? runId;
  final String? runUrl;
  final ReleaseRunStatus status;
  final List<GhJob> jobs;

  /// R8: what failed and the last lines of `--log-failed`.
  final String? failedJob;
  final String? failedStep;
  final List<String> failedLog;

  /// R8: the PR of the version, when the workflow opened one.
  final String? prUrl;
  final int? prNumber;

  /// The draft (R6.3) or the published release.
  final String? releaseUrl;

  /// The last poll failed (shown, the poll goes on).
  final String? error;
  final DateTime? checkedAt;

  int get doneJobs => jobs.where((j) => j.status == 'completed').length;

  ReleaseRun copyWith({
    int? runId,
    String? runUrl,
    ReleaseRunStatus? status,
    List<GhJob>? jobs,
    String? failedJob,
    String? failedStep,
    List<String>? failedLog,
    String? prUrl,
    int? prNumber,
    String? releaseUrl,
    String? Function()? error,
    DateTime? checkedAt,
  }) => ReleaseRun(
    workspaceId: workspaceId,
    repoPath: repoPath,
    version: version,
    tag: tag,
    branch: branch,
    dispatchedAt: dispatchedAt,
    workflowFile: workflowFile,
    workflowName: workflowName,
    runId: runId ?? this.runId,
    runUrl: runUrl ?? this.runUrl,
    status: status ?? this.status,
    jobs: jobs ?? this.jobs,
    failedJob: failedJob ?? this.failedJob,
    failedStep: failedStep ?? this.failedStep,
    failedLog: failedLog ?? this.failedLog,
    prUrl: prUrl ?? this.prUrl,
    prNumber: prNumber ?? this.prNumber,
    releaseUrl: releaseUrl ?? this.releaseUrl,
    error: error == null ? this.error : error(),
    checkedAt: checkedAt ?? this.checkedAt,
  );

  /// What survives a restart (the jobs are read again).
  Map<String, Object?> toJson() => {
    'workspaceId': workspaceId,
    'repoPath': repoPath,
    'version': version,
    'tag': tag,
    'branch': branch,
    'dispatchedAt': dispatchedAt.toUtc().toIso8601String(),
    'workflowFile': workflowFile,
    'workflowName': workflowName,
    'runId': runId,
    'runUrl': runUrl,
    'status': status.name,
    'failedJob': failedJob,
    'failedStep': failedStep,
    'failedLog': failedLog,
    'prUrl': prUrl,
    'prNumber': prNumber,
    'releaseUrl': releaseUrl,
  };

  static ReleaseRun? fromJson(String text) {
    try {
      final j = jsonDecode(text);
      if (j is! Map) return null;
      return ReleaseRun(
        workspaceId: j['workspaceId'] as int,
        repoPath: j['repoPath'] as String,
        version: j['version'] as String,
        tag: j['tag'] as String,
        branch: j['branch'] as String,
        dispatchedAt: DateTime.parse(j['dispatchedAt'] as String),
        workflowFile: j['workflowFile'] as String?,
        workflowName: (j['workflowName'] as String?) ?? '',
        runId: j['runId'] as int?,
        runUrl: j['runUrl'] as String?,
        status:
            ReleaseRunStatus.values.asNameMap()[j['status']] ??
            ReleaseRunStatus.finding,
        failedJob: j['failedJob'] as String?,
        failedStep: j['failedStep'] as String?,
        failedLog: [
          for (final l in (j['failedLog'] as List?) ?? const []) '$l',
        ],
        prUrl: j['prUrl'] as String?,
        prNumber: j['prNumber'] as int?,
        releaseUrl: j['releaseUrl'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// The run of the dispatch: the first one created after [dispatchedAt]
/// (a little before counts: the clocks of the computer and GitHub differ).
GhRun? findDispatchedRun(List<GhRun> runs, DateTime dispatchedAt) {
  final after = [
    for (final r in runs)
      if (r.createdAt != null &&
          !r.createdAt!.isBefore(
            dispatchedAt.subtract(const Duration(seconds: 30)),
          ))
        r,
  ]..sort((a, b) => a.createdAt!.compareTo(b.createdAt!));
  return after.firstOrNull;
}

/// Starts the poll timer (overridden in tests to see the interval).
typedef ReleaseTicker = Timer Function(Duration every, void Function() tick);

final releaseTickerProvider = Provider<ReleaseTicker>(
  (ref) =>
      (every, tick) => Timer.periodic(every, (_) => tick()),
);

/// Polls with the Releases tab open (R7).
const releasePollOnScreen = Duration(seconds: 10);

/// Polls with the tab closed or the app in the background (R7).
const releasePollOffScreen = Duration(seconds: 60);

/// Gives up looking for the run after this long.
const releaseFindTimeout = Duration(minutes: 5);

/// Dispatches releases and follows their runs, one per workspace (R5–R8).
/// The run in progress is kept in the app settings, by workspace, so the
/// poll comes back when the app opens again ([resume]).
class ReleaseDispatcher extends Notifier<Map<int, ReleaseRun>> {
  static String settingKey(int workspaceId) => 'releases.run.$workspaceId';

  Timer? _timer;
  Duration? _every;
  bool _visible = false;
  bool _polling = false;

  @override
  Map<int, ReleaseRun> build() {
    ref.onDispose(() => _timer?.cancel());
    return const {};
  }

  GhCli _gh(String root) => ref.read(ghCliFactoryProvider)(root);

  AppSettingsController get _settings => ref.read(appSettingsProvider.notifier);

  /// The poll interval now in use (null = not polling).
  Duration? get interval => _every;

  /// The Releases tab tells when it is on screen: 10 s there, 60 s away.
  void setVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    _schedule();
    if (visible) unawaited(pollAll());
  }

  /// Reads the runs kept in the settings and polls them again (R7: the
  /// app was closed in the middle).
  Future<void> resume() async {
    final saved = <int, ReleaseRun>{};
    for (final e in ref.read(appSettingsProvider).entries) {
      if (!e.key.startsWith('releases.run.')) continue;
      final run = ReleaseRun.fromJson(e.value);
      if (run != null) saved[run.workspaceId] = run;
    }
    if (saved.isEmpty) return;
    state = {...state, ...saved};
    _schedule();
    await pollAll();
  }

  Future<void> _save(ReleaseRun run) async {
    state = {...state, run.workspaceId: run};
    await _settings.set(settingKey(run.workspaceId), jsonEncode(run.toJson()));
    _schedule();
  }

  void _schedule() {
    final active = state.values.any((r) => !r.status.done);
    final every = active
        ? (_visible ? releasePollOnScreen : releasePollOffScreen)
        : null;
    if (every == _every && (_timer != null) == (every != null)) return;
    _timer?.cancel();
    _timer = null;
    _every = every;
    if (every != null) {
      _timer = ref.read(releaseTickerProvider)(every, () => pollAll());
    }
  }

  /// Dispatches the release (R5, R6) and starts following it (R7). Throws
  /// [GhException] when `gh` refuses.
  Future<ReleaseRun> dispatch({
    required int workspaceId,
    required String repoPath,
    required String branch,
    required String version,
    required String tag,
    required ReleasePath path,
    required String changelog,
    DateTime? now,
  }) async {
    final gh = _gh(repoPath);
    final at = (now ?? DateTime.now()).toUtc();
    final w = path.workflow;
    if (w == null) {
      final dir = await Directory.systemTemp.createTemp('promptorium-notes-');
      try {
        final notes = File('${dir.path}/notes.md')
          ..writeAsStringSync(changelog);
        final url = await gh.releaseCreateDraft(
          tag,
          target: branch,
          notesFile: notes.path,
        );
        final run = ReleaseRun(
          workspaceId: workspaceId,
          repoPath: repoPath,
          version: version,
          tag: tag,
          branch: branch,
          dispatchedAt: at,
          status: ReleaseRunStatus.draftCreated,
          releaseUrl: url.isEmpty ? null : url,
        );
        await _save(run);
        return run;
      } finally {
        unawaited(dir.delete(recursive: true).catchError((_) => dir));
      }
    }
    await gh.workflowRun(w.file, ref: branch, inputs: {path.input: version});
    final run = ReleaseRun(
      workspaceId: workspaceId,
      repoPath: repoPath,
      version: version,
      tag: tag,
      branch: branch,
      dispatchedAt: at,
      workflowFile: w.file,
      workflowName: w.label,
    );
    await _save(run);
    return run;
  }

  /// Polls every run that is not over.
  Future<void> pollAll() async {
    if (_polling) return;
    _polling = true;
    try {
      for (final id in [...state.keys]) {
        await poll(id);
      }
    } finally {
      _polling = false;
    }
  }

  /// One poll of the run of [workspaceId] (R7): find it, then read its jobs,
  /// then finish it (R8).
  Future<void> poll(int workspaceId, {DateTime? now}) async {
    final saved = state[workspaceId];
    if (saved == null || saved.status.done || saved.workflowFile == null) {
      return;
    }
    var run = saved;
    final gh = _gh(run.repoPath);
    try {
      if (run.runId == null) {
        final found = findDispatchedRun(
          await gh.runList(workflow: run.workflowFile!),
          run.dispatchedAt,
        );
        if (found == null) {
          final waited = (now ?? DateTime.now()).toUtc().difference(
            run.dispatchedAt,
          );
          await _save(
            run.copyWith(
              checkedAt: now ?? DateTime.now(),
              error: () => waited > releaseFindTimeout
                  ? 'A execução não apareceu no GitHub. Confira em Actions.'
                  : null,
            ),
          );
          return;
        }
        run = run.copyWith(
          runId: found.id,
          runUrl: found.url,
          status: ReleaseRunStatus.running,
        );
        await _save(run);
      }
      final view = await gh.runView(run.runId!);
      run = run.copyWith(
        jobs: view.jobs,
        runUrl: view.url,
        checkedAt: now ?? DateTime.now(),
        error: () => null,
      );
      if (!view.completed) {
        await _save(run.copyWith(status: ReleaseRunStatus.running));
        return;
      }
      await _finish(run, view, gh);
    } on GhException catch (e) {
      await _save(run.copyWith(error: () => '$e', checkedAt: now));
    }
  }

  Future<void> _finish(ReleaseRun run, GhRunView view, GhCli gh) async {
    if (view.conclusion == 'success') {
      GhPullRequest? pr;
      try {
        pr =
            (await gh.prList(head: 'release/${run.tag}')).firstOrNull ??
            (await gh.prList(search: '${run.tag} in:title'))
                .where((p) => p.title.contains(run.tag))
                .firstOrNull;
      } on GhException {
        pr = null;
      }
      final done = run.copyWith(
        status: ReleaseRunStatus.success,
        prUrl: pr?.url,
        prNumber: pr?.number,
      );
      await _save(done);
      _notify('${run.tag} publicada', 'Release ${run.tag} pronta no GitHub.');
      return;
    }
    if (view.conclusion == 'cancelled') {
      await _save(run.copyWith(status: ReleaseRunStatus.cancelled));
      _notify('Release ${run.tag} cancelada', 'A execução foi cancelada.');
      return;
    }
    final job = view.jobs
        .where((j) => j.conclusion == 'failure' || j.conclusion == 'timed_out')
        .firstOrNull;
    final step = job?.steps.where((s) => s.conclusion == 'failure').firstOrNull;
    var log = const <String>[];
    try {
      log = await gh.runFailedLog(run.runId!);
    } on GhException {
      log = const [];
    }
    await _save(
      run.copyWith(
        status: ReleaseRunStatus.failure,
        failedJob: job?.name,
        failedStep: step?.name,
        failedLog: log,
      ),
    );
    _notify(
      'Release ${run.tag} falhou',
      job == null
          ? 'A execução terminou com ${view.conclusion}.'
          : 'Falhou no job ${job.name}${step == null ? '' : ' · ${step.name}'}.',
    );
  }

  void _notify(String title, String body) {
    unawaited(ref.read(appNotifierProvider).show(title, body));
    unawaited(
      ref
          .read(notificationsRepoProvider)
          .add(title: title, body: body, section: 'repository')
          .catchError((_) {}),
    );
  }

  /// "Cancelar execução" (R7), after the confirmation.
  Future<void> cancel(int workspaceId) async {
    final run = state[workspaceId];
    final id = run?.runId;
    if (run == null || id == null) return;
    await _gh(run.repoPath).runCancel(id);
    await poll(workspaceId);
  }

  /// Closes a finished run (the card goes back to "Não lançado").
  Future<void> dismiss(int workspaceId) async {
    final next = {...state}..remove(workspaceId);
    state = next;
    await _settings.remove(settingKey(workspaceId));
    _schedule();
  }
}

final releaseDispatcherProvider =
    NotifierProvider<ReleaseDispatcher, Map<int, ReleaseRun>>(
      ReleaseDispatcher.new,
    );
