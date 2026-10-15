import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';

export 'task_rules.dart';

class TaskException implements Exception {
  const TaskException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Labels of the kanban columns (mockup Tarefas).
String taskStatusLabel(TaskStatus s) => switch (s) {
  TaskStatus.backlog => 'Backlog',
  TaskStatus.running => 'Em execução',
  TaskStatus.review => 'Review',
  TaskStatus.done => 'Feito',
};

/// First message of the session created by "Executar com agente".
String taskSessionPrompt(Task task, {Spec? spec}) {
  final b = StringBuffer()
    ..writeln('Implemente a tarefa ${task.code}: ${task.title}');
  final body = task.body?.trim() ?? '';
  if (body.isNotEmpty) {
    b
      ..writeln()
      ..writeln(body);
  }
  if (spec != null) {
    b
      ..writeln()
      ..writeln(
        'Contexto: spec ${spec.code} @${spec.path}'
        '${(task.requirement?.isNotEmpty ?? false) ? ' — requisito ${task.requirement}' : ''}.',
      );
  }
  if (task.dependsOn.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Dependências já concluídas: ${task.dependsOn.join(', ')}.');
  }
  b
    ..writeln()
    ..writeln('Ao terminar, rode os testes do projeto e resuma o que mudou.');
  return b.toString().trimRight();
}

/// Title of that session.
String taskSessionTitle(Task task) => '${task.code} · ${task.title}';

/// Kanban actions (plano, Fase 8). Session-driven moves live in
/// `SessionManager` (`taskStatusForSession`).
class TaskActions {
  TaskActions(this._ref);

  final Ref _ref;

  /// Manual move (drag between columns).
  Future<void> move(int taskId, TaskStatus status) =>
      _ref.read(tasksRepoProvider).setStatus(taskId, status);

  /// "Feito": called by the merge of the Review screen (Fase 9).
  Future<void> markDone(int taskId) => move(taskId, TaskStatus.done);

  /// "Nova tarefa".
  Future<Task> create({
    required int workspaceId,
    required String title,
    String? description,
    int? specId,
    String? agentName,
    String? requirement,
    List<String> dependsOn = const [],
  }) async {
    final t = title.trim();
    if (t.isEmpty) throw const TaskException('Informe o título da tarefa.');
    final repo = _ref.read(tasksRepoProvider);
    final code = await repo.nextCode(workspaceId);
    return repo.insert(
      workspaceId: workspaceId,
      code: code,
      title: t,
      body: (description?.trim().isEmpty ?? true) ? null : description!.trim(),
      specId: specId,
      agentName: (agentName?.isEmpty ?? true) ? null : agentName,
      requirement: (requirement?.trim().isEmpty ?? true)
          ? null
          : requirement!.trim(),
      dependsOn: [
        for (final d in dependsOn)
          if (d.trim().isNotEmpty && d.trim() != code) d.trim(),
      ],
    );
  }

  Future<void> update(int taskId, TasksCompanion changes) =>
      _ref.read(tasksRepoProvider).update(taskId, changes);

  Future<void> setAgent(int taskId, String? agent) => update(
    taskId,
    TasksCompanion(agentName: Value((agent?.isEmpty ?? true) ? null : agent)),
  );

  Future<void> delete(int taskId) =>
      _ref.read(tasksRepoProvider).delete(taskId);
}

final taskActionsProvider = Provider(TaskActions.new);

/// Parses "TASK-001, TASK-002" (dependency field of the dialog).
List<String> parseTaskCodes(String text) => [
  for (final p in text.split(RegExp(r'[\s,;]+')))
    if (p.trim().isNotEmpty) p.trim().toUpperCase(),
];
