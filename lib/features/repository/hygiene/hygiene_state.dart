import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/gh_cli.dart';
import '../../../core/git/git_service.dart';
import '../../../core/process/process_runner.dart';
import '../../../data/providers.dart';
import '../../sessions/session_manager.dart';
import '../repository_info.dart';
import 'hygiene_cleaner.dart';
import 'hygiene_scan.dart';

/// Sessions and specs of the active workspace, as the scan needs them
/// (overridden in tests).
final hygieneContextProvider = Provider<Future<HygieneContext> Function()>(
  (ref) =>
      () => _loadContext(ref),
);

Future<HygieneContext> _loadContext(Ref ref) async {
  final ws = ref.read(activeWorkspaceProvider);
  if (ws == null) return const HygieneContext();
  final sessions = await ref
      .read(sessionsRepoProvider)
      .watchByWorkspace(ws.id)
      .first;
  final specs = await ref.read(specsRepoProvider).watchByWorkspace(ws.id).first;
  final manager = ref.read(sessionManagerProvider);
  final live = [
    for (final s in sessions)
      if (manager.isAlive(s.id)) s,
  ];
  final codeById = {for (final s in specs) s.id: s.code};
  final byStart = [...sessions]
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  final refKeys = <String, RefKeyInfo>{};
  for (final s in byStart) {
    refKeys[s.id] = RefKeyInfo(
      closed: s.status == SessionStatus.merged,
      mergedAt: s.status == SessionStatus.merged ? s.endedAt : null,
      branch: s.worktreePath == ws.path ? null : s.branch,
    );
  }
  for (final spec in specs) {
    DateTime? mergedAt;
    for (final s in sessions) {
      if (s.specId == spec.id && s.status == SessionStatus.merged) {
        final e = s.endedAt;
        if (e != null && (mergedAt == null || e.isAfter(mergedAt))) {
          mergedAt = e;
        }
      }
    }
    refKeys[spec.code] = RefKeyInfo(
      closed:
          spec.stage == SpecStage.done ||
          spec.status == SpecStatus.done ||
          spec.status == SpecStatus.archived,
      mergedAt: mergedAt,
    );
  }
  return HygieneContext(
    liveBranches: {
      for (final s in live)
        if (s.worktreePath != ws.path) s.branch,
    },
    liveWorktrees: {for (final s in live) s.worktreePath},
    sessionByBranch: {
      for (final s in byStart)
        if (s.worktreePath != ws.path) s.branch: s.id,
    },
    specByBranch: {
      for (final s in specs)
        if (s.branch != null) s.branch!: s.code,
      for (final s in byStart)
        if (s.specId != null && codeById[s.specId] != null)
          s.branch: codeById[s.specId]!,
    },
    refKeys: refKeys,
  );
}

/// Runs the scan (overridden in tests to pin the clock).
final hygieneScannerProvider =
    Provider<Future<HygieneReport> Function(RepositoryInfo repo, {bool light})>(
      (ref) {
        return (repo, {light = false}) async => scanHygiene(
          git: ref.read(gitServiceFactoryProvider)(repo.path),
          repoPath: repo.path,
          defaultBranch: repo.defaultBranch,
          remote: repo.remote,
          gh: repo.githubSlug == null
              ? null
              : ref.read(ghCliFactoryProvider)(repo.path),
          context: await ref.read(hygieneContextProvider)(),
          run: ref.read(processRunnerProvider),
          light: light,
        );
      },
    );

/// Clock of the undo window (overridden in tests).
final hygieneClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

@immutable
class HygieneState {
  const HygieneState({
    this.report,
    this.scanning = false,
    this.cleaning = false,
    this.error,
    this.selected = const {},
    this.remote = const {},
    this.errors = const {},
    this.lastCleanup,
  });

  final HygieneReport? report;
  final bool scanning;
  final bool cleaning;
  final String? error;

  /// Ids of the selected items ([MergedBranch.id], [WorktreeItem.id]).
  final Set<String> selected;

  /// Branch names whose "também no remoto" box is checked.
  final Set<String> remote;

  /// Item id → why git refused it (kept across scans until it works).
  final Map<String, String> errors;

