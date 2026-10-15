import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/claude/claude_args.dart';
import '../../core/claude/claude_cli.dart';
import '../../core/claude/claude_event.dart';
import '../../core/claude/claude_process.dart';
import '../../core/claude/usage_tracker.dart';
import '../../core/providers/claude_code_provider.dart';
import '../../data/providers.dart';
import '../../data/repos/tasks_repo.dart';

/// "Gerar tarefas com o planner" (plano, Fase 8): a short, read-only
/// `claude -p` with `--json-schema` that breaks a spec into tasks.

/// JSON Schema of the planner answer (`--json-schema`). The CLI asks for an
/// object at the top level, so the list lives in `tasks`.
const plannerTaskSchema = <String, Object?>{
  'type': 'object',
  'additionalProperties': false,
  'required': ['tasks'],
  'properties': {
    'tasks': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['title', 'description', 'requirement', 'dependsOn'],
        'properties': {
          'code': {'type': 'string'},
          'title': {'type': 'string'},
          'description': {'type': 'string'},
          'requirement': {'type': 'string'},
          'dependsOn': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
      },
    },
  },
};

/// System prompt appended to the planner run.
const plannerSystemPrompt =
    'Você é o planner do Promptorium. Quebre a spec indicada em tarefas de '
    'implementação pequenas, verificáveis e em ordem de execução. Para cada '
    'tarefa: code curto e único (T1, T2, …), title (até 70 caracteres, '
    'imperativo), description (o que fazer e como verificar), requirement '
    '(id do requisito da spec, ex.: R1; vazio se não houver) e dependsOn '
    '(codes de tarefas desta lista que precisam terminar antes). Não altere '
    'arquivos. Responda somente com a saída estruturada pedida.';

/// User message of the planner run (the spec goes as an `@path` mention,
/// which the CLI attaches — observed in the Fase 8 probe).
String plannerPrompt({
  required String specPath,
  required String specCode,
  List<String> existingTasks = const [],
}) {
  final b = StringBuffer()
    ..writeln(
      'Leia a spec @$specPath ($specCode) e gere a lista de tarefas de '
      'implementação.',
    );
  if (existingTasks.isNotEmpty) {
    b
      ..writeln()
      ..writeln(
        'Já existem estas tarefas para a spec (não as repita; use o código '
        'delas em dependsOn quando fizer sentido):',
      );
    for (final t in existingTasks) {
      b.writeln('- $t');
    }
  }
  return b.toString().trimRight();
}

/// One task of the planner answer.
@immutable
class PlannedTask {
  const PlannedTask({
    this.code,
    required this.title,
    this.description = '',
    this.requirement = '',
    this.dependsOn = const [],
  });

  final String? code;
  final String title;
  final String description;
  final String requirement;
  final List<String> dependsOn;
}

