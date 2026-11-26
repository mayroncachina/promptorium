import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/claude/claude_event.dart';
import '../../../core/claude/run_prefs.dart' show defaultEffort;
import '../../../core/providers/agent_provider.dart' show PromptMode;
import '../../../core/providers/capabilities.dart';
import '../../../core/providers/quota_source.dart';
import '../../cost/usage_ledger.dart' show reasoningTokensOf;
import '../../sessions/timeline.dart';
import 'compare_handoff.dart';

/// "Comparar respostas" (SPEC-079): the same prompt on two sides, side by
/// side. The run is stored as one event of the conversation
/// (`conversation_events`, [AppEventTypes.compare]) with both sides. Each
/// side has its provider, model, effort and mode (SPEC-108 R1).

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

/// One reading of the plan usage of one provider (0–1): the Claude's
/// (`/usage` or a `rate_limit_event`) or the Codex's (SPEC-108 R8). [five]
/// is the short window and [week] the long one, whose real durations are
/// [fiveMinutes] and [weekMinutes] (the Codex tells `windowDurationMins`).
@immutable
class UsageReading {
  const UsageReading({
    this.five,
    this.week,
    this.fiveResetsAt,
    this.weekResetsAt,
    this.fiveMinutes = 300,
    this.weekMinutes = 10080,
  });

  /// The windows of [s] (SPEC-097): the shortest is [five], the longest is
  /// [week]; a single window goes where its duration says (a day or more
  /// is the long one). Null without windows.
  static UsageReading? ofSnapshot(QuotaSnapshot? s) {
    if (s == null) return null;
    final ws = [
      for (final w in s.main.windows)
        if (w.usedPercent != null) w,
    ]..sort((a, b) => (a.minutes ?? 0).compareTo(b.minutes ?? 0));
    if (ws.isEmpty) return null;
    final single = ws.length == 1;
    final longOnly = single && (ws.first.minutes ?? 0) >= 1440;
    final short = longOnly ? null : ws.first;
    final long = longOnly ? ws.first : (single ? null : ws.last);
    return UsageReading(
      five: short == null ? null : short.usedPercent! / 100,
      week: long == null ? null : long.usedPercent! / 100,
      fiveResetsAt: short?.resetsAt,
      weekResetsAt: long?.resetsAt,
      fiveMinutes: short == null ? 300 : short.minutes ?? 0,
      weekMinutes: long == null ? 10080 : long.minutes ?? 0,
    );
  }

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

  /// Minutes of each window (0 = not informed).
  final int fiveMinutes;
  final int weekMinutes;

  Map<String, dynamic> toJson() => {
    'five': ?five,
    'week': ?week,
    if (fiveMinutes != 300) 'fiveMinutes': fiveMinutes,
    if (weekMinutes != 10080) 'weekMinutes': weekMinutes,
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
      fiveMinutes: j['fiveMinutes'] is num
          ? (j['fiveMinutes'] as num).toInt()
          : 300,
      weekMinutes: j['weekMinutes'] is num
          ? (j['weekMinutes'] as num).toInt()
          : 10080,
    );
  }
}

/// `janela de 5 h`, `semana`, `janela de 12 h`, `janela` (the real
/// duration, SPEC-108 R5).
String compareWindowLabel(int minutes) => switch (minutes) {
  10080 => 'semana',
  <= 0 => 'janela',
  _ => 'janela de ${QuotaWindow.labelOf(minutes)}',
};

/// `janela de 5 horas` (read aloud, R12).
String compareWindowSpoken(int minutes) => switch (minutes) {
  10080 => 'semana',
  <= 0 => 'janela',
  final m when m % 1440 == 0 =>
    m == 1440 ? 'janela de 1 dia' : 'janela de ${m ~/ 1440} dias',
  final m when m % 60 == 0 =>
    m == 60 ? 'janela de 1 hora' : 'janela de ${m ~/ 60} horas',
  final m => 'janela de $m minutos',
};