  /// The last cleanup, while it can be undone.
  final CleanupOutcome? lastCleanup;

  HygieneState copyWith({
    HygieneReport? report,
    bool? scanning,
    bool? cleaning,
    String? Function()? error,
    Set<String>? selected,
    Set<String>? remote,
    Map<String, String>? errors,
    CleanupOutcome? Function()? lastCleanup,
  }) => HygieneState(
    report: report ?? this.report,
    scanning: scanning ?? this.scanning,
    cleaning: cleaning ?? this.cleaning,
    error: error == null ? this.error : error(),
    selected: selected ?? this.selected,
    remote: remote ?? this.remote,
    errors: errors ?? this.errors,
    lastCleanup: lastCleanup == null ? this.lastCleanup : lastCleanup(),
  );

  /// Whether [b] can be selected now: not protected, or held only by a
  /// worktree that is selected too (it is removed first).
  bool branchSelectable(MergedBranch b) {
    final p = b.protection;
    if (p == null) return true;
    final wt = p.worktreePath;
    if (wt == null) return false;
    final item = report?.worktrees
        .where((w) => samePath(w.path, wt))
        .firstOrNull;
    return item != null &&
        item.protection == null &&
        selected.contains(item.id);
  }

  List<WorktreeItem> get selectedWorktrees => [
    for (final w in report?.worktrees ?? const <WorktreeItem>[])
      if (w.protection == null && selected.contains(w.id)) w,
  ];

  List<MergedBranch> get selectedBranches => [
    for (final b in report?.merged ?? const <MergedBranch>[])
      if (selected.contains(b.id) && branchSelectable(b)) b,
  ];

  List<MergedBranch> get selectedRemote => [
    for (final b in report?.merged ?? const <MergedBranch>[])
      if (b.remoteRef != null && remote.contains(b.name)) b,
  ];

  /// "Limpar selecionados (7)": worktrees and branches (local or remote).
  int get selectionCount =>
      selectedWorktrees.length +
      {
        for (final b in selectedBranches) b.name,
        for (final b in selectedRemote) b.name,
      }.length;
}

/// The Higiene tab of one repository: the last scan, the selection and the
/// cleanup (SPEC-047).
class HygieneController extends Notifier<HygieneState> {
  HygieneController(this.repo);

  final RepositoryInfo repo;

  @override
  HygieneState build() => const HygieneState();

  /// "Analisar de novo" (and the first scan when the tab opens).
  Future<void> scan() async {
    if (state.scanning) return;
    state = state.copyWith(scanning: true, error: () => null);
    try {
      final report = await ref.read(hygieneScannerProvider)(repo);
      if (!ref.mounted) return;
      final ids = {
        for (final b in report.merged) b.id,
        for (final w in report.worktrees) w.id,
      };
      final names = {
        for (final b in report.merged)
          if (b.remoteRef != null) b.name,
      };
      state = state.copyWith(
        report: report,
        scanning: false,
        selected: state.selected.intersection(ids),
        remote: state.remote.intersection(names),
        errors: {
          for (final MapEntry(:key, :value) in state.errors.entries)
            if (ids.contains(key) ||
                key.startsWith('remote:') ||
                key.startsWith('refs:'))
              key: value,
        },
      );
      ref
          .read(hygieneSummaryProvider(repo.path).notifier)
          .set(report.cleanable);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(scanning: false, error: () => '$e');
    }
  }

  void toggle(String id, bool on) {
    final report = state.report;
    if (report == null) return;
    final next = {...state.selected};
    on ? next.add(id) : next.remove(id);
    // A worktree carries the merged branch it holds.
    final wt = report.worktrees.where((w) => w.id == id).firstOrNull;
    if (wt != null && wt.branch != null) {
      final b = report.merged.where((b) => b.name == wt.branch).firstOrNull;
      if (b != null && b.protection?.worktreePath != null) {
        on ? next.add(b.id) : next.remove(b.id);
      }
    }
    state = state.copyWith(selected: next);
  }

  void toggleRemote(String branch, bool on) {
    final next = {...state.remote};
    on ? next.add(branch) : next.remove(branch);
    state = state.copyWith(remote: next);
  }

