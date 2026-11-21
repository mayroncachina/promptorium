import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../claude/claude_event.dart' show RateLimit;
import '../claude/usage_tracker.dart';
import '../codex/codex_cli.dart';
import '../codex/codex_quota.dart';
import '../codex/codex_rpc.dart';
import '../process/process_runner.dart';
import '../update/update_check.dart' show appVersionProvider;
import 'agent_event.dart' show QuotaWindow;
import 'provider_availability.dart';
import 'provider_preferences.dart';

/// The plan quota of each provider in one shape (SPEC-097 R3, R5, R6): the
/// Claude reading (`rate_limit_event` / `/usage`) and the Codex one
/// (`account/rateLimits/read` + updates), each kept apart.

/// Credits of a Codex bucket.
@immutable
class QuotaCredits {
  const QuotaCredits({this.hasCredits, this.unlimited, this.balance});

  final bool? hasCredits;
  final bool? unlimited;

  /// Decimal as text ("0", "12.50").
  final String? balance;

  QuotaCredits merge(QuotaCredits? o) => o == null
      ? this
      : QuotaCredits(
          hasCredits: o.hasCredits ?? hasCredits,
          unlimited: o.unlimited ?? unlimited,
          balance: o.balance ?? balance,
        );

  Map<String, dynamic> toJson() => {
    'has': ?hasCredits,
    'unlimited': ?unlimited,
    'balance': ?balance,
  };

  static QuotaCredits? fromJson(Object? j) => j is! Map
      ? null
      : QuotaCredits(
          hasCredits: j['has'] is bool ? j['has'] as bool : null,
          unlimited: j['unlimited'] is bool ? j['unlimited'] as bool : null,
          balance: j['balance'] is String ? j['balance'] as String : null,
        );
}

/// One metered limit: its windows, credits, plan and the limit reached.
@immutable
class QuotaBucket {
  const QuotaBucket({
    required this.id,
    this.name,
    this.model,
    this.windows = const [],
    this.credits,
    this.plan,
    this.reached,
  });

  final String id;
  final String? name;

  /// The model the bucket describes (`normalModelSlug`).
  final String? model;
  final List<QuotaWindow> windows;
  final QuotaCredits? credits;
  final String? plan;

  /// Kind of limit reached (`rate_limit_reached`, …); null = none.
  final String? reached;

  /// "gpt-6.2-sol · limite próprio" → the name, else the model, else the id.
  String get label => name ?? model ?? id;

  /// Fields of [o] win; absent ones keep this value (R2). Windows merge by
  /// id, field by field.
  QuotaBucket merge(QuotaBucket o) {
    final byId = {for (final w in windows) w.id: w};
    for (final w in o.windows) {
      final old = byId[w.id];
      byId[w.id] = old == null
          ? w
          : QuotaWindow(
              id: w.id,
              label: w.minutes != null ? w.label : old.label,
              usedPercent: w.usedPercent ?? old.usedPercent,
              resetsAt: w.resetsAt ?? old.resetsAt,
              minutes: w.minutes ?? old.minutes,
            );
    }
    return QuotaBucket(
      id: id.isEmpty ? o.id : id,
      name: o.name ?? name,
      model: o.model ?? model,
      windows: byId.values.toList(),
      credits: credits == null ? o.credits : credits!.merge(o.credits),
      plan: o.plan ?? plan,
      reached: o.reached ?? reached,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': ?name,
    'model': ?model,
    'windows': [for (final w in windows) w.toJson()],
    'credits': ?credits?.toJson(),
    'plan': ?plan,
    'reached': ?reached,
  };

  static QuotaBucket fromJson(Object? j) {
    if (j is! Map) return const QuotaBucket(id: '');
    return QuotaBucket(
      id: '${j['id'] ?? ''}',
      name: j['name'] is String ? j['name'] as String : null,
      model: j['model'] is String ? j['model'] as String : null,
      windows: [
        for (final w in j['windows'] as List? ?? const [])
          ?QuotaWindow.fromJson(w),
      ],
      credits: QuotaCredits.fromJson(j['credits']),
      plan: j['plan'] is String ? j['plan'] as String : null,
      reached: j['reached'] is String ? j['reached'] as String : null,
    );
  }
}

/// How the reading came.
enum QuotaVia {
  /// `account/rateLimits/read` (Codex).
  read,

  /// `account/rateLimits/updated` during a run (Codex).
  update,

  /// `claude -p /usage` (Claude).
  usage,

