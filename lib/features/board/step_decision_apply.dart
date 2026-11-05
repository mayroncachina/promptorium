import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../sessions/session_manager.dart';
import '../sessions/timeline_provider.dart';
import '../specs/spec_service.dart';
import '../specs/workspace_watcher.dart';
import 'board_rules.dart';
import 'spec_runner.dart';
import 'step_decision.dart';
import 'step_decision_choices.dart';
import 'step_decision_compiler.dart';

/// The spec is not what the modal saw when it opened: nothing was written
/// (R11).
class StepDecisionConflict implements Exception {
  const StepDecisionConflict();
}

/// The step could not be resumed. The spec and the queue are back to what
/// they were.
class StepDecisionResumeFailed implements Exception {
  const StepDecisionResumeFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What the person approved in the Compilar phase.
@immutable
class StepDecisionPlan {
  const StepDecisionPlan({
    required this.spec,
    required this.step,
    required this.choices,
    required this.message,
    required this.opened,
    this.compiled,
  });

  final Spec spec;
  final StepView step;
  final List<StepDecisionChoice> choices;

  /// The text the agent gets, as edited.
  final String message;

  /// The file when the modal opened (or at "Recompilar").
  final SpecFileStamp? opened;

  /// Null when the compiler did not run: nothing in the choices touches the
  /// file.
  final StepCompilation? compiled;

  bool _has(StepDecisionKind kind) => choices.any((c) => c.kind == kind);

  bool get splits => _has(StepDecisionKind.split);

  bool get defers => _has(StepDecisionKind.defer);

  /// Only a message: nothing is written, so there is nothing to conflict.
  bool get answersOnly =>
      choices.every((c) => c.kind == StepDecisionKind.answer);

  bool get changesSpec => compiled?.changesSpec ?? false;

  /// The step leaves its session: the agent of that session must not go on,
  /// as its marker would conclude a step that is no longer its own.
  bool get leavesSession => splits || defers;

  /// The notice of R10.
  String get notice {
    final head = '${spec.code}: etapa ${step.id}';
    if (defers) return '$head adiada para o fim da fila';
    final changed = changesSpec ? ' · requisito alterado' : '';
    if (splits) {
      final count = stepDecisionSplitBodies(choices).length;
      return '$head dividida em $count subetapas$changed';
    }
    return '$head retomada$changed';
  }
}

/// What "Desfazer" needs: the file and the queue from before "Compilar e
/// continuar", in memory, and the session that went on from there.
@immutable
class StepDecisionUndo {
  const StepDecisionUndo._(
    this._saved, {
    required this.sessionId,
    required this.eventVersion,
  });

  final _Saved _saved;

  /// The session that got the message, new or not.
  final String sessionId;

  /// Version of its timeline after the message: a higher one means that the
  /// session emitted an event.
  final int eventVersion;
}

class _Saved {
  const _Saved({
    required this.ws,
    required this.plan,
    required this.rows,
    required this.written,
  });

  final Workspace ws;
  final StepDecisionPlan plan;
  final List<SpecStep> rows;

  /// The file after [StepDecisionPlan.compiled]; null when it did not change.
  final String? written;
}

/// The steps of R10 and R11, in order: writes the spec, restructures the
/// queue and resumes the step.
class StepDecisionApplier {
  StepDecisionApplier(this._ref);

  final Ref _ref;

  SpecService get _service => _ref.read(specServiceProvider);
  WorkspaceWatcher get _watcher => _ref.read(workspaceWatcherProvider.notifier);

  Future<Workspace> _workspace(Spec spec) async {
    final ws = await _ref
        .read(workspacesRepoProvider)
        .getById(spec.workspaceId);
    if (ws == null) throw const SpecException('Workspace não encontrado.');
    return ws;
  }

  /// The file of [spec] now; null when it is not there.
  Future<SpecFileStamp?> stamp(Spec spec) async {
    final ws = await _ref
        .read(workspacesRepoProvider)
        .getById(spec.workspaceId);
    if (ws == null) return null;
    try {
      return SpecFileStamp.of(_service.fileOf(ws, spec));
    } on SpecException {
      return null;
    }
  }

  /// Step 1 of R10: throws [StepDecisionConflict], writing nothing, when the
  /// file changed. The saved text becomes what the running spec started
  /// from: to the watcher, this is not an edit that blocks the next step.
  /// Returns the file, or null when there was nothing to write.
  Future<String?> _write(Workspace ws, StepDecisionPlan plan) async {
    if (plan.answersOnly) return null;
    if (await stamp(plan.spec) != plan.opened) {
      throw const StepDecisionConflict();
    }
    final compiled = plan.compiled;
    if (compiled == null || !compiled.changesSpec) return null;
    try {
      await _service.save(
        ws,
        plan.spec,
        compiled.after,
        expectedText: compiled.before,
      );
    } on SpecException {
      throw const StepDecisionConflict();
    }
    final written = await _service.read(ws, plan.spec);
    _watcher.markStart(plan.spec.id, written ?? compiled.after);
    return written;
  }

