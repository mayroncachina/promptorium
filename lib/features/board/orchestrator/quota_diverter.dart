import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/git/git_service.dart';
import '../../../core/providers/agent_event.dart' show Result;
import '../../../core/providers/capabilities.dart';
import '../../../core/providers/provider_availability.dart';
import '../../../core/providers/quota_source.dart';
import '../../../data/providers.dart';
import '../../activities/automation_pause.dart';
import 'orchestrator_rules.dart';
import 'quota_divert.dart';
import 'step_plan.dart';

/// Reads the quotas (SPEC-097) and keeps what the desvio por cota needs
/// between steps (SPEC-109 R5–R8), in `app_settings`: the limits reached,
/// where a spec was diverted to and why it waits. The decision itself is
/// [divertFor].
class QuotaDiverter {
  QuotaDiverter(this._ref);

  final Ref _ref;

  OrchestratorPrefs get _prefs => _ref.read(orchestratorPrefsProvider);
  AppSettingsController get _settings =>
      _ref.read(appSettingsProvider.notifier);

  /// Some kind of diversion is on (off by default) and "Pausar automáticos"
  /// (SPEC-076 R8, R12) is not.
  bool get enabled =>
      (_prefs.divertOnQuota || _prefs.divertAbovePercent != null) &&
      !automationPaused(_ref);

  /// R5 only: a step that reaches the limit goes to the other provider.
  bool get onQuota => _prefs.divertOnQuota && !automationPaused(_ref);

  /// Why [provider] cannot run a step now (R8, R1); null = it can.
  Future<String?> blocked(String provider) async {
    if (!_ref.read(providerFlowsProvider).allows(provider, AppFlow.runSpec)) {
      return 'desligado em "Executar spec"';
    }
    try {
      final a = await _ref.read(providerAvailabilityProvider(provider).future);
      return a.available ? null : a.label;
    } catch (e) {
      return 'não verificado';
    }
  }

  /// The last limit [provider] reached in a step.
  QuotaHit? hitOf(String provider) => QuotaHit.decode(
    _settings.get(AppSettingKeys.orchestratorQuotaHit(provider)),
  );

  Future<void> recordHit(QuotaHit hit) => _settings.set(
    AppSettingKeys.orchestratorQuotaHit(hit.provider),
    hit.encode(),
  );

  /// What a step planned as [plan] does now. Everything off = the plan,
  /// without reading anything.
  Future<DivertDecision> decide(StepRunPlan plan, {DateTime? now}) async {
    if (!enabled) return DivertDecision.plan(plan.rule);
    final rule = plan.rule;
    final reserve = _prefs.fallback(plan.kind, from: rule.provider);
    DivertDecision decision(String? blocked) => divertFor(
      plan: rule,
      reserve: reserve,
      prefs: _prefs,
      now: now ?? DateTime.now(),
      readings: {
        for (final p in const ['claude', 'codex'])
          p: _ref.read(quotaSnapshotProvider(p)),
      },
      hits: {
        for (final p in const ['claude', 'codex']) p: hitOf(p),
      },
      reserveBlocked: blocked,
    );
    final first = decision(null);
    // The other provider is only probed when the step would go there.
    if (reserve == null || first.reason == null && !first.waits) return first;
    return decision(await blocked(reserve.provider));
  }

  /// The limit that ended the turn [r] of a session on [provider] (R5), or
  /// null. [seen] is the limit the session reported during it. On the
  /// Codex the turn must have failed: a limit reported at the end of a turn
  /// that finished is for the next one.
  Future<QuotaHit?> hitOfTurn(String provider, Result r, QuotaHit? seen) async {
    if (r.isInterrupted) return null;
    if (provider == 'claude') return seen;
    if (r.isSuccess) return null;
    if (seen != null) return seen;
    final error = r.json['error'];
    final info = error is Map ? error['codexErrorInfo'] : null;
    if (info != 'usageLimitExceeded') {
      // `ordinaryUsageAllowed = false` only comes in a full reading (free,
      // never a turn).
      await _ref.read(codexQuotaProvider.notifier).refresh();
    }
    final now = DateTime.now();
    final reading = _ref.read(quotaSnapshotProvider(provider));
    final limit = reading?.limit(now);
    if (limit == null && info != 'usageLimitExceeded') return null;
    final w = limit?.window ?? mostUsedWindow(reading, now);
    return QuotaHit(
      provider: provider,
      at: now,
      minutes: w?.minutes,
      resetsAt: w?.resetsAt,
    );
  }

