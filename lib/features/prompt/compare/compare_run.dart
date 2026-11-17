import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/claude/claude_event.dart';
import '../../../core/providers/agent_provider.dart' show PromptMode;
import '../../sessions/timeline.dart';

/// "Comparar respostas" (SPEC-079): the same prompt on two sides, side by
/// side. The run is stored as one event of the conversation
/// (`conversation_events`, [AppEventTypes.compare]) with both sides.

/// Where a side is.
enum CompareSideState {
  /// Waiting for its process (the usage is read first, R8).
  starting,
  running,

  /// The turn ended with a `result`.
  done,

  /// Planejar reached "plano pronto" and stopped there (R3).
  planReady,

  /// Stopped by the person, or still running when the app closed (R10, R13).
  stopped,

  /// The process ended with an error, or before answering.
  error;

  bool get live => this == starting || this == running;

  /// A side that can be chosen (R11).
  bool get choosable => this == done || this == planReady || this == stopped;

  static CompareSideState fromName(String? n) =>
      values.asNameMap()[n] ?? CompareSideState.stopped;
}

/// Lifecycle of the whole comparison.
enum CompareStatus {
  open,
  chosen;

  static CompareStatus fromName(String? n) =>
      values.asNameMap()[n] ?? CompareStatus.open;
}

/// One reading of the plan usage (`/usage` or a `rate_limit_event`), 0–1.
@immutable
class UsageReading {
  const UsageReading({
    this.five,
    this.week,
    this.fiveResetsAt,
    this.weekResetsAt,
  });

  factory UsageReading.of(RateLimit r) => UsageReading(
    five: r.fiveHourUtilization,
    week: r.sevenDayUtilization,
    fiveResetsAt: r.fiveHourResetsAt,
    weekResetsAt: r.sevenDayResetsAt,
  );

  final double? five;
  final double? week;
  final DateTime? fiveResetsAt;
  final DateTime? weekResetsAt;

  Map<String, dynamic> toJson() => {
    'five': ?five,
    'week': ?week,
    if (fiveResetsAt != null) 'fiveResetsAt': fiveResetsAt!.toIso8601String(),
    if (weekResetsAt != null) 'weekResetsAt': weekResetsAt!.toIso8601String(),
  };

  static UsageReading? fromJson(Object? j) {
    if (j is! Map) return null;
    double? d(Object? v) => v is num ? v.toDouble() : null;
    DateTime? t(Object? v) => v is String ? DateTime.tryParse(v) : null;
    return UsageReading(
      five: d(j['five']),
      week: d(j['week']),
      fiveResetsAt: t(j['fiveResetsAt']),
      weekResetsAt: t(j['weekResetsAt']),
    );
  }
}

/// What one side spent, from its `result` (R7). No US$ is ever shown: the
/// cost only splits the weight between the sides (R8).
@immutable
class CompareMetrics {
  const CompareMetrics({
    this.durationMs = 0,
    this.tokensIn = 0,
    this.tokensOut = 0,
    this.costUsd = 0,
    this.tools = const {},
  });

  factory CompareMetrics.ofResult(Result r, Map<String, int> tools) {
    final u = r.usage;
    return CompareMetrics(
      durationMs: r.durationMs,
      tokensIn:
          u.inputTokens + u.cacheCreationInputTokens + u.cacheReadInputTokens,
      tokensOut: u.outputTokens,
      costUsd: r.totalCostUsd,
      tools: Map.unmodifiable(tools),
    );
  }

  final int durationMs;

  /// Input with the cache.
  final int tokensIn;
  final int tokensOut;

  /// Only a proportion (R8).
  final double costUsd;

  /// Top-level tool calls of the turn, by tool name.
  final Map<String, int> tools;

  Map<String, dynamic> toJson() => {
    'durationMs': durationMs,
    'tokensIn': tokensIn,
    'tokensOut': tokensOut,
    'costUsd': costUsd,
    'tools': tools,
  };

  static CompareMetrics? fromJson(Object? j) {
    if (j is! Map) return null;
    int i(Object? v) => v is num ? v.toInt() : 0;
    final tools = j['tools'];
    return CompareMetrics(
      durationMs: i(j['durationMs']),
      tokensIn: i(j['tokensIn']),
      tokensOut: i(j['tokensOut']),
      costUsd: j['costUsd'] is num ? (j['costUsd'] as num).toDouble() : 0,
      tools: {
        if (tools is Map)
          for (final e in tools.entries)
            if (e.value is num) '${e.key}': (e.value as num).toInt(),
      },
    );
  }
}

/// Weight of a side in the 5-hour window and in the week (0–1, R8).
typedef SideWeight = ({double five, double week});

/// One side of a comparison (A or B).
@immutable
class CompareSide {
  const CompareSide({
    required this.letter,
    required this.model,
    required this.mode,
    this.sessionId,
    this.started = false,
    this.state = CompareSideState.starting,
    this.startedAt,
    this.metrics,
    this.weight,
    this.plan,
    this.events = const [],
    this.error,
  });

  /// `A` or `B`.
  final String letter;
  final String model;
  final PromptMode mode;

