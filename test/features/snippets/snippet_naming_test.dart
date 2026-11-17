import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/snippets/snippet_naming.dart';

void main() {
  group('suggestSnippetName (R3)', () {
    test('the first line comment, without the marker', () {
      expect(
        suggestSnippetName(
          '-- Pedidos atrasados há mais de 3 dias, por cliente\nSELECT 1;',
          'sql',
          'Pedidos atrasados no DBeaver',
        ),
        'Pedidos atrasados há mais de 3 dias, por cliente',
      );
      expect(
        suggestSnippetName(
          '#!/bin/sh\n# Subir o banco local\ndocker up',
          'bash',
          null,
        ),
        'Subir o banco local',
      );
      expect(
        suggestSnippetName('\n// Seed de cupons\nvoid main() {}', 'dart', 't'),
        'Seed de cupons',
      );
      expect(
        suggestSnippetName('/* Índice parcial */\nCREATE INDEX', 'sql', 't'),
        'Índice parcial',
      );
    });

    test('# is not a comment in C', () {
      expect(
        suggestSnippetName('#include <stdio.h>\nint main() {}', 'c', 'Olá'),
        'Olá (c)',
      );
    });

    test('without a comment: the title, plus the language it lacks', () {
      expect(
        suggestSnippetName('SELECT 1;', 'sql', 'Pedidos atrasados no DBeaver'),
        'Pedidos atrasados no DBeaver (sql)',
      );
      expect(
        suggestSnippetName('SELECT 1;', 'sql', 'Query SQL dos pedidos'),
        'Query SQL dos pedidos',
      );
      expect(suggestSnippetName('ls', null, 'Listar'), 'Listar');
      expect(suggestSnippetName('ls', 'bash', null), 'Snippet (bash)');
      expect(suggestSnippetName('ls', null, '  '), 'Snippet');
    });

    test('cut at 60 characters on a whole word', () {
      final long =
          '-- Lista os pedidos atrasados de cada cliente ativo com o valor '
          'total e o pior atraso';
      final name = suggestSnippetName(long, 'sql', null);
      expect(name.length, lessThanOrEqualTo(60));
      expect(
        name,
        'Lista os pedidos atrasados de cada cliente ativo com o valor',
      );
      final title = suggestSnippetName(
        'x',
        'sql',
        'Relatório semanal de pedidos atrasados para o time de suporte',
      );
      expect(title.length, lessThanOrEqualTo(60));
      expect(title, endsWith(' (sql)'));
      expect(
        title,
        'Relatório semanal de pedidos atrasados para o time de (sql)',
      );
    });
  });

  test('meta and lines', () {
    expect(snippetMeta('sql', 'a\nb\nc'), 'sql · 3 linhas');
    expect(snippetMeta(null, 'a'), 'texto · 1 linha');
    expect(
      shortName('Pedidos atrasados há mais de 3 dias'),
      'Pedidos atrasados há mai…',
    );
  });
}
