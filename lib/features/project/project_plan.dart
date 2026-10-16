import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/db/enums.dart';
import '../specs/spec_file.dart';

/// Planning of a new project (Projeto screen): the conversation with the
/// planner, the vision it extracts, the stack + CLAUDE.md and the roadmap of
/// specs (cards of the Quadro). Stored as JSON in `project_plans.data`.

/// Steps of the Projeto screen. The folder / repository step happens before
/// the plan exists (workspace picker → "Novo projeto…").
enum ProjectStep {
  vision('Visão', 'O que é e para quem'),
  stack('Stack e convenções', 'Tecnologias e CLAUDE.md'),
  roadmap('Roadmap', 'Specs e dependências'),
  create('Revisar e criar', 'Arquivos, quadro e 1ª sessão');

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

/// Phase of a roadmap spec: the foundation runs first, one spec at a time;
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

/// A spec of the roadmap: one card of the Quadro, one branch, one PR. Its
/// requirements are the steps the agent runs, one session each.
@immutable
class RoadmapSpec {
  const RoadmapSpec({
    this.code = '',
    required this.title,
    required this.phase,
    this.objective = '',
    this.requirements = const [],
    this.acceptance = const [],
    this.dependsOn = const [],
  });

  /// Planner code, unique in the roadmap (`S1`); becomes `SPEC-NNN`.
  final String code;
  final String title;
  final RoadmapPhase phase;
  final String objective;
  final List<SpecRequirement> requirements;
  final List<String> acceptance;

  /// Codes of the specs that must be done first.
  final List<String> dependsOn;

  RoadmapSpec copyWith({
    String? code,
    String? title,
    RoadmapPhase? phase,
    String? objective,
    List<SpecRequirement>? requirements,
    List<String>? acceptance,
    List<String>? dependsOn,
  }) => RoadmapSpec(
    code: code ?? this.code,
    title: title ?? this.title,
    phase: phase ?? this.phase,
    objective: objective ?? this.objective,
    requirements: requirements ?? this.requirements,
    acceptance: acceptance ?? this.acceptance,
    dependsOn: dependsOn ?? this.dependsOn,
  );

  factory RoadmapSpec.fromJson(Map j) {
    final reqs = j['requirements'];
    return RoadmapSpec(
      code: _str(j['code']),
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
      dependsOn: _strings(j['dependsOn']),
    );
  }

  Map<String, Object?> toJson() => {
    'code': code,
    'title': title,
    'phase': phase.name,
    'objective': objective,
    'requirements': [
      for (final r in requirements) {'id': r.id, 'text': r.text},
    ],
    'acceptance': acceptance,
    'dependsOn': dependsOn,
  };
}

@immutable
class Roadmap {
  const Roadmap({
    this.specs = const [],
    this.later = const [],
    this.edited = false,
  });

  /// More requirements than this and the spec is too big for one PR: the
  /// planner is told to split it and the screen suggests doing so.
  static const maxRequirements = 6;

  /// Foundation specs first, then the MVP (see [normalized]).
  final List<RoadmapSpec> specs;

  /// Out-of-scope ideas (not turned into specs).
  final List<String> later;

  /// Changed by the user after the planner generated it (regenerating
  /// discards the changes, so the UI asks first).
  final bool edited;

  Roadmap copyWith({
    List<RoadmapSpec>? specs,
    List<String>? later,
    bool? edited,
  }) => Roadmap(
    specs: specs ?? this.specs,
    later: later ?? this.later,
    edited: edited ?? this.edited,
  );

  /// A spec code not used yet (`S<n>`).
  String nextSpecCode() {
    final used = {for (final s in specs) s.code};
    var n = used.length + 1;
    while (used.contains('S$n')) {
      n++;
    }
    return 'S$n';
  }

  /// At least one spec with requirements (the steps).
  bool get isReady => specs.any((s) => s.requirements.isNotEmpty);

  List<RoadmapSpec> ofPhase(RoadmapPhase p) => [
    for (final s in specs)
      if (s.phase == p) s,
  ];

  /// Number of spec dependencies.
  int get dependencyCount => specs.fold(0, (n, s) => n + s.dependsOn.length);

  /// Total of requirements (steps) of every spec.
  int get stepCount => specs.fold(0, (n, s) => n + s.requirements.length);

  /// Specs too big for one PR ([maxRequirements]).
  List<RoadmapSpec> get oversized => [
    for (final s in specs)
      if (s.requirements.length > maxRequirements) s,
  ];

