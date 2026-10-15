import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/db/enums.dart';
import '../specs/spec_file.dart';

/// Planning of a new project (Projeto screen): the conversation with the
/// planner, the vision it extracts, the stack + CLAUDE.md and the roadmap of
/// specs and tasks. Stored as JSON in `project_plans.data`.

/// Steps of the Projeto screen. The folder / repository step happens before
/// the plan exists (workspace picker → "Novo projeto…").
enum ProjectStep {
  vision('Visão', 'O que é e para quem'),
  stack('Stack e convenções', 'Tecnologias e CLAUDE.md'),
  roadmap('Roadmap', 'Specs e tarefas'),
  create('Revisar e criar', 'Arquivos, tarefas e 1ª sessão');

  const ProjectStep(this.label, this.hint);

  final String label;
  final String hint;

  static ProjectStep fromName(String? name) =>
      values.asNameMap()[name] ?? vision;
}

List<String> _strings(Object? v) => [
  if (v is List)
    for (final e in v)
      if ('$e'.trim().isNotEmpty) '$e'.trim(),
];

String _str(Object? v) => v == null ? '' : '$v'.trim();

/// One message of the Visão conversation.
@immutable
class PlanMessage {
  const PlanMessage({
    required this.fromUser,
    required this.text,
    this.suggestions = const [],
    this.note,
    this.error = false,
  });

  final bool fromUser;
  final String text;

  /// Quick replies offered by the planner (clickable chips).
  final List<String> suggestions;

  /// "Plano atualizado · …" line shown before a planner answer.
  final String? note;

  /// Failure of a turn (shown in red; not sent to the planner).
  final bool error;

  factory PlanMessage.fromJson(Map<String, Object?> j) => PlanMessage(
    fromUser: j['fromUser'] == true,
    text: _str(j['text']),
    suggestions: _strings(j['suggestions']),
    note: j['note'] is String ? j['note'] as String : null,
    error: j['error'] == true,
  );

  Map<String, Object?> toJson() => {
    'fromUser': fromUser,
    'text': text,
    if (suggestions.isNotEmpty) 'suggestions': suggestions,
    'note': ?note,
    if (error) 'error': true,
  };
}

/// What the project is (right panel of Visão).
@immutable
class VisionPlan {
  const VisionPlan({
    this.name = '',
    this.summary = '',
    this.audience = '',
    this.mvp = const [],
    this.outOfScope = const [],
    this.openQuestions = const [],
  });

  final String name;
  final String summary;
  final String audience;
  final List<String> mvp;
  final List<String> outOfScope;
  final List<String> openQuestions;

  /// Enough to propose a stack.
  bool get isReady => summary.isNotEmpty && mvp.isNotEmpty;

  bool get isEmpty =>
      name.isEmpty &&
      summary.isEmpty &&
      audience.isEmpty &&
      mvp.isEmpty &&
      outOfScope.isEmpty &&
      openQuestions.isEmpty;

  factory VisionPlan.fromJson(Object? j) {
    if (j is! Map) return const VisionPlan();
    return VisionPlan(
      name: _str(j['name']),
      summary: _str(j['summary']),
      audience: _str(j['audience']),
      mvp: _strings(j['mvp']),
      outOfScope: _strings(j['outOfScope']),
      openQuestions: _strings(j['openQuestions']),
    );
  }

  Map<String, Object?> toJson() => {
    'name': name,
    'summary': summary,
    'audience': audience,
    'mvp': mvp,
    'outOfScope': outOfScope,
    'openQuestions': openQuestions,
  };
}

/// "Plano atualizado · Resumo · MVP +2" (null when nothing changed).
String? visionChanges(VisionPlan before, VisionPlan after) {
  final parts = <String>[];
  void text(String label, String a, String b) {
    if (a != b && b.isNotEmpty) parts.add(label);
  }

  void list(String label, List<String> a, List<String> b) {
    final added = b.where((x) => !a.contains(x)).length;
    final removed = a.where((x) => !b.contains(x)).length;
    if (added > 0) {
      parts.add('$label +$added');
    } else if (removed > 0) {
      parts.add('$label −$removed');
    }
  }

  text('Nome', before.name, after.name);
  text('Resumo', before.summary, after.summary);
  text('Público', before.audience, after.audience);
  list('MVP', before.mvp, after.mvp);
  list('Fora do escopo', before.outOfScope, after.outOfScope);
  list('Em aberto', before.openQuestions, after.openQuestions);
  return parts.isEmpty ? null : 'Plano atualizado · ${parts.join(' · ')}';
}