  /// The fork of this side (`--session-id` with `--fork-session`, R5).
  final String? sessionId;

  /// Its session exists in the CLI (a `system/init` arrived).
  final bool started;
  final CompareSideState state;

  /// When its turn started (the live time).
  final DateTime? startedAt;
  final CompareMetrics? metrics;
  final SideWeight? weight;

  /// The plan of "plano pronto" (Planejar).
  final String? plan;

  /// Its stored CLI events (raw JSON lines, no stream deltas), in order.
  final List<String> events;
  final String? error;

  CompareSide copyWith({
    String? model,
    PromptMode? mode,
    String? sessionId,
    bool? started,
    CompareSideState? state,
    DateTime? startedAt,
    CompareMetrics? metrics,
    SideWeight? weight,
    bool clearWeight = false,
    String? plan,
    List<String>? events,
    String? error,
  }) => CompareSide(
    letter: letter,
    model: model ?? this.model,
    mode: mode ?? this.mode,
    sessionId: sessionId ?? this.sessionId,
    started: started ?? this.started,
    state: state ?? this.state,
    startedAt: startedAt ?? this.startedAt,
    metrics: metrics ?? this.metrics,
    weight: clearWeight ? null : (weight ?? this.weight),
    plan: plan ?? this.plan,
    events: events ?? this.events,
    error: error ?? this.error,
  );

  Map<String, dynamic> toJson() => {
    'letter': letter,
    'model': model,
    'mode': mode.name,
    'sessionId': ?sessionId,
    'started': started,
    'state': state.name,
    if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
    if (metrics != null) 'metrics': metrics!.toJson(),
    if (weight != null) 'weight': {'five': weight!.five, 'week': weight!.week},
    'plan': ?plan,
    'events': events,
    'error': ?error,
  };

  static CompareSide fromJson(Map<String, dynamic> j) {
    final w = j['weight'];
    return CompareSide(
      letter: '${j['letter'] ?? 'A'}',
      model: '${j['model'] ?? 'inherit'}',
      mode: PromptMode.fromName(j['mode'] as String?),
      sessionId: j['sessionId'] as String?,
      started: j['started'] == true,
      state: CompareSideState.fromName(j['state'] as String?),
      startedAt: DateTime.tryParse('${j['startedAt']}'),
      metrics: CompareMetrics.fromJson(j['metrics']),
      weight: w is Map && w['five'] is num && w['week'] is num
          ? (
              five: (w['five'] as num).toDouble(),
              week: (w['week'] as num).toDouble(),
            )
          : null,
      plan: j['plan'] as String?,
      events: [
        for (final e in (j['events'] as List?) ?? const [])
          if (e is String) e,
      ],
      error: j['error'] as String?,
    );
  }

  /// The timeline of this side, from its stored events.
  Timeline timeline() {
    final t = Timeline();
    for (final e in events) {
      t.applyStored(e);
    }
    return t;
  }

  /// `Sonnet · Perguntar`.
  String get label => '${compareModelLabel(model)} · ${mode.label}';
}

/// The comparison of one conversation.
@immutable
class CompareRun {
  const CompareRun({
    required this.conversationId,
    required this.prompt,
    required this.at,
    required this.sides,
    this.seq,
    this.originalSessionId,
    this.originalModel,
    this.originalMode,
    this.before,
    this.after,
    this.measured = false,
    this.status = CompareStatus.open,
    this.chosen,
  });

  final int conversationId;
  final String prompt;
  final DateTime at;

  /// A and B, in this order.
  final List<CompareSide> sides;

  /// `seq` of its row in `conversation_events`.
  final int? seq;

  /// The conversation before the comparison (R12): its session, model and
  /// mode.
  final String? originalSessionId;
  final String? originalModel;
  final PromptMode? originalMode;

  /// Readings of the plan usage before and after the two sides (R8).
  final UsageReading? before;
  final UsageReading? after;

  /// The weights come from the two readings (false = the Atividades rule).
  final bool measured;
  final CompareStatus status;

  /// Letter of the chosen side.
  final String? chosen;

  CompareSide get a => sides[0];
  CompareSide get b => sides[1];

  CompareSide side(String letter) =>
      sides.firstWhere((s) => s.letter == letter);

  CompareSide? get chosenSide => chosen == null ? null : side(chosen!);

  CompareSide? get otherSide =>
      chosen == null ? null : sides.firstWhere((s) => s.letter != chosen);

  bool get anyLive => sides.any((s) => s.state.live);

  bool get allDone => sides.every((s) => !s.state.live);

  CompareRun copyWith({
    List<CompareSide>? sides,
    int? seq,
    UsageReading? before,
    UsageReading? after,
    bool clearAfter = false,
    bool? measured,
    CompareStatus? status,
    String? chosen,
  }) => CompareRun(
    conversationId: conversationId,
    prompt: prompt,
    at: at,
    sides: sides ?? this.sides,
    seq: seq ?? this.seq,
    originalSessionId: originalSessionId,
    originalModel: originalModel,
    originalMode: originalMode,
    before: before ?? this.before,
    after: clearAfter ? null : (after ?? this.after),
    measured: measured ?? this.measured,
    status: status ?? this.status,
    chosen: chosen ?? this.chosen,
  );

