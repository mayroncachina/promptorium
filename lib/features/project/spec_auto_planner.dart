import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/readonly_run.dart' show PlannerException;
import '../../core/git/git_service.dart';
import '../../core/git/repo_setup.dart';
import '../../data/providers.dart';
import '../board/autopilot.dart';
import '../board/board_rules.dart';
import '../specs/spec_action.dart';
import '../specs/spec_design.dart';
import '../specs/spec_service.dart';

/// Commit of the specs planned by the queue (SPEC-037 R7).
const specPlansCommitMessage = 'Plano das specs';

/// Commit of a spec planned again (SPEC-037 R13).
String planUpdatedCommitMessage(String code) => 'Plano atualizado: $code';

/// Why Executar and Planejar wait (SPEC-037 R10, R13).
const autoPlanQueueReason = 'Planejando as specs do projeto';
const autoPlanUpdateReason = 'Atualizando o plano';

/// Where a spec is in the queue.
enum AutoPlanStatus {
  queued('Na fila'),
  planning('Refinando e planejando'),
  ready('Pronta'),
  partial('Plano parcial'),
  failed('Falhou'),
  unplanned('Sem plano');

  const AutoPlanStatus(this.label);

  /// Text of the line (R8, R9).
  final String label;

  /// The spec got its plan in this queue.
  bool get planned => this == ready || this == partial;
}

/// One spec of the queue.
@immutable
class AutoPlanItem {
  const AutoPlanItem({
    required this.specId,
    required this.code,
    required this.title,
    required this.path,
    required this.dependsOn,
    this.status = AutoPlanStatus.queued,
    this.error,
    this.missingPlans = const [],
    this.addedRequirements = 0,
    this.questions = 0,
    this.previous,
  });

  final int specId;
  final String code;
  final String title;
  final String path;
  final List<String> dependsOn;
  final AutoPlanStatus status;

  /// Why it failed (R9).
  final String? error;

  /// Dependencies whose plan this spec did not get (R9: "Plano parcial").
  final List<String> missingPlans;

  /// Requirements and questions the round added (R12).
  final int addedRequirements;
  final int questions;

  /// What a dependent redone by "Tentar de novo" goes back to when it can
  /// no longer be redone; null on the other specs.
  final AutoPlanStatus? previous;

  AutoPlanItem copyWith({
    AutoPlanStatus? status,
    String? error,
    List<String>? missingPlans,
    int? addedRequirements,
    int? questions,
    AutoPlanStatus? previous,
  }) => AutoPlanItem(
    specId: specId,
    code: code,
    title: title,
    path: path,
    dependsOn: dependsOn,
    status: status ?? this.status,
    error: error,
    missingPlans: missingPlans ?? this.missingPlans,
    addedRequirements: addedRequirements ?? this.addedRequirements,
    questions: questions ?? this.questions,
    previous: previous,
  );
}

/// Whether the queue is working, was stopped or got to the end.
enum AutoPlanPhase { running, stopped, finished }

/// The queue of a workspace (R8): kept here, not in the widget, so it
/// survives leaving the screen.
@immutable
class AutoPlanQueue {
  const AutoPlanQueue({
    required this.items,
    required this.active,
    this.phase = AutoPlanPhase.running,
    this.stopping = false,
    this.commit = true,
    this.wroteClaudeMd = false,
    this.initialCommitError,
    this.committed = false,
    this.commitError,
    this.wantsFirstRun = false,
    this.firstRunSpecId,
    this.sessionOpened = false,
  });

  final List<AutoPlanItem> items;

  /// Specs of the current pass: the ones Executar and the editor wait for.
  final Set<int> active;
  final AutoPlanPhase phase;

  /// "Parar a fila" was pressed and the round is ending.
  final bool stopping;

  /// "Commitar" of the Revisar e criar step.
  final bool commit;
  final bool wroteClaudeMd;

  /// Failure of the commit "Plano inicial do projeto".
  final String? initialCommitError;

  /// A commit "Plano das specs" was made.
  final bool committed;
  final String? commitError;

  /// The first session was asked for, and the spec it waits for: cleared by
  /// "Parar a fila" (R10) and when the session opens.
  final bool wantsFirstRun;
  final int? firstRunSpecId;
  final bool sessionOpened;

  bool get running => phase == AutoPlanPhase.running;

  int get plannedCount => items.where((i) => i.status.planned).length;

