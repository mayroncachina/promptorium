import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/debts/debt_item.dart';
import 'package:promptorium/features/debts/debt_table.dart';

/// SPEC-112 R1, R5: the parser and the writer of the Markdown tables.
void main() {
  final debts = File('test/fixtures/debts/debitos.md').readAsStringSync();
  final decisions = File('test/fixtures/debts/decisoes.md').readAsStringSync();

  /// Every line of [a] and [b] equal except the ones in [changed].
  void sameOutside(String a, String b, Set<int> changed) {
    final la = a.split('\n'), lb = b.split('\n');
    expect(la.length, lb.length);
    for (var i = 0; i < la.length; i++) {
      if (changed.contains(i)) continue;
      expect(lb[i], la[i], reason: 'line $i');
    }
  }

  group('parse', () {
    test('reads DT-01 to DT-08 of the example, with DT-02 paid', () {
      final d = DebtDocument.parse(debts, DebtKind.debt);
      expect(d.debts.map((e) => e.code), [
        for (var i = 1; i <= 8; i++) 'DT-0$i',
      ]);
      expect(d.unrecognized, isEmpty);
      final dt2 = d.debts[1];
      expect(dt2.paid, isTrue);
      expect(dt2.title, 'Arquivos da coreografia numa pasta local');
      expect(dt2.resolvedBy, 'spec 28');
      expect(dt2.resolvedByLink, 'specs/28-armazenamento-s3.md');
      expect(dt2.toResolve, isEmpty);
      final dt5 = d.debts[4];
      expect(dt5.paid, isFalse);
      expect(dt5.title, 'Pagamento simulado');
      expect(dt5.reason, startsWith('PIX, boleto e cartão'));
      expect(dt5.reason, endsWith('(spec 29, P3).'));
      expect(dt5.where, '`PagarView.vue`');
      expect(dt5.whereRefs, ['PagarView.vue']);
      expect(dt5.toResolve, startsWith('ligar o gateway'));
      expect(d.debts[3].whereRefs, [
        'coreografias_servico.preco_modalidade',
        'eventos_servico.preco_atual',
      ]);
      expect(d.debts[5].whereRefs, ['pagamentos_servico']);
    });

    test('reads DP-01 to DP-08, all decided, and the origin spec', () {
      final d = DebtDocument.parse(decisions, DebtKind.decision);
      expect(d.decisions.map((e) => e.code), [
        for (var i = 1; i <= 8; i++) 'DP-0$i',
      ]);
      expect(d.decisions.every((e) => e.decided), isTrue);
      final dp1 = d.decisions.first;
      expect(
        dp1.title,
        'Quem cadastra as funções de equipe técnica do evento?',
      );
      expect(dp1.originSpecNumber, 31);
      expect(dp1.originQuestion, 'Q1');
      expect(dp1.decision, startsWith('**Decidido (2026-11-24):**'));
    });

    test('the header matches without accents and in any case', () {
      const t =
          '| id | DESDE | O que | Onde | Para Resolver |\n'
          '|:---|---|---|---|---:|\n'
          '| DT-100 | x | **a** | b | c |\n';
      final d = DebtDocument.parse(t, DebtKind.debt);
      expect(d.debts.single.code, 'DT-100');
      expect(d.debts.single.number, 100);
    });

    test('a pipe escaped or inside backticks does not split the cell', () {
      const t =
          '| ID | Desde | O quê | Onde | Para resolver |\n'
          '|---|---|---|---|---|\n'
          r'| DT-01 | x | **a \| b** | `x | y` | — |'
          '\n';
      final d = DebtDocument.parse(t, DebtKind.debt).debts.single;
      expect(d.title, 'a | b');
      expect(d.where, '`x | y`');
    });

    test('odd lines inside the table are unrecognized and kept raw', () {
      final odd = debts.replaceFirst(
        '| DT-03 |',
        '| nota solta sem ID |\n| DT-9 | curto |\n| DT-03 |',
      );
      final d = DebtDocument.parse(odd, DebtKind.debt);
      expect(d.debts, hasLength(8));
      expect(d.unrecognized.map((u) => u.text), [
        '| nota solta sem ID |',
        '| DT-9 | curto |',
      ]);
      // Writing another row never touches them.
      final t = d.table;
      final out = t.replace('DT-05', d.debts[4].cells);
      expect(out, odd);
      final appended = t.append(['DT-09', 'x', '**y**', '—', '—']);
      expect(appended, contains('| nota solta sem ID |\n| DT-9 | curto |'));
    });

    test('no table = no items; text without a separator is not a table', () {
      expect(DebtTable.parse('', DebtKind.debt).hasTable, isFalse);
      expect(
        DebtTable.parse(
          '| ID | Desde | O quê | Onde | Para resolver |\ntexto\n',
          DebtKind.debt,
        ).hasTable,
        isFalse,
      );
    });
  });

  group('write', () {
    test('rewriting every row as read changes no byte', () {
      for (final (text, kind) in [
        (debts, DebtKind.debt),
        (decisions, DebtKind.decision),
      ]) {
        final d = DebtDocument.parse(text, kind);
        var out = text;
        for (final r in d.table.rows) {
          final t = DebtTable.parse(out, kind);
          out = t.replace(kind.code(r.number), r.cells, expectedRaw: r.raw);
        }
        // The fixture uses `| a | b |` with single spaces: same bytes.
        expect(out, text);
      }
    });

    test('parse(write(parse(x))) == parse(x), and only the row changes', () {
      final d = DebtDocument.parse(debts, DebtKind.debt);
      final dt5 = d.debts[4];
      final out = d.table.replace(
        'DT-05',
        dt5.struckCells(label: 'spec 118', link: 'docs/specs/SPEC-118.md'),
        expectedRaw: dt5.raw,
      );
      final again = DebtDocument.parse(out, DebtKind.debt);
      expect(again.debts[4].paid, isTrue);
      expect(again.debts[4].title, 'Pagamento simulado');
      expect(again.debts[4].resolvedBy, 'spec 118');
      expect(again.debts[4].toResolve, isEmpty);
      expect(again.debts[4].where, dt5.where);
      final rewritten = again.table.replace('DT-05', again.debts[4].cells);
      expect(DebtDocument.parse(rewritten, DebtKind.debt).debts, again.debts);
      sameOutside(debts, out, {d.table.rows[4].line});
    });

    test('the struck row follows the format of R15', () {
      final d = DebtDocument.parse(debts, DebtKind.debt).debts[4];
      final cells = d.struckCells(
        label: 'spec 118',
        link: 'docs/specs/SPEC-118-x.md',
      );
      expect(cells.first, '~~DT-05~~');
      expect(
        cells[2],
        startsWith(
          '~~Pagamento simulado~~ — **resolvido** pela '
          '[spec 118](docs/specs/SPEC-118-x.md) (PIX, boleto',
        ),
      );
      expect(cells[2], endsWith('P3)).'));
      expect(cells.last, '—');
    });

    test('append goes after the last row, with the same line break', () {
      final d = DebtDocument.parse(debts, DebtKind.debt);
      final cells = DebtItem.newCells(
        code: 'DT-09',
        since: '2026-11-24',
        title: 'Lotes depois',
        reason: 'ficam para outra spec',
        origin: 'spec 33, Q5',
        where: 'backend/app/lotes.py',
        toResolve: 'fazer os lotes',
      );
      final out = d.table.append(cells);
      final lines = out.split('\n');
      final at = d.table.endLine!;
      expect(
        lines[at],
        '| DT-09 | 2026-11-24 | **Lotes depois**: ficam para outra spec '
        '(spec 33, Q5). | `backend/app/lotes.py` | fazer os lotes |',
      );
      lines.removeAt(at);
      expect(lines.join('\n'), debts);
      final again = DebtDocument.parse(out, DebtKind.debt);
      expect(again.debts.last.code, 'DT-09');
      expect(again.debts.last.title, 'Lotes depois');
    });

    test('CRLF files keep CRLF everywhere', () {
      final crlf = debts.replaceAll('\n', '\r\n');
      final d = DebtDocument.parse(crlf, DebtKind.debt);
      expect(d.debts, hasLength(8));
      expect(d.debts.first.what.contains('\r'), isFalse);
      final out = d.table.append(['DT-09', 'x', '**y**', '—', '—']);
      expect(out.replaceAll('\r\n', ''), isNot(contains('\n')));
      expect(out, contains('| DT-09 | x | **y** | — | — |\r\n'));
      final changed = d.table.replace('DT-01', d.debts.first.cells);
      expect(changed, crlf);
    });

    test('a table at the very end without a final break', () {
      final t = debts.trimRight();
      final d = DebtTable.parse(t, DebtKind.debt);
      final out = d.append(['DT-09', 'x', '**y**', '—', '—']);
      expect(out, '$t\n| DT-09 | x | **y** | — | — |');
    });

    test('a file without the table gets the header first', () {
      final out = DebtTable.parse(
        '# Notas\n\ntexto',
        DebtKind.decision,
      ).append(['DP-01', 'x', 'y', '**z?**', 'r', '']);
      expect(
        out,
        '# Notas\n\ntexto\n\n'
        '| ID | Desde | Origem | Pergunta | Recomendação | Decisão |\n'
        '|---|---|---|---|---|---|\n'
        '| DP-01 | x | y | **z?** | r |  |\n',
      );
      expect(
        DebtDocument.parse(out, DebtKind.decision).decisions.single.decided,
        isFalse,
      );
    });

    test('a changed row makes the write give up (DebtRowChanged)', () {
      final d = DebtDocument.parse(debts, DebtKind.debt);
      final read = d.debts[4].raw;
      final other = debts.replaceFirst('PagarView.vue', 'PagarView2.vue');
      final t = DebtTable.parse(other, DebtKind.debt);
      expect(
        () => t.replace('DT-05', d.debts[4].cells, expectedRaw: read),
        throwsA(isA<DebtRowChanged>()),
      );
      expect(
        () => t.replace('DT-77', d.debts[4].cells),
        throwsA(isA<DebtRowMissing>()),
      );
    });

    test('cells: pipes escaped, line breaks flattened, paths in backticks', () {
      expect(DebtTable.escapeCell('a | b\nc'), r'a \| b c');
      expect(DebtTable.escapeCell(r'a \| b'), r'a \| b');
      expect(DebtItem.formatWhere('src/a.dart'), '`src/a.dart`');
      expect(DebtItem.formatWhere('PagarView.vue'), '`PagarView.vue`');
      expect(DebtItem.formatWhere('pagamentos_servico'), 'pagamentos_servico');
      expect(DebtItem.formatWhere(''), '—');
    });

    test('a decision decided and with the generated debt', () {
      final d = DebtDocument.parse(
        '| ID | Desde | Origem | Pergunta | Recomendação | Decisão |\n'
        '|---|---|---|---|---|---|\n'
        '| DP-09 | 2026-11-24 | spec 33, Q7 | **Lotes?** | Depois. |  |\n',
        DebtKind.decision,
      ).decisions.single;
      expect(d.decided, isFalse);
      final cells = d.decidedCells('Depois mesmo.', date: '2026-11-25');
      expect(cells.last, '**Decidido (2026-11-25):** Depois mesmo.');
      final decided = DecisionItem(
        code: d.code,
        number: d.number,
        since: d.since,
        origin: d.origin,
        question: d.question,
        title: d.title,
        recommendation: d.recommendation,
        decision: cells.last,
      );
      expect(
        decided.withGenerated('DT-10').last,
        '**Decidido (2026-11-25):** Depois mesmo. Gerou o DT-10.',
      );
    });
  });

  test('a motive ending with a full stop does not double it before the '
      'origin', () {
    final cells = DebtItem.newCells(
      code: 'DT-12',
      since: '2026-11-25',
      title: 'Validação no cliente',
      reason: 'o servidor não confere o tamanho.',
      origin: 'revisão da spec 33',
    );
    expect(
      cells[2],
      '**Validação no cliente**: o servidor não confere o tamanho '
      '(revisão da spec 33).',
    );
  });

  test('DebtKind codes have two digits or more', () {
    expect(DebtKind.debt.code(9), 'DT-09');
    expect(DebtKind.decision.code(123), 'DP-123');
    expect(DebtKind.debt.numberOf('~~DT-02~~'), 2);
    expect(DebtKind.debt.numberOf('DT-2'), isNull);
    expect(DebtKind.debt.numberOf('DP-02'), isNull);
  });

  group('remove (R8, Desfazer)', () {
    final cells = DebtItem.newCells(
      code: 'DT-09',
      since: '2026-11-25',
      title: 'Upload lido inteiro na memória',
    );

    test('append then remove gives the same bytes back', () {
      for (final text in [
        debts,
        debts.replaceAll('\n', '\r\n'),
        debts.trimRight(),
      ]) {
        final added = DebtTable.parse(text, DebtKind.debt).append(cells);
        final row = DebtTable.parse(added, DebtKind.debt).rowOf('DT-09')!;
        final back = DebtTable.parse(
          added,
          DebtKind.debt,
        ).remove('DT-09', expectedRaw: row.raw);
        expect(back, text);
      }
    });

    test('a changed row is kept and the remove gives up', () {
      final added = DebtTable.parse(debts, DebtKind.debt).append(cells);
      expect(
        () => DebtTable.parse(
          added,
          DebtKind.debt,
        ).remove('DT-09', expectedRaw: '| DT-09 | outra coisa |'),
        throwsA(isA<DebtRowChanged>()),
      );
      expect(
        () => DebtTable.parse(debts, DebtKind.debt).remove('DT-09'),
        throwsA(isA<DebtRowMissing>()),
      );
    });
  });
}
