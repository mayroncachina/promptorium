import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/debts/debt_detector.dart';

/// SPEC-112 R7, P3 (the expressions) and R17 (the "paguei o DT-05").
void main() {
  group('detectDebtIntent (R7, P3)', () {
    test('debt expressions, with or without accent and case', () {
      for (final s in [
        'bota em débito, por ora só loga o nome do arquivo',
        'BOTA EM DEBITO',
        'deixa simulado por hora e cria um débito técnico',
        'Deixa simulado',
        'provisório por hora',
        'por hora fica fixo em 20 MB',
        'cria uma dívida técnica',
      ]) {
        expect(detectDebtIntent(s), DebtIntent.debt, reason: s);
      }
    });

    test('decision expressions', () {
      for (final s in [
        'decide depois',
        'Decidimos depois, com o cliente',
        'isso fica pendente',
        'Deixa pendente por enquanto',
      ]) {
        expect(detectDebtIntent(s), DebtIntent.decision, reason: s);
      }
    });

    test('"débito" wins over "decide depois"', () {
      expect(
        detectDebtIntent('decide depois, mas bota em débito'),
        DebtIntent.debt,
      );
    });

    test('a plain answer asks for nothing', () {
      for (final s in ['', 'recusar no envio', '20 MB por arquivo', 'S3']) {
        expect(detectDebtIntent(s), isNull, reason: s);
      }
    });
  });

  test('splitNumberedAnswers reads "5 - …" per question', () {
    final a = splitNumberedAnswers(
      '4 - 20 MB\n5 - deixa simulado por hora e cria um débito técnico\n'
      'e avisa o suporte\n6) decide depois',
    );
    expect(a.map((x) => x.number), [4, 5, 6]);
    expect(
      a[1].text,
      'deixa simulado por hora e cria um débito técnico '
      'e avisa o suporte',
    );
    expect(splitNumberedAnswers('bota em débito').single.number, isNull);
  });

  group('paidDebtCodes (R17)', () {
    test('reads the codes said to be paid', () {
      expect(paidDebtCodes('Pronto. Paguei o DT-05 de passagem.'), ['DT-05']);
      expect(paidDebtCodes('DT-3 e DT-07 resolvidos; DT-07 também quitado'), [
        'DT-03',
        'DT-07',
      ]);
      expect(paidDebtCodes('paguei o dt 12'), ['DT-12']);
    });

    test('a negation or a mere mention does not count', () {
      expect(paidDebtCodes('Não paguei o DT-05.'), isEmpty);
      expect(paidDebtCodes('O DT-05 continua aberto.'), isEmpty);
    });
  });
}
