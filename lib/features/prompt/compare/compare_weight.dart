import '../../../core/providers/agent_event.dart';
import '../../../core/providers/capabilities.dart' show isClaudeCode;
import '../../activities/quota_forecast.dart' show sessionQuotaWeights;
import 'compare_run.dart';

/// The weight of each side in the plan (SPEC-079 R7, R8). Pure.

/// The weights of the sides and how they were found.
typedef CompareWeights = ({Map<String, SideWeight> weights, bool measured});

/// Splits the rise of the 5-hour window and of the week between the sides
/// by their share of [costs] (the US$ is only a proportion, P2).
///
/// Without both readings ([before] and [after]), or when a window renewed
/// in between, it falls back to the Atividades rule (`sessionQuotaWeights`,
/// SPEC-076 R7) on the last reading [last]: the share of each side in the
/// cost of what ran in the window ([windowCosts] + [costs]) times its use.
CompareWeights compareWeights({
  required Map<String, double> costs,
  UsageReading? before,
  UsageReading? after,
  UsageReading? last,
  Map<String, double> windowCosts = const {},
}) {
  final total = costs.values.fold(0.0, (a, c) => a + c);
  double share(String k) =>
      total <= 0 ? 1 / costs.length : (costs[k] ?? 0) / total;

  final b = before, a = after;
  final sameWindow =
      b != null &&
      a != null &&
      (b.fiveResetsAt == null ||
          a.fiveResetsAt == null ||
          b.fiveResetsAt == a.fiveResetsAt);
  if (sameWindow && b.five != null && a.five != null) {
    final five = a.five! - b.five!;
    final week = (a.week ?? 0) - (b.week ?? 0);
    if (five >= 0 && week >= 0) {
      return (
        weights: {
          for (final k in costs.keys)
            k: (five: five * share(k), week: week * share(k)),
        },
        measured: true,
      );
    }
  }

  final reading = last ?? after ?? before;
  final all = {...windowCosts, ...costs};
  final five = sessionQuotaWeights(all, reading?.five);
  final week = sessionQuotaWeights(all, reading?.week);
  if (five.isEmpty && week.isEmpty) return (weights: const {}, measured: false);
  return (
    weights: {
      for (final k in costs.keys) k: (five: five[k] ?? 0, week: week[k] ?? 0),
    },
    measured: false,
  );
}

/// The weights of the sides of a comparison, each on the quota of its
/// provider (SPEC-108 R8).
///
/// * Different providers: the whole variation of each quota is of its only
///   side; no cost enters, and without both readings there is no weight.
/// * Both on the Claude: [compareWeights], by the cost (SPEC-079 R8).
/// * Both on the Codex (no cost): the variation by the share of the total
///   tokens; without both readings there is no weight.
CompareWeights compareRunWeights({
  required List<CompareSide> sides,
  required Map<String, UsageReading> before,
  required Map<String, UsageReading> after,
  UsageReading? lastClaude,
  Map<String, double> windowCosts = const {},
}) {
  final byProvider = <String, List<CompareSide>>{};
  for (final s in sides) {
    (byProvider[s.provider] ??= []).add(s);
  }
  final out = <String, SideWeight>{};
  var measured = true;
  for (final MapEntry(key: provider, value: group) in byProvider.entries) {
    final claudePair = isClaudeCode(provider) && group.length > 1;
    final w = compareWeights(
      costs: {
        for (final s in group)
          s.letter: group.length == 1
              ? 1.0
              : claudePair
              ? s.metrics?.costUsd ?? 0
              : (s.metrics?.totalTokens ?? 0).toDouble(),
      },
      before: before[provider],
      after: after[provider],
      last: claudePair ? lastClaude : null,
      windowCosts: claudePair ? windowCosts : const {},
    );
    if (!claudePair && !w.measured) {
      measured = false;
      continue;
    }
    measured = measured && w.measured;
    out.addAll(w.weights);
  }
  return (weights: out, measured: measured);
}

/// What a command of the agent counts as (SPEC-108 R7): a read, a search
/// or a command, by its classified actions (Codex `commandActions`). The
/// keys are the Claude tools, so both providers count alike.
String compareCommandTool(CommandEvent e) {
  final types = {for (final a in e.actions) a.type};
  if (types.contains(CommandAction.read)) return 'Read';
  if (types.contains(CommandAction.search)) return 'Grep';
  if (types.contains(CommandAction.listFiles)) return 'Glob';
  return 'Bash';
}

String _num(double v, {int digits = 1}) =>
    v.toStringAsFixed(digits).replaceAll('.', ',');

/// `≈ 1,2%` (0–1 in).
String compareWeightLabel(double w) => '≈ ${_num(w * 100)}%';

/// "cerca de 1,2 por cento" (R15).
String compareWeightSpoken(double w) => 'cerca de ${_num(w * 100)} por cento';

/// `38 s`, `1 min 52 s`, `2 min`.
String compareDuration(int ms) {
  final s = (ms / 1000).round();
  if (s < 60) return '$s s';
  final m = s ~/ 60, rest = s % 60;
  return rest == 0 ? '$m min' : '$m min $rest s';
}

