import '../project/project_config.dart';
import 'debt_board.dart' show debtCitesPath;
import 'debt_item.dart';

/// How many debts the reminder lists (SPEC-112 P6).
const debtReminderMax = 5;

/// File paths and file names cited in [text] (a spec): tokens with an
/// extension (`lib/a/b.dart`, `PagarView.vue`), in order, without repeats.
/// URLs and version numbers do not count.
List<String> citedFiles(String text) {
  final clean = text.replaceAll(RegExp(r'https?://\S+'), ' ');
  final re = RegExp(
    r'(?<![\w/.\-@])((?:[\w.\-]+/)*[\w\-]+(?:\.[\w\-]+)*\.[A-Za-z][A-Za-z0-9]{1,5})(?![\w/\-])',
  );
  final out = <String>[];
  for (final m in re.allMatches(clean)) {
    final p = m.group(1)!;
    if (!out.contains(p)) out.add(p);
  }
  return out;
}

/// The open debts of [open] whose "Onde" cites one of [files] (R16's
/// rule: by path, or by file name when "Onde" has only the name), oldest
/// first.
List<DebtItem> debtsForFiles(Iterable<DebtItem> open, List<String> files) {
  final out = [
    for (final d in open)
      if (!d.paid && files.any((f) => debtCitesPath(d, f))) d,
  ];
  out.sort((a, b) => a.number.compareTo(b.number));
  return out;
}

String _title(DebtItem d) =>
    d.title.trim().replaceAll(RegExp(r'[\s:;,.—-]+$'), '');

String _oneLine(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// The reminder line of a step prompt (R17, P6): up to [max] debts, the
/// oldest first, each with ID, title and "Onde"; more → "e mais N (veja
/// [debtsPath])". Null when [debts] is empty.
String? debtReminderLine(
  List<DebtItem> debts, {
  required String debtsPath,
  int max = debtReminderMax,
}) {
  if (debts.isEmpty) return null;
  final sorted = [...debts]..sort((a, b) => a.number.compareTo(b.number));
  final shown = sorted.take(max).map((d) {
    final where = _oneLine(d.where);
    final title = _oneLine(_title(d));
    final inside = [
      if (title.isNotEmpty) title,
      if (where.isNotEmpty) where,
    ].join(' · ');
    return inside.isEmpty ? d.code : '${d.code} ($inside)';
  }).toList();
  final rest = sorted.length - shown.length;
  final list = rest > 0
      ? '${shown.join(', ')} e mais $rest (veja $debtsPath)'
      : shown.join(', ');
  return 'Débitos abertos nestes arquivos: $list. '
      'Pague se for barato e diga quais pagou.';
}

/// The reminder of the step of a spec (R17): the open debts of [open] in
/// the files [specText] cites. Null when `debitos.lembrar_na_execucao` is
/// off or no debt matches.
String? debtReminderFor({
  required String specText,
  required Iterable<DebtItem> open,
  required DebtsConfig config,
  int max = debtReminderMax,
}) {
  if (!config.remindOnRun) return null;
  final files = citedFiles(specText);
  if (files.isEmpty) return null;
  return debtReminderLine(
    debtsForFiles(open, files),
    debtsPath: config.debtsPath,
    max: max,
  );
}
