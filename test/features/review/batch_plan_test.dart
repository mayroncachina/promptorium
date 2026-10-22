import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/features/review/criteria_batch.dart';
import 'package:promptorium/features/specs/spec_file.dart';

CriterionState crit(
  String text, {
  String? verify,
  List<String> reqs = const ['R1'],
  bool inFile = false,
  String? by,
  bool checked = true,
}) => (
  criterion: SpecCriterion(
    text: text,
    requirements: reqs,
    verify: verify,
    checkedInFile: inFile,
  ),
  mark: by == null
      ? null
      : SpecCriteriaData(
          specId: 1,
          criterion: text,
          checked: checked,
          checkedBy: checked ? by : null,
        ),
);

void main() {
  test('batchPlan: eligible (unchecked, no verificar:), awaiting '
      '(unchecked, with verificar:) and the marks of the user', () {
    final plan = batchPlan([
      crit('a'),
      crit('b', verify: 'true'),
      crit('c', verify: 'true', reqs: const []),
      crit('d', by: 'humano'),
      crit('e', by: 'gate', verify: 'true'),
      crit('f', by: 'revisor'),
      crit('g', by: 'humano', checked: false),
    ]);
    expect(plan.eligible, ['a', 'g']);
    expect(plan.awaiting, ['b', 'c']);
    expect(plan.mine, ['d']);
  });

  test('a `- [x]` of the file with no mark is in no group', () {
    final plan = batchPlan([crit('x', inFile: true)]);
    expect(plan.eligible, isEmpty);
    expect(plan.awaiting, isEmpty);
    expect(plan.mine, isEmpty);
    // Unchecked in the Review (mark wins over the file): eligible again.
    expect(
      batchPlan([crit('x', inFile: true, by: 'humano', checked: false)])
          .eligible,
      ['x'],
    );
  });

  group('table of modes', () {
    test('1 · eligible ones: mark (even with marks of the user)', () {
      final c = batchControl([
        crit('a'),
        crit('b'),
        crit('c', verify: 'true'),
        crit('d', by: 'humano'),
      ]);
      expect(c.action, BatchAction.mark);
      expect(c.label, 'Marcar todos (2 elegíveis · 1 aguarda a verificação)');
      expect(c.value, isNull);
      expect(batchControl([crit('a')]).label, 'Marcar todos (1 elegível)');
      expect(batchControl([crit('a')]).value, isFalse);
    });

    test('2 · no eligible, marks of the user: unmark mine', () {
      final some = batchControl([
        crit('a', by: 'humano'),
        crit('b', verify: 'true'),
        crit('c', verify: 'true'),
      ]);
      expect(some.action, BatchAction.unmarkMine);
      expect(some.label, 'Desmarcar os meus (1 · 2 aguardam a verificação)');
      expect(some.value, isNull);
      final all = batchControl([
        crit('a', by: 'humano'),
        crit('b', by: 'gate'),
      ]);
      expect(all.action, BatchAction.unmarkMine);
      expect(all.label, 'Todos marcados · desmarcar os meus (1)');
      expect(all.value, isTrue);
    });

    test('3 · only awaiting ones: disabled', () {
      final c = batchControl([
        crit('a', by: 'gate'),
        crit('b', verify: 'true'),
      ]);
      expect(c.action, BatchAction.none);
      expect(c.label, 'Nada a marcar em lote · 1 aguarda a verificação');
    });

    test('4 · everything checked by others: disabled', () {
      final c = batchControl([
        crit('a', by: 'gate'),
        crit('b', by: 'revisor'),
        crit('c', inFile: true),
      ]);
      expect(c.action, BatchAction.none);
      expect(c.label, 'Todos marcados · nada meu para desmarcar');
      expect(c.value, isTrue);
    });
  });
}