/// "38 segundos", "1 minuto e 52 segundos" (R15).
String compareDurationSpoken(int ms) {
  final s = (ms / 1000).round();
  String sec(int n) => n == 1 ? '1 segundo' : '$n segundos';
  if (s < 60) return sec(s);
  final m = s ~/ 60, rest = s % 60;
  final min = m == 1 ? '1 minuto' : '$m minutos';
  return rest == 0 ? min : '$min e ${sec(rest)}';
}

/// The live clock: `0:42`, `1:04`.
String compareClock(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// `950`, `14,2 mil`, `1,3 mi`.
String compareTokens(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) return '${_num(n / 1000)} mil';
  return '${_num(n / 1000000)} mi';
}

/// `14,2 mil → 1,1 mil` (the reasoning goes apart, [compareReasoningLine]).
String compareTokensLine(CompareMetrics m) =>
    '${compareTokens(m.tokensIn)} → ${compareTokens(m.answerTokens)}';

/// `raciocínio 2,1 mil` (SPEC-108 R7); null without it.
String? compareReasoningLine(CompareMetrics m) =>
    m.reasoning > 0 ? 'raciocínio ${compareTokens(m.reasoning)}' : null;

/// `9 leituras · 2 buscas · 1 comando · 1 outra` (R7); `nenhuma` without
/// calls.
String compareCalls(Map<String, int> tools) {
  var reads = 0, searches = 0, web = 0, agents = 0, other = 0;
  var commands = 0, mcp = 0;
  for (final MapEntry(:key, :value) in tools.entries) {
    switch (key) {
      case 'Read' || 'NotebookRead':
        reads += value;
      case 'Grep' || 'Glob' || 'LS':
        searches += value;
      case 'WebFetch' || 'WebSearch':
        web += value;
      case 'Task' || 'Agent':
        agents += value;
      case 'Bash' || 'PowerShell':
        commands += value;
      case _ when key.startsWith('mcp__'):
        mcp += value;
      default:
        other += value;
    }
  }
  String n(int v, String one, String many) => v == 1 ? '1 $one' : '$v $many';
  final parts = [
    if (reads > 0) n(reads, 'leitura', 'leituras'),
    if (searches > 0) n(searches, 'busca', 'buscas'),
    if (commands > 0) n(commands, 'comando', 'comandos'),
    if (mcp > 0) n(mcp, 'chamada MCP', 'chamadas MCP'),
    if (web > 0) n(web, 'consulta web', 'consultas web'),
    if (agents > 0) n(agents, 'subagente', 'subagentes'),
    if (other > 0) n(other, 'outra', 'outras'),
  ];
  return parts.isEmpty ? 'nenhuma' : parts.join(' · ');
}

/// "cotas diferentes" (SPEC-108 R8, P2): there is no ratio of weights.
const compareNoRatio = 'cotas diferentes · sem razão de peso';

/// The hint of the tokens between providers (SPEC-108 R7).
const compareTokenizersHint =
    'tokenizadores diferentes: os tokens servem de ordem de grandeza';

/// "B levou 0,6× o tempo · usou 1,3× os tokens" (SPEC-108 R7): B over A;
/// null until both sides have both values.
String? compareTimeTokens(CompareSide a, CompareSide b) {
  final x = a.metrics, y = b.metrics;
  if (x == null || y == null) return null;
  String? ratio(int n, int d) => n <= 0 || d <= 0 ? null : _num(n / d);
  final time = ratio(y.durationMs, x.durationMs);
  final tokens = ratio(y.totalTokens, x.totalTokens);
  final parts = [
    if (time != null) 'levou $time× o tempo',
    if (tokens != null) 'usou $tokens× os tokens',
  ];
  return parts.isEmpty ? null : '${b.letter} ${parts.join(' · ')}';
}

/// "B pesou 4,8× o A" and "B levou 2,9× o tempo" (R7): the heavier side
/// over the lighter. Null parts when a side has no value yet (or both are
/// even). Sides on different quotas have no ratio of weights (SPEC-108 R8).
({String? weight, String? time}) compareRatio(CompareSide a, CompareSide b) {
  String? ratio(
    double x,
    double y,
    String Function(String hi, String lo, String r) text,
  ) {
    if (x <= 0 || y <= 0) return null;
    final hi = x >= y ? b.letter : a.letter;
    final lo = x >= y ? a.letter : b.letter;
    final r = x >= y ? x / y : y / x;
    if (r < 1.05) return null;
    return text(hi, lo, _num(r));
  }

  final wa = a.weight?.five ?? 0, wb = b.weight?.five ?? 0;
  final weight = a.provider != b.provider
      ? null
      : wa > 0 && wb > 0
      ? ratio(wb, wa, (hi, lo, r) => '$hi pesou $r× o $lo')
      : ratio(
          b.metrics?.costUsd ?? 0,
          a.metrics?.costUsd ?? 0,
          (hi, lo, r) => '$hi pesou $r× o $lo',
        );
  final time = ratio(
    (b.metrics?.durationMs ?? 0).toDouble(),
    (a.metrics?.durationMs ?? 0).toDouble(),
    (hi, lo, r) => '$hi levou $r× o tempo',
  );
  return (weight: weight, time: time);
}
