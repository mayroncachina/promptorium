import 'package:flutter/foundation.dart';

/// Contract of the context window of one execution (SPEC-087 R1).
///
/// Every number here comes from the agent (docs/pesquisa/
/// contexto-e-compactacao.md): the size is the `usage` of the last top-level
/// call (`input + cache write + cache read`), the capacity is
/// `result.modelUsage[model].contextWindow` and the compaction threshold is
/// `autoCompactThreshold` of the `get_context_usage` control request. A value
/// the agent did not report stays null; the interface never fills it in.

/// One measured reading: the context of one top-level model call.
@immutable
class ContextReading {
  const ContextReading({
    required this.tokens,
    required this.at,
    required this.turn,
    required this.itemIndex,
    this.input = 0,
    this.cacheWrite = 0,
    this.cacheRead = 0,
    this.model,
    this.messageId,
    this.live = true,
    this.turnEnd = false,
    this.source = ContextReadingSource.claudeUsage,
  });

  /// `input + cacheWrite + cacheRead` of the call (output is not context
  /// until the next call reads it back).
  final int tokens;
  final int input;
  final int cacheWrite;
  final int cacheRead;
  final String? model;
  final String? messageId;
  final DateTime at;

  /// 1-based turn (user message → `result`) of the execution history.
  final int turn;

  /// Length of the timeline when the reading arrived: where "Ir ao turno"
  /// scrolls to.
  final int itemIndex;

  /// Received from the running process (false = rebuilt from stored events).
  final bool live;

  /// The `result` of its turn arrived ("medido no fim do turno N").
  final bool turnEnd;

  /// Where the agent reported it (SPEC-095 R3): `claude-usage` (the
  /// `usage` of a Claude call) or `codex-tokenUsage` (`tokenUsage.last`).
  final String source;

  /// The three parts are measured in the same call and do not overlap.
  bool get hasComposition => input + cacheWrite + cacheRead == tokens;

  ContextReading copyWith({bool? turnEnd, bool? live}) => ContextReading(
    tokens: tokens,
    at: at,
    turn: turn,
    itemIndex: itemIndex,
    input: input,
    cacheWrite: cacheWrite,
    cacheRead: cacheRead,
    model: model,
    messageId: messageId,
    live: live ?? this.live,
    turnEnd: turnEnd ?? this.turnEnd,
    source: source,
  );
}

/// Values of [ContextReading.source] (SPEC-095 R3).
abstract final class ContextReadingSource {
  static const claudeUsage = 'claude-usage';
  static const codexTokenUsage = 'codex-tokenUsage';
}

enum ContextMarkerKind { compaction, modelChange }

/// A compaction (`system/compact_boundary`) or a model change in the history
/// (R6). [readingsBefore] = number of readings before it (its x position).
@immutable
class ContextMarker {
  const ContextMarker({
    required this.kind,
    required this.at,
    required this.turn,
    required this.itemIndex,
    required this.readingsBefore,
    this.trigger,
    this.preTokens,
    this.postTokens,
    this.fromModel,
    this.toModel,
    this.key,
  });

  final ContextMarkerKind kind;
  final DateTime at;
  final int turn;
  final int itemIndex;
  final int readingsBefore;

  /// `auto` or `manual` (compaction).
  final String? trigger;

  /// `compact_metadata.pre_tokens` / `post_tokens`: the CLI's own count of
  /// the conversation part; `post_tokens` is not the next reading (the
  /// system prompt and tools come back on top of it).
  final int? preTokens;
  final int? postTokens;
  final String? fromModel;
  final String? toModel;

  /// Deduplication key (the event's `uuid`, or its content).
  final String? key;
}

/// Phases of the compaction as the agent reports them (R8).
enum CompactionPhase {
  /// Threshold known, nothing happening.
  configured,

  /// `system/status` `compacting` arrived.
  compacting,

  /// `compact_boundary` / `compact_result: success`.
  done,

  /// `compact_result: failed`.
  failed,

  /// The agent reported no compaction setting for this execution.
  notReported,
}

/// A category of `get_context_usage` (system prompt, tools, skills,
/// messages, memory files, MCP tools…): the agent's local estimate.
@immutable
class ContextCategory {
  const ContextCategory({
    required this.id,
    required this.name,
    required this.tokens,
    required this.kind,
  });

  final String id;
  final String name;
  final int tokens;

  /// `used`, `deferred`, `buffer` or `free`.
  final String kind;

  bool get used => kind == 'used';

  static ContextCategory? fromJson(Object? j) {
    if (j is! Map) return null;
    final tokens = j['tokens'];
    if (tokens is! num) return null;
    return ContextCategory(
      id: '${j['id'] ?? ''}',
      name: '${j['name'] ?? ''}',
      tokens: tokens.toInt(),
      kind: '${j['kind'] ?? 'used'}',
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'tokens': tokens,
    'kind': kind,
  };
}

/// Which limit a warning is about (R10).
enum ContextReference { threshold, capacity }

@immutable
class ContextWarning {
  const ContextWarning({
    required this.tokens,
    required this.reference,
    required this.kind,
    required this.turn,
  });

