import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'project_planner.dart' show ProjectPlanner;

/// Honest cost and time of "Criar projeto" (SPEC-072 R7–R10, R19): calls of
/// the planner instead of dollars on a subscription plan, the refine queue
/// as "N specs × time" from the recorded rounds, and the plan usage.

/// Rounds of the refine queue kept for the estimate (any project, R9).
const refineRoundsKept = 20;

/// Recorded durations (seconds) of the last refine rounds.
List<int> decodeRefineRounds(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    return [
      for (final x in list)
        if (x is num && x > 0) x.round(),
    ];
  } catch (_) {
    return const [];
  }
}

/// [rounds] plus [seconds], keeping the last [refineRoundsKept].
List<int> addRefineRound(List<int> rounds, int seconds) {
  final all = [...rounds, seconds];
  return all.length <= refineRoundsKept
      ? all
      : all.sublist(all.length - refineRoundsKept);
}

/// Median of [rounds] in seconds, or null with fewer than 3 (R9).
int? refineMedian(List<int> rounds) {
  if (rounds.length < 3) return null;
  final s = [...rounds]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : ((s[m - 1] + s[m]) / 2).round();
}

int _minutes(int seconds) => seconds < 60 ? 1 : (seconds / 60).round();

/// "16 min", "1 h 20 min".
String formatMinutes(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

/// The queue estimate of R9.
@immutable
class QueueEstimate {
  const QueueEstimate(this.rounds);

  final List<int> rounds;

  int? get median => refineMedian(rounds);

  /// "~2 min" or "1–3 min".
  String get perSpec =>
      median == null ? '1–3 min' : '~${_minutes(median!)} min';

  /// "(mediana de 14 rodadas)", or null without history.
  String? get basis =>
      median == null ? null : 'mediana de ${rounds.length} rodadas';

  /// "≈ 16 min" or "≈ 8–24 min" for [specs].
  String total(int specs) {
    final m = median;
    if (m == null) {
      return '≈ ${formatMinutes(specs)}–${formatMinutes(specs * 3)}'
          .replaceFirst(RegExp(r' min–'), '–');
    }
    return '≈ ${formatMinutes(specs * _minutes(m))}';
  }

  /// "8 specs × ~2 min ≈ 16 min".
  String forSpecs(int specs) => '$specs specs × $perSpec ${total(specs)}';

  /// "~16 min" or "8–24 min" (the step of the queue, R10).
  String short(int specs) {
    final t = total(specs).substring(2);
    return median == null ? t : '~$t';
  }
}

/// "depois, ~38 min por spec (média de 6 specs deste projeto)" from the
/// execution time of the specs that ran, or null without history (R9).
String? executionEstimate(Iterable<Duration> times) {
  final ran = [
    for (final t in times)
      if (t > Duration.zero) t,
  ];
  if (ran.isEmpty) return null;
  final avg = ran.fold(Duration.zero, (a, b) => a + b).inSeconds ~/ ran.length;
  final n = ran.length;
  return 'depois, ~${formatMinutes(_minutes(avg))} por spec (média de '
      '$n ${n == 1 ? 'spec' : 'specs'} deste projeto)';
}

/// Calls of the planner of one workspace, by kind (R8, R10, R19).
@immutable
class PlannerCalls {
  const PlannerCalls([this.byKind = const {}]);

  factory PlannerCalls.decode(String? raw) {
    if (raw == null || raw.isEmpty) return const PlannerCalls();
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return const PlannerCalls();
      return PlannerCalls({
        for (final e in m.entries)
          if (e.value is num) '${e.key}': (e.value as num).toInt(),
      });
    } catch (_) {
      return const PlannerCalls();
    }
  }

  /// `visao`, `stack`, `roadmap`, `ideia`, `outro` (the "Outro…" modal).
  final Map<String, int> byKind;

  int get total => byKind.values.fold(0, (a, b) => a + b);

  PlannerCalls add(String kind, [int n = 1]) =>
      PlannerCalls({...byKind, kind: (byKind[kind] ?? 0) + n});

  String encode() => jsonEncode(byKind);

  static const _labels = {
    'visao': 'visão',
    'stack': 'stack',
    'roadmap': 'roadmap',
    'ideia': 'ideias',
    'outro': 'stack do Outro…',
  };

  /// "4 chamadas", "1 chamada".
  String get label => callsLabel(total);

  /// "visão 2, stack 1, roadmap 1".
  String get detail => [
    for (final k in _labels.keys)
      if ((byKind[k] ?? 0) > 0) '${_labels[k]} ${byKind[k]}',
  ].join(', ');
}

String callsLabel(int n) => n == 1 ? '1 chamada' : '$n chamadas';

/// "US$ 0,50".
String usd(double v) => 'US\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

/// The ceiling of an API key (R8).
String get apiCeiling =>
    'até ${usd(ProjectPlanner.budgetUsd)} por chamada do planner, '
    '${usd(ProjectPlanner.roadmapBudgetUsd)} no roadmap';

/// Calls of the planner of a workspace ([AppSettingKeys.plannerCalls]).
final plannerCallsProvider = Provider.family<PlannerCalls, int>(
  (ref, workspaceId) => PlannerCalls.decode(
    ref.watch(
      appSettingsProvider.select(
        (s) => s[AppSettingKeys.plannerCalls(workspaceId)],
      ),
    ),
  ),
);

/// Counts [n] calls of [kind] for [workspaceId].
Future<void> recordPlannerCalls(
  Ref ref,
  int workspaceId,
  String kind, [
  int n = 1,
]) {
  if (n <= 0) return Future.value();
  final settings = ref.read(appSettingsProvider.notifier);
  final key = AppSettingKeys.plannerCalls(workspaceId);
  return settings.set(
    key,
    PlannerCalls.decode(settings.get(key)).add(kind, n).encode(),
  );
}

/// Durations of the last refine rounds ([AppSettingKeys.refineRounds]).
final refineRoundsProvider = Provider<List<int>>(
  (ref) => decodeRefineRounds(
    ref.watch(
      appSettingsProvider.select((s) => s[AppSettingKeys.refineRounds]),
    ),
  ),
);

/// Records one refine round of the queue (R9).
Future<void> recordRefineRound(Ref ref, Duration d) {
  final settings = ref.read(appSettingsProvider.notifier);
  final rounds = decodeRefineRounds(settings.get(AppSettingKeys.refineRounds));
  final seconds = d.inSeconds < 1 ? 1 : d.inSeconds;
  return settings.set(
    AppSettingKeys.refineRounds,
    jsonEncode(addRefineRound(rounds, seconds)),
  );
}

/// The steps of "O que acontece" on the Começar screen (R7, R19): no
/// promise of seconds or dollars; calls and the queue time instead.
/// [customCalls] = proposals and adjustments of the "Outro…" stack.
List<String> startSteps(QueueEstimate queue, {int customCalls = 0}) => [
  'Pasta, git init e commit inicial · segundos',
  'Proposta do planner: 3 chamadas (visão, stack e roadmap) · cada mensagem '
      'a mais na Visão é mais uma'
      '${customCalls > 0 ? ' · +${callsLabel(customCalls)} (a stack do Outro…)' : ''}',
  'Fila de refino: 1 rodada por spec · ${queue.perSpec} cada'
      '${queue.basis == null ? '' : ' (${queue.basis})'}',
  'Revisar e criar: AGENTS.md, CLAUDE.md, config.yml, specs e Quadro',
];
