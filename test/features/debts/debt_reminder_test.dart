import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/repos/debt_links_repo.dart';
import 'package:promptorium/features/debts/debt_item.dart';
import 'package:promptorium/features/debts/debt_reminder.dart';
import 'package:promptorium/features/debts/debt_table.dart';
import 'package:promptorium/features/debts/piggyback.dart';
import 'package:promptorium/features/debts/piggyback_detector.dart';
import 'package:promptorium/features/project/project_config.dart';

import '../../helpers/test_db.dart';
import 'debt_board_test.dart' show debtsText;

List<DebtItem> get openDebts => [
  for (final d in DebtDocument.parse(debtsText, DebtKind.debt).debts)
    if (!d.paid) d,
];

String row(int n, String where) =>
    '| ${DebtKind.debt.code(n)} | 2026-11-2$n | **Débito $n** | `$where` | — |';

/// SPEC-112 R17, P6: the reminder in the step prompt and "pago de carona?".
void main() {
  group('citedFiles', () {
    test('paths and names with extension; no URLs nor versions', () {
      expect(
        citedFiles(
          'Mexe em `frontend/src/views/PagarView.vue` e em arquivos.py. '
          'Veja https://exemplo.com/a.html, versão 0.21.0, e.g. nada. '
          'De novo PagarView.vue.',
        ),
        ['frontend/src/views/PagarView.vue', 'arquivos.py', 'PagarView.vue'],
      );
    });
  });

  group('debtReminderLine', () {
    test('each debt with ID, title and where, oldest first', () {
      final line = debtReminderLine(
        debtsForFiles(openDebts, ['frontend/src/views/PagarView.vue']),
        debtsPath: 'DEBITO_TECNICO.md',
      );
      expect(
        line,
        'Débitos abertos nestes arquivos: DT-05 (Pagamento simulado · '
        '`PagarView.vue`). Pague se for barato e diga quais pagou.',
      );
    });

    test('up to 5, the rest as "e mais N (veja <arquivo>)"', () {
      final text = [
        '| ID | Desde | O quê | Onde | Para resolver |',
        '|---|---|---|---|---|',
        for (var n = 7; n >= 1; n--) row(n, 'a.py'),
      ].join('\n');
      final debts = DebtDocument.parse(text, DebtKind.debt).debts;
      final line = debtReminderLine(debts, debtsPath: 'docs/debitos.md')!;
      expect(line, startsWith('Débitos abertos nestes arquivos: DT-01 ('));
      expect(line, contains('DT-05 (Débito 5 · `a.py`) e mais 2 '));
      expect(line, contains('(veja docs/debitos.md).'));
      expect(line, isNot(contains('DT-06')));
      expect(debtReminderLine(const [], debtsPath: 'x'), isNull);
    });

    test('only the debts of the files the spec cites; a function without '
        'file does not count; off with lembrar_na_execucao: false', () {
      const spec =
          'Plano: mudar `backend/app/arquivos.py`, '
          'NovaInscricaoView.vue e coreografias_servico._ajustar_valor.';
      final on = debtReminderFor(
        specText: spec,
        open: openDebts,
        config: const DebtsConfig(),
      )!;
      expect(on, contains('DT-08 (Editar coreografia sem nenhum participante'));
      // DT-02 is paid; DT-03 cites only a function.
      expect(on, isNot(contains('DT-02')));
      expect(on, isNot(contains('DT-03')));
      expect(
        debtReminderFor(
          specText: spec,
          open: openDebts,
          config: const DebtsConfig(remindOnRun: false),
        ),
        isNull,
      );
      expect(
        debtReminderFor(
          specText: 'Nada de arquivos.',
          open: openDebts,
          config: const DebtsConfig(),
        ),
        isNull,
      );
    });
  });

  group('piggybackPaidCodes', () {
    test('"paguei o DT-05", "DT-05 pago", "resolvi o DT-03 e o DT-5"', () {
      expect(piggybackPaidCodes('Paguei o DT-05 de carona.'), {'DT-05'});
      expect(piggybackPaidCodes('DT-05 pago na etapa.'), {'DT-05'});
      expect(piggybackPaidCodes('Resolvi o DT-03 e o DT-5 também.'), {
        'DT-03',
        'DT-05',
      });
      expect(
        piggybackPaidCodes('O DT-07 foi resolvido.\nETAPA CONCLUÍDA: R1'),
        {'DT-07'},
      );
    });

    test('negated, a mere mention or the reminder echoed do not count', () {
      expect(piggybackPaidCodes('Não paguei o DT-05.'), isEmpty);
      expect(piggybackPaidCodes('O DT-05 não foi pago.'), isEmpty);
      expect(piggybackPaidCodes('O DT-05 continua aberto.'), isEmpty);
      expect(
        piggybackPaidCodes(
          'Débitos abertos nestes arquivos: DT-03 (x). Pague se for barato '
          'e diga quais pagou.',
        ),
        isEmpty,
      );
      expect(piggybackPaidCodes('Paguei o DT-03, mas o DT-05 fica.'), {
        'DT-03',
      });
      expect(piggybackPaidCodes(null), isEmpty);
    });
  });

  group('markPiggybacks', () {
    test('marks "a_confirmar" only on open codes; confirmed stays; '
        'Confirmar / Recusar record the state', () async {
      final db = memoryDatabase();
      addTearDown(db.close);
      final repo = DebtLinksRepo(db);
      await db.customStatement(
        "INSERT INTO workspaces(path,name) VALUES('/r','r')",
      );
      for (var i = 1; i <= 36; i++) {
        await db.customStatement(
          "INSERT INTO specs(workspace_id,code,title,path) "
          "VALUES(1,'SPEC-0$i','S$i','specs/$i.md')",
        );
      }
      final marked = await markPiggybacks(
        repo,
        repoRoot: '/r',
        specId: 36,
        answer: 'Paguei o DT-05 e o DT-02. Resolvi o DT-99.',
        open: {'DT-05', 'DT-03'},
      );
      expect(marked, ['DT-05']);
      final l = (await repo.byCode('/r', 'DT-05'))!;
      expect(l.piggybackSpecId, 36);
      expect(l.piggybackState, DebtPiggybackState.toConfirm);
      expect(await repo.byCode('/r', 'DT-02'), isNull);

      await settlePiggyback(repo, l.id, confirmed: true);
      expect(
        (await repo.byId(l.id))!.piggybackState,
        DebtPiggybackState.confirmed,
      );
      // Said again: the confirmation stays.
      expect(
        await markPiggybacks(
          repo,
          repoRoot: '/r',
          specId: 36,
          answer: 'DT-05 pago.',
          open: {'DT-05'},
        ),
        isEmpty,
      );
      await settlePiggyback(repo, l.id, confirmed: false);
      expect(
        (await repo.byId(l.id))!.piggybackState,
        DebtPiggybackState.refused,
      );
    });
  });
}