  final int tokens;
  final int reference;
  final ContextReference kind;
  final int turn;

  int get percent => (tokens * 100 / reference).round();

  int get remaining => (reference - tokens).clamp(0, reference);
}

/// Everything the indicator and the panel show about one execution.
@immutable
class ContextSnapshot {
  const ContextSnapshot({
    this.current,
    this.last,
    this.pendingAfterCompaction = false,
    this.capacity,
    this.threshold,
    this.autocompactWindow,
    this.autocompactEnabled,
    this.autocompactSource,
    this.configuredAutocompact,
    this.model,
    this.phase = CompactionPhase.notReported,
    this.phaseSince,
    this.compactError,
    this.readings = const [],
    this.markers = const [],
    this.categories = const [],
    this.warning,
    this.turn = 0,
    this.subagents = const [],
  });

  static const empty = ContextSnapshot();

  /// The reading that describes the window now; null while waiting for one
  /// (no call yet, or a compaction invalidated it).
  final ContextReading? current;

  /// The newest reading, current or not (history, "Última leitura").
  final ContextReading? last;

  /// A compaction happened after [last]: "aguardando medição" (R3).
  final bool pendingAfterCompaction;

  /// `contextWindow` reported for [model] (null = unknown: no percentage).
  final int? capacity;

  /// `autoCompactThreshold` reported by the agent for this execution.
  final int? threshold;

  /// `maxTokens` of `get_context_usage`: the window the CLI compacts in
  /// (`--autocompact`), not the model's capacity.
  final int? autocompactWindow;
  final bool? autocompactEnabled;

  /// `autocompactSource` (`settings`, `model-default`, …).
  final String? autocompactSource;

  /// `--autocompact` sent to this execution by the app (`200k`, `auto`) or
  /// null when the app sent none (other providers, old executions).
  final String? configuredAutocompact;
  final String? model;
  final CompactionPhase phase;
  final DateTime? phaseSince;
  final String? compactError;
  final List<ContextReading> readings;
  final List<ContextMarker> markers;

  /// Last `get_context_usage` categories (estimates, may overlap with the
  /// usage composition: never summed with it).
  final List<ContextCategory> categories;
  final ContextWarning? warning;

  /// Turns seen (`result`s) — the running turn is [turn] + 1.
  final int turn;

  /// Subagent types started in this history (R11): separate windows the
  /// app does not measure.
  final List<String> subagents;

  bool get hasReading => current != null;

  /// 0–100, only with a reading and a known capacity.
  int? get percent {
    final c = current, cap = capacity;
    if (c == null || cap == null || cap <= 0) return null;
    return (c.tokens * 100 / cap).round().clamp(0, 100);
  }

  int? get free {
    final c = current, cap = capacity;
    if (c == null || cap == null) return null;
    return (cap - c.tokens).clamp(0, cap);
  }

  /// Tokens until the compaction threshold (null when either is unknown).
  int? get untilCompaction {
    final c = current, t = threshold;
    if (c == null || t == null) return null;
    return (t - c.tokens).clamp(0, t);
  }

  ContextMarker? get lastCompaction {
    for (final m in markers.reversed) {
      if (m.kind == ContextMarkerKind.compaction) return m;
    }
    return null;
  }

  /// "medido no fim do turno 12 · 14:32", "medido no turno 3 (em curso)".
  String? get measuredLabel {
    final c = current;
    if (c == null) return null;
    final hh = _hhmm(c.at);
    if (!c.live) return 'última medição às $hh · turno ${c.turn}';
    return c.turnEnd
        ? 'medido no fim do turno ${c.turn} · $hh'
        : 'medido no turno ${c.turn} · $hh';
  }
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// `14:32`.
String contextTime(DateTime t) => _hhmm(t);

/// `182 mil`, `1 milhão`, `1,2 milhão`, `850` (R2: same unit as the mocks).
String contextTokens(int n) {
  if (n >= 1000000) {
    final v = n / 1000000;
    final s = v == v.roundToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(1).replaceAll('.', ',');
    return v >= 2 ? '$s milhões' : '$s milhão';
  }
  if (n >= 10000) return '${(n / 1000).round()} mil';
  if (n >= 1000) {
    final v = (n / 100).round() / 10;
    final s = v == v.roundToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(1).replaceAll('.', ',');
    return '$s mil';
  }
  return '$n';
}

/// `200k` → 200000, `1M` → 1000000, `auto` → null.
int? autocompactTokens(String? v) {
  if (v == null) return null;
  final s = v.trim().toLowerCase();
  final m = RegExp(r'^(\d+(?:\.\d+)?)\s*([km]?)$').firstMatch(s);
  if (m == null) return null;
  final n = double.parse(m.group(1)!);
  return switch (m.group(2)) {
    'k' => (n * 1000).round(),
    'm' => (n * 1000000).round(),
    _ => n.round(),
  };
}

/// `200k` → `200 mil`; `auto` → `padrão do agente`.
String autocompactLabel(String? v) {
  final n = autocompactTokens(v);
  return n == null ? 'padrão do agente' : contextTokens(n);
}