  /// "Só alterar a spec": step 1 alone; the step stays waiting.
  Future<void> saveSpec(StepDecisionPlan plan) async {
    await _write(await _workspace(plan.spec), plan);
    _forget(plan);
  }

  /// "Compilar e continuar" (R10), steps 1 to 3. When the step cannot be
  /// resumed, the spec and the queue go back and [StepDecisionResumeFailed]
  /// is thrown.
  Future<StepDecisionUndo> continueStep(StepDecisionPlan plan) async {
    final ws = await _workspace(plan.spec);
    final rows = await _ref.read(specStepsRepoProvider).bySpec(plan.spec.id);
    final saved = _Saved(
      ws: ws,
      plan: plan,
      rows: rows,
      written: await _write(ws, plan),
    );
    final String sessionId;
    try {
      await _restructure(plan);
      sessionId = await _resume(plan);
    } catch (e) {
      await _restore(saved);
      throw StepDecisionResumeFailed('$e');
    }
    _forget(plan);
    final timeline = _ref.read(sessionTimelineProvider(sessionId));
    return StepDecisionUndo._(
      saved,
      sessionId: sessionId,
      // The stored events arrive in the one emit that ends the load.
      eventVersion: timeline.version + (timeline.loading ? 1 : 0),
    );
  }

  Future<void> _restructure(StepDecisionPlan plan) async {
    final repo = _ref.read(specStepsRepoProvider);
    final specId = plan.spec.id;
    if (plan.splits) {
      await repo.addSubSteps(
        specId,
        plan.step.id,
        stepDecisionSplitBodies(plan.choices),
      );
    } else if (plan.defers) {
      await repo.reset(specId, [plan.step.id]);
    }
  }

  /// The session that goes on. A step that left its session never goes back
  /// to it: the session ends and the next step of the queue, which is not
  /// the same any more, gets a new one with the message.
  Future<String> _resume(StepDecisionPlan plan) async {
    final id = plan.step.sessionId;
    final alive = id != null && _ref.read(sessionManagerProvider).isAlive(id);
    if (alive && !plan.leavesSession) {
      await _ref
          .read(specStepsRepoProvider)
          .set(plan.spec.id, plan.step.id, StepStatus.running, sessionId: id);
      await _ref.read(sessionManagerProvider.notifier).send(id, plan.message);
      return id;
    }
    if (alive) await _end(id);
    return _ref
        .read(specRunnerProvider)
        .runNext(plan.spec.id, context: plan.message);
  }

  /// Ends [id] without its exit touching the steps (as "Refazer etapa"
  /// does): the queue is already what it has to be.
  Future<void> _end(String id) async {
    await _ref.read(sessionManagerProvider.notifier).release(id);
    final sessions = _ref.read(sessionsRepoProvider);
    final s = await sessions.getById(id);
    if (s != null && !s.status.isTerminal) {
      await sessions.setStatus(id, SessionStatus.stopped);
    }
  }

  /// "Desfazer" (R10): stops the session that got the message, which may be
  /// on its way, and only then restores the file and the queue. Throws
  /// [StepDecisionConflict], touching nothing, when the file changed after
  /// "Compilar e continuar".
  Future<void> undo(StepDecisionUndo undo) async {
    final saved = undo._saved;
    final written = saved.written;
    if (written != null &&
        await _service.read(saved.ws, saved.plan.spec) != written) {
      throw const StepDecisionConflict();
    }
    await _end(undo.sessionId);
    await _restore(saved);
    final choices = _ref.read(stepDecisionChoicesProvider.notifier);
    for (final c in saved.plan.choices) {
      choices.set(_key(saved.plan), c);
    }
  }

  Future<void> _restore(_Saved saved) async {
    final spec = saved.plan.spec;
    await _ref.read(specStepsRepoProvider).restore(spec.id, saved.rows);
    final written = saved.written;
    if (written == null) return;
    final previous = saved.plan.compiled!.before;
    await _service.save(saved.ws, spec, previous, expectedText: written);
    _watcher.markStart(spec.id, previous);
  }

  StepDecisionChoiceKey _key(StepDecisionPlan plan) =>
      stepDecisionChoiceKey(plan.spec.id, plan.step);

  /// The stop is over: what was chosen does not apply to the next one.
  void _forget(StepDecisionPlan plan) =>
      _ref.read(stepDecisionChoicesProvider.notifier).clear(_key(plan));
}

final stepDecisionApplierProvider = Provider(StepDecisionApplier.new);
