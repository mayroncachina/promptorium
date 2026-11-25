import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/debts/debt_item.dart';
import 'package:promptorium/features/debts/debt_merge.dart';
import 'package:promptorium/features/debts/debt_payment.dart';
import 'package:promptorium/features/debts/debt_table.dart';

import 'debt_board_test.dart' show debtsText;

List<DebtItem> itemsOf(String text, List<String> codes) {
  final doc = DebtDocument.parse(text, DebtKind.debt);
  return [for (final c in codes) doc.debts.firstWhere((d) => d.code == c)];
}

const _head =
    '# Débitos\n\n| ID | Desde | O quê | Onde | Para resolver |\n'
    '|---|---|---|---|---|\n';

String row(int n, {bool paid = false}) {
  final code = 'DT-${n.toString().padLeft(2, '0')}';
  return paid
      ? '| ~~$code~~ | 2026-11-24 | ~~Item $n~~ — **resolvido** pela spec 9. '
            '| `a$n.py` | — |'
      : '| $code | 2026-11-24 | **Item $n**: motivo. | `a$n.py` | fazer |';
}

/// SPEC-112 R15 (pagar e riscar) and P4 (conflito no fim da tabela).
void main() {
  group('R15 · sugestão e textos', () {
    test('2 débitos sugerem VIBE, 3 sugerem spec', () {
      expect(suggestedPayMode(1), DebtPayMode.vibe);
      expect(suggestedPayMode(2), DebtPayMode.vibe);
      expect(suggestedPayMode(3), DebtPayMode.spec);
      expect(suggestedPayMode(7), DebtPayMode.spec);
    });

    test('o prompt da VIBE traz cada débito com onde e o que fazer', () {
      final p = vibePaymentPrompt(
        itemsOf(debtsText, ['DT-05', 'DT-06']),
        file: 'DEBITO_TECNICO.md',
      );
      final lines = p.split('\n');
      expect(
        lines.first,
        'Pague os débitos DT-05 e DT-06 de DEBITO_TECNICO.md.',
      );
      expect(
        lines[1],
        'DT-05 · Pagamento simulado (PagarView.vue): ligar o gateway '
        '(homologação) junto com o DT-03.',
      );
      expect(lines[2], startsWith('DT-06 · Responsável não cancela'));
      expect(lines[2], contains('(pagamentos_servico)'));
      expect(lines.last, 'No fim, diga quais pagou e o que ficou de fora.');
    });

    test('a spec "Pagar débitos" tem os itens no Objetivo e um requisito por '
        'débito', () {
      final items = itemsOf(debtsText, ['DT-03', 'DT-05', 'DT-06']);
      expect(paymentSpecTitle(items), 'Pagar débitos: DT-03, DT-05, DT-06');
      final md = paymentSpecMarkdown(
        code: 'SPEC-118',
        items: items,
        file: 'DEBITO_TECNICO.md',
      );
      expect(md, contains('id: SPEC-118'));
      expect(md, contains('# Pagar débitos: DT-03, DT-05, DT-06'));
      final objective = md.substring(
        md.indexOf('## Objetivo'),
        md.indexOf('## Requisitos'),
      );
      expect(objective, contains('DT-03, DT-05 e DT-06'));
      expect(objective, contains('- DT-05 · **Pagamento simulado**'));
      expect(md, contains('- R1 · Pagar o DT-03 (PIX/boleto antigo'));
      expect(md, contains('- R2 · Pagar o DT-05 (Pagamento simulado)'));
      expect(md, contains('- R3 · Pagar o DT-06'));
      expect(md, isNot(contains('- R4')));
    });
  });

  group('R15 · riscar no merge', () {
    test('risca as linhas com "resolvido pela spec N" e "—" em Para '
        'resolver; o resto do arquivo fica igual', () {
      final r = strikeDebtRows(
        debtsText,
        debtsText,
        ['DT-05', 'DT-06'],
        label: 'spec 118',
        link: 'docs/specs/SPEC-118-pagar.md',
      );
      expect(r.struck, ['DT-05', 'DT-06']);
      expect(r.warnings, isEmpty);
      final doc = DebtDocument.parse(r.text, DebtKind.debt);
      final dt05 = doc.debts.firstWhere((d) => d.code == 'DT-05');
      expect(dt05.paid, isTrue);
      expect(dt05.resolvedBy, 'spec 118');
      expect(dt05.toResolve, isEmpty);
      expect(dt05.raw.trimRight(), endsWith('| — |'));
      expect(
        dt05.raw,
        contains(
          '~~Pagamento simulado~~ — **resolvido** pela '
          '[spec 118](docs/specs/SPEC-118-pagar.md)',
        ),
      );
      final before = debtsText.split('\n'), after = r.text.split('\n');
      expect(after.length, before.length);
      for (var i = 0; i < before.length; i++) {
        if (before[i].startsWith('| DT-05') ||
            before[i].startsWith('| DT-06')) {
          continue;
        }
        expect(after[i], before[i]);
      }
    });

    test('a linha que só está na branch principal entra riscada no arquivo '
        'da worktree', () {
      final main = '$_head${row(1)}\n${row(2)}\n${row(3)}\n';
      final wt = '$_head${row(1)}\n${row(2)}\n';
      final r = strikeDebtRows(wt, main, ['DT-03'], label: 'spec 4');
      expect(r.struck, ['DT-03']);
      final doc = DebtDocument.parse(r.text, DebtKind.debt);
      expect(doc.debts.map((d) => d.code), ['DT-01', 'DT-02', 'DT-03']);
      expect(doc.debts.last.paid, isTrue);
    });

    test('a linha que mudou desde a branch é deixada de lado com aviso', () {
      final main =
          '$_head${row(1)}\n${row(2).replaceFirst('fazer', 'outro')}\n';
      final wt = '$_head${row(1)}\n${row(2)}\n';
      final r = strikeDebtRows(wt, main, ['DT-01', 'DT-02'], label: 'spec 4');
      expect(r.struck, ['DT-01']);
      expect(r.warnings.single, contains('DT-02 mudou'));
      expect(r.text, contains(row(2)));
    });

    test('mensagem do commit', () {
      expect(
        paidCommitMessage(['DT-03', 'DT-05'], 'spec 118'),
        'docs: DT-03, DT-05 pagos pela spec 118',
      );
      expect(
        paidCommitMessage(['DT-03'], 'VIBE-007'),
        'docs: DT-03 pago pela VIBE-007',
      );
      expect(
        specLinkFrom('DEBITO_TECNICO.md', 'docs/specs/S.md'),
        'docs/specs/S.md',
      );
      expect(specLinkFrom('docs/debitos.md', 'docs/specs/S.md'), 'specs/S.md');
    });
  });

  group('P4 · conflito no fim da tabela', () {
    test('duas specs acrescentando linhas: junta os dois lados em ordem de '
        'ID', () {
      final text =
          '$_head${row(1)}\n'
          '<<<<<<< HEAD\n${row(3)}\n${row(5)}\n'
          '=======\n${row(2)}\n${row(4)}\n'
          '>>>>>>> spec/2\n'
          '\nTexto depois.\n';
      final out = resolveDebtTableConflict(text, DebtKind.debt);
      expect(
        out,
        '$_head${row(1)}\n${row(2)}\n${row(3)}\n${row(4)}\n${row(5)}\n'
        '\nTexto depois.\n',
      );
    });

    test('com a base (diff3): a última linha riscada de um lado e linhas '
        'novas do outro', () {
      final text =
          '$_head${row(1)}\n'
          '<<<<<<< HEAD\n${row(2)}\n${row(3)}\n'
          '||||||| base\n${row(2)}\n'
          '=======\n${row(2, paid: true)}\n${row(4)}\n'
          '>>>>>>> spec/2\n';
      final out = resolveDebtTableConflict(text, DebtKind.debt);
      expect(
        out,
        '$_head${row(1)}\n${row(2, paid: true)}\n${row(3)}\n${row(4)}\n',
      );
    });

    test('a mesma linha dos dois lados, uma riscada: fica a riscada', () {
      final text =
          '$_head${row(1)}\n'
          '<<<<<<< HEAD\n${row(2)}\n'
          '=======\n${row(2, paid: true)}\n'
          '>>>>>>> spec/2\n';
      expect(
        resolveDebtTableConflict(text, DebtKind.debt),
        '$_head${row(1)}\n${row(2, paid: true)}\n',
      );
    });

    test('CRLF é mantido', () {
      final text =
          '$_head${row(1)}\n<<<<<<< HEAD\n${row(3)}\n=======\n${row(2)}\n'
                  '>>>>>>> x\n'
              .replaceAll('\n', '\r\n');
      expect(
        resolveDebtTableConflict(text, DebtKind.debt),
        '$_head${row(1)}\n${row(2)}\n${row(3)}\n'.replaceAll('\n', '\r\n'),
      );
    });

    test('qualquer outro conflito segue para a resolução normal', () {
      // No meio da tabela.
      expect(
        resolveDebtTableConflict(
          '$_head<<<<<<< HEAD\n${row(1)}\n=======\n${row(9)}\n>>>>>>> x\n'
          '${row(2)}\n',
          DebtKind.debt,
        ),
        isNull,
      );
      // Fora da tabela.
      expect(
        resolveDebtTableConflict(
          '<<<<<<< HEAD\n# A\n=======\n# B\n>>>>>>> x\n$_head${row(1)}\n',
          DebtKind.debt,
        ),
        isNull,
      );
      // A mesma linha mudada dos dois lados, nenhuma riscada.
      expect(
        resolveDebtTableConflict(
          '$_head<<<<<<< HEAD\n${row(1)}\n=======\n'
          '${row(1).replaceFirst('fazer', 'outro')}\n>>>>>>> x\n',
          DebtKind.debt,
        ),
        isNull,
      );
      // Um lado apagou uma linha da base.
      expect(
        resolveDebtTableConflict(
          '$_head<<<<<<< HEAD\n${row(1)}\n${row(2)}\n||||||| b\n${row(1)}\n'
          '=======\n${row(3)}\n>>>>>>> x\n',
          DebtKind.debt,
        ),
        isNull,
      );
      // Sem conflito.
      expect(
        resolveDebtTableConflict('$_head${row(1)}\n', DebtKind.debt),
        isNull,
      );
    });
  });
}