  int get questions => items.fold(0, (a, i) => a + i.questions);

  bool get hasFailures => items.any((i) => i.status == AutoPlanStatus.failed);

  /// Finished, with a failure or a partial plan (R9).
  bool get withPending =>
      phase == AutoPlanPhase.finished &&
      items.any(
        (i) =>
            i.status == AutoPlanStatus.failed ||
            i.status == AutoPlanStatus.partial,
      );

  AutoPlanItem? get current =>
      items.where((i) => i.status == AutoPlanStatus.planning).firstOrNull;

  /// "3 de 7" of the spec being planned.
  String? get position {
    final c = current;
    return c == null ? null : '${items.indexOf(c) + 1} de ${items.length}';
  }

  AutoPlanQueue copyWith({
    List<AutoPlanItem>? items,
    Set<int>? active,
    AutoPlanPhase? phase,
    bool? stopping,
    bool? committed,
    String? commitError,
    bool clearCommitError = false,
    int? firstRunSpecId,
    bool clearFirstRun = false,
    bool? sessionOpened,
  }) => AutoPlanQueue(
    items: items ?? this.items,
    active: active ?? this.active,
    phase: phase ?? this.phase,
    stopping: stopping ?? this.stopping,
    commit: commit,
    wroteClaudeMd: wroteClaudeMd,
    initialCommitError: initialCommitError,
    committed: committed ?? this.committed,
    commitError: clearCommitError ? null : commitError ?? this.commitError,
    wantsFirstRun: wantsFirstRun,
    firstRunSpecId: clearFirstRun
        ? null
        : firstRunSpecId ?? this.firstRunSpecId,
    sessionOpened: sessionOpened ?? this.sessionOpened,
  );
}

/// A round of R13 that did not end well.
@immutable
class ReplanFailure {
  const ReplanFailure({
    required this.workspaceId,
    required this.specId,
    required this.code,
    required this.cause,
    this.commitFailed = false,
  });

  final int workspaceId;
  final int specId;
  final String code;
  final String cause;

  /// The plan was written, only its commit failed (D8): the spec does not
  /// have the previous plan any more.
  final bool commitFailed;
}

/// What holds a spec (R10, R13).
typedef SpecPlanLock = ({
  String reason,
  String strip,
  String? chip,
  bool writing,
});

@immutable
class AutoPlanState {
  const AutoPlanState({
    this.queues = const {},
    this.replanning = const {},
    this.failures = const {},
  });

  /// By workspace id.
  final Map<int, AutoPlanQueue> queues;

  /// Specs waiting for or in a round of R13.
  final Set<int> replanning;

  /// Last failed round of R13, by spec id.
  final Map<int, ReplanFailure> failures;

  /// Why [specId] cannot be run, planned or edited now; null = it can.
  SpecPlanLock? lockOf(int specId) {
    if (replanning.contains(specId)) {
      return (
        reason: autoPlanUpdateReason,
        strip:
            '$autoPlanUpdateReason desta spec. Ela fica bloqueada até a '
            'rodada terminar.',
        chip: null,
        writing: true,
      );
    }
    for (final q in queues.values) {
      if (!q.running || !q.active.contains(specId)) continue;
      final item = q.items.where((i) => i.specId == specId).firstOrNull;
      final waiting =
          item?.status == AutoPlanStatus.queued ||
          item?.status == AutoPlanStatus.planning;
      final at = switch ((q.position, q.current)) {
        (final p?, final c?) => ' · $p, em ${c.code}',
        _ => '',
      };
      return (
        reason: autoPlanQueueReason,
        strip:
            '$autoPlanQueueReason$at. Esta spec fica bloqueada até a fila '
            '${waiting ? 'passar por ela' : 'terminar'}.',
        chip: switch (item?.status) {
          AutoPlanStatus.queued => 'Na fila',
          AutoPlanStatus.planning => 'Planejando',
          _ => null,
        },
        writing: waiting,
      );
    }
    return null;
  }

  /// Workspaces whose queue ended with the first session still to open.
  List<int> get firstRunReady => [
    for (final e in queues.entries)
      if (e.value.phase == AutoPlanPhase.finished &&
          e.value.firstRunSpecId != null)
        e.key,
  ];
}