class PlannerException implements Exception {
  const PlannerException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Structured answer of a `--json-schema` run. Real format (CLI 2.1.300,
/// plano Fase 8): `structured_output` plus the same JSON as a string in
/// `result`; `structured_output` is preferred, `result` is the fallback.
/// Throws [PlannerException] when the run failed.
Object? structuredOutput(Result r) {
  if (!r.isSuccess) {
    throw PlannerException(
      'O planner terminou com erro (${r.subtype.isEmpty ? 'erro' : r.subtype}).',
    );
  }
  final data = r.json['structured_output'];
  if (data != null || r.result == null) return data;
  try {
    return jsonDecode(r.result!);
  } on FormatException {
    return null;
  }
}

/// Tasks of a planner `result` (`{"tasks": [...]}`, see [structuredOutput]).
List<PlannedTask> parsePlannerResult(Result r) {
  final data = structuredOutput(r);
  final list = data is Map ? data['tasks'] : data;
  if (list is! List) {
    throw const PlannerException(
      'O planner não devolveu a lista de tarefas (structured_output).',
    );
  }
  final out = <PlannedTask>[];
  for (final item in list) {
    if (item is! Map) continue;
    final title = '${item['title'] ?? ''}'.trim();
    if (title.isEmpty) continue;
    final deps = item['dependsOn'];
    final code = item['code'];
    out.add(
      PlannedTask(
        code: code is String && code.trim().isNotEmpty ? code.trim() : null,
        title: title,
        description: '${item['description'] ?? ''}'.trim(),
        requirement: '${item['requirement'] ?? ''}'.trim(),
        dependsOn: [
          if (deps is List)
            for (final d in deps)
              if ('$d'.trim().isNotEmpty) '$d'.trim(),
        ],
      ),
    );
  }
  if (out.isEmpty) {
    throw const PlannerException('O planner não gerou nenhuma tarefa.');
  }
  return out;
}

/// Inserts [planned] as `TASK-NNN` (sequential per workspace) of [specId], in
/// one transaction. `dependsOn` is translated from the planner codes
/// (`T1`, or the 1-based position) to the new codes; references to existing
/// task codes of the workspace are kept; anything else (and self references)
/// is dropped.
Future<List<Task>> savePlannedTasks(
  TasksRepo repo, {
  required int workspaceId,
  required int? specId,
  required List<PlannedTask> planned,
  String? agentName,
  Set<String> existingCodes = const {},
}) => repo.transaction(() async {
  final first = await repo.maxNumber(workspaceId) + 1;
  final codeMap = <String, String>{};
  for (var i = 0; i < planned.length; i++) {
    final newCode = TasksRepo.codeFor(first + i);
    final c = planned[i].code;
    if (c != null) codeMap.putIfAbsent(c, () => newCode);
    codeMap.putIfAbsent('${i + 1}', () => newCode);
  }
  final out = <Task>[];
  for (var i = 0; i < planned.length; i++) {
    final p = planned[i];
    final code = TasksRepo.codeFor(first + i);
    final deps = <String>[];
    for (final d in p.dependsOn) {
      final mapped = codeMap[d] ?? (existingCodes.contains(d) ? d : null);
      if (mapped != null && mapped != code && !deps.contains(mapped)) {
        deps.add(mapped);
      }
    }
    out.add(
      await repo.insert(
        workspaceId: workspaceId,
        specId: specId,
        code: code,
        title: p.title.length > 120 ? p.title.substring(0, 120) : p.title,
        body: p.description.isEmpty ? null : p.description,
        requirement: p.requirement.isEmpty ? null : p.requirement,
        dependsOn: deps,
        agentName: agentName,
      ),
    );
  }
  return out;
});

/// Outcome of a planner run.
typedef PlannerOutcome = ({List<Task> tasks, double costUsd});

/// Runs the planner: `claude -p` (stream-json, like the sessions) in the
/// workspace root, **read-only** like the Prompt "Perguntar" mode
/// (`--permission-mode default` + [ClaudeCodeProvider.readOnlyDisallowedTools];
/// any permission request is denied), `--json-schema` [plannerTaskSchema],
/// then stops the process after the `result`.
class TaskPlanner {
  TaskPlanner(this._ref);

  final Ref _ref;

  static const timeout = Duration(minutes: 5);

  /// Default `--max-budget-usd` of a planner run (safety net).
  static const defaultBudgetUsd = 0.5;

  /// CLI options of a run (pure; tested).
  static ClaudeOptions options({String? model, double? maxBudgetUsd}) =>
      ClaudeOptions(
        model: model == null || model.isEmpty || model == 'inherit'
            ? null
            : model,
        permissionMode: ClaudePermissionMode.defaultMode,
        disallowedTools: ClaudeCodeProvider.readOnlyDisallowedTools,
        appendSystemPrompt: plannerSystemPrompt,
        jsonSchema: jsonEncode(plannerTaskSchema),
        maxBudgetUsd: maxBudgetUsd ?? defaultBudgetUsd,
        includePartialMessages: false,
      );

  /// Generates and saves the tasks of [spec]. Throws [PlannerException].
  Future<PlannerOutcome> generate({
    required Workspace workspace,
    required Spec spec,
    String? model,
    double? maxBudgetUsd,
    String? agentName,
  }) async {
    final tasksRepo = _ref.read(tasksRepoProvider);
    final all = await tasksRepo.watchByWorkspace(workspace.id).first;
    final ofSpec = [
      for (final t in all)
        if (t.specId == spec.id) '${t.code} — ${t.title}',
    ];
    final result = await _run(
      workspace.path,
      options(model: model, maxBudgetUsd: maxBudgetUsd),
      plannerPrompt(
        specPath: spec.path,
        specCode: spec.code,
        existingTasks: ofSpec,
      ),
    );
    await _ref
        .read(usageTrackerProvider)
        .handle(result, costDelta: result.totalCostUsd);
    final planned = parsePlannerResult(result);
    final tasks = await savePlannedTasks(
      tasksRepo,
      workspaceId: workspace.id,
      specId: spec.id,
      planned: planned,
      agentName: agentName,
      existingCodes: {for (final t in all) t.code},
    );
    return (tasks: tasks, costUsd: result.totalCostUsd);
  }

  Future<Result> _run(String cwd, ClaudeOptions o, String prompt) =>
      runReadOnlyClaude(_ref, cwd: cwd, options: o, prompt: prompt);
}

/// Runs one non-interactive turn of `claude -p` in [cwd] and returns its
/// `result`: permission requests are denied (read-only runs), rate limits go
/// to the usage tracker and the process is stopped afterwards. Throws
/// [PlannerException] when the CLI cannot start, exits early or times out.
Future<Result> runReadOnlyClaude(
  Ref ref, {
  required String cwd,
  required ClaudeOptions options,
  required String prompt,
  Duration timeout = TaskPlanner.timeout,
}) async {
  final ClaudeProcess process;
  try {
    process = await ClaudeProcess.start(
      options,
      workingDirectory: cwd,
      executable: ref.read(claudeExecutableProvider),
      starter: ref.read(claudeProcessStarterProvider),
    );
  } catch (e) {
    throw PlannerException('Falha ao iniciar o Claude Code: $e');
  }
  final done = Completer<Result>();
  final logSub = process.logs.listen(
    (l) => debugPrint('planner: $l'),
    onError: (_) {},
  );
  final sub = process.events.listen(
    (e) {
      switch (e) {
        case PermissionRequest():
          // Non-interactive and read-only: nothing to approve.
          process.deny(
            e.requestId,
            'O planner do Promptorium é somente leitura.',
          );
        case Result():
          if (!done.isCompleted) done.complete(e);
        case RateLimit():
          ref.read(usageTrackerProvider).handle(e);
        default:
          break;
      }
    },
    onDone: () {
      if (!done.isCompleted) {
        done.completeError(
          const PlannerException('O Claude Code encerrou antes de responder.'),
        );
      }
    },
  );
  try {
    await process.send(prompt);
    return await done.future.timeout(
      timeout,
      onTimeout: () => throw PlannerException(
        'O planner não respondeu em ${timeout.inMinutes} minutos.',
      ),
    );
  } finally {
    await process.stop(timeout: const Duration(seconds: 2));
    await sub.cancel();
    await logSub.cancel();
  }
}

final taskPlannerProvider = Provider(TaskPlanner.new);
