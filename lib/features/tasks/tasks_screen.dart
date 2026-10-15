import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../ui/shell/navigation.dart';
import '../../ui/theme/tokens.dart';
import '../sessions/new_session_dialog.dart';
import '../sessions/session_manager.dart';
import '../sessions/widgets/session_style.dart';
import 'task_actions.dart';

/// Column dot colors (mockup Tarefas).
Color taskStatusColor(TaskStatus s) => switch (s) {
  TaskStatus.backlog => AppColors.textMuted,
  TaskStatus.running => AppColors.teal,
  TaskStatus.review => AppColors.amber,
  TaskStatus.done => AppColors.blue,
};

/// Filters of the board ("Spec: todas" / "Agente: todos").
class TaskFilters {
  const TaskFilters({this.specId, this.agent});

  /// null = all; -1 = tasks without spec.
  final int? specId;

  /// null = all; '' = no agent.
  final String? agent;

  bool matches(Task t) =>
      (specId == null ||
          (specId == -1 ? t.specId == null : t.specId == specId)) &&
      (agent == null ||
          (agent!.isEmpty ? t.agentName == null : t.agentName == agent));
}

/// Kanban of the workspace tasks (plano, Fase 8; docs/mockups/Tarefas.dc.html).
class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  TaskFilters _filters = const TaskFilters();

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(activeWorkspaceProvider);
    if (ws == null) {
      return const _Empty('Selecione um workspace na barra de título.');
    }
    final tasks = ref.watch(tasksProvider(ws.id)).value ?? const <Task>[];
    final specs = ref.watch(specsProvider(ws.id)).value ?? const <Spec>[];
    final sessions =
        ref.watch(sessionsProvider(ws.id)).value ?? const <Session>[];
    final specById = {for (final s in specs) s.id: s};
    final byCode = tasksByCode(tasks);
    // Latest session of each task (by start time; list order not assumed).
    final latest = <int, Session>{};
    for (final s in sessions) {
      final id = s.taskId;
      if (id == null) continue;
      final cur = latest[id];
      if (cur == null || s.startedAt.isAfter(cur.startedAt)) latest[id] = s;
    }
    final agents = {
      for (final t in tasks)
        if (t.agentName != null) t.agentName!,
    }.toList()..sort();
    final visible = tasks.where(_filters.matches).toList();

    return ColoredBox(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            filters: _filters,
            specs: specs,
            agents: agents,
            total: visible.length,
            onFilters: (f) => setState(() => _filters = f),
          ),
          Expanded(
            child: _Board(
              tasks: visible,
              byCode: byCode,
              specById: specById,
              latest: latest,
              onRun: (t) => _run(t, specById[t.specId]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _run(Task task, Spec? spec) async {
    final id = await showNewSessionDialog(
      context,
      agent: task.agentName,
      title: taskSessionTitle(task),
      prompt: taskSessionPrompt(task, spec: spec),
      taskId: task.id,
    );
    if (id == null || !mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Sessão criada para ${task.code}.'),
          action: SnackBarAction(
            label: 'Ver sessão',
            onPressed: () {
              ref.read(selectedSessionProvider.notifier).select(id);
              ref.read(navigationProvider.notifier).go(AppSection.sessions);
            },
          ),
        ),
      );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.background,
    child: Center(
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.filters,
    required this.specs,
    required this.agents,
    required this.total,
    required this.onFilters,
  });

  final TaskFilters filters;
  final List<Spec> specs;
  final List<String> agents;
  final int total;
  final ValueChanged<TaskFilters> onFilters;

  @override
  Widget build(BuildContext context) {
    final specLabel = switch (filters.specId) {
      null => 'todas',
      -1 => 'sem spec',
      final id => specs.where((s) => s.id == id).firstOrNull?.code ?? '—',
    };
    final agentLabel = switch (filters.agent) {
      null => 'todos',
      '' => 'sem agente',
      final a => a,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Text(
            'Tarefas',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 10),
          Text(
            '$total',
            style: const TextStyle(
              fontFamily: AppFonts.mono,
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          _FilterMenu<int?>(
            key: const ValueKey('tasks-filter-spec'),
            label: 'Spec: $specLabel',
            items: [
              (null, 'todas'),
              (-1, 'sem spec'),
              for (final s in specs) (s.id, '${s.code} · ${s.title}'),
            ],
            onSelected: (v) =>
                onFilters(TaskFilters(specId: v, agent: filters.agent)),
          ),
          const SizedBox(width: 8),
          _FilterMenu<String?>(
            key: const ValueKey('tasks-filter-agent'),
            label: 'Agente: $agentLabel',
            items: [
              (null, 'todos'),
              ('', 'sem agente'),
              for (final a in agents) (a, a),
            ],
            onSelected: (v) =>
                onFilters(TaskFilters(specId: filters.specId, agent: v)),
          ),
        ],
      ),
    );
  }
}

/// Wrapper so a `null` value can be selected in a [PopupMenuButton].
class _Choice<T> {
  const _Choice(this.value);

  final T value;
}

class _FilterMenu<T> extends StatelessWidget {
  const _FilterMenu({
    super.key,
    required this.label,
    required this.items,
    required this.onSelected,
  });

  final String label;
  final List<(T, String)> items;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<_Choice<T>>(
    tooltip: '',
    color: AppColors.panel,
    onSelected: (c) => onSelected(c.value),
    itemBuilder: (_) => [
      for (final (v, l) in items)
        PopupMenuItem(
          value: _Choice(v),
          child: Text(l, style: const TextStyle(fontSize: 12)),
        ),
    ],
    child: Container(
      height: 30,
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: AppColors.text),
      ),
    ),
  );
}