/// [specs] in the order of the roadmap, with every spec after the ones it
/// depends on (R6). A cycle keeps the order it had.
List<Spec> autoPlanOrder(List<Spec> specs) {
  final codes = {for (final s in specs) s.code};
  final placed = <String>{};
  final out = <Spec>[];
  var left = specs.toList();
  while (left.isNotEmpty) {
    final next = left
        .where(
          (s) => s.dependsOn.every(
            (d) => !codes.contains(d) || placed.contains(d),
          ),
        )
        .firstOrNull;
    final pick = next ?? left.first;
    out.add(pick);
    placed.add(pick.code);
    left = [
      for (final s in left)
        if (s.id != pick.id) s,
    ];
  }
  return out;
}

/// Codes of the [items] that depend, directly or not, on [roots].
Set<String> _dependentsOf(List<AutoPlanItem> items, Set<String> roots) {
  final out = <String>{};
  var changed = true;
  while (changed) {
    changed = false;
    for (final i in items) {
      if (out.contains(i.code) || roots.contains(i.code)) continue;
      if (i.dependsOn.any((d) => roots.contains(d) || out.contains(d))) {
        out.add(i.code);
        changed = true;
      }
    }
  }
  return out;
}

/// The queue of "Criar projeto" (R5–R10, R12) and the second round when the
/// dependencies of a spec finish (R13). One spec at a time per workspace: a
/// plan feeds the ones that depend on it (D5).
class SpecAutoPlanner extends Notifier<AutoPlanState> {
  @override
  AutoPlanState build() => const AutoPlanState();

  final Map<int, Completer<void>> _cancels = {};
  final Map<int, Set<String>> _uncommitted = {};

  /// R13: specs waiting for their round, by workspace.
  final Map<int, List<int>> _waiting = {};
  final Set<int> _draining = {};

  /// R13: specs already planned again (one round per spec).
  final Set<int> _replanned = {};

  SpecService get _service => ref.read(specServiceProvider);

  void _update(int workspaceId, AutoPlanQueue Function(AutoPlanQueue) f) {
    final q = state.queues[workspaceId];
    if (q == null || !ref.mounted) return;
    state = AutoPlanState(
      queues: {...state.queues, workspaceId: f(q)},
      replanning: state.replanning,
      failures: state.failures,
    );
  }

  void _updateItem(
    int workspaceId,
    int specId,
    AutoPlanItem Function(AutoPlanItem) f,
  ) => _update(
    workspaceId,
    (q) => q.copyWith(
      items: [
        for (final i in q.items)
          if (i.specId == specId) f(i) else i,
      ],
    ),
  );

  void _setRounds({Set<int>? replanning, Map<int, ReplanFailure>? failures}) {
    if (!ref.mounted) return;
    state = AutoPlanState(
      queues: state.queues,
      replanning: replanning ?? state.replanning,
      failures: failures ?? state.failures,
    );
  }

  // --- queue of "Criar projeto" ---------------------------------------------

  /// Plans [specs], the ones "Criar projeto" just created (R5). Completes
  /// when the queue stops or ends; nothing here throws. [firstRunSpecId] is
  /// the session to open at the end (R10, [takeFirstRun]).
  Future<void> start(
    Workspace ws,
    List<Spec> specs, {
    bool commit = true,
    bool wroteClaudeMd = false,
    String? initialCommitError,
    int? firstRunSpecId,
  }) {
    final items = [
      for (final s in autoPlanOrder(specs))
        AutoPlanItem(
          specId: s.id,
          code: s.code,
          title: s.title,
          path: s.path,
          dependsOn: s.dependsOn,
        ),
    ];
    state = AutoPlanState(
      queues: {
        ...state.queues,
        ws.id: AutoPlanQueue(
          items: items,
          active: {for (final i in items) i.specId},
          commit: commit,
          wroteClaudeMd: wroteClaudeMd,
          initialCommitError: initialCommitError,
          wantsFirstRun: firstRunSpecId != null,
          firstRunSpecId: firstRunSpecId,
        ),
      },
      replanning: state.replanning,
      failures: state.failures,
    );
    return _drain(ws);
  }

  /// "Parar a fila" (R8): ends the round in progress; the plans already
  /// written stay and go to the commit. The first session no longer opens
  /// (D10).
  void stop(int workspaceId) {
    final q = state.queues[workspaceId];
    if (q == null || !q.running || q.stopping) return;
    _update(
      workspaceId,
      (q) => q.copyWith(stopping: true, clearFirstRun: true),
    );
    final cancel = _cancels[workspaceId];
    if (cancel != null && !cancel.isCompleted) cancel.complete();
  }

