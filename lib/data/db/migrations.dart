import 'dart:convert';

import 'package:drift/drift.dart';

import 'app_database.dart';

/// Schema v8 data step: the tasks of each spec become the state of its
/// steps, task dependencies across specs become spec dependencies and
/// sessions of a task point to its spec.
///
/// - step (`tasks.requirement`) = `done` when every task of that requirement
///   is done, else `pending` (the step list itself comes from the file on the
///   next sync);
/// - stage = `running` if a task is running, else `review` if one is in
///   review, else `done` if all are done, else `backlog`;
/// - tasks without a spec or without a requirement stay in `tasks` (the
///   Quadro offers to turn them into specs). Nothing is written to the
///   repositories.
///
/// Raw SQL on purpose: it runs inside the upgrade, on the v8 shape.
Future<void> migrateTasksToSteps(AppDatabase db) async {
  final specCodes = <int, String>{
    for (final r in await db.customSelect('SELECT id, code FROM specs').get())
      r.read<int>('id'): r.read<String>('code'),
  };
  final tasks = await db
      .customSelect(
        'SELECT id, spec_id, code, status, requirement, depends_on FROM tasks',
      )
      .get();
  final specOfTask = <String, int>{};
  for (final t in tasks) {
    final spec = t.readNullable<int>('spec_id');
    if (spec != null) specOfTask[t.read<String>('code')] = spec;
  }

  final bySpec = <int, List<QueryRow>>{};
  for (final t in tasks) {
    final spec = t.readNullable<int>('spec_id');
    if (spec != null && specCodes.containsKey(spec)) {
      bySpec.putIfAbsent(spec, () => []).add(t);
    }
  }
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  for (final MapEntry(key: spec, value: list) in bySpec.entries) {
    final statuses = [for (final t in list) t.read<String>('status')];

    // Steps.
    final reqDone = <String, bool>{};
    for (final t in list) {
      final req = t.readNullable<String>('requirement')?.trim() ?? '';
      if (req.isEmpty) continue;
      final done = t.read<String>('status') == TaskStatus.done.name;
      reqDone[req] = (reqDone[req] ?? true) && done;
    }
    for (final MapEntry(key: step, value: done) in reqDone.entries) {
      await db.customStatement(
        'INSERT OR REPLACE INTO spec_steps (spec_id, step, status, done_at) '
        'VALUES (?, ?, ?, ?)',
        [
          spec,
          step,
          done ? StepStatus.done.name : StepStatus.pending.name,
          done ? now : null,
        ],
      );
    }

    // Stage.
    final SpecStage stage;
    if (statuses.contains(TaskStatus.running.name)) {
      stage = SpecStage.running;
    } else if (statuses.contains(TaskStatus.review.name)) {
      stage = SpecStage.review;
    } else if (statuses.every((s) => s == TaskStatus.done.name)) {
      stage = SpecStage.done;
    } else {
      stage = SpecStage.backlog;
    }

    // Dependencies on other specs.
    final deps = <String>{};
    for (final t in list) {
      for (final code in const StringListConverter().fromSql(
        t.read<String>('depends_on'),
      )) {
        final other = specOfTask[code];
        if (other != null && other != spec && specCodes[other] != null) {
          deps.add(specCodes[other]!);
        }
      }
    }
    await db.customStatement(
      'UPDATE specs SET stage = ?, depends_on = ? WHERE id = ?',
      [stage.name, jsonEncode(deps.toList()..sort()), spec],
    );
  }

  await db.customStatement(
    'UPDATE sessions SET spec_id = (SELECT spec_id FROM tasks '
    'WHERE tasks.id = sessions.task_id) WHERE task_id IS NOT NULL',
  );
}
