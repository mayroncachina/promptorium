import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/review/review_logic.dart';
import 'package:promptorium/features/review/review_stack.dart';

import '../board/board_rules_test.dart' show spec;
import 'review_logic_test.dart' show session;

ReviewItem item(
  String id, {
  String? code,
  int? specId,
  String? base = 'main',
  DateTime? at,
}) {
  final branch = 'pr/$id';
  return ReviewItem(
    session: session(
      id: id,
      startedAt: at,
    ).copyWith(branch: branch, baseBranch: Value(base), specId: Value(specId)),
    spec: code == null ? null : spec(specId!, code),
  );
}

List<List<String>> ids(List<ReviewStack> s) => [
  for (final g in s) [for (final i in g.items) i.session.id],
];

void main() {
  group('orderQueue (R1, R2)', () {
    test('a stack of three goes from the base to the top, before the loose '
        'specs; tasks go last', () {
      final items = [
        item('t1', at: DateTime(2026)),
        item('c', code: 'SPEC-033', specId: 3, base: 'pr/b'),
        item('x', code: 'SPEC-030', specId: 9),
        item('b', code: 'SPEC-031', specId: 2, base: 'pr/a'),
        item('a', code: 'SPEC-029', specId: 1),
      ];
      expect(ids(orderQueue(items)), [
        ['a', 'b', 'c'],
        ['x'],
        ['t1'],
      ]);
    });

    test('two stacks keep their own order; waves decide between loose '
        'specs, then the code', () {
      final items = [
        item('d2', code: 'SPEC-041', specId: 6, base: 'pr/d1'),
        item('d1', code: 'SPEC-040', specId: 5),
        item('b', code: 'SPEC-031', specId: 2, base: 'pr/a'),
        item('a', code: 'SPEC-029', specId: 1),
        item('z', code: 'SPEC-001', specId: 7),
        item('y', code: 'SPEC-050', specId: 8),
      ];
      expect(ids(orderQueue(items, waves: {7: 2, 8: 0})), [
        ['a', 'b'],
        ['d1', 'd2'],
        ['y'],
        ['z'],
      ]);
    });

    test('a cycle (should not happen) is broken by the spec code', () {
      final items = [
        item('b', code: 'SPEC-002', specId: 2, base: 'pr/a'),
        item('a', code: 'SPEC-001', specId: 1, base: 'pr/b'),
      ];
      expect(ids(orderQueue(items)), [
        ['a', 'b'],
      ]);
    });
  });

  test('nextAfterMerge (R5): the child, else the next, else the previous', () {
    final items = [
      item('b', code: 'SPEC-031', specId: 2, base: 'pr/a'),
      item('a', code: 'SPEC-029', specId: 1),
      item('x', code: 'SPEC-030', specId: 9),
    ];
    expect(nextAfterMerge(items, 'a')?.session.id, 'b');
    expect(nextAfterMerge(items, 'b')?.session.id, 'x');
    expect(nextAfterMerge(items, 'x')?.session.id, 'b');
    expect(nextAfterMerge([items[2]], 'x'), isNull);
  });

  group('state and primary action (R3, R8)', () {
    test('precedence of the states', () {
      expect(
        mergeStatusOf(reviewing: true, motherCode: 'SPEC-029').state,
        MergeState.revisando,
      );
      expect(
        mergeStatusOf(motherCode: 'SPEC-029', conflictFiles: ['a']).text,
        'Espera SPEC-029',
      );
      expect(
        mergeStatusOf(conflictFiles: ['lib/a.dart'], pending: true).text,
        'Conflito em lib/a.dart',
      );
      expect(
        mergeStatusOf(conflictFiles: ['a', 'b', 'c']).text,
        'Conflito em a +2',
      );
      expect(
        mergeStatusOf(restackConflict: true).text,
        'Conflito ao refazer a base',
      );
      expect(
        mergeStatusOf(conflictFiles: [], pending: true).text,
        'Pendências',
      );
      expect(mergeStatusOf().text, 'Verificando…');
      expect(
        mergeStatusOf(rebaseStep: '1 de 2', reviewing: true).text,
        'Rebase em andamento · 1 de 2',
      );
      expect(mergeStatusOf(conflictFiles: []).text, 'Pronto para merge');
    });

    test('one primary action per state', () {
      PrimaryAction of(MergeState s, {bool pr = false}) =>
          primaryActionOf(MergeStatus(s), hasPr: pr);
      expect(of(MergeState.pronto), PrimaryAction.fazerMerge);
      expect(of(MergeState.pronto, pr: true), PrimaryAction.mergearPr);
      expect(of(MergeState.verificando), PrimaryAction.fazerMerge);
      expect(of(MergeState.esperaMae), PrimaryAction.irParaMae);
      expect(of(MergeState.conflito), PrimaryAction.resolverConflito);
      expect(of(MergeState.conflitoBase), PrimaryAction.resolverConflito);
      expect(of(MergeState.baseDesatualizada), PrimaryAction.refazerBase);
      expect(of(MergeState.pendencias), PrimaryAction.pedirAjustes);
      expect(of(MergeState.revisando), PrimaryAction.nenhuma);
      expect(of(MergeState.rebaseManual), PrimaryAction.abrirEditor);
      const wait = MergeStatus(MergeState.esperaMae, detail: 'SPEC-029');
      expect(
        primaryLabel(primaryActionOf(wait, hasPr: false), wait),
        'Ir para SPEC-029',
      );
    });

    test('accessible label of a card (R14)', () {
      expect(
        queueSemanticLabel(
          title: 'SPEC-031',
          position: 2,
          stackSize: 2,
          status: const MergeStatus(MergeState.esperaMae, detail: 'SPEC-029'),
        ),
        'SPEC-031, 2 de 2 na pilha, espera SPEC-029',
      );
      expect(
        queueSemanticLabel(
          title: 'SPEC-030',
          position: 1,
          stackSize: 1,
          status: const MergeStatus(MergeState.pronto),
        ),
        'SPEC-030, pronto para merge',
      );
    });
  });
}
