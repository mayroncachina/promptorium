import 'package:drift/drift.dart' show Value;

import '../../data/db/app_database.dart';
import '../../data/repos/debt_links_repo.dart';
import 'debt_table.dart';
import 'piggyback_detector.dart';

/// "pago de carona?" (SPEC-112 R17): the debts the answer of a step of
/// [specId] says it paid, among the [open] codes of the file, get
/// `piggybackSpecId = specId` and `piggybackState = a_confirmar`. A mark the
/// person already confirmed or refused for this spec stays. The debt never
/// closes here: only the merge of a confirmed mark strikes the row.
/// Returns the codes marked now.
Future<List<String>> markPiggybacks(
  DebtLinksRepo repo, {
  required String repoRoot,
  required int specId,
  required String? answer,
  required Set<String> open,
}) async {
  final marked = <String>[];
  for (final code in piggybackPaidCodes(answer)) {
    if (!open.contains(code)) continue;
    final found = await repo.byCode(repoRoot, code);
    if (found != null &&
        found.piggybackSpecId == specId &&
        found.piggybackState != null) {
      continue;
    }
    final id =
        found?.id ?? await repo.ensure(repoRoot, DebtKind.debt.dbName, code);
    await repo.update(
      id,
      DebtLinksCompanion(
        piggybackSpecId: Value(specId),
        piggybackState: const Value(DebtPiggybackState.toConfirm),
      ),
    );
    marked.add(code);
  }
  return marked;
}

/// "Confirmar pago" / "Não foi pago" of a mark (R17): [confirmed] true
/// records `confirmado` (the merge strikes the row), false `recusado`.
Future<void> settlePiggyback(
  DebtLinksRepo repo,
  int linkId, {
  required bool confirmed,
}) => repo.update(
  linkId,
  DebtLinksCompanion(
    piggybackState: Value(
      confirmed ? DebtPiggybackState.confirmed : DebtPiggybackState.refused,
    ),
  ),
);