class _Board extends ConsumerWidget {
  const _Board({
    required this.tasks,
    required this.byCode,
    required this.specById,
    required this.latest,
    required this.onRun,
  });

  final List<Task> tasks;
  final Map<String, Task> byCode;
  final Map<int, Spec> specById;
  final Map<int, Session> latest;
  final ValueChanged<Task> onRun;

  static const _gap = 14.0;
  static const _pad = 20.0;
  static const _minCol = 230.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, c) {
        final avail = c.maxWidth - 2 * _pad - 3 * _gap;
        final colW = math.max(_minCol, avail / 4);
        final width = colW * 4 + 3 * _gap + 2 * _pad;
        final board = SizedBox(
          width: width,
          height: c.maxHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _pad, vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final s in TaskStatus.values) ...[
                  if (s != TaskStatus.backlog) const SizedBox(width: _gap),
                  SizedBox(
                    width: colW,
                    child: _Column(
                      status: s,
                      width: colW,
                      tasks: [
                        for (final t in tasks)
                          if (t.status == s) t,
                      ],
                      byCode: byCode,
                      specById: specById,
                      latest: latest,
                      onRun: onRun,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
        if (width <= c.maxWidth + 0.5) return board;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: board,
        );
      },
    );
  }
}

class _Column extends ConsumerWidget {
  const _Column({
    required this.status,
    required this.width,
    required this.tasks,
    required this.byCode,
    required this.specById,
    required this.latest,
    required this.onRun,
  });

