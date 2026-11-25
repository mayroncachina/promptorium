/// Codex App Server payloads → neutral events (SPEC-095 R1–R7). Pure: the
/// `CodexRun` adds the session fields, redacts and emits. Shapes from the
/// 0.170 transcripts of SPEC-093 (`docs/pesquisa/codex-0170.md`).
library;

import '../providers/agent_event.dart';

String? _str(Object? v) => v is String ? v : null;

int? _int(Object? v) => v is num ? v.toInt() : null;

/// Lines of [text] as `+line` (or `-line`) hunk rows.
String _hunk(String text, {required bool add}) {
  final body = text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
  final lines = body.isEmpty ? const <String>[] : body.split('\n');
  final n = lines.length;
  final head = add ? '@@ -0,0 +1,$n @@' : '@@ -1,$n +0,0 @@';
  final sign = add ? '+' : '-';
  return '${[head, for (final l in lines) '$sign$l'].join('\n')}\n';
}

/// `item.status` → [FileChangeStatus].
FileChangeStatus codexFileStatus(Object? status) => switch (status) {
  'completed' => FileChangeStatus.applied,
  'failed' => FileChangeStatus.failed,
  'declined' => FileChangeStatus.declined,
  _ => FileChangeStatus.proposed,
};

/// One `fileChange.changes[]` entry as the stored JSON of a
/// [FileChangeEvent] (without the diff cut) and its whole diff.
///
/// 0.170: `kind` is an object (`{"type":"add"}`, `{"type":"update",
/// "move_path":…}`); `diff` is a unified hunk for `update` and the whole
/// content for `add` (and `delete`). The content becomes a hunk here, so
/// every consumer reads one format, and it is kept as [FileChangeEvent.after]
/// (or `before`) because it is the whole file.
({Map<String, dynamic> json, String? diff}) codexFileChange(
  Map<String, dynamic> change, {
  required String toolUseId,
  required int index,
  required Object? status,
}) {
  final rawKind = change['kind'];
  final type = rawKind is Map ? _str(rawKind['type']) : _str(rawKind);
  final movePath = rawKind is Map ? _str(rawKind['move_path']) : null;
  final path = _str(change['path']) ?? '';
  final raw = _str(change['diff']);
  final isHunk = raw != null && raw.trimLeft().startsWith('@@');
  var kind = FileChangeKind.parse(type);
  String? diff = raw;
  String? before, after;
  switch (kind) {
    case FileChangeKind.add when raw != null && !isHunk:
      after = raw;
      diff = _hunk(raw, add: true);
    case FileChangeKind.delete when raw != null && !isHunk:
      before = raw;
      diff = _hunk(raw, add: false);
    default:
      break;
  }
  var target = path;
  String? from;
  if (movePath != null && movePath.isNotEmpty && movePath != path) {
    kind = FileChangeKind.move;
    target = movePath;
    from = path;
  }
  final json = FileChangeEvent.toJson(
    provider: 'codex',
    toolUseId: toolUseId,
    index: index,
    path: target,
    fromPath: from,
    kind: kind,
    status: codexFileStatus(status),
    diff: diff,
    before: before,
    after: after,
    cut: false,
  );
  return (json: json, diff: diff);
}

/// `item.status` of a `commandExecution` → [CommandStatus].
CommandStatus codexCommandStatus(Object? status) => switch (status) {
  'completed' => CommandStatus.completed,
  'failed' => CommandStatus.failed,
  'declined' => CommandStatus.declined,
  _ => CommandStatus.running,
};

/// A `commandExecution` item as the stored JSON of a [CommandEvent] (the
/// output cut to the limit, P3).
Map<String, dynamic> codexCommand(Map<String, dynamic> item) {
  final reads = <String>[
    for (final a in item['commandActions'] as List? ?? const [])
      if (a is Map && a['type'] == 'read' && a['path'] is String)
        a['path'] as String,
  ];
  return CommandEvent.toJson(
    provider: 'codex',
    toolUseId: '${item['id']}',
    command: _str(item['command']) ?? '',
    cwd: _str(item['cwd']),
    status: codexCommandStatus(item['status']),
    exitCode: _int(item['exitCode']),
    output: _str(item['aggregatedOutput']),
    durationMs: _int(item['durationMs']),
    reads: reads,
    actions: [
      for (final a in item['commandActions'] as List? ?? const [])
        ?CommandAction.fromJson(a),
    ],
    unknownActions: [
      for (final a in item['commandActions'] as List? ?? const [])
        if (CommandAction.fromJson(a) == null) a,
    ].length,
  );
}