/// One stack choice (aplicação, banco, testes…).
@immutable
class StackDecision {
  const StackDecision({
    required this.area,
    required this.choice,
    this.why = '',
    this.alternatives = const [],
    this.pinned = false,
  });

  /// Value of a choice the planner could not make yet.
  static const undecided = '[A DEFINIR]';

  final String area;
  final String choice;
  final String why;
  final List<String> alternatives;

  /// Chosen by the user (kept when the planner proposes again).
  final bool pinned;

  bool get isUndecided => choice.isEmpty || choice == undecided;

  /// Picks [option] (an alternative); the previous choice becomes one.
  StackDecision choose(String option) => StackDecision(
    area: area,
    choice: option,
    why: why,
    alternatives: [
      if (!isUndecided) choice,
      for (final a in alternatives)
        if (a != option) a,
    ],
    pinned: true,
  );

  factory StackDecision.fromJson(Map j) => StackDecision(
    area: _str(j['area']),
    choice: _str(j['choice']),
    why: _str(j['why']),
    alternatives: _strings(j['alternatives']),
    pinned: j['pinned'] == true,
  );

  Map<String, Object?> toJson() => {
    'area': area,
    'choice': choice,
    'why': why,
    'alternatives': alternatives,
    if (pinned) 'pinned': true,
  };
}

@immutable
class StackPlan {
  const StackPlan({
    this.decisions = const [],
    this.claudeMd = '',
    this.claudeMdStale = false,
  });

  final List<StackDecision> decisions;

  /// Content of the project's CLAUDE.md (editable).
  final String claudeMd;

  /// A choice changed after [claudeMd] was generated.
  final bool claudeMdStale;

  bool get isReady => decisions.isNotEmpty;

  StackPlan copyWith({
    List<StackDecision>? decisions,
    String? claudeMd,
    bool? claudeMdStale,
  }) => StackPlan(
    decisions: decisions ?? this.decisions,
    claudeMd: claudeMd ?? this.claudeMd,
    claudeMdStale: claudeMdStale ?? this.claudeMdStale,
  );

  factory StackPlan.fromJson(Object? j) {
    if (j is! Map) return const StackPlan();
    final list = j['decisions'];
    return StackPlan(
      decisions: [
        if (list is List)
          for (final d in list)
            if (d is Map && _str(d['area']).isNotEmpty)
              StackDecision.fromJson(d),
      ],
      claudeMd: j['claudeMd'] is String ? j['claudeMd'] as String : '',
      claudeMdStale: j['claudeMdStale'] == true,
    );
  }

  Map<String, Object?> toJson() => {
    'decisions': [for (final d in decisions) d.toJson()],
    'claudeMd': claudeMd,
    if (claudeMdStale) 'claudeMdStale': true,
  };
}

/// Phase of a roadmap spec: the foundation runs first, one task at a time;
/// the MVP is released after its merge.
enum RoadmapPhase {
  foundation('Fundação'),
  mvp('MVP');

  const RoadmapPhase(this.label);

  final String label;

  static RoadmapPhase fromName(Object? v) =>
      '$v'.toLowerCase().contains('found') || '$v'.toLowerCase() == 'fundacao'
      ? foundation
      : mvp;
}

@immutable
class RoadmapTask {
  const RoadmapTask({
    required this.code,
    required this.title,
    this.description = '',
    this.requirement = '',
    this.dependsOn = const [],
  });

  /// Planner code, unique in the roadmap (`T1`); becomes `TASK-NNN`.
  final String code;
  final String title;
  final String description;
  final String requirement;
  final List<String> dependsOn;

  RoadmapTask withDeps(List<String> deps) => RoadmapTask(
    code: code,
    title: title,
    description: description,
    requirement: requirement,
    dependsOn: deps,
  );

  factory RoadmapTask.fromJson(Map j) => RoadmapTask(
    code: _str(j['code']),
    title: _str(j['title']),
    description: _str(j['description']),
    requirement: _str(j['requirement']),
    dependsOn: _strings(j['dependsOn']),
  );

  Map<String, Object?> toJson() => {
    'code': code,
    'title': title,
    'description': description,
    'requirement': requirement,
    'dependsOn': dependsOn,
  };
}

@immutable
class RoadmapSpec {
  const RoadmapSpec({
    required this.title,
    required this.phase,
    this.objective = '',
    this.requirements = const [],
    this.acceptance = const [],
    this.tasks = const [],
  });

  final String title;
  final RoadmapPhase phase;
  final String objective;
  final List<SpecRequirement> requirements;
  final List<String> acceptance;
  final List<RoadmapTask> tasks;