/// What one side spent, from its `result` (R7). No US$ is ever shown: the
/// cost only splits the weight between the sides (R8).
@immutable
class CompareMetrics {
  const CompareMetrics({
    this.durationMs = 0,
    this.tokensIn = 0,
    this.tokensOut = 0,
    this.reasoning = 0,
    this.costUsd = 0,
    this.tools = const {},
  });

  /// [elapsedMs] stands in when the agent does not tell the turn's time.
  factory CompareMetrics.ofResult(
    Result r,
    Map<String, int> tools, {
    int elapsedMs = 0,
  }) {
    final u = r.usage;
    return CompareMetrics(
      durationMs: r.durationMs > 0 ? r.durationMs : elapsedMs,
      tokensIn:
          u.inputTokens + u.cacheCreationInputTokens + u.cacheReadInputTokens,
      tokensOut: u.outputTokens,
      reasoning: reasoningTokensOf(r),
      costUsd: r.totalCostUsd,
      tools: Map.unmodifiable(tools),
    );
  }

  final int durationMs;

  /// Input with the cache.
  final int tokensIn;
  final int tokensOut;

  /// Reasoning, part of [tokensOut] (Codex, SPEC-108 R7).
  final int reasoning;

  /// Output without the reasoning.
  int get answerTokens => tokensOut > reasoning ? tokensOut - reasoning : 0;

  int get totalTokens => tokensIn + tokensOut;

  /// Only a proportion (R8).
  final double costUsd;

  /// Top-level tool calls of the turn, by tool name.
  final Map<String, int> tools;

