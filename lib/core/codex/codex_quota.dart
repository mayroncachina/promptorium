import 'dart:async';
import 'dart:io';

import '../claude/claude_process.dart' show ProcessStarter;
import '../providers/agent_provider.dart' show AgentUnavailable;
import '../providers/agent_event.dart' show QuotaWindow;
import '../providers/quota_source.dart';
import 'codex_rpc.dart';

/// The plan quota of the Codex (SPEC-097 R1, R2): `account/rateLimits/read`
/// through a short-lived `codex app-server` (or a live connection), and the
/// sparse `account/rateLimits/updated` of the runs. Nothing here opens a
/// thread or a turn.

/// Every `account/rateLimits/updated` of every Codex run, raw (the params):
/// the quota store merges them into the last reading (R2). The run still
/// emits its `QuotaEvent` for the timeline.
final codexRateLimitUpdates =
    StreamController<Map<String, dynamic>>.broadcast();

int? _int(Object? v) => v is int
    ? v
    : v is num
    ? v.toInt()
    : null;

/// One `RateLimitWindow`: `usedPercent` integer, `resetsAt` Unix seconds.
QuotaWindow? _window(String id, Object? w) {
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

QuotaCredits? _credits(Object? c) {
  if (c is! Map) return null;
  return QuotaCredits(
    hasCredits: c['hasCredits'] is bool ? c['hasCredits'] as bool : null,
    unlimited: c['unlimited'] is bool ? c['unlimited'] as bool : null,
    balance: c['balance'] is String ? c['balance'] as String : null,
  );
}

/// A `RateLimitSnapshot` as a [QuotaBucket]. Absent and null fields stay
/// null: in a sparse update that means "not informed" (R2).
QuotaBucket codexBucket(Map<dynamic, dynamic> s, {String? fallbackId}) =>
    QuotaBucket(
      id: s['limitId'] is String ? s['limitId'] as String : fallbackId ?? '',
      name: s['limitName'] is String ? s['limitName'] as String : null,
      model: s['normalModelSlug'] is String
          ? s['normalModelSlug'] as String
          : null,
      windows: [
        ?_window('primary', s['primary']),
        ?_window('secondary', s['secondary']),
      ],
      credits: _credits(s['credits']),
      plan: s['planType'] is String ? s['planType'] as String : null,
      reached: s['rateLimitReachedType'] is String
          ? s['rateLimitReachedType'] as String
          : null,
    );

/// The full answer of `account/rateLimits/read` (R1, R5): the bucket shown
/// is `codex` of `rateLimitsByLimitId` when there is one, else the main
/// `rateLimits`; the other buckets go to [QuotaSnapshot.others]. A full
/// reading: a null field there means "none".
QuotaSnapshot codexSnapshotFromRead(
  Map<String, dynamic> result, {
  DateTime? at,
}) {
  final byId = result['rateLimitsByLimitId'];
  final buckets = <String, QuotaBucket>{
    if (byId is Map)
      for (final MapEntry(:key, :value) in byId.entries)
        if (value is Map) '$key': codexBucket(value, fallbackId: '$key'),
  };
  final main = result['rateLimits'];
  final shown =
      buckets.remove('codex') ??
      (main is Map ? codexBucket(main, fallbackId: 'codex') : null) ??
      const QuotaBucket(id: 'codex');
  if (main is Map) buckets.remove(shown.id);
  final allowed = result['ordinaryUsageAllowed'];
  return QuotaSnapshot(
    provider: 'codex',
    main: shown,
    others: buckets.values.toList(),
    ordinaryUsageAllowed: allowed is bool ? allowed : null,
    readAt: at ?? DateTime.now(),
    via: QuotaVia.read,
  );
}

/// Merges one `account/rateLimits/updated` into [last] (R2): fields absent
/// or null keep the value read before. A bucket other than the one shown
/// goes to its own line.
QuotaSnapshot codexMergeUpdate(
  QuotaSnapshot? last,
  Map<String, dynamic> params, {
  DateTime? at,
}) {
  final base =
      last ??
      QuotaSnapshot(
        provider: 'codex',
        main: const QuotaBucket(id: 'codex'),
        readAt: at ?? DateTime.now(),
        via: QuotaVia.update,
      );
  final s = params['rateLimits'];
  if (s is! Map) return base;
  final update = codexBucket(s);
  final id = update.id;
  final isMain = id.isEmpty || id == 'codex' || id == base.main.id;
  return base.copyWith(
    main: isMain ? base.main.merge(update) : base.main,
    others: isMain
        ? base.others
        : [
            for (final o in base.others)
              if (o.id == id) o.merge(update) else o,
            if (!base.others.any((o) => o.id == id)) update,
          ],
    readAt: at ?? DateTime.now(),
    via: QuotaVia.update,
    clearError: true,
  );
}

/// Why a reading failed, in words for the footer tip (R4).
String codexQuotaFailure(Object e) {
  final text = '$e'.toLowerCase();
  if (e is ProcessException || text.contains('não encontrado')) {
    return 'Codex CLI não encontrado';
  }
  if (e is TimeoutException || text.contains('timeout')) {
    return 'o Codex não respondeu';
  }
  if (text.contains('auth') ||
      text.contains('login') ||
      text.contains('401') ||
      text.contains('unauthorized')) {
    return 'sem login: rode codex login';
  }
  if (text.contains('network') ||
      text.contains('connect') ||
      text.contains('dns') ||
      text.contains('offline') ||
      text.contains('rede')) {
    return 'sem rede';
  }
  return 'erro do App Server';
}

/// `account/rateLimits/read` (R1): through a live, initialized App Server
/// connection when there is one; else a short-lived `codex app-server`
/// (`initialize` → `initialized` → `account/rateLimits/read` → ends). Never
/// `thread/start` nor `turn/start`. Throws on failure ([codexQuotaFailure]
/// says why).
Future<Map<String, dynamic>> readCodexRateLimits({
  required String executable,
  ProcessStarter? starter,
  String clientVersion = '0.0.0',
  Duration timeout = const Duration(seconds: 15),
  bool useLive = true,
}) async {
  if (useLive) {
    for (final rpc in CodexRpc.live.toList()) {
      if (rpc.exited) continue;
      try {
        return await rpc
            .request('account/rateLimits/read', const {})
            .timeout(timeout);
      } catch (_) {
        // That connection could not answer: a short-lived one does.
      }
    }
  }
  final Process process;
  try {
    process = await (starter ?? _start)(
      executable,
      const ['app-server'],
      workingDirectory: Directory.systemTemp.path,
      environment: null,
    );
  } on ProcessException {
    throw const AgentUnavailable('Codex CLI não encontrado.');
  }
  final rpc = CodexRpc(process, timeout: timeout, ephemeral: true);
  final sub = rpc.messages.stream.listen((_) {});
  try {
    await rpc.request('initialize', {
      'clientInfo': {
        'name': 'promptorium',
        'title': 'Promptorium',
        'version': clientVersion,
      },
    });
    await rpc.write({'method': 'initialized', 'params': <String, dynamic>{}});
    return await rpc.request('account/rateLimits/read', const {});
  } finally {
    await sub.cancel();
    await rpc.stop(timeout: const Duration(seconds: 2));
  }
}

Future<Process> _start(
  String exe,
  List<String> args, {
  String? workingDirectory,
  Map<String, String>? environment,
}) => Process.start(exe, args, workingDirectory: workingDirectory);
