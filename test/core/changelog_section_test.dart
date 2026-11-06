import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/update/changelog_section.dart';

const _changelog = '''
# Changelog

Todas as mudanças relevantes do Promptorium.

## [não lançado]

### Funcionalidades

- Ainda sem versão (aaaaaaa)

## [0.8.0] - 2026-11-03

### Funcionalidades

- **specs:** Cabeçalho da spec com ações por estado (SPEC-024) (058194b)
- Sem escopo nesta linha (2480123)
- **board:** [**incompatível**] Quebra o formato antigo (20c0dfa)

### Correções

- **shell:** Corrige o foco do Sobre (b5750b3)

### Documentação

- **specs:** Não interessa a quem usa (d353a10)

### Testes

- Também não (7e0c31d)

### Build e CI

- Nem isto (c8989f3)

### Manutenção

- Nem aquilo (2a8b56a)

## [0.7.0] - 2026-10-20

### Correções

- Só da versão anterior (553b99e)

## [0.6.0] - 2026-10-01

### Documentação

- **specs:** Só documentação (34f1fc2)
''';

void main() {
  group('R5 · section', () {
    test('picks the section of the installed version', () {
      final s = latestChanges(_changelog, version: '0.7.0');
      expect(s.version, '0.7.0');
      expect(s.date, DateTime(2026, 10, 20));
      expect(s.groups.single.items, ['Só da versão anterior']);
    });

    test('accepts a version written with a leading v', () {
      expect(latestChanges(_changelog, version: 'v0.7.0').version, '0.7.0');
    });

    test('without that section, picks the first version section, not the '
        'unreleased one', () {
      expect(latestChanges(_changelog, version: '9.9.9').version, '0.8.0');
      expect(latestChanges(_changelog).version, '0.8.0');
    });

    test('a heading without a date has a null date', () {
      final s = latestChanges('## [1.0.0]\n\n### Correções\n\n- Algo (abcdef0)');
      expect(s.version, '1.0.0');
      expect(s.date, isNull);
    });

    test('reads the real CHANGELOG.md', () {
      final md = File('CHANGELOG.md').readAsStringSync();
      final s = latestChanges(md, version: '0.0.0');
      expect(s.version, isNotNull);
      expect(s.groups, isNotEmpty);
      expect(
        RegExp(r'\([0-9a-f]{7}\)$', multiLine: true).hasMatch(s.markdown),
        isFalse,
      );
    });
  });

  group('R6 · filter', () {
    test('only Funcionalidades and Correções, in the order of the file', () {
      final s = latestChanges(_changelog, version: '0.8.0');
      expect(s.groups.map((g) => g.title), ['Funcionalidades', 'Correções']);
      expect(s.markdown, isNot(contains('Não interessa')));
      expect(s.markdown, isNot(contains('Nem isto')));
    });

    test('removes the hash at the end and the scope at the start', () {
      final s = latestChanges(_changelog, version: '0.8.0');
      expect(s.groups.first.items, [
        'Cabeçalho da spec com ações por estado (SPEC-024)',
        'Sem escopo nesta linha',
        '[**incompatível**] Quebra o formato antigo',
      ]);
    });

    test('a version with neither group is empty', () {
      final s = latestChanges(_changelog, version: '0.6.0');
      expect(s.version, '0.6.0');
      expect(s.isEmpty, isTrue);
    });

    test('an empty text is empty', () {
      expect(latestChanges('').isEmpty, isTrue);
    });
  });

  group('release notes', () {
    test('git-cliff notes go through the same filter, without the link the '
        'release workflow appends', () {
      const notes = '''
## [0.9.0] - 2026-11-05

### Funcionalidades

- **board:** Decidir a etapa pelo balão (1234567)

### Testes

- Fora (7654321)

**Changelog completo**: https://github.com/o/p/compare/v0.8.0...v0.9.0
''';
      final s = latestChanges(notes, version: '0.9.0');
      expect(s.rawText, isNull);
      expect(s.groups.single.items, ['Decidir a etapa pelo balão']);
      expect(s.markdown, isNot(contains('Changelog completo')));
    });

    test('notes with groups but no version heading are filtered too', () {
      final s = latestChanges(
        '### Correções\n\n- **ui:** Conserta X (abcdef0)\n',
        version: '0.9.0',
      );
      expect(s.groups.single.items, ['Conserta X']);
    });

    test('D3 · notes outside the format are shown whole', () {
      const notes = 'Corrige o bug X\n\n## O que mudou\n\n- Uma linha';
      final s = latestChanges(notes, version: '0.9.0');
      expect(s.groups, isEmpty);
      expect(s.isEmpty, isFalse);
      expect(s.markdown, notes);
    });
  });
}