  RoadmapSpec withTasks(List<RoadmapTask> tasks) => RoadmapSpec(
    title: title,
    phase: phase,
    objective: objective,
    requirements: requirements,
    acceptance: acceptance,
    tasks: tasks,
  );

  factory RoadmapSpec.fromJson(Map j) {
    final reqs = j['requirements'];
    final tasks = j['tasks'];
    return RoadmapSpec(
      title: _str(j['title']),
      phase: RoadmapPhase.fromName(j['phase']),
      objective: _str(j['objective']),
      requirements: [
        if (reqs is List)
          for (final r in reqs)
            if (r is Map && _str(r['id']).isNotEmpty)
              (id: _str(r['id']), text: _str(r['text'])),
      ],
      acceptance: _strings(j['acceptance']),
      tasks: [
        if (tasks is List)
          for (final t in tasks)
            if (t is Map && _str(t['title']).isNotEmpty)
              RoadmapTask.fromJson(t),
      ],
    );
  }

  Map<String, Object?> toJson() => {
    'title': title,
    'phase': phase.name,
    'objective': objective,
    'requirements': [
      for (final r in requirements) {'id': r.id, 'text': r.text},
    ],
    'acceptance': acceptance,
    'tasks': [for (final t in tasks) t.toJson()],
  };
}

@immutable
class Roadmap {
  const Roadmap({this.specs = const [], this.later = const []});

  /// Foundation specs first, then the MVP (see [normalized]).
  final List<RoadmapSpec> specs;

  /// Out-of-scope ideas (not turned into tasks).
  final List<String> later;

  bool get isReady => specs.any((s) => s.tasks.isNotEmpty);

  Iterable<RoadmapTask> get tasks => specs.expand((s) => s.tasks);

  List<RoadmapSpec> ofPhase(RoadmapPhase p) => [
    for (final s in specs)
      if (s.phase == p) s,
  ];

  /// Number of task dependencies.
  int get dependencyCount => tasks.fold(0, (n, t) => n + t.dependsOn.length);

  /// Rules the app enforces on the planner output: foundation specs first;
  /// unique task codes (missing / repeated ones become `T<n>`); dependencies
  /// only on known, earlier-or-other tasks (no self references); MVP tasks
  /// without dependencies wait for every foundation task (sessions start
  /// from the base branch, so the foundation must be merged first).
  Roadmap normalized() {
    final ordered = [
      ...ofPhase(RoadmapPhase.foundation),
      ...ofPhase(RoadmapPhase.mvp),
    ];
    final used = <String>{};
    var n = 0;
    String fresh() {
      String c;
      do {
        c = 'T${++n}';
      } while (used.contains(c));
      return c;
    }

    // Codes: keep the planner's when unique.
    final renamed = <List<RoadmapTask>>[];
    for (final s in ordered) {
      final list = <RoadmapTask>[];
      for (final t in s.tasks) {
        final code = t.code.isEmpty || used.contains(t.code) ? fresh() : t.code;
        used.add(code);
        list.add(
          RoadmapTask(
            code: code,
            title: t.title,
            description: t.description,
            requirement: t.requirement,
            dependsOn: t.dependsOn,
          ),
        );
      }
      renamed.add(list);
    }
    final foundation = [
      for (var i = 0; i < ordered.length; i++)
        if (ordered[i].phase == RoadmapPhase.foundation)
          for (final t in renamed[i]) t.code,
    ];
    final out = <RoadmapSpec>[];
    for (var i = 0; i < ordered.length; i++) {
      final s = ordered[i];
      final tasks = [
        for (final t in renamed[i])
          () {
            final deps = <String>[];
            for (final d in t.dependsOn) {
              if (used.contains(d) && d != t.code && !deps.contains(d)) {
                deps.add(d);
              }
            }
            if (s.phase == RoadmapPhase.mvp && deps.isEmpty) {
              deps.addAll(foundation);
            }
            return t.withDeps(deps);
          }(),
      ];
      out.add(s.withTasks(tasks));
    }
    return Roadmap(specs: out, later: later);
  }