  final TaskStatus status;
  final double width;
  final List<Task> tasks;
  final Map<String, Task> byCode;
  final Map<int, Spec> specById;
  final Map<int, Session> latest;
  final ValueChanged<Task> onRun;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DragTarget<int>(
      key: ValueKey('task-column-${status.name}'),
      onWillAcceptWithDetails: (d) => !tasks.any((t) => t.id == d.data),
      onAcceptWithDetails: (d) =>
          ref.read(taskActionsProvider).move(d.data, status),
      builder: (context, candidate, _) => Container(
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: candidate.isNotEmpty ? AppColors.amber : AppColors.border,
          ),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
              child: Row(
                children: [
                  Dot(taskStatusColor(status)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      taskStatusLabel(status).toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sectionTitleStyle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${tasks.length}',
                    key: ValueKey('task-column-count-${status.name}'),
                    style: const TextStyle(
                      fontFamily: AppFonts.mono,
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: tasks.isEmpty
                  ? const Center(
                      child: Text(
                        'Arraste tarefas para cá',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: tasks.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final t = tasks[i];
                        final card = TaskCard(
                          task: t,
                          spec: specById[t.specId],
                          session: latest[t.id],
                          blockers: blockersOf(t, byCode),
                          onRun: () => onRun(t),
                        );
                        return Draggable<int>(
                          key: ValueKey('task-card-${t.code}'),
                          data: t.id,
                          feedback: Material(
                            color: Colors.transparent,
                            child: SizedBox(
                              width: width - 20,
                              child: Opacity(opacity: 0.9, child: card),
                            ),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.35,
                            child: card,
                          ),
                          child: card,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card of the kanban: code, spec, title, agent, meta, live line and
/// "Executar com agente" (only for unblocked backlog tasks).
class TaskCard extends ConsumerWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.spec,
    required this.session,
    required this.blockers,
    required this.onRun,
  });

  final Task task;
  final Spec? spec;
  final Session? session;
  final List<String> blockers;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = session;
    final alive =
        s != null &&
        ref.watch(sessionManagerProvider.select((m) => m.isAlive(s.id)));
    final waiting = s?.status == SessionStatus.waitingApproval && alive;
    final blocked = blockers.isNotEmpty && task.status != TaskStatus.done;
    var meta = '';
    var metaColor = AppColors.textSecondary;
    var border = AppColors.border;
    if (task.status == TaskStatus.backlog) {
      meta = blocked ? 'bloqueada por ${blockers.join(', ')}' : 'pronta';
      if (blocked) metaColor = AppColors.red;
    } else if (s != null) {
      final look = SessionLook.of(s.status, alive: alive);
      final dur = (s.endedAt ?? DateTime.now()).difference(s.startedAt);
      meta = waiting
          ? 'aguardando você'
          : '${look.label.toLowerCase()} · ${formatDuration(dur)} · '
                '${formatCost(s.costUsd)}';
      if (waiting) {
        metaColor = AppColors.amber;
        border = SessionColors.approvalBorder;
      } else if (task.status == TaskStatus.running &&
          look == SessionLook.running) {
        border = SessionColors.runningToolBorder;
      }
    } else if (blocked) {
      meta = 'bloqueada por ${blockers.join(', ')}';
      metaColor = AppColors.red;
    }
    final agent = task.agentName;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
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
                const SizedBox(width: 6),
                Text(
                  task.requirement!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
              const Spacer(),
              if (spec != null)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      spec!.code,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              _CardMenu(task: task),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            task.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.border,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  (agent == null || agent.isEmpty)
                      ? '–'
                      : agent[0].toUpperCase(),
                  style: const TextStyle(fontSize: 10, color: AppColors.text),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  agent ?? 'sem agente',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: Text(
                  meta,
                  key: ValueKey('task-meta-${task.code}'),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: metaColor),
                ),
              ),
            ],
          ),
          if (task.status == TaskStatus.backlog && !blocked) ...[
            const SizedBox(height: 8),
            SmallButton(
              key: ValueKey('task-run-${task.code}'),
              label: 'Executar com agente',
              height: 28,
              expand: true,
              color: AppColors.amber,
              border: SessionColors.approvalBorder,
              background: SessionColors.approvalBg,
              onTap: onRun,
            ),
          ],
        ],
      ),
    );
  }
}

class _CardMenu extends ConsumerWidget {
  const _CardMenu({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(
    width: 22,
    height: 18,
    child: PopupMenuButton<String>(
      key: ValueKey('task-menu-${task.code}'),
      padding: EdgeInsets.zero,
      iconSize: 14,
      tooltip: 'Ações',
      color: AppColors.panel,
      icon: const Icon(Icons.more_horiz, color: AppColors.textSecondary),
      onSelected: (v) async {
        final actions = ref.read(taskActionsProvider);
        switch (v) {
          case 'delete':
            await actions.delete(task.id);
          default:
            final s = TaskStatus.values.asNameMap()[v];
            if (s != null) await actions.move(task.id, s);
        }
      },
      itemBuilder: (_) => [
        for (final s in TaskStatus.values)
          if (s != task.status)
            PopupMenuItem(
              value: s.name,
              child: Text(
                'Mover para ${taskStatusLabel(s)}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
        const PopupMenuItem(
          value: 'delete',
          child: Text(
            'Excluir tarefa',
            style: TextStyle(fontSize: 12, color: AppColors.red),
          ),
        ),
      ],
    ),
  );
}