  // --- state of a spec --------------------------------------------------------

  SpecDivert? divertOf(int specId) =>
      SpecDivert.decode(_settings.get(AppSettingKeys.specDivert(specId)));

  Future<void> setDivert(int specId, SpecDivert? d) => d == null
      ? _settings.remove(AppSettingKeys.specDivert(specId))
      : _settings.set(AppSettingKeys.specDivert(specId), d.encode());

  SpecQuotaWait? waitOf(int specId) =>
      SpecQuotaWait.decode(_settings.get(AppSettingKeys.specQuotaWait(specId)));

  Future<void> setWait(int specId, SpecQuotaWait? w) async {
    final key = AppSettingKeys.specQuotaWait(specId);
    if (w != null) return _settings.set(key, w.encode());
    if (_settings.get(key) != null) await _settings.remove(key);
  }

  /// The specs that wait, by id.
  Map<int, SpecQuotaWait> get waits => {
    for (final MapEntry(:key, :value) in _ref.read(appSettingsProvider).entries)
      if (RegExp(r'^spec\.(\d+)\.quotaWait$').firstMatch(key) case final m?)
        int.parse(m.group(1)!): ?SpecQuotaWait.decode(value),
  };

  // --- worktree ----------------------------------------------------------------

  /// The automatic rewind (R5) only touches the worktree of the spec: [path]
  /// must be the top of one of the worktrees of [root] and never the root
  /// itself. Null = it is; else why not.
  Future<String?> notOwnWorktree(String root, String path) async {
    final factory = _ref.read(gitServiceFactoryProvider);
    try {
      final top = (await factory(path).git(['rev-parse', '--show-toplevel']))
          .trim();
      String real(String p) =>
          p.endsWith('/') ? p.substring(0, p.length - 1) : p;
      if (real(top) != real(path)) {
        return '$path não é a raiz de um worktree';
      }
      if (real(path) == real(root)) return 'a spec roda na raiz do projeto';
      final known = await factory(root).listWorktrees();
      if (!known.any((w) => real(w.path) == real(path) && !w.prunable)) {
        return '$path não é um worktree deste projeto';
      }
      return null;
    } on GitException catch (e) {
      return '$e';
    }
  }

  /// What the interrupted attempt left, files not committed included, kept
  /// in a ref before the rewind (nothing of it is lost for good) and as the
  /// diff against [startSha] for the package (R5, P4).
  Future<({String diff, List<String> files, String? ref})> keepAttempt(
    String worktree,
    String startSha,
    String ref, {
    required int maxChars,
  }) async {
    final git = _ref.read(gitServiceFactoryProvider)(worktree);
    try {
      final state = await git.snapshot() ?? await git.headSha();
      if (state == null || state == startSha) {
        return (diff: '', files: const <String>[], ref: null);
      }
      await git.updateRef(ref, state);
      final diff = await git.git(['diff', startSha, state]);
      final files = [
        for (final l in (await git.git([
          'diff',
          '--name-only',
          startSha,
          state,
        ])).split('\n'))
          if (l.trim().isNotEmpty) l.trim(),
      ];
      return (
        diff: diff.length <= maxChars
            ? diff.trimRight()
            : '${diff.substring(0, maxChars)}…',
        files: files,
        ref: files.isEmpty ? null : ref,
      );
    } on GitException catch (e) {
      debugPrint('$ref: tentativa não guardada — $e');
      return (diff: '', files: const <String>[], ref: null);
    }
  }
}

final quotaDiverterProvider = Provider(QuotaDiverter.new);

/// Where the spec was diverted to (card, steps); null = on its plan.
final specDivertProvider = Provider.autoDispose.family<SpecDivert?, int>(
  (ref, specId) => SpecDivert.decode(
    ref.watch(
      appSettingsProvider.select((s) => s[AppSettingKeys.specDivert(specId)]),
    ),
  ),
);

/// Why the spec waits for quota (R8); null = it does not.
final specQuotaWaitProvider = Provider.autoDispose.family<SpecQuotaWait?, int>(
  (ref, specId) => SpecQuotaWait.decode(
    ref.watch(
      appSettingsProvider.select(
        (s) => s[AppSettingKeys.specQuotaWait(specId)],
      ),
    ),
  ),
);