  /// Tasks grouped by when they can start: wave 0 has no dependencies, wave
  /// n depends on tasks of earlier waves. Cycles end up in the last wave.
  List<List<RoadmapTask>> waves() {
    final all = tasks.toList();
    final level = <String, int>{};
    var pending = all;
    while (pending.isNotEmpty) {
      final next = <RoadmapTask>[];
      for (final t in pending) {
        final deps = t.dependsOn.where((d) => all.any((x) => x.code == d));
        if (deps.every(level.containsKey)) {
          level[t.code] =
              deps.fold(-1, (m, d) => m > level[d]! ? m : level[d]!) + 1;
        } else {
          next.add(t);
        }
      }
      if (next.length == pending.length) {
        final last = level.values.fold(-1, (m, v) => m > v ? m : v) + 1;
        for (final t in next) {
          level[t.code] = last;
        }
        break;
      }
      pending = next;
    }
    final count = level.values.fold(-1, (m, v) => m > v ? m : v) + 1;
    return [
      for (var i = 0; i < count; i++)
        [
          for (final t in all)
            if (level[t.code] == i) t,
        ],
    ];
  }

  /// The task to run first: a foundation task without dependencies.
  RoadmapTask? get firstTask {
    for (final s in ofPhase(RoadmapPhase.foundation)) {
      for (final t in s.tasks) {
        if (t.dependsOn.isEmpty) return t;
      }
    }
    return tasks.where((t) => t.dependsOn.isEmpty).firstOrNull;
  }

  factory Roadmap.fromJson(Object? j) {
    if (j is! Map) return const Roadmap();
    final specs = j['specs'];
    return Roadmap(
      specs: [
        if (specs is List)
          for (final s in specs)
            if (s is Map && _str(s['title']).isNotEmpty)
              RoadmapSpec.fromJson(s),
      ],
      later: _strings(j['later']),
    );
  }

  Map<String, Object?> toJson() => {
    'specs': [for (final s in specs) s.toJson()],
    'later': later,
  };
}

/// Everything stored in `project_plans.data`.
@immutable
class ProjectPlanData {
  const ProjectPlanData({
    this.messages = const [],
    this.vision = const VisionPlan(),
    this.stack = const StackPlan(),
    this.roadmap = const Roadmap(),
  });

  final List<PlanMessage> messages;
  final VisionPlan vision;
  final StackPlan stack;
  final Roadmap roadmap;

  /// Steps that can be opened (each needs the previous one).
  bool reachable(ProjectStep s) => switch (s) {
    ProjectStep.vision => true,
    ProjectStep.stack => vision.isReady,
    ProjectStep.roadmap => vision.isReady && stack.isReady,
    ProjectStep.create => vision.isReady && stack.isReady && roadmap.isReady,
  };

  ProjectPlanData copyWith({
    List<PlanMessage>? messages,
    VisionPlan? vision,
    StackPlan? stack,
    Roadmap? roadmap,
  }) => ProjectPlanData(
    messages: messages ?? this.messages,
    vision: vision ?? this.vision,
    stack: stack ?? this.stack,
    roadmap: roadmap ?? this.roadmap,
  );

  factory ProjectPlanData.decode(String text) {
    Object? j;
    try {
      j = jsonDecode(text);
    } on FormatException {
      j = null;
    }
    if (j is! Map) return const ProjectPlanData();
    final msgs = j['messages'];
    return ProjectPlanData(
      messages: [
        if (msgs is List)
          for (final m in msgs)
            if (m is Map) PlanMessage.fromJson(m.cast<String, Object?>()),
      ],
      vision: VisionPlan.fromJson(j['vision']),
      stack: StackPlan.fromJson(j['stack']),
      roadmap: Roadmap.fromJson(j['roadmap']),
    );
  }

  String encode() => jsonEncode({
    'messages': [for (final m in messages) m.toJson()],
    'vision': vision.toJson(),
    'stack': stack.toJson(),
    'roadmap': roadmap.toJson(),
  });
}

/// File of a roadmap spec (same shape as "Nova spec", already approved).
String roadmapSpecMarkdown(RoadmapSpec s, {required String code}) {
  final b = StringBuffer()
    ..writeln('---')
    ..writeln('id: $code')
    ..writeln('status: ${specStatusValue(SpecStatus.approved)}')
    ..writeln(
      'fase: ${s.phase == RoadmapPhase.foundation ? 'fundacao' : 'mvp'}',
    )
    ..writeln('---')
    ..writeln()
    ..writeln('# ${s.title}')
    ..writeln()
    ..writeln('## Objetivo')
    ..writeln()
    ..writeln(s.objective.isEmpty ? s.title : s.objective)
    ..writeln()
    ..writeln('## Requisitos')
    ..writeln();
  for (final r in s.requirements) {
    b.writeln('- ${r.id} · ${r.text}');
  }
  if (s.acceptance.isNotEmpty) {
    b
      ..writeln()
      ..writeln('## Critérios de aceite')
      ..writeln();
    for (final a in s.acceptance) {
      b.writeln('- [ ] $a');
    }
  }
  return b.toString();
}