  /// A deleted project: the queue stops and is forgotten.
  void forget(int workspaceId) {
    stop(workspaceId);
    _waiting.remove(workspaceId);
    if (!ref.mounted) return;
    state = AutoPlanState(
      queues: {...state.queues}..remove(workspaceId),
      replanning: state.replanning,
      failures: {
        for (final e in state.failures.entries)
          if (e.value.workspaceId != workspaceId) e.key: e.value,
      },
    );
  }

  /// "Retomar a fila" (R8): goes on with the specs left without a plan.
  Future<void> resume(Workspace ws) async {
    final q = state.queues[ws.id];
    if (q == null || q.phase != AutoPlanPhase.stopped) return;
    _update(
      ws.id,
      (q) => q.copyWith(
        phase: AutoPlanPhase.running,
        stopping: false,
        clearCommitError: true,
        active: {
          for (final i in q.items)
            if (i.status == AutoPlanStatus.unplanned) i.specId,
        },
        items: [
          for (final i in q.items)
            i.status == AutoPlanStatus.unplanned
                ? i.copyWith(status: AutoPlanStatus.queued)
                : i,
        ],
      ),
    );
    await _drain(ws);
  }

  /// "Tentar de novo" (R9): redoes the failed spec [specId] (null = all of
  /// them) and the specs that depend on it, with a new commit of only those.
  Future<void> retry(Workspace ws, {int? specId}) async {
    final q = state.queues[ws.id];
    if (q == null || q.running) return;
    final roots = {
      for (final i in q.items)
        if (i.status == AutoPlanStatus.failed &&
            (specId == null || i.specId == specId))
          i.code,
    };
    if (roots.isEmpty) return;
    final dependents = _dependentsOf(q.items, roots);
    bool redo(AutoPlanItem i) {
      if (roots.contains(i.code)) return true;
      // A dependent the queue did not get to stays for "Retomar a fila".
      return dependents.contains(i.code) &&
          (i.status.planned || i.status == AutoPlanStatus.failed);
    }

    _update(
      ws.id,
      (q) => q.copyWith(
        phase: AutoPlanPhase.running,
        stopping: false,
        clearCommitError: true,
        active: {
          for (final i in q.items)
            if (redo(i)) i.specId,
        },
        items: [
          for (final i in q.items)
            redo(i)
                ? i.copyWith(
                    status: AutoPlanStatus.queued,
                    missingPlans: const [],
                    previous: i.status.planned ? i.status : null,
                  )
                : i,
        ],
      ),
    );
    await _drain(ws);
  }

  /// The spec of the first session, once: the queue ended and it was not
  /// stopped (R10).
  int? takeFirstRun(int workspaceId) {
    final q = state.queues[workspaceId];
    final id = q?.firstRunSpecId;
    if (q == null || id == null || q.phase != AutoPlanPhase.finished) {
      return null;
    }
    _update(
      workspaceId,
      (q) => q.copyWith(clearFirstRun: true, sessionOpened: true),
    );
    return id;
  }

  Future<void> _drain(Workspace ws) async {
    while (ref.mounted) {
      final q = state.queues[ws.id];
      if (q == null) return;
      if (q.stopping) break;
      final next = q.items
          .where((i) => i.status == AutoPlanStatus.queued)
          .firstOrNull;
      if (next == null) break;
      await _plan(ws, next);
    }
    if (!ref.mounted) return;
    await _commit(ws);
    _update(ws.id, (q) {
      if (!q.stopping) return q.copyWith(phase: AutoPlanPhase.finished);
      return q.copyWith(
        phase: AutoPlanPhase.stopped,
        stopping: false,
        items: [
          for (final i in q.items)
            i.status == AutoPlanStatus.queued
                ? i.copyWith(
                    status: i.previous ?? AutoPlanStatus.unplanned,
                    missingPlans: i.missingPlans,
                  )
                : i,
        ],
      );
    });
  }

