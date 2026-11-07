import 'package:flutter/foundation.dart';

import '../../data/db/app_database.dart';

/// What the sprint selector of the Quadro shows (SPEC-042 R2).
@immutable
class SprintFilter {
  const SprintFilter.all() : sprintId = null, _none = false;
  const SprintFilter.none() : sprintId = null, _none = true;
  const SprintFilter.sprint(int this.sprintId) : _none = false;

  /// The sprint chosen; null in "Todas" and "Sem sprint".
  final int? sprintId;
  final bool _none;

  bool get isAll => sprintId == null && !_none;
  bool get isNone => _none;

  /// `app_settings` value.
  String get stored => isAll
      ? 'all'
      : isNone
      ? 'none'
      : '$sprintId';

  bool matches(Spec spec) =>
      isAll || (isNone ? spec.sprintId == null : spec.sprintId == sprintId);

  @override
  bool operator ==(Object other) =>
      other is SprintFilter &&
      other.sprintId == sprintId &&
      other._none == _none;

  @override
  int get hashCode => Object.hash(sprintId, _none);
}

/// The filter of a [stored] choice. Nothing saved, or a sprint that no longer
/// exists, opens the active sprint and, without one, "Todas" (R2).
SprintFilter resolveSprintFilter(String? stored, List<Sprint> sprints) {
  if (stored == 'all') return const SprintFilter.all();
  if (stored == 'none' && sprints.isNotEmpty) return const SprintFilter.none();
  final id = int.tryParse(stored ?? '');
  if (id != null && sprints.any((s) => s.id == id)) {
    return SprintFilter.sprint(id);
  }
  for (final s in sprints) {
    if (s.state == SprintState.active) return SprintFilter.sprint(s.id);
  }
  return const SprintFilter.all();
}

/// The filter that shows [spec].
SprintFilter sprintFilterOf(Spec spec) => spec.sprintId == null
    ? const SprintFilter.none()
    : SprintFilter.sprint(spec.sprintId!);

/// Numbers of a sprint in the selector (R3).
@immutable
class SprintProgress {
  const SprintProgress({
    this.done = 0,
    this.total = 0,
    this.running = 0,
    this.waiting = 0,
  });

  final int done;
  final int total;
  final int running;
  final int waiting;

  /// `5 de 8`.
  String get label => '$done de $total';
}

SprintProgress sprintProgress(
  Iterable<Spec> specs, {
  required bool Function(Spec) waiting,
}) {
  var done = 0, total = 0, running = 0, wait = 0;
  for (final s in specs) {
    total++;
    if (s.stage == SpecStage.done) done++;
    if (s.stage == SpecStage.running) running++;
    if (waiting(s)) wait++;
  }
  return SprintProgress(
    done: done,
    total: total,
    running: running,
    waiting: wait,
  );
}

/// `Sprint 4`: the next number free in [sprints] (R4).
String nextSprintName(List<Sprint> sprints) {
  var max = 0;
  for (final s in sprints) {
    final n = int.tryParse(RegExp(r'(\d+)$').stringMatch(s.name) ?? '');
    if (n != null && n > max) max = n;
  }
  return 'Sprint ${(max > sprints.length ? max : sprints.length) + 1}';
}

/// Active and planned sprints, in the order of the list: the ones that accept
/// specs (R5).
List<Sprint> openSprints(List<Sprint> sprints) => [
  for (final s in sprints)
    if (s.state == SprintState.active) s,
  for (final s in sprints)
    if (s.state == SprintState.planned) s,
];

List<Sprint> closedSprints(List<Sprint> sprints) => [
  for (final s in sprints.reversed)
    if (s.state == SprintState.done) s,
];

/// The sprint suggested for what [current] left undone (R10): the next
/// planned one in the list.
Sprint? nextPlannedSprint(Sprint current, List<Sprint> sprints) {
  final planned = [
    for (final s in sprints)
      if (s.state == SprintState.planned && s.id != current.id) s,
  ];
  for (final s in planned) {
    if (s.position > current.position) return s;
  }
  return planned.firstOrNull;
}

/// Codes in `spec.dependsOn` outside [filter], as [Spec]s (R7, R8).
List<Spec> externalDependencies(
  Spec spec,
  Map<String, Spec> byCode,
  SprintFilter filter,
) => [
  for (final code in spec.dependsOn)
    if (byCode[code] case final dep? when !filter.matches(dep)) dep,
];

String sprintNameOf(Spec spec, List<Sprint> sprints) {
  for (final s in sprints) {
    if (s.id == spec.sprintId) return s.name;
  }
  return 'Sem sprint';
}

/// A warning for each spec of [moving] that would go to [target] before a
/// dependency not done (R12): `SPEC-012 depende de SPEC-030, na Sprint 5`.
/// Moving to "Sem sprint" never warns: nothing is planned there.
List<String> moveWarnings(
  Iterable<Spec> moving,
  Sprint? target,
  Map<String, Spec> byCode,
  List<Sprint> sprints,
) {
  if (target == null) return const [];
  final ids = {for (final s in moving) s.id};
  final positions = {for (final s in sprints) s.id: s.position};
  final warnings = <String>[];
  for (final spec in moving) {
    for (final code in spec.dependsOn) {
      final dep = byCode[code];
      if (dep == null ||
          dep.stage == SpecStage.done ||
          ids.contains(dep.id) ||
          dep.sprintId == target.id) {
        continue;
      }
      final position = positions[dep.sprintId];
      if (position != null && position < target.position) continue;
      warnings.add(
        dep.sprintId == null
            ? '${spec.code} depende de ${dep.code}, que fica em Sem sprint'
            : '${spec.code} depende de ${dep.code}, na '
                  '${sprintNameOf(dep, sprints)}',
      );
    }
  }
  return warnings;
}

/// What the Autopilot may start (R11): only the active sprint, or everything
/// without one. A dependency outside still blocks: see [specBlockers].
List<Spec> autopilotScope(List<Spec> specs, Sprint? active) => active == null
    ? specs
    : [
        for (final s in specs)
          if (s.sprintId == active.id) s,
      ];