  /// `rate_limit_event` of a reply (Claude).
  reply,
}

/// The last reading of one provider (R3), with when it was read and, after
/// a failed reading, why (R4): the old values stay, marked by their time.
@immutable
class QuotaSnapshot {
  const QuotaSnapshot({
    required this.provider,
    required this.main,
    this.others = const [],
    this.ordinaryUsageAllowed,
    this.readAt,
    this.via,
    this.error,
    this.errorAt,
  });

  final String provider;

  /// The bucket the footer shows (`codex` for the Codex, R5).
  final QuotaBucket main;

  /// The other buckets of `rateLimitsByLimitId` (R6).
  final List<QuotaBucket> others;

  /// Null = unknown, never "allowed" (R7).
  final bool? ordinaryUsageAllowed;
  final DateTime? readAt;
  final QuotaVia? via;

  /// Why the last reading failed (null = it worked).
  final String? error;
  final DateTime? errorAt;

  /// Whether there are values to show (a reading worked once).
  bool get hasReading => main.windows.isNotEmpty;

  QuotaSnapshot copyWith({
    QuotaBucket? main,
    List<QuotaBucket>? others,
    DateTime? readAt,
    QuotaVia? via,
    String? error,
    DateTime? errorAt,
    bool clearError = false,
  }) => QuotaSnapshot(
    provider: provider,
    main: main ?? this.main,
    others: others ?? this.others,
    ordinaryUsageAllowed: ordinaryUsageAllowed,
    readAt: readAt ?? this.readAt,
    via: via ?? this.via,
    error: clearError ? null : error ?? this.error,
    errorAt: clearError ? null : errorAt ?? this.errorAt,
  );

  /// The window of [minutes] (300 = 5 h, 10080 = semana), else by position.
  QuotaWindow? window(int minutes, {String? fallbackId}) =>
      main.windows.where((w) => w.minutes == minutes).firstOrNull ??
      (fallbackId == null
          ? null
          : main.windows
                .where((w) => w.id == fallbackId && w.minutes == null)
                .firstOrNull);

  /// The window that hit the limit, when one did (R7): the kind said by the
  /// server, a blocked ordinary use, or a window at 100% that has not reset
  /// yet. A null `ordinaryUsageAllowed` never counts as allowed, and a
  /// reported limit only clears with a new reading (the protocol forbids
  /// inferring recovery from the times).
  QuotaLimit? limit(DateTime now) {
    final full = [
      for (final w in main.windows)
        if ((w.usedPercent ?? 0) >= 100 && !planWindowExpired(w.resetsAt, now))
          w,
    ];
    if (main.reached == null && ordinaryUsageAllowed != false && full.isEmpty) {
      return null;
    }
    final w = full.firstOrNull ?? _firstPrimary;
    return QuotaLimit(
      kind: main.reached ?? (full.isNotEmpty ? 'rate_limit_reached' : null),
      window: w,
    );
  }

  QuotaWindow? get _firstPrimary =>
      main.windows.where((w) => w.id == 'primary').firstOrNull ??
      main.windows.firstOrNull;

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'main': main.toJson(),
    'others': [for (final o in others) o.toJson()],
    'allowed': ?ordinaryUsageAllowed,
    'read_at': ?readAt?.toUtc().toIso8601String(),
    'via': ?via?.name,
    'error': ?error,
    'error_at': ?errorAt?.toUtc().toIso8601String(),
  };

  static QuotaSnapshot? fromJson(Object? j) {
    if (j is! Map) return null;
    return QuotaSnapshot(
      provider: '${j['provider'] ?? ''}',
      main: QuotaBucket.fromJson(j['main']),
      others: [
        for (final o in j['others'] as List? ?? const [])
          QuotaBucket.fromJson(o),
      ],
      ordinaryUsageAllowed: j['allowed'] is bool ? j['allowed'] as bool : null,
      readAt: DateTime.tryParse('${j['read_at']}'),
      via: QuotaVia.values.where((v) => v.name == j['via']).firstOrNull,
      error: j['error'] is String ? j['error'] as String : null,
      errorAt: DateTime.tryParse('${j['error_at']}'),
    );
  }

  static QuotaSnapshot? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }
}

/// A limit reached (R7): its kind (null = only "uso bloqueado") and the
/// window that renews it.
@immutable
class QuotaLimit {
  const QuotaLimit({this.kind, this.window});

  final String? kind;
  final QuotaWindow? window;

  DateTime? get resetsAt => window?.resetsAt;

