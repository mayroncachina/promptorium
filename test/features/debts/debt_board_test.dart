import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/data/repos/debt_links_repo.dart';
import 'package:promptorium/features/debts/debt_board.dart';
import 'package:promptorium/features/debts/debt_files.dart';
import 'package:promptorium/features/debts/debt_item.dart';
import 'package:promptorium/features/debts/debt_table.dart';
import 'package:promptorium/features/project/project_config.dart';

final debtsText = File('test/fixtures/debts/debitos.md').readAsStringSync();
final decisionsText = File('test/fixtures/debts/decisoes.md')
    .readAsStringSync();

DebtSnapshot snapshotOf({String? debts, String? decisions}) => DebtSnapshot(
  repoRoot: '/r',
  config: const DebtsConfig(),
  debts: DebtDocument.parse(debts ?? debtsText, DebtKind.debt),
  decisions: DebtDocument.parse(decisions ?? decisionsText, DebtKind.decision),
  debtsExists: true,
  decisionsExists: true,
);

Spec spec(
  int id,
  String code, {
  String? wt,
  SpecStage stage = SpecStage.running,
}) => Spec(
  issueCommentPending: false,
  hasPlan: false,
  inTray: false,
  kind: SpecKind.spec,
  id: id,
  workspaceId: 1,
  code: code,
  title: code,
  status: SpecStatus.approved,
  path: 'specs/$code.md',
  stage: stage,
  requirements: const [],
  dependsOn: const [],
  autoAdvance: true,
  reviewRounds: 0,
  gateResends: 0,
  rejectedHunks: 0,
  worktreePath: wt,
);

DebtLink link(
  int id, {
  String? code,
  int? originSpecId,
  String? originQuestion,
  int? paymentSpecId,
  String? suggestionState,
  String? originDecision,
  String? piggybackState,
}) => DebtLink(
  id: id,
  repoRoot: '/r',
  kind: 'debito',
  code: code,
  originSpecId: originSpecId,
  originQuestion: originQuestion,
  paymentSpecId: paymentSpecId,
  suggestionState: suggestionState,
  originDecision: originDecision,
  piggybackState: piggybackState,
  createdAt: DateTime(2026),
);

/// SPEC-112 R4, R13, R14, R16: what the screen shows.
void main() {
  test('opens and paid, origins from the links and from the text', () {
    final b = DebtBoard.build(
      snapshot: snapshotOf(),
      links: [link(1, code: 'DT-03', originSpecId: 7, originQuestion: 'Q5')],
      specs: [spec(7, 'SPEC-031')],
    );
    expect(b.openDebts.map((d) => d.item.code), [
      'DT-01',
      'DT-03',
      'DT-04',
      'DT-05',
      'DT-06',
      'DT-07',
      'DT-08',
    ]);
    expect(b.paidDebts.single.item.code, 'DT-02');
    expect(b.openCount, 7);
    String origin(String c) =>
        b.debts.firstWhere((d) => d.item.code == c).origin;
    expect(origin('DT-03'), 'spec 31 · Q5');
    expect(origin('DT-05'), 'spec 29 · P3');
    expect(origin('DT-01'), 'spec 25 · Q5');
    expect(origin('DT-07'), 'spec 31');
    expect(origin('DT-06'), 'spec 29 · P8');
    expect(b.pending, isEmpty);
    expect(b.decided, hasLength(8));
  });

  test('a debt paid by an open spec is "em pagamento"; by a done one, '
      'back to open', () {
    final open = DebtBoard.build(
      snapshot: snapshotOf(),
      links: [link(1, code: 'DT-05', paymentSpecId: 9)],
      specs: [spec(9, 'VIBE-003')],
    );
    final r = open.debts.firstWhere((d) => d.item.code == 'DT-05');
    expect(r.state, DebtRowState.paying);
    expect(specLabel(r.paymentSpec!), 'VIBE-003');
    expect(open.openCount, 7, reason: 'still open until the merge');
    final done = DebtBoard.build(
      snapshot: snapshotOf(),
      links: [link(1, code: 'DT-05', paymentSpecId: 9)],
      specs: [spec(9, 'VIBE-003', stage: SpecStage.done)],
    );
    expect(
      done.debts.firstWhere((d) => d.item.code == 'DT-05').state,
      DebtRowState.open,
    );
  });

  test('a row only in the worktree of an open spec is "na spec N"; a link '
      'in no file is an orphan and recreates nothing (R4)', () {
    final wt = DebtTable.parse(
      debtsText,
      DebtKind.debt,
    ).append(['DT-09', '2026-11-24', '**Upload fixo**: x.', '`a.py`', 'y']);
    final b = DebtBoard.build(
      snapshot: snapshotOf(),
      links: [
        link(1, code: 'DT-09', originSpecId: 33, originQuestion: 'Q4'),
        link(2, code: 'DT-12'),
        link(3, suggestionState: DebtSuggestionState.pending),
      ],
      specs: [spec(33, 'SPEC-033', wt: '/wt')],
      worktreeDebts: {33: DebtDocument.parse(wt, DebtKind.debt)},
    );
    final dt9 = b.debts.firstWhere((d) => d.item.code == 'DT-09');
    expect(dt9.state, DebtRowState.inSpec);
    expect(specLabel(dt9.inSpec!), 'spec 33');
    expect(b.openCount, 7, reason: 'the chip counts the main file only');
    expect(b.openDebts, hasLength(8));
    expect(b.orphans.map((l) => l.code), ['DT-12']);
    expect(b.suggestions.map((l) => l.id), [3]);
    expect(b.debts.where((d) => d.item.code == 'DT-12'), isEmpty);
  });

  test('a file edited outside drops the row: the link becomes orphan', () {
    final edited = debtsText
        .split('\n')
        .where((l) => !l.startsWith('| DT-08'))
        .join('\n');
    final b = DebtBoard.build(
      snapshot: snapshotOf(debts: edited),
      links: [link(1, code: 'DT-08', originSpecId: 32)],
      specs: [spec(32, 'SPEC-032')],
    );
    expect(b.orphans.map((l) => l.code), ['DT-08']);
    expect(b.openCount, 6);
  });

  test('debtCitesPath: by path, or by name when "Onde" has only the name '
      '(R16)', () {
    final d = DebtDocument.parse(debtsText, DebtKind.debt).debts;
    DebtItem by(String c) => d.firstWhere((x) => x.code == c);
    expect(
      debtCitesPath(by('DT-05'), 'frontend/src/views/PagarView.vue'),
      isTrue,
    );
    expect(debtCitesPath(by('DT-05'), 'frontend/src/views/Pagar.vue'), isFalse);
    expect(
      debtCitesPath(by('DT-01'), 'frontend/src/lib/minhasInscricoes.js'),
      isTrue,
    );
    expect(debtCitesPath(by('DT-01'), 'outro/minhasInscricoes.js'), isFalse);
    // A function without a file never matches.
    expect(debtCitesPath(by('DT-06'), 'pagamentos_servico'), isFalse);
    expect(debtCitesPath(by('DT-03'), 'coreografias_servico.py'), isFalse);
  });

  test('originFromText', () {
    expect(originFromText('x (spec 29, P3).'), 'spec 29 · P3');
    expect(originFromText('Decidido na spec 25 (Q5).'), 'spec 25 · Q5');
    expect(originFromText('([spec 31](specs/31.md), DP-01)'), 'spec 31');
    expect(originFromText('gerado pela DP-04'), 'DP-04');
    expect(originFromText('nada'), isNull);
  });
}
