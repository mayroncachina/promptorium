import '../../data/db/app_database.dart';
import '../specs/spec_file.dart';

/// A criterion of the spec with its mark (who checked it).
typedef CriterionState = ({SpecCriterion criterion, SpecCriteriaData? mark});

bool criterionChecked(CriterionState c) =>
    c.mark?.checked ?? c.criterion.checkedInFile;

/// Unchecked criterion with a `verificar:`: left to the gate (SPEC-014 R3).
bool awaitsVerification(CriterionState c) =>
    !criterionChecked(c) && c.criterion.verify != null;

/// Criteria split for "Marcar todos" (SPEC-014): [eligible] (unchecked,
/// no `verificar:`) is what the batch checks; [awaiting] (unchecked, with
/// `verificar:`) stays out; [mine] are the user's own marks. A `- [x]` of
/// the file with no mark is in none of them.
typedef BatchPlan = ({
  List<String> eligible,
  List<String> awaiting,
  List<String> mine,
});

BatchPlan batchPlan(List<CriterionState> all) => (
  eligible: [
    for (final c in all)
      if (!criterionChecked(c) && c.criterion.verify == null) c.criterion.text,
  ],
  awaiting: [
    for (final c in all)
      if (awaitsVerification(c)) c.criterion.text,
  ],
  mine: [
    for (final c in all)
      if (c.mark != null && c.mark!.checked && c.mark!.checkedBy == 'humano')
        c.criterion.text,
  ],
);

enum BatchAction { mark, unmarkMine, none }

/// State of the "Marcar todos" control (the table of modes of SPEC-014).
typedef BatchControl = ({
  BatchAction action,
  String label,

  /// true: every criterion checked; false: none; null: mixed.
  bool? value,
  BatchPlan plan,
});

BatchControl batchControl(List<CriterionState> all) {
  final plan = batchPlan(all);
  final e = plan.eligible.length, b = plan.awaiting.length;
  final m = plan.mine.length;
  final done = all.where(criterionChecked).length;
  final value = done == all.length ? true : (done == 0 ? false : null);
  final awaiting = '$b ${b == 1 ? 'aguarda' : 'aguardam'} a verificação';
  final (action, label) = e > 0
      ? (
          BatchAction.mark,
          'Marcar todos ($e ${e == 1 ? 'elegível' : 'elegíveis'}'
              '${b > 0 ? ' · $awaiting' : ''})',
        )
      : m > 0
      ? (
          BatchAction.unmarkMine,
          b == 0
              ? 'Todos marcados · desmarcar os meus ($m)'
              : 'Desmarcar os meus ($m · $awaiting)',
        )
      : b > 0
      ? (BatchAction.none, 'Nada a marcar em lote · $awaiting')
      : (BatchAction.none, 'Todos marcados · nada meu para desmarcar');
  return (action: action, label: label, value: value, plan: plan);
}