  /// "limite do plano", "créditos do workspace esgotados"…
  String get words => quotaLimitWords(kind);
}

/// The kind of limit in words (R7).
String quotaLimitWords(String? kind) => switch (kind) {
  'rate_limit_reached' || 'five_hour' || 'seven_day' => 'limite do plano',
  'workspace_owner_credits_depleted' => 'créditos do workspace esgotados',
  'workspace_member_credits_depleted' => 'seus créditos do workspace esgotados',
  'workspace_owner_usage_limit_reached' => 'limite de uso do workspace',
  'workspace_member_usage_limit_reached' => 'seu limite de uso no workspace',
  null => 'uso do plano bloqueado',
  final k => k.replaceAll('_', ' '),
};

/// The name of a plan (P5): the known `planType`s translated, the others
/// raw; null for none or `unknown`.
String? quotaPlanName(String? plan) => switch (plan?.toLowerCase()) {
  null || '' || 'unknown' => null,
  'free' => 'ChatGPT Free',
  'go' => 'ChatGPT Go',
  'plus' => 'ChatGPT Plus',
  'pro' => 'ChatGPT Pro',
  'prolite' => 'ChatGPT Pro Lite',
  'promax' => 'ChatGPT Pro Max',
  'team' => 'Team',
  'business' => 'Business',
  'enterprise' => 'Enterprise',
  'edu' => 'Edu',
  'max' => 'Max',
  _ => plan,
};

/// The label of a window by its duration (R5): "Uso 5h", "Semana", else
/// "Janela de N h".
String quotaWindowTitle(int? minutes) => switch (minutes) {
  300 => 'Uso 5h',
  10080 => 'Semana',
  null => 'Janela',
  final m when m % 60 == 0 => 'Janela de ${m ~/ 60} h',
  final m => 'Janela de $m min',
};

/// The Claude reading in the same shape (R3): the 5-hour and weekly
/// windows (0–1 → %), the plan of `claude auth status`, `rejected` as the
/// limit reached.
QuotaSnapshot claudeSnapshot(
  RateLimit r, {
  String? plan,
  DateTime? readAt,
  QuotaVia? via,
}) => QuotaSnapshot(
  provider: 'claude',
  main: QuotaBucket(
    id: 'claude',
    plan: plan,
    reached: r.status == 'rejected' ? (r.rateLimitType ?? 'five_hour') : null,
    windows: [
      if (r.fiveHourUtilization != null || r.fiveHourResetsAt != null)
        QuotaWindow(
          id: 'five_hour',
          label: QuotaWindow.labelOf(300),
          usedPercent: r.fiveHourUtilization == null
              ? null
              : r.fiveHourUtilization! * 100,
          resetsAt: r.fiveHourResetsAt,
          minutes: 300,
        ),
      if (r.sevenDayUtilization != null || r.sevenDayResetsAt != null)
        QuotaWindow(
          id: 'seven_day',
          label: QuotaWindow.labelOf(10080),
          usedPercent: r.sevenDayUtilization == null
              ? null
              : r.sevenDayUtilization! * 100,
          resetsAt: r.sevenDayResetsAt,
          minutes: 10080,
        ),
    ],
  ),
  readAt: readAt,
  via: via,
);

// --- Codex store ---------------------------------------------------------------

/// Reads `account/rateLimits/read` (tests replace it).
typedef CodexQuotaReader = Future<Map<String, dynamic>> Function();

final codexQuotaReaderProvider = Provider<CodexQuotaReader>((ref) {
  return () async {
    final starter = ref.read(codexProcessStarterProvider);
    // Like the handshake: the App Server only starts for real with the real
    // runner, or with an injected starter (tests).
    final underTest = Platform.environment['FLUTTER_TEST'] == 'true';
    final real = identical(
      ref.read(processRunnerProvider),
      defaultProcessRunner,
    );
    if (starter == null && (!real || underTest)) {
      throw StateError('leitura da cota desligada nos testes');
    }
    return readCodexRateLimits(
      executable: ref.read(codexExecutableProvider),
      starter: starter,
      clientVersion: ref.read(appVersionProvider).value ?? '0.0.0',
    );
  };
});