  Map<String, dynamic> toJson() => {
    'durationMs': durationMs,
    'tokensIn': tokensIn,
    'tokensOut': tokensOut,
    if (reasoning > 0) 'reasoning': reasoning,
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
      reasoning: i(j['reasoning']),
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
    this.provider = 'claude',
    this.effort,
    this.handoff = false,
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

  /// Who answers on this side (SPEC-108 R1).
  final String provider;

  /// Effort of this side; null = the provider's preference (old events).
  final String? effort;

  /// It starts from the package, without the conversation's session (R4).
  final bool handoff;

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
    provider: provider,
    effort: effort,
    handoff: handoff,
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
    'provider': provider,
    'model': model,
    'effort': ?effort,
    'mode': mode.name,
    if (handoff) 'handoff': true,
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

  /// [provider] is the one of an event before SPEC-108, without `provider`
  /// (R10).
  static CompareSide fromJson(
    Map<String, dynamic> j, {
    String provider = 'claude',
  }) {
    final w = j['weight'];
    return CompareSide(
      letter: '${j['letter'] ?? 'A'}',
      model: '${j['model'] ?? 'inherit'}',
      mode: PromptMode.fromName(j['mode'] as String?),
      provider: j['provider'] is String ? j['provider'] as String : provider,
      effort: j['effort'] as String?,
      handoff: j['handoff'] == true,
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

  /// `Sonnet`, `gpt-6.2-sol`, `Padrão`.
  String get modelLabel => compareModelLabel(model, provider);

  /// `Sonnet · Perguntar`.
  String get label => '$modelLabel · ${mode.label}';

  /// `Codex · gpt-6.2-sol · Perguntar`.
  String get fullLabel => '${compareProviderLabel(provider)} · $label';

  /// ` · medium` (nothing on the provider's default).
  String get effortSuffix =>
      effort == null || effort == defaultEffort ? '' : ' · $effort';
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
    this.originalProvider,
    this.handoff,
    this.before = const {},
    this.after = const {},
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
  final String? originalProvider;

  /// What the sides that do not fork receive (SPEC-108 R4, R10).
  final CompareHandoff? handoff;

  /// Readings of the plan usage of each provider involved, before and
  /// after the two sides (R8).
  final Map<String, UsageReading> before;
  final Map<String, UsageReading> after;

  /// The weights come from the two readings (false = the Atividades rule).
  final bool measured;
  final CompareStatus status;

  /// Letter of the chosen side.
  final String? chosen;

  /// The providers of the sides, A's first.
  List<String> get providers => {for (final s in sides) s.provider}.toList();

  /// The sides run on different providers, so on different quotas (P2).
  bool get crossProvider => sides[0].provider != sides[1].provider;

  /// The last reading of [provider], for the names of its windows.
  UsageReading? readingOf(String provider) =>
      after[provider] ?? before[provider];

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
    Map<String, UsageReading>? before,
    Map<String, UsageReading>? after,
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
    originalProvider: originalProvider,
    handoff: handoff,
    before: before ?? this.before,
    after: clearAfter ? const {} : (after ?? this.after),
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
    'originalProvider': ?originalProvider,
    'handoff': ?handoff?.toJson(),
    if (before.isNotEmpty) 'before': _readingsJson(before),
    if (after.isNotEmpty) 'after': _readingsJson(after),
    'measured': measured,
    'sides': [for (final s in sides) s.toJson()],
  };

  String encode() => jsonEncode(toJson());

  static Map<String, dynamic> _readingsJson(Map<String, UsageReading> r) => {
    for (final MapEntry(:key, :value) in r.entries) key: value.toJson(),
  };

  /// By provider; an event before SPEC-108 kept one reading, of [provider].
  static Map<String, UsageReading> _readings(Object? j, String provider) {
    if (j is! Map) return const {};
    final old = j.keys.any(
      (k) => const {'five', 'week', 'fiveResetsAt', 'weekResetsAt'}.contains(k),
    );
    if (old) return {provider: ?UsageReading.fromJson(j)};
    return {
      for (final MapEntry(:key, :value) in j.entries)
        '$key': ?UsageReading.fromJson(value),
    };
  }

  /// From a stored row; null when it is not a comparison. [provider] is
  /// the conversation's, for an event before SPEC-108 (R10).
  static CompareRun? fromJson(
    Map<String, dynamic> j, {
    required int conversationId,
    int? seq,
    String provider = 'claude',
  }) {
    if (j['type'] != AppEventTypes.compare) return null;
    final sides = [
      for (final s in (j['sides'] as List?) ?? const [])
        if (s is Map<String, dynamic>)
          CompareSide.fromJson(s, provider: provider),
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
      originalProvider: j['originalProvider'] as String?,
      handoff: CompareHandoff.fromJson(j['handoff']),
      before: _readings(j['before'], provider),
      after: _readings(j['after'], provider),
      measured: j['measured'] == true,
      status: CompareStatus.fromName(j['status'] as String?),
      chosen: j['chosen'] as String?,
    );
  }
}

/// What a side is set to before sending (SPEC-108 R1): provider, model,
/// effort ([defaultEffort] = the provider's) and mode.
@immutable
class CompareChoice {
  const CompareChoice({
    this.provider = 'claude',
    required this.model,
    this.effort = defaultEffort,
    required this.mode,
  });

  final String provider;
  final String model;
  final String effort;
  final PromptMode mode;

  CompareChoice copyWith({String? model, String? effort, PromptMode? mode}) =>
      CompareChoice(
        provider: provider,
        model: model ?? this.model,
        effort: effort ?? this.effort,
        mode: mode ?? this.mode,
      );

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'model': model,
    'effort': effort,
    'mode': mode.name,
  };

  @override
  bool operator ==(Object other) =>
      other is CompareChoice &&
      other.provider == provider &&
      other.model == model &&
      other.effort == effort &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(provider, model, effort, mode);

  @override
  String toString() => '$provider/$model/$effort/${mode.name}';
}

/// Modes a side accepts (R3): never Editar.
const compareModes = [PromptMode.ask, PromptMode.plan];

/// The providers Comparar knows, in order.
const compareProviders = ['claude', 'codex'];

/// The other one of [compareProviders].
String otherCompareProvider(String provider) =>
    provider == 'codex' ? 'claude' : 'codex';

/// Why Editar is off on a side (R3).
const compareEditHint =
    'Editar mudaria a pasta duas vezes ao mesmo tempo. Compare em Perguntar '
    'ou Planejar.';

/// Same provider, model, effort and mode on both sides (R2).
const compareSameSidesMessage =
    'Os dois lados estão iguais. Troque o provedor, o modelo, o esforço ou o '
    'modo de um deles.';

/// The composer while a comparison waits for a choice (R14).
const compareBlockedMessage = 'Escolha uma resposta para continuar.';

/// The "other" model of side B (R1, P8): Sonnet ↔ Opus, Haiku → Sonnet.
String otherCompareModel(String model) => switch (model) {
  'opus' => 'sonnet',
  'sonnet' => 'opus',
  'haiku' => 'sonnet',
  _ => 'opus',
};

/// `sonnet` → `Sonnet`; `inherit` → `Padrão`. Codex ids stay as they are.
String compareModelLabel(String model, [String provider = 'claude']) {
  if (model.isEmpty || model == 'inherit') return 'Padrão';
  if (!isClaudeCode(provider)) return model;
  return model[0].toUpperCase() + model.substring(1);
}

/// `Claude`, `Codex`.
String compareProviderLabel(String provider) => switch (provider) {
  'claude' => 'Claude',
  'codex' => 'Codex',
  _ => provider,
};

/// The two sides when Comparar is turned on (R1): A = the current model
/// and mode, B = the other model in the same mode. "Modelo padrão" of the
/// Claude is compared as Sonnet × Opus (the most common doubt, P8). On the
/// Codex, B is another model of [codexModels] (its `model/list`). Editar
/// becomes Perguntar.
(CompareChoice, CompareChoice) defaultCompareSides(
  String model,
  PromptMode mode, {
  String provider = 'claude',
  String effort = defaultEffort,
  List<String> codexModels = const [],
}) {
  final m = compareModes.contains(mode) ? mode : PromptMode.ask;
  CompareChoice side(String model) =>
      CompareChoice(provider: provider, model: model, effort: effort, mode: m);
  if (!isClaudeCode(provider)) {
    final a = model.isEmpty ? 'inherit' : model;
    final b = codexModels.where((o) => o != a).firstOrNull;
    return (
      side(a),
      // Another model may not have the same effort.
      b == null ? side(a) : side(b).copyWith(effort: defaultEffort),
    );
  }
  final a = model == 'inherit' || model.isEmpty ? 'sonnet' : model;
  return (side(a), side(otherCompareModel(a)));
}

/// Two sides that cannot be sent (R2, R3); null = fine.
String? compareSidesProblem(CompareChoice a, CompareChoice b) {
  if (!compareModes.contains(a.mode) || !compareModes.contains(b.mode)) {
    return compareEditHint;
  }
  if (a == b) return compareSameSidesMessage;
  return null;
}

/// The last pair of a workspace (P8), stored in `app_settings`.
String encodeCompareSides(CompareChoice a, CompareChoice b) =>
    jsonEncode({'a': a.toJson(), 'b': b.toJson()});

(CompareChoice, CompareChoice)? decodeCompareSides(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final j = jsonDecode(raw);
    if (j is! Map) return null;
    CompareChoice? one(Object? s) {
      if (s is! Map || s['model'] is! String) return null;
      final mode = PromptMode.fromName(s['mode'] as String?);
      if (!compareModes.contains(mode)) return null;
      // A pair saved before SPEC-108 has no provider: Claude.
      final provider = s['provider'] is String
          ? s['provider'] as String
          : 'claude';
      if (!compareProviders.contains(provider)) return null;
      return CompareChoice(
        provider: provider,
        model: s['model'] as String,
        effort: s['effort'] is String ? s['effort'] as String : defaultEffort,
        mode: mode,
      );
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
