// Formats of the cost per spec (SPEC-081 R13): weights with "≈" and a
// decimal comma, windows above 100% as windows, tokens in k and M.

String _comma(double v, int decimals) =>
    v.toStringAsFixed(decimals).replaceAll('.', ',');

/// A weight (0–1) as a percent: "≈ 0,4%", "≈ 23%", "< 0,1%"; "—" without
/// one.
String formatQuota(double? fraction) {
  if (fraction == null) return '—';
  final pct = fraction * 100;
  if (pct < 0.1) return '< 0,1%';
  if (pct < 10) {
    final one = _comma(pct, 1);
    // 9,96% rounds to "10,0": no decimal from 10 on; "9,0" is "9".
    if (one.startsWith('10')) return '≈ 10%';
    return '≈ ${one.endsWith(',0') ? one.substring(0, one.length - 2) : one}%';
  }
  return '≈ ${pct.round()}%';
}

/// The weight in the 5-hour window: a percent up to 100%, then windows
/// ("≈ 1,4 janela de 5 h"; [short]: "≈ 1,4 jan.").
String formatFiveHour(double? fraction, {bool short = false}) {
  if (fraction == null) return '—';
  if (fraction * 100 < 99.5) return formatQuota(fraction);
  final n = _comma(fraction, 1);
  if (short) return '≈ $n jan.';
  return '≈ $n ${fraction >= 1.95 ? 'janelas' : 'janela'} de 5 h';
}

/// Only the number of [formatFiveHour] (the tile writes the unit below):
/// "≈ 86%" or "≈ 1,4".
String formatFiveHourValue(double? fraction) {
  if (fraction == null) return '—';
  if (fraction * 100 < 99.5) return formatQuota(fraction);
  return '≈ ${_comma(fraction, 1)}';
}

/// "812 k", "1,8 M", "41 M", "640".
String formatTokens(int n) {
  if (n < 1000) return '$n';
  if (n < 999500) return '${(n / 1000).round()} k';
  final m = n / 1e6;
  return m >= 9.95 ? '${m.round()} M' : '${_comma(m, 1)} M';
}

/// Dollars of the API key (R12): "US$ 4,12".
String formatUsd(double usd) => 'US\$ ${_comma(usd, 2)}';

/// What the screen reader says (R14): "cerca de 6,2%", "menos de 0,1%".
String spokenQuota(double? fraction) {
  if (fraction == null) return 'sem leitura da cota';
  final pct = fraction * 100;
  if (pct < 0.1) return 'menos de 0,1%';
  return 'cerca de ${formatQuota(fraction).substring(2)}';
}

/// "1,4 janela de 5 horas" / "cerca de 86% da janela de 5 horas".
String spokenFiveHour(double? fraction) {
  if (fraction == null) return 'sem leitura da janela de 5 horas';
  if (fraction * 100 < 99.5) {
    return '${spokenQuota(fraction)} da janela de 5 horas';
  }
  final n = _comma(fraction, 1);
  return '$n ${fraction >= 1.95 ? 'janelas' : 'janela'} de 5 horas';
}

/// "1,8 milhão de tokens", "812 mil tokens".
String spokenTokens(int n) {
  if (n < 1000) return '$n tokens';
  if (n < 999500) return '${(n / 1000).round()} mil tokens';
  final m = n / 1e6;
  return '${_comma(m, 1)} ${m >= 1.95 ? 'milhões' : 'milhão'} de tokens';
}

/// What a turn without a cost in US$ shows (SPEC-097 R9): never "US$ 0,00".
const costUnavailable = 'custo indisponível';

/// The same in a narrow cell of a table.
const costUnavailableShort = 'indisp.';

/// "1,2 mi", "820 mil", "640" (the words of SPEC-097 R9).
String formatTokenWords(int n) {
  if (n < 1000) return '$n';
  if (n < 999500) return '${(n / 1000).round()} mil';
  final m = n / 1e6;
  return m >= 9.95 ? '${m.round()} mi' : '${_comma(m, 1)} mi';
}

/// The total of a spec with turns in both providers (SPEC-097 R9):
/// "US$ 4,20 (Claude Code) + 1,2 mi tokens (Codex)"; only tokens:
/// "custo indisponível · 1,2 mi tokens (Codex)".
String formatMixedCost(double usd, int unpricedTokens, {bool priced = true}) {
  final tokens = '${formatTokenWords(unpricedTokens)} tokens (Codex)';
  return priced
      ? '${formatUsd(usd)} (Claude Code) + $tokens'
      : '$costUnavailable · $tokens';
}
