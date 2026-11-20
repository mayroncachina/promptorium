import '../../core/claude/claude_event.dart';
import '../../core/claude/context_usage.dart';
import 'context_snapshot.dart';
import 'context_sources.dart';

/// App events of the context contract (SPEC-087), stored with the session /
/// conversation events.
abstract final class ContextEventTypes {
  /// Sanitized answer of `get_context_usage` ([contextUsageEvent]).
  static const usage = contextUsageType;

  /// What the app sent to one execution: `{"type":"promptorium_run","v":1,
  /// "autocompact":"200k"|null,"model":…,"provider":…}`.
  static const run = 'promptorium_run';

  static Map<String, dynamic> runEvent({
    String? autocompact,
    String? model,
    String? provider,
    DateTime? at,
  }) => {
    'type': run,
    'v': 1,
    'autocompact': autocompact,
    'model': ?model,
    'provider': ?provider,
    'at': (at ?? DateTime.now()).toIso8601String(),
  };
}

/// Reduces the events of ONE execution history (a session or a
/// conversation) into a [ContextSnapshot] (SPEC-087 R1, R3, R6, R8, R10).
///
/// - A reading replaces the previous one (never a sum); several lines of
///   the same `message.id` are one reading.
/// - Subagent messages (`parent_tool_use_id`) never count (R11).
/// - A compaction invalidates the current reading until the next call; a
///   model change invalidates the capacity and the threshold.
/// - Repeated events (same `uuid`, replay of stored rows) mark once.
class ContextTracker {
  final List<ContextReading> _readings = [];
  final List<ContextMarker> _markers = [];
  final Set<String> _compactionKeys = {};
  final Map<String, String> _subagents = {};
  final ContextSources sources = ContextSources();
  ContextReading? _current;
  bool _pending = false;
  int _results = 0;
  String? _model;
  final Map<String, int> _windows = {};
  int? _threshold;
  int? _autocompactWindow;
  bool? _enabled;
  String? _source;
  String? _configured;
  bool _sawRun = false;
  CompactionPhase _phase = CompactionPhase.notReported;
  DateTime? _phaseSince;
  int _phaseTurn = 0;
  String? _compactError;
  List<ContextCategory> _categories = const [];

  // R10: one warning per crossing, re-armed below 75% or after compacting.
  bool _armed = true;
  ContextWarning? _warning;
  int? _warnReference;

  ContextSnapshot? _snap;

  static const _subagentTools = {'Task', 'Agent'};

  /// Current state (cached until the next event).
  ContextSnapshot get snapshot => _snap ??= _build();

  /// Hides the warning until the next crossing (R10).
  void dismissWarning() {
    _warning = null;
    _snap = null;
  }

  /// Applies one event. [itemIndex] = timeline length (for "Ir ao turno");
  /// [live] = received from the running process.
  void apply(
    AgentEvent e, {
    required DateTime at,
    int itemIndex = 0,
    bool live = true,
  }) {
    _snap = null;
    sources.apply(e, turn: _results + 1, at: at, itemIndex: itemIndex);
    switch (e) {
      case SystemInit():
        if (e.model.isNotEmpty) _changeModel(e.model, at, itemIndex);
      case AssistantMessage(parentToolUseId: null):
        _reading(e, at, itemIndex, live);
        // R11: a subagent has its own window; the app has no measurement of
        // it, so it is only named, never summed.
        for (final b in e.blocks) {
          if (b is ToolUseBlock && _subagentTools.contains(b.name)) {
            final type = '${b.input['subagent_type'] ?? ''}';
            _subagents[b.id] = type.isEmpty ? 'subagente' : type;
          }
        }
      // A `/compact` alone ends with `num_turns: 0`: not a turn.
      case Result() when e.json['num_turns'] == 0:
        break;
      case Result():
        _results++;
        if (_phase == CompactionPhase.failed && _results > _phaseTurn) {
          _phase = _baseline;
        }
        _capacity(e.json);
        final last = _readings.lastOrNull;
        if (last != null && !last.turnEnd && last.turn == _results) {
          final ended = last.copyWith(turnEnd: true);
          _readings[_readings.length - 1] = ended;
          if (identical(_current, last)) _current = ended;
        }
      case SystemStatus(:final status):
        _status(e.json, status, at);
      case SystemOther(subtype: 'compact_boundary'):
        _boundary(e.json, at, itemIndex);
      case UnknownEvent(:final json):
        switch (json['type']) {
          case ContextEventTypes.usage:
            _usage(json);
          case ContextEventTypes.run:
            _run(json);
        }
      default:
        break;
    }
  }