/// The last Codex reading (R3), kept in `app_settings`
/// ([AppSettingKeys.codexLastRateLimit]) apart from the Claude one, and
/// merged with the updates of the runs (R2).
class CodexQuotaController extends Notifier<QuotaSnapshot?> {
  @override
  QuotaSnapshot? build() {
    final sub = codexRateLimitUpdates.stream.listen(
      (p) => unawaited(applyUpdate(p)),
    );
    ref.onDispose(sub.cancel);
    // Listened, not watched: a rebuild would drop the subscription above.
    // The settings load after the start; the store follows them.
    ref.listen(
      appSettingsProvider.select((s) => s[AppSettingKeys.codexLastRateLimit]),
      (_, raw) {
        if (raw != _saved) state = QuotaSnapshot.decode(raw);
      },
    );
    return QuotaSnapshot.decode(
      ref.read(appSettingsProvider)[AppSettingKeys.codexLastRateLimit],
    );
  }

  /// What this store wrote last (its own write is not a change to follow).
  String? _saved;

  bool _reading = false;

  Future<void> _save(QuotaSnapshot s) {
    state = s;
    final raw = _saved = jsonEncode(s.toJson());
    return ref
        .read(appSettingsProvider.notifier)
        .set(AppSettingKeys.codexLastRateLimit, raw);
  }

  /// One `account/rateLimits/read` (R1). A failure keeps the last values
  /// and says why (R4); never throws.
  Future<void> refresh() async {
    if (_reading) return;
    _reading = true;
    try {
      final result = await ref.read(codexQuotaReaderProvider)();
      if (!ref.mounted) return;
      await _save(codexSnapshotFromRead(result));
    } catch (e) {
      debugPrint('cota do Codex: leitura falhou — $e');
      if (ref.mounted) await fail(codexQuotaFailure(e));
    } finally {
      _reading = false;
    }
  }

  /// A reading that could not happen ([reason] for the tip, R4).
  Future<void> fail(String reason) => _save(
    (state ??
            const QuotaSnapshot(
              provider: 'codex',
              main: QuotaBucket(id: 'codex'),
            ))
        .copyWith(error: reason, errorAt: DateTime.now()),
  );

  /// `account/rateLimits/updated` (R2).
  Future<void> applyUpdate(Map<String, dynamic> params) async {
    if (!ref.mounted) return;
    await _save(codexMergeUpdate(state, params));
  }
}

final codexQuotaProvider =
    NotifierProvider<CodexQuotaController, QuotaSnapshot?>(
      CodexQuotaController.new,
    );

/// When the Codex quota is read (R1, P1): at start with the Codex installed
/// and logged in, then every 5 minutes only while the Codex is the active
/// provider or has a run open. Never blocks the start nor a run (R4).
class CodexQuotaPoller {
  CodexQuotaPoller(this._ref);

  final Ref _ref;

  /// Whether the Codex is installed and logged in; a missing login is
  /// recorded as the reason (R4). Null = not installed (nothing to read).
  Future<bool> _ready() async {
    try {
      if (await _ref.read(codexCliInfoProvider.future) == null) return false;
      final a = await _ref.read(providerAvailabilityProvider('codex').future);
      if (a.status == ProviderStatus.loginRequired) {
        await _ref
            .read(codexQuotaProvider.notifier)
            .fail('sem login: rode codex login');
        return false;
      }
      return a.available;
    } catch (_) {
      return false;
    }
  }

  /// At start (R1).
  Future<void> start() async {
    if (await _ready()) {
      await _ref.read(codexQuotaProvider.notifier).refresh();
    }
  }

  /// The 5-minute tick (P1): only with the Codex active or running.
  Future<void> tick() async {
    final active = _ref.read(activeAgentProvider) == 'codex';
    if (!active && !CodexRpc.runAlive) return;
    if (await _ready()) {
      await _ref.read(codexQuotaProvider.notifier).refresh();
    }
  }
}

final codexQuotaPollerProvider = Provider(CodexQuotaPoller.new);

// --- both providers --------------------------------------------------------------

/// The last reading of [provider] (`claude` or `codex`; null = none yet).
final quotaSnapshotProvider = Provider.family<QuotaSnapshot?, String>((
  ref,
  provider,
) {
  switch (provider) {
    case 'codex':
      return ref.watch(codexQuotaProvider);
    case 'claude':
      final r = ref.watch(rateLimitProvider);
      if (r == null) return null;
      final read = ref.watch(rateLimitReadProvider);
      return claudeSnapshot(
        r,
        plan: quotaPlanName(
          ref
              .watch(providerAvailabilityProvider('claude'))
              .value
              ?.subscriptionType,
        ),
        readAt: read?.at,
        via: read?.via,
      );
    default:
      return null;
  }
});