  /// One round (R6, R7, R12): the spec is saved as soon as it ends, and any
  /// failure leaves the file as it was (R9).
  Future<void> _plan(Workspace ws, AutoPlanItem item) async {
    _updateItem(
      ws.id,
      item.specId,
      (i) => i.copyWith(status: AutoPlanStatus.planning, previous: i.previous),
    );
    final cancel = _cancels[ws.id] = Completer<void>();
    try {
      final spec = await ref.read(specsRepoProvider).getById(item.specId);
      if (spec == null) {
        throw PlannerException('${item.code} não existe mais.');
      }
      final started =
          spec.stage != SpecStage.backlog || spec.worktreePath != null;
      final text = await _service.read(ws, spec);
      if (text == null) {
        throw PlannerException('O arquivo ${spec.path} não existe.');
      }
      final previous = item.previous;
      if (previous != null &&
          (started || !SpecDocument.parse(text).autoPlanned)) {
        // A dependent someone saved or started meanwhile is not overwritten
        // (D7): it stays as it was.
        _updateItem(
          ws.id,
          item.specId,
          (i) => i.copyWith(status: previous, missingPlans: item.missingPlans),
        );
        return;
      }
      if (started) throw const PlannerException('A execução já começou.');
      final (:plans, :missing) = await _dependencies(ws, spec);
      final answer = await ref
          .read(specDesignerProvider)
          .refineAndPlan(
            ws,
            text,
            dependencyPlans: plans,
            cancelled: cancel.future,
          );
      await _service.save(
        ws,
        spec,
        SpecDocument.parse(answer.text).withAutoPlan(true),
        expectedText: text,
      );
      (_uncommitted[ws.id] ??= {}).add(spec.path);
      _updateItem(
        ws.id,
        item.specId,
        (i) => i.copyWith(
          status: missing.isEmpty
              ? AutoPlanStatus.ready
              : AutoPlanStatus.partial,
          missingPlans: missing,
          addedRequirements: answer.addedRequirements,
          questions: answer.questions,
        ),
      );
    } on SpecActionCancelled {
      _updateItem(
        ws.id,
        item.specId,
        (i) => i.copyWith(status: i.previous ?? AutoPlanStatus.unplanned),
      );
    } catch (e) {
      debugPrint('fila de planos: ${item.code} — $e');
      _updateItem(
        ws.id,
        item.specId,
        (i) => i.copyWith(
          status: AutoPlanStatus.failed,
          error: errorCause(e),
          missingPlans: const [],
          addedRequirements: 0,
          questions: 0,
        ),
      );
    } finally {
      _cancels.remove(ws.id);
    }
  }

  /// Plans of the specs [spec] depends on (R6), and the dependencies of the
  /// queue whose plan is missing, here or further back (R9).
  Future<({Map<String, String> plans, List<String> missing})> _dependencies(
    Workspace ws,
    Spec spec,
  ) async {
    final items = {
      for (final i in state.queues[ws.id]?.items ?? const <AutoPlanItem>[])
        i.code: i,
    };
    final repo = ref.read(specsRepoProvider);
    final plans = <String, String>{};
    final missing = <String>{};
    for (final code in spec.dependsOn) {
      final dep = await repo.getByCode(ws.id, code);
      final text = dep == null ? null : await _service.read(ws, dep);
      final plan = text == null ? null : SpecDocument.parse(text).design;
      if (plan != null) plans[code] = plan;
      final item = items[code];
      if (item == null) continue;
      if (item.status.planned) {
        missing.addAll(item.missingPlans);
      } else {
        missing.add(code);
      }
    }
    return (plans: plans, missing: missing.toList());
  }

  /// One commit with what this pass wrote (R7, R9). A failure is shown and
  /// undoes nothing.
  Future<void> _commit(Workspace ws) async {
    final files = (_uncommitted.remove(ws.id) ?? const <String>{}).toList()
      ..sort();
    final q = state.queues[ws.id];
    if (q == null || !q.commit || files.isEmpty) return;
    final git = ref.read(gitServiceFactoryProvider)(ws.path);
    try {
      await git.git(['add', '--', ...files]);
      await git.git([
        'commit',
        '-q',
        '-m',
        specPlansCommitMessage,
        '--',
        ...files,
      ]);
      _update(ws.id, (q) => q.copyWith(committed: true));
    } catch (e) {
      _update(ws.id, (q) => q.copyWith(commitError: repoSetupError(e)));
    }
  }

  // --- second round (R13) ---------------------------------------------------

