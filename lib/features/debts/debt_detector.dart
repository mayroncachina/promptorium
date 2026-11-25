import 'debt_table.dart';

/// What an interview answer asks for (SPEC-112 R7, P3).
enum DebtIntent {
  /// "bota em débito", "deixa simulado por hora".
  debt,

  /// "decide depois", "fica pendente".
  decision;

  DebtKind get kind => this == debt ? DebtKind.debt : DebtKind.decision;
}

/// [text] without accents, in lower case and with the spaces collapsed.
String foldDebtText(String text) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final r in text.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    final i = from.indexOf(c);
    b.write(i < 0 ? c : to[i]);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Expressions of a debt said in free text (P3), over [foldDebtText]. The
/// explicit ones ("débito") win over the decision; the loose ones ("por
/// hora") lose to it.
final _explicitDebt = [RegExp(r'\bdebitos?\b'), RegExp(r'\bdivida tecnica\b')];
final _decision = [
  RegExp(r'\bdecid(e|o|ir|imos|em|a)? (isso )?(mais )?depois\b'),
  RegExp(r'\bdecide la na frente\b'),
  RegExp(r'\ba decidir\b'),
  RegExp(r'\b(fica|deixa|ficar|deixar) (como )?pendente\b'),
  RegExp(r'\bdecisao pendente\b'),
  RegExp(r'\bpara decidir depois\b'),
];
final _looseDebt = [
  RegExp(r'\b(deixa|deixar|fica|ficar|mantem|manter) (isso )?simulad[oa]s?\b'),
  RegExp(r'\bsimulad[oa]s? por (h)?ora\b'),
  RegExp(r'\bprovisori[oa]s?( por (h)?ora)?\b'),
  RegExp(r'\bpor (h)?ora\b'),
  RegExp(r'\b(fica|deixa) (isso )?pra(ra)? depois\b'),
  RegExp(r'\bfica para depois\b'),
  RegExp(r'\bgambiarra\b'),
];

/// Whether an answer to an interview question asks for a debt or a
/// decision (R7, P3): a local list of expressions, no model. Null when it
/// asks for neither. Applied only to the answers of the interview.
DebtIntent? detectDebtIntent(String answer) {
  final t = foldDebtText(answer);
  if (t.isEmpty) return null;
  if (_explicitDebt.any((r) => r.hasMatch(t))) return DebtIntent.debt;
  if (_decision.any((r) => r.hasMatch(t))) return DebtIntent.decision;
  if (_looseDebt.any((r) => r.hasMatch(t))) return DebtIntent.debt;
  return null;
}

/// One answer of a numbered reply ("5 - deixa simulado por hora…"):
/// [number] is the question it answers (1-based), null when the reply is
/// not numbered.
typedef NumberedAnswer = ({int? number, String text});

/// The answers of a reply to several questions: lines that start with
/// `5 -`, `5.`, `5)` or `5:` open the answer of the question 5; the lines
/// after it belong to it. A reply without numbers is one answer.
List<NumberedAnswer> splitNumberedAnswers(String reply) {
  final out = <NumberedAnswer>[];
  final head = RegExp(
    r'^\s*(?:[-*]\s*)?(?:[QPqp])?(\d{1,2})\s*[-–—.):]\s*(.*)$',
  );
  int? number;
  final buf = <String>[];
  void flush() {
    final t = buf.join(' ').trim();
    if (t.isNotEmpty || number != null) out.add((number: number, text: t));
    buf.clear();
  }

  for (final line in reply.split('\n')) {
    final m = head.firstMatch(line);
    if (m != null) {
      flush();
      number = int.parse(m.group(1)!);
      buf.add(m.group(2)!.trim());
    } else if (line.trim().isNotEmpty) {
      buf.add(line.trim());
    }
  }
  flush();
  return [
    for (final a in out)
      if (a.text.isNotEmpty) a,
  ];
}

final _payVerb = RegExp(
  r'\b(paguei|pago|paga|pagos|pagas|pagamos|quitei|quitado|quitada|quitados|'
  r'resolvi|resolvido|resolvidos|resolvemos|corrigi|corrigido)\b',
);
final _negation = RegExp(r'\b(nao|nem|sem|ainda nao|nunca)\b');
final _dtCode = RegExp(r'\bdt[- ]?0*(\d{1,4})\b');

/// The DT codes [text] says were paid ("paguei o DT-05", "DT-03 e DT-07
/// resolvidos"), in order and without repeats (R17). A clause with a
/// negation ("não paguei o DT-05") does not count.
List<String> paidDebtCodes(String text) {
  final out = <String>[];
  for (final clause in text.split(RegExp(r'[.;!?\n]')).map(foldDebtText)) {
    if (!_payVerb.hasMatch(clause)) continue;
    final verb = _payVerb.firstMatch(clause)!;
    final before = clause.substring(0, verb.start);
    final tail = before.length > 12
        ? before.substring(before.length - 12)
        : before;
    if (_negation.hasMatch(tail)) continue;
    for (final m in _dtCode.allMatches(clause)) {
      final code = DebtKind.debt.code(int.parse(m.group(1)!));
      if (!out.contains(code)) out.add(code);
    }
  }
  return out;
}
