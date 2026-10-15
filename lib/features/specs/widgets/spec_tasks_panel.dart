import 'package:flutter/material.dart';

import '../../../data/db/app_database.dart';
import '../../../ui/theme/tokens.dart';
import '../../sessions/widgets/session_style.dart';
import '../../tasks/task_actions.dart';
import '../spec_file.dart';

/// Status color of a task in the spec panel (mockup Specs).
Color _taskColor(TaskStatus s) => switch (s) {
  TaskStatus.backlog => AppColors.textSecondary,
  TaskStatus.running => AppColors.teal,
  TaskStatus.review => AppColors.amber,
  TaskStatus.done => AppColors.blue,
};

/// Session shown per task in the traceability: the merged one (it carries the
/// merge commit, Fase 9), otherwise the most recent.
Map<int, Session> traceSessions(Iterable<Session> sessions) {
  final out = <int, Session>{};
  for (final s in sessions) {
    final id = s.taskId;
    if (id == null) continue;
    final cur = out[id];
    final bool better;
    if (cur == null) {
      better = true;
    } else if ((s.mergeCommit != null) != (cur.mergeCommit != null)) {
      better = s.mergeCommit != null;
    } else {
      better = s.startedAt.isAfter(cur.startedAt);
    }
    if (better) out[id] = s;
  }
  return out;
}

/// One line of the traceability block: requirement → tasks → sessions →
/// commit (hash of the Review merge, `sessions.merge_commit`; "—" before).
typedef TraceRow = ({
  String requirement,
  String? text,
  List<({Task task, Session? session})> tasks,
});

/// Requirements of the spec (in file order) followed by requirement ids that
/// only appear on tasks; tasks without requirement go under "—".
List<TraceRow> traceability({
  required List<SpecRequirement> requirements,
  required List<Task> tasks,
  required Map<int, Session> latestSession,
}) {
  final rows = <TraceRow>[];
  final used = <int>{};
  List<({Task task, Session? session})> of(bool Function(Task) test) => [
    for (final t in tasks)
      if (test(t)) (task: t, session: latestSession[t.id]),
  ];
  for (final r in requirements) {
    final ts = of((t) => t.requirement == r.id);
    used.addAll(ts.map((e) => e.task.id));
    rows.add((requirement: r.id, text: r.text, tasks: ts));
  }
  final extra = <String>{
    for (final t in tasks)
      if (t.requirement != null && !used.contains(t.id)) t.requirement!,
  };
  for (final id in extra) {
    final ts = of((t) => t.requirement == id && !used.contains(t.id));
    used.addAll(ts.map((e) => e.task.id));
    rows.add((requirement: id, text: null, tasks: ts));
  }
  final rest = of((t) => !used.contains(t.id));
  if (rest.isNotEmpty) rows.add((requirement: '—', text: null, tasks: rest));
  return rows;
}

/// Right column of the Specs screen: generated tasks + traceability.
class SpecTasksPanel extends StatelessWidget {
  const SpecTasksPanel({
    super.key,
    required this.tasks,
    required this.requirements,
    required this.latestSession,
    required this.generating,
    required this.onGenerate,
    required this.onNewTask,
  });

  final List<Task> tasks;
  final List<SpecRequirement> requirements;
  final Map<int, Session> latestSession;
  final bool generating;
  final VoidCallback? onGenerate;
  final VoidCallback? onNewTask;

  @override
  Widget build(BuildContext context) {
    final byCode = tasksByCode(tasks);
    final rows = traceability(
      requirements: requirements,
      tasks: tasks,
      latestSession: latestSession,
    );
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'TAREFAS GERADAS · ${tasks.length}',
                  style: sectionTitleStyle,
                ),
              ),
              if (onNewTask != null)
                SmallButton(
                  key: const ValueKey('spec-new-task'),
                  label: 'Nova',
                  height: 24,
                  fontSize: 11,
                  onTap: onNewTask,
                ),
            ],
          ),
          const SizedBox(height: 10),
          AmberButton(
            key: const ValueKey('spec-generate-tasks'),
            label: generating
                ? 'Gerando tarefas…'
                : 'Gerar tarefas com o planner',
            height: 34,
            expand: true,
            onTap: generating ? null : onGenerate,
          ),
          if (generating) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(
              minHeight: 2,
              color: AppColors.amber,
              backgroundColor: AppColors.border,
            ),
          ],
          const SizedBox(height: 12),
          for (final t in tasks) ...[
            _TaskTile(task: t, blockers: blockersOf(t, byCode)),
            const SizedBox(height: 6),
          ],
          if (tasks.isEmpty)
            const Text(
              'Nenhuma tarefa ainda. O planner lê a spec salva (somente '
              'leitura) e cria tarefas com dependências.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          const SizedBox(height: 18),
          const Text('RASTREABILIDADE', style: sectionTitleStyle),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            const Text(
              'Liste requisitos como "- R1 · texto" na spec.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          for (final r in rows) ...[
            _TraceLine(row: r),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.blockers});

  final Task task;
  final List<String> blockers;

  @override
  Widget build(BuildContext context) {
    final dep = task.dependsOn.isEmpty
        ? 'sem dependências'
        : 'depende de ${task.dependsOn.join(', ')}';
    return Container(
      key: ValueKey('spec-task-${task.code}'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                task.code,
                style: const TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              if (task.requirement != null) ...[
                const SizedBox(width: 8),
                Text(
                  task.requirement!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const Spacer(),
              Text(
                taskStatusLabel(task.status),
                style: TextStyle(fontSize: 11, color: _taskColor(task.status)),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            task.title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 3),
          Text(
            dep,
            style: TextStyle(
              fontSize: 11,
              color: blockers.isNotEmpty && task.status == TaskStatus.backlog
                  ? AppColors.red
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TraceLine extends StatelessWidget {
  const _TraceLine({required this.row});

  final TraceRow row;

  @override
  Widget build(BuildContext context) {
    Widget chip(String text, {Color color = AppColors.text, Key? key}) =>
        Container(
          key: key,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 11,
              color: color,
            ),
          ),
        );
    const arrow = Text(
      '→',
      style: TextStyle(fontSize: 11, color: AppColors.textMuted),
    );
    final parts = <Widget>[
      Tooltip(
        message: row.text ?? '',
        child: chip(row.requirement, key: ValueKey('trace-${row.requirement}')),
      ),
    ];
    if (row.tasks.isEmpty) {
      parts.addAll([arrow, chip('sem tarefa', color: AppColors.textMuted)]);
    }
    for (final (:task, :session) in row.tasks) {
      parts.addAll([
        arrow,
        chip(task.code, color: _taskColor(task.status)),
        arrow,
        chip(
          session == null ? 'sem sessão' : 'sessão ${_short(session.id)}',
          color: session == null ? AppColors.textMuted : AppColors.text,
        ),
        arrow,
        if (session?.mergeCommit case final commit?)
          Tooltip(
            message: 'Commit de merge $commit',
            child: chip(
              'merge ${commit.length > 7 ? commit.substring(0, 7) : commit}',
              key: ValueKey('trace-commit-${task.code}'),
              color: AppColors.teal,
            ),
          )
        else
          chip('commit —', color: AppColors.textMuted),
      ]);
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: parts,
    );
  }
}

String _short(String id) => id.length > 4 ? id.substring(0, 4) : id;
