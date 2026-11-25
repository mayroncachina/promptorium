import 'debt_table.dart';

const _verbs =
    r'paguei|pagamos|pago|paga|pagos|pagas|quitei|quitamos|quitado|quitada|'
    r'quitados|resolvi|resolvemos|resolvido|resolvida|resolvidos|resolvidas';

final _code = RegExp(r'\bDT-(\d{1,4})\b', caseSensitive: false);
final _verb = RegExp(
  '(?<![\\wÀ-ÿ])(?:$_verbs)(?![\\wÀ-ÿ])',
  caseSensitive: false,
);
final _negated = RegExp(
  '(?<![\\wÀ-ÿ])(?:não|nao|nem|sem)\\s+(?:\\S+\\s+){0,2}?(?:$_verbs)'
  '(?![\\wÀ-ÿ])',
  caseSensitive: false,
);

/// Codes of the debts a step answer says it paid (SPEC-112 R17): "paguei o
/// DT-05", "DT-05 pago", "resolvi o DT-03 e o DT-05". Each clause (split at
/// `.`, `;`, `!`, `?`, line breaks and "mas") with a code and a verb of
/// paying counts, unless the verb is negated ("não paguei o DT-05"). The
/// result only marks "pago de carona?": the person confirms.
Set<String> piggybackPaidCodes(String? text) {
  if (text == null || text.isEmpty) return const {};
  final out = <String>{};
  final clauses = text.split(
    RegExp(r'[.;!?\n]+|,?\s+(?:mas|porém|porem)\s+', caseSensitive: false),
  );
  for (final c in clauses) {
    if (!_verb.hasMatch(c) || _negated.hasMatch(c)) continue;
    for (final m in _code.allMatches(c)) {
      out.add(DebtKind.debt.code(int.parse(m.group(1)!)));
    }
  }
  return out;
}