  /// [done] finished: the specs marked `plano: automatico`, still in the
  /// Backlog, whose last dependency this was enter the queue of R13.
  Future<void> specFinished(Workspace ws, Spec done) async {
    try {
      final all = await ref
          .read(specsRepoProvider)
          .watchByWorkspace(ws.id)
          .first;
      final byCode = specsByCode(all);
      var added = false;
      for (final s in all) {
        if (!s.dependsOn.contains(done.code) ||
            _replanned.contains(s.id) ||
            state.replanning.contains(s.id) ||
            state.lockOf(s.id) != null ||
            !_canReplan(s) ||
            specBlockers(s, byCode).isNotEmpty) {
          continue;
        }
        final text = await _service.read(ws, s);
        if (text == null || !SpecDocument.parse(text).autoPlanned) continue;
        _enqueue(ws, s);
        added = true;
      }
      if (added) unawaited(_drainReplans(ws));
    } catch (e) {
      // The conclusion of a spec never fails because of this.
      debugPrint('replanejar depois de ${done.code}: $e');
    }
  }

  /// "Tentar de novo" of the Quadro's warning (R13).
  Future<void> retryReplan(Workspace ws, int specId) async {
    final spec = await ref.read(specsRepoProvider).getById(specId);
    if (spec == null || state.replanning.contains(specId)) return;
    _enqueue(ws, spec);
    await _drainReplans(ws);
  }

  /// A spec that started no longer shows "Plano anterior" (R13).
  void clearFailure(int specId) {
    if (!state.failures.containsKey(specId)) return;
    _setRounds(failures: {...state.failures}..remove(specId));
  }

  static bool _canReplan(Spec s) =>
      s.stage == SpecStage.backlog && s.worktreePath == null;

  void _enqueue(Workspace ws, Spec spec) {
    (_waiting[ws.id] ??= []).add(spec.id);
    _setRounds(
      replanning: {...state.replanning, spec.id},
      failures: {...state.failures}..remove(spec.id),
    );
  }

  Future<void> _drainReplans(Workspace ws) async {
    if (!_draining.add(ws.id)) return;
    try {
      while (ref.mounted) {
        final waiting = _waiting[ws.id];
        if (waiting == null || waiting.isEmpty) break;
        final id = waiting.removeAt(0);
        await _replan(ws, id);
        _setRounds(replanning: {...state.replanning}..remove(id));
      }
    } finally {
      _draining.remove(ws.id);
    }
    // The autopilot skipped the specs that were waiting.
    if (ref.mounted) {
      unawaited(ref.read(autopilotProvider.notifier).tick(ws.id));
    }
  }

  Future<void> _replan(Workspace ws, int specId) async {
    var code = 'A spec';
    try {
      final spec = await ref.read(specsRepoProvider).getById(specId);
      if (spec == null || !_canReplan(spec)) return;
      code = spec.code;
      final text = await _service.read(ws, spec);
      // Saved by hand while it waited (D7).
      if (text == null || !SpecDocument.parse(text).autoPlanned) return;
      // No dependency plans: the round reads the real code.
      final answer = await ref
          .read(specDesignerProvider)
          .refineAndPlan(ws, text);
      await _service.save(ws, spec, answer.text, expectedText: text);
      _replanned.add(specId);
      await _commitReplan(ws, spec);
    } catch (e) {
      debugPrint('replanejar $code: $e');
      _setRounds(
        failures: {
          ...state.failures,
          specId: ReplanFailure(
            workspaceId: ws.id,
            specId: specId,
            code: code,
            cause: errorCause(e),
          ),
        },
      );
    }
  }

  /// Only the file of the spec, even without the commit option of the
  /// creation, since the execution starts from the repository. No `git add`:
  /// a spec never committed fails here and the warning says so (D8).
  Future<void> _commitReplan(Workspace ws, Spec spec) async {
    try {
      await ref.read(gitServiceFactoryProvider)(ws.path).git([
        'commit',
        '-q',
        '-m',
        planUpdatedCommitMessage(spec.code),
        '--',
        spec.path,
      ]);
    } catch (e) {
      _setRounds(
        failures: {
          ...state.failures,
          spec.id: ReplanFailure(
            workspaceId: ws.id,
            specId: spec.id,
            code: spec.code,
            cause: e is GitException ? repoSetupError(e) : errorCause(e),
            commitFailed: true,
          ),
        },
      );
    }
  }
}

final specAutoPlannerProvider =
    NotifierProvider<SpecAutoPlanner, AutoPlanState>(SpecAutoPlanner.new);