  /// Header box of a group: every selectable item on or off.
  void toggleAll(Iterable<String> ids, bool on) {
    final next = {...state.selected};
    on ? next.addAll(ids) : next.removeAll(ids);
    state = state.copyWith(selected: next);
  }

  HygieneCleaner _cleaner() => HygieneCleaner(
    ref.read(gitServiceFactoryProvider)(repo.path),
    remote: repo.remote,
    clock: ref.read(hygieneClockProvider),
  );

  /// Cleans the selection (after the confirmation), then scans again.
  Future<CleanupOutcome?> clean({bool deleteRemote = false}) => _run(
    CleanupRequest(
      worktrees: state.selectedWorktrees,
      branches: state.selectedBranches,
      remoteBranches: state.selectedRemote,
      deleteRemote: deleteRemote,
    ),
    clearSelection: true,
  );

  /// "Limpar" of one spec of Refs internas, or "Limpar todas".
  Future<CleanupOutcome?> cleanRefs(List<RefGroup> groups) =>
      _run(CleanupRequest(refs: groups));

  Future<CleanupOutcome?> _run(
    CleanupRequest request, {
    bool clearSelection = false,
  }) async {
    if (state.cleaning || request.isEmpty) return null;
    state = state.copyWith(cleaning: true);
    CleanupOutcome? outcome;
    try {
      outcome = await _cleaner().clean(request);
    } catch (e) {
      if (ref.mounted) {
        state = state.copyWith(cleaning: false, error: () => '$e');
      }
      return null;
    }
    if (!ref.mounted) return outcome;
    final done = {
      for (final w in outcome.worktrees) 'wt:${w.path}',
      for (final b in outcome.branches) 'branch:${b.name}',
    };
    state = state.copyWith(
      cleaning: false,
      selected: clearSelection
          ? {
              for (final id in state.selected)
                if (outcome.errors.containsKey(id)) id,
            }
          : null,
      remote: clearSelection ? <String>{} : null,
      errors: {
        for (final MapEntry(:key, :value) in state.errors.entries)
          if (!done.contains(key)) key: value,
        ...outcome.errors,
      },
      lastCleanup: outcome.undoable ? () => outcome : null,
    );
    await scan();
    return outcome;
  }

  /// "Desfazer" of the last cleanup (R7).
  Future<UndoOutcome?> undo() async {
    final last = state.lastCleanup;
    if (last == null) return null;
    state = state.copyWith(lastCleanup: () => null);
    final result = await _cleaner().undo(last);
    if (ref.mounted) await scan();
    return result;
  }
}

final hygieneProvider =
    NotifierProvider.family<HygieneController, HygieneState, RepositoryInfo>(
      HygieneController.new,
    );

/// Merged branches + worktrees of closed specs of a repository (by its main
/// path),
/// for the Início card (R8). Read with a light scan the first time; the tab
/// keeps it up to date.
class HygieneSummary extends AsyncNotifier<int?> {
  HygieneSummary(this.path);

  final String path;

  @override
  Future<int?> build() async {
    try {
      final repo = await ref.watch(repositoryInfoProvider(path).future);
      return (await ref.read(hygieneScannerProvider)(
        repo,
        light: true,
      )).cleanable;
    } catch (e) {
      debugPrint('higiene: resumo falhou — $e');
      return null;
    }
  }

  void set(int count) => state = AsyncData(count);
}

final hygieneSummaryProvider =
    AsyncNotifierProvider.family<HygieneSummary, int?, String>(
      HygieneSummary.new,
    );

/// The Início card shows above this many items (R8).
const hygieneCardThreshold = 20;

/// How long "Dispensar" hides the card.
const hygieneDismissal = Duration(days: 30);

/// App setting with the end of the card's dismissal (ISO date), per
/// repository.
String hygieneDismissKey(String repoPath) => 'hygiene.dismissedUntil.$repoPath';

/// Whether the card of [repoPath] is dismissed at [now].
bool hygieneDismissed(
  Map<String, String> settings,
  String repoPath,
  DateTime now,
) {
  final until = DateTime.tryParse(settings[hygieneDismissKey(repoPath)] ?? '');
  return until != null && now.isBefore(until);
}