/// `thread/tokenUsage/updated` as a [ContextUsageEvent] (R4).
///
/// Formula proven by SPEC-093 R14 (`docs/pesquisa/codex-0170.md`, "Contexto
/// e compactação"): the current context is `tokenUsage.last.totalTokens`
/// (`last` = the last model call, not the turn) and the capacity is
/// `tokenUsage.modelContextWindow`. `total` is accumulated across the
/// thread: it goes to the ledger, never to the context. Null without
/// `last`.
///
/// SPEC-107 R3: `last.totalTokens` = `inputTokens + outputTokens`, and
/// `inputTokens` includes `cachedInputTokens`; the parts are new input,
/// cache read, cache write and the call's output. When they do not add up
/// to the total (overlap), the panel says "Detalhamento indisponível".
Map<String, dynamic>? codexContextUsage(
  Map<String, dynamic> params, {
  String? model,
}) {
  final usage = params['tokenUsage'];
  if (usage is! Map) return null;
  final last = usage['last'];
  if (last is! Map) return null;
  final tokens = _int(last['totalTokens']);
  if (tokens == null || tokens <= 0) return null;
  final cached = _int(last['cachedInputTokens']) ?? 0;
  final input = _int(last['inputTokens']) ?? 0;
  return ContextUsageEvent.toJson(
    provider: 'codex',
    tokens: tokens,
    input: (input - cached).clamp(0, 1 << 62),
    cacheRead: cached,
    cacheWrite: _int(last['cacheWriteInputTokens']) ?? 0,
    output: _int(last['outputTokens']) ?? 0,
    window: _int(usage['modelContextWindow']),
    model: model,
    turnId: _str(params['turnId']),
    source: ContextUsageEvent.codexTokenUsage,
  );
}

/// `account/rateLimits/updated` (or `read`) as a [QuotaEvent] (R5).
/// `primary` is the 5-hour window and `secondary` the weekly one;
/// `usedPercent` is an integer and `resetsAt` Unix seconds.
Map<String, dynamic>? codexQuota(Map<String, dynamic> params) {
  final r = params['rateLimits'];
  if (r is! Map) return null;
  QuotaWindow? window(String id) {
    final w = r[id];
    if (w is! Map) return null;
    final minutes = _int(w['windowDurationMins']);
    final resets = w['resetsAt'];
    return QuotaWindow(
      id: id,
      label: QuotaWindow.labelOf(minutes),
      usedPercent: w['usedPercent'] is num
          ? (w['usedPercent'] as num).toDouble()
          : null,
      resetsAt: resets is num
          ? DateTime.fromMillisecondsSinceEpoch(
              (resets * 1000).round(),
              isUtc: true,
            )
          : null,
      minutes: minutes,
    );
  }

  return QuotaEvent.toJson(
    provider: 'codex',
    windows: [?window('primary'), ?window('secondary')],
    plan: _str(r['planType']),
    reached: _str(r['rateLimitReachedType']),
  );
}

/// Items the adapter knows and does not show on their own.
const codexSilentItems = {'userMessage', 'reasoning'};

/// An item without translation (R6) as the JSON of an [OtherItemEvent]:
/// its type and a one-line summary.
Map<String, dynamic> codexOtherItem(Map<String, dynamic> item) {
  final type = _str(item['type']) ?? 'desconhecido';
  String? text;
  for (final k in const [
    'text',
    'query',
    'title',
    'prompt',
    'summary',
    'path',
    'command',
  ]) {
    final v = item[k];
    if (v is String && v.trim().isNotEmpty) {
      text = v;
      break;
    }
    if (v is List && v.isNotEmpty) {
      text = v
          .map((e) => e is Map ? (e['text'] ?? e['step'] ?? e) : e)
          .join(' ');
      break;
    }
  }
  final one = (text ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  return OtherItemEvent.toJson(
    provider: 'codex',
    itemType: type,
    summary: one.length > 160 ? '${one.substring(0, 159)}…' : one,
    toolUseId: _str(item['id']),
    text: type == 'plan' ? _str(item['text']) : null,
  );
}

/// The text of a `reasoning` item (SPEC-110 R1): its summary, or its
/// content. Null when the App Server sent neither (the usual case).
String? codexReasoningText(Map<String, dynamic> item) {
  for (final k in const ['summary', 'content']) {
    final parts = [
      for (final e in item[k] as List? ?? const [])
        if (e is String)
          e
        else if (e is Map && e['text'] is String)
          e['text'] as String,
    ].where((e) => e.trim().isNotEmpty);
    if (parts.isNotEmpty) return parts.join('\n\n');
  }
  return null;
}

/// `turn/plan/updated` as an [OtherItemEvent] (SPEC-110 R1): one card per
/// turn, updated by each notification.
Map<String, dynamic>? codexTurnPlan(Map<String, dynamic> params) {
  final steps = [
    for (final s in params['plan'] as List? ?? const [])
      if (s is Map && s['step'] is String)
        '${switch (s['status']) {
          'completed' => '✓',
          'inProgress' => '▸',
          _ => '○',
        }} ${s['step']}',
  ];
  if (steps.isEmpty) return null;
  final done = steps.where((s) => s.startsWith('✓')).length;
  final why = _str(params['explanation'])?.trim() ?? '';
  return OtherItemEvent.toJson(
    provider: 'codex',
    itemType: 'turnPlan',
    summary: '$done de ${steps.length} passos',
    toolUseId: 'plan-${params['turnId'] ?? ''}',
    text: [if (why.isNotEmpty) '$why\n', ...steps].join('\n'),
  );
}

/// `subtype` of the app event that marks the `turn/started` of the App
/// Server (SPEC-110 R1, R6): it brings the turn's id even when nothing else
/// of the turn was stored.
const codexTurnStartedSubtype = 'turn_started';