  void _reading(AssistantMessage e, DateTime at, int itemIndex, bool live) {
    final u = e.json['message'];
    if (u is! Map || u['usage'] is! Map<String, dynamic>) return;
    final usage = Usage.fromJson(u['usage'] as Map<String, dynamic>);
    final tokens =
        usage.inputTokens +
        usage.cacheCreationInputTokens +
        usage.cacheReadInputTokens;
    if (tokens <= 0) return;
    if (e.model != null && e.model!.isNotEmpty) {
      _changeModel(e.model!, at, itemIndex);
    }
    final r = ContextReading(
      tokens: tokens,
      input: usage.inputTokens,
      cacheWrite: usage.cacheCreationInputTokens,
      cacheRead: usage.cacheReadInputTokens,
      model: e.model ?? _model,
      messageId: e.messageId.isEmpty ? null : e.messageId,
      at: at,
      turn: _results + 1,
      itemIndex: itemIndex,
      live: live,
    );
    final last = _readings.lastOrNull;
    if (last != null &&
        r.messageId != null &&
        last.messageId == r.messageId &&
        !_pending) {
      _readings[_readings.length - 1] = r;
    } else {
      _readings.add(r);
    }
    _current = r;
    _pending = false;
    if (_phase == CompactionPhase.compacting ||
        (_phase == CompactionPhase.done && _phaseTurn < r.turn)) {
      _phase = _baseline;
    }
    _evaluateWarning();
  }

  void _changeModel(String model, DateTime at, int itemIndex) {
    final from = _model;
    _model = model;
    if (from == null || from == model) return;
    _markers.add(
      ContextMarker(
        kind: ContextMarkerKind.modelChange,
        at: at,
        turn: _results + 1,
        itemIndex: itemIndex,
        readingsBefore: _readings.length,
        fromModel: from,
        toModel: model,
      ),
    );
    // R3: the limits of the previous model do not hold for the new one.
    _threshold = null;
    _autocompactWindow = null;
    _categories = const [];
    _evaluateWarning();
  }

  void _capacity(Map<String, dynamic> json) {
    final mu = json['modelUsage'];
    if (mu is! Map) return;
    for (final MapEntry(:key, :value) in mu.entries) {
      if (value is Map && value['contextWindow'] is num) {
        _windows['$key'] = (value['contextWindow'] as num).toInt();
      }
    }
    _evaluateWarning();
  }

  int? get _capacityNow {
    final m = _current?.model ?? _model;
    if (m != null && _windows[m] != null) return _windows[m];
    // `modelUsage` keys are full ids; the init may carry the same id.
    if (m != null) {
      for (final MapEntry(:key, :value) in _windows.entries) {
        if (key.startsWith(m) || m.startsWith(key)) return value;
      }
    }
    return null;
  }

  void _status(Map<String, dynamic> json, String? status, DateTime at) {
    if (status == 'compacting') {
      if (_phase != CompactionPhase.compacting) {
        _phase = CompactionPhase.compacting;
        _phaseSince = at;
        _compactError = null;
      }
      return;
    }
    switch (json['compact_result']) {
      case 'success':
        _phase = CompactionPhase.done;
        _phaseSince = at;
        _phaseTurn = _results + 1;
      case 'failed':
        _phase = CompactionPhase.failed;
        _phaseSince = at;
        _phaseTurn = _results + 1;
        _compactError = json['compact_error'] as String?;
    }
  }