  /// Rules the app enforces on the planner output: foundation specs first;
  /// unique spec codes (missing / repeated ones become `S<n>`); dependencies
  /// only on known specs (no self references, no repeats); MVP specs
  /// without dependencies wait for every foundation spec (sessions start
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
        c = 'S${++n}';
      } while (used.contains(c));
      return c;
    }

    // Codes: keep the planner's when unique.
    final coded = <RoadmapSpec>[];
    for (final s in ordered) {
      final code = s.code.isEmpty || used.contains(s.code) ? fresh() : s.code;
      used.add(code);
      coded.add(s.copyWith(code: code));
    }
    final foundation = [
      for (final s in coded)
        if (s.phase == RoadmapPhase.foundation) s.code,
    ];
    final out = <RoadmapSpec>[];
    for (final s in coded) {
      final deps = <String>[];
      for (final d in s.dependsOn) {
        if (used.contains(d) && d != s.code && !deps.contains(d)) deps.add(d);
      }
      if (s.phase == RoadmapPhase.mvp && deps.isEmpty) {
        deps.addAll(foundation);
      }
      out.add(s.copyWith(dependsOn: deps));
    }
    return Roadmap(specs: out, later: later, edited: edited);
  }

  /// Specs grouped by when they can start: wave 0 has no dependencies, wave
  /// n depends on specs of earlier waves. Cycles end up in the last wave.
  List<List<RoadmapSpec>> waves() {
    final all = specs.toList();
    final level = <String, int>{};
    var pending = all;
    while (pending.isNotEmpty) {
      final next = <RoadmapSpec>[];
      for (final s in pending) {
        final deps = s.dependsOn.where((d) => all.any((x) => x.code == d));
        if (deps.every(level.containsKey)) {
          level[s.code] =
              deps.fold(-1, (m, d) => m > level[d]! ? m : level[d]!) + 1;
        } else {
          next.add(s);
        }
      }
      if (next.length == pending.length) {
        final last = level.values.fold(-1, (m, v) => m > v ? m : v) + 1;
        for (final s in next) {
          level[s.code] = last;
        }
        break;
      }
      pending = next;
    }
    final count = level.values.fold(-1, (m, v) => m > v ? m : v) + 1;
    return [
      for (var i = 0; i < count; i++)
        [
          for (final s in all)
            if (level[s.code] == i) s,
        ],
    ];
  }

  /// The spec to run first: a foundation spec without dependencies.
  RoadmapSpec? get firstSpec {
    for (final s in ofPhase(RoadmapPhase.foundation)) {
      if (s.dependsOn.isEmpty && s.requirements.isNotEmpty) return s;
    }
    return specs
        .where((s) => s.dependsOn.isEmpty && s.requirements.isNotEmpty)
        .firstOrNull;
  }

  factory Roadmap.fromJson(Object? j) {
    if (j is! Map) return const Roadmap();
    final raw = j['specs'];
    final list = [
      if (raw is List)
        for (final s in raw)
          if (s is Map && _str(s['title']).isNotEmpty) s,
    ];
    // Drafts saved when the roadmap had tasks: codes by position, and the
    // dependencies between tasks of different specs become dependencies
    // between those specs.
    final legacy =
        list.any((s) => s['tasks'] is List) &&
        list.every((s) => !s.containsKey('dependsOn'));
    final codeOf = <String, String>{};
    if (legacy) {
      for (var i = 0; i < list.length; i++) {
        final tasks = list[i]['tasks'];
        if (tasks is List) {
          for (final t in tasks) {
            if (t is Map && _str(t['code']).isNotEmpty) {
              codeOf[_str(t['code'])] = 'S${i + 1}';
            }
          }
        }
      }
    }
    final specs = <RoadmapSpec>[];
    for (var i = 0; i < list.length; i++) {
      var s = RoadmapSpec.fromJson(list[i]);
      if (legacy) {
        final deps = <String>{};
        final tasks = list[i]['tasks'];
        if (tasks is List) {
          for (final t in tasks) {
            if (t is! Map) continue;
            for (final d in _strings(t['dependsOn'])) {
              final other = codeOf[d];
              if (other != null && other != 'S${i + 1}') deps.add(other);
            }
          }
        }
        s = s.copyWith(code: 'S${i + 1}', dependsOn: deps.toList());
      }
      specs.add(s);
    }
    return Roadmap(
      specs: specs,
      later: _strings(j['later']),
      edited: j['edited'] == true,
    );
  }

  Map<String, Object?> toJson() => {
    'specs': [for (final s in specs) s.toJson()],
    'later': later,
    if (edited) 'edited': true,
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
String roadmapSpecMarkdown(
  RoadmapSpec s, {
  required String code,
  List<String> dependsOn = const [],
}) {
  final b = StringBuffer()
    ..writeln('---')
    ..writeln('id: $code')
    ..writeln('status: ${specStatusValue(SpecStatus.approved)}')
    ..writeln(
      'fase: ${s.phase == RoadmapPhase.foundation ? 'fundacao' : 'mvp'}',
    );
  if (dependsOn.isNotEmpty) {
    b.writeln('$dependsOnKey: [${dependsOn.join(', ')}]');
  }
  b
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