  CompareRun withSide(CompareSide s) =>
      copyWith(sides: [for (final o in sides) o.letter == s.letter ? s : o]);

  Map<String, dynamic> toJson() => {
    'type': AppEventTypes.compare,
    'at': at.toIso8601String(),
    'prompt': prompt,
    'status': status.name,
    'chosen': ?chosen,
    'originalSessionId': ?originalSessionId,
    'originalModel': ?originalModel,
    'originalMode': ?originalMode?.name,
    if (before != null) 'before': before!.toJson(),
    if (after != null) 'after': after!.toJson(),
    'measured': measured,
    'sides': [for (final s in sides) s.toJson()],
  };

  String encode() => jsonEncode(toJson());

  /// From a stored row; null when it is not a comparison.
  static CompareRun? fromJson(
    Map<String, dynamic> j, {
    required int conversationId,
    int? seq,
  }) {
    if (j['type'] != AppEventTypes.compare) return null;
    final sides = [
      for (final s in (j['sides'] as List?) ?? const [])
        if (s is Map<String, dynamic>) CompareSide.fromJson(s),
    ];
    if (sides.length != 2) return null;
    return CompareRun(
      conversationId: conversationId,
      prompt: '${j['prompt'] ?? ''}',
      at: DateTime.tryParse('${j['at']}')?.toLocal() ?? DateTime.now(),
      sides: sides,
      seq: seq,
      originalSessionId: j['originalSessionId'] as String?,
      originalModel: j['originalModel'] as String?,
      originalMode: j['originalMode'] == null
          ? null
          : PromptMode.fromName(j['originalMode'] as String?),
      before: UsageReading.fromJson(j['before']),
      after: UsageReading.fromJson(j['after']),
      measured: j['measured'] == true,
      status: CompareStatus.fromName(j['status'] as String?),
      chosen: j['chosen'] as String?,
    );
  }
}

/// What a side is set to before sending: model and mode.
typedef CompareChoice = ({String model, PromptMode mode});

/// Modes a side accepts (R3): never Editar.
const compareModes = [PromptMode.ask, PromptMode.plan];

/// Why Editar is off on a side (R3).
const compareEditHint =
    'Editar mudaria a pasta duas vezes ao mesmo tempo. Compare em Perguntar '
    'ou Planejar.';

/// Same model and same mode on both sides (R2).
const compareSameSidesMessage =
    'Os dois lados estão iguais. Troque o modelo ou o modo de um deles.';

/// The composer while a comparison waits for a choice (R14).
const compareBlockedMessage = 'Escolha uma resposta para continuar.';

/// The "other" model of side B (R1, P8): Sonnet ↔ Opus, Haiku → Sonnet.
String otherCompareModel(String model) => switch (model) {
  'opus' => 'sonnet',
  'sonnet' => 'opus',
  'haiku' => 'sonnet',
  _ => 'opus',
};

/// `sonnet` → `Sonnet`; `inherit` → `Padrão`.
String compareModelLabel(String model) {
  if (model.isEmpty || model == 'inherit') return 'Padrão';
  return model[0].toUpperCase() + model.substring(1);
}

/// The two sides when Comparar is turned on (R1): A = the current model
/// and mode, B = the other model in the same mode. "Modelo padrão" is
/// compared as Sonnet × Opus (the most common doubt, P8). Editar becomes
/// Perguntar.
(CompareChoice, CompareChoice) defaultCompareSides(
  String model,
  PromptMode mode,
) {
  final m = compareModes.contains(mode) ? mode : PromptMode.ask;
  final a = model == 'inherit' || model.isEmpty ? 'sonnet' : model;
  return ((model: a, mode: m), (model: otherCompareModel(a), mode: m));
}

/// Two sides that cannot be sent (R2, R3); null = fine.
String? compareSidesProblem(CompareChoice a, CompareChoice b) {
  if (!compareModes.contains(a.mode) || !compareModes.contains(b.mode)) {
    return compareEditHint;
  }
  if (a.model == b.model && a.mode == b.mode) return compareSameSidesMessage;
  return null;
}

/// The last pair of a workspace (P8), stored in `app_settings`.
String encodeCompareSides(CompareChoice a, CompareChoice b) => jsonEncode({
  'a': {'model': a.model, 'mode': a.mode.name},
  'b': {'model': b.model, 'mode': b.mode.name},
});

(CompareChoice, CompareChoice)? decodeCompareSides(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final j = jsonDecode(raw);
    if (j is! Map) return null;
    CompareChoice? one(Object? s) {
      if (s is! Map || s['model'] is! String) return null;
      final mode = PromptMode.fromName(s['mode'] as String?);
      if (!compareModes.contains(mode)) return null;
      return (model: s['model'] as String, mode: mode);
    }

    final a = one(j['a']), b = one(j['b']);
    if (a == null || b == null || compareSidesProblem(a, b) != null) {
      return null;
    }
    return (a, b);
  } catch (_) {
    return null;
  }
}