  void _boundary(Map<String, dynamic> json, DateTime at, int itemIndex) {
    final meta = json['compact_metadata'];
    final m = meta is Map ? meta : const {};
    final key =
        json['uuid'] as String? ??
        '${m['trigger']}:${m['pre_tokens']}:${m['post_tokens']}';
    if (!_compactionKeys.add(key)) return;
    int? n(Object? v) => v is num ? v.toInt() : null;
    _markers.add(
      ContextMarker(
        kind: ContextMarkerKind.compaction,
        at: at,
        turn: _results + 1,
        itemIndex: itemIndex,
        readingsBefore: _readings.length,
        trigger: m['trigger'] as String?,
        preTokens: n(m['pre_tokens']),
        postTokens: n(m['post_tokens']),
        key: key,
      ),
    );
    _current = null;
    _pending = true;
    _phase = CompactionPhase.done;
    _phaseSince = at;
    _phaseTurn = _results + 1;
    _compactError = null;
    sources.compacted();
    // R10: a confirmed compaction re-arms the warning.
    _armed = true;
    _warning = null;
  }

  void _usage(Map<String, dynamic> j) {
    int? n(Object? v) => v is num ? v.toInt() : null;
    final model = j['model'] as String?;
    if (model != null && _model != null && model != _model) return;
    _threshold = n(j['threshold']);
    _autocompactWindow = n(j['max']);
    _enabled = j['enabled'] as bool?;
    _source = j['source'] as String?;
    _categories = [
      for (final c in (j['categories'] as List?) ?? const [])
        ?ContextCategory.fromJson(c),
    ];
    sources.categories(_categories);
    if (_phase == CompactionPhase.notReported) _phase = _baseline;
    _evaluateWarning();
  }

  void _run(Map<String, dynamic> j) {
    _sawRun = true;
    _configured = j['autocompact'] as String?;
    // A new execution: its limits come with its own answers.
    _threshold = null;
    _autocompactWindow = null;
    if (_phase == CompactionPhase.notReported ||
        _phase == CompactionPhase.configured) {
      _phase = _baseline;
    }
    _evaluateWarning();
  }

  /// Phase when nothing is happening.
  CompactionPhase get _baseline =>
      _enabled == true || (_sawRun && _configured != null)
      ? CompactionPhase.configured
      : CompactionPhase.notReported;

  void _evaluateWarning() {
    final c = _current;
    final threshold = _threshold;
    final capacity = _capacityNow;
    final ref = threshold ?? capacity;
    final kind = threshold != null
        ? ContextReference.threshold
        : ContextReference.capacity;
    if (ref == null || ref <= 0) {
      // R10: unknown limit, no alarm.
      _warning = null;
      _warnReference = null;
      return;
    }
    if (ref != _warnReference) {
      // R10: a new reference restarts the evaluation.
      _warnReference = ref;
      _armed = true;
      _warning = null;
    }
    if (c == null) return;
    final ratio = c.tokens / ref;
    if (ratio < 0.75) {
      _armed = true;
      _warning = null;
    } else if (ratio >= 0.85 && _armed && c.live) {
      _armed = false;
      _warning = ContextWarning(
        tokens: c.tokens,
        reference: ref,
        kind: kind,
        turn: c.turn,
      );
    } else if (_warning != null && c.live) {
      // The same crossing: the warning follows the newest reading.
      _warning = ContextWarning(
        tokens: c.tokens,
        reference: ref,
        kind: kind,
        turn: _warning!.turn,
      );
    }
  }

  ContextSnapshot _build() => ContextSnapshot(
    current: _current,
    last: _readings.lastOrNull,
    pendingAfterCompaction: _pending,
    capacity: _capacityNow,
    threshold: _threshold,
    autocompactWindow: _autocompactWindow,
    autocompactEnabled: _enabled,
    autocompactSource: _source,
    configuredAutocompact: _sawRun ? _configured : null,
    model: _current?.model ?? _model,
    phase: _phase,
    phaseSince: _phaseSince,
    compactError: _compactError,
    readings: List.unmodifiable(_readings),
    markers: List.unmodifiable(_markers),
    categories: _categories,
    warning: _warning,
    turn: _results,
    subagents: List.unmodifiable(_subagents.values),
  );
}
