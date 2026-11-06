import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_cli.dart';
import 'package:promptorium/core/claude/run_extensions.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/specs/spec_action.dart';
import 'package:promptorium/features/specs/spec_design.dart';
import 'package:promptorium/features/specs/spec_file.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../helpers/test_db.dart';
import '../sessions/session_test_utils.dart';

void main() {
  test('"Planejar" asks for "O que já existe" and at least one file per '
      'step (SPEC-017 R3)', () {
    expect(designPrompt, contains('### O que já existe'));
    expect(designPrompt, contains('ao menos um arquivo'));
    final etapa =
        ((designSchema['properties'] as Map)['etapas'] as Map)['items'] as Map;
    final arquivos = (etapa['properties'] as Map)['arquivos'] as Map;
    expect(arquivos['minItems'], 1);
  });

  group('SPEC-037 R3, R4: the plan section', () {
    const plain =
        '---\nid: SPEC-001\nstatus: aprovada\n---\n\n# A\n\n'
        '## Requisitos\n\n- R1 · x\n\n## Critérios de aceite\n\n- [ ] ok\n';
    final answer = {
      'design': '### R1\n\nFaça em lib/a.dart.',
      'etapas': [
        {
          'requisito': 'R1',
          'arquivos': ['lib/a.dart'],
          'verificar': 'make t',
        },
      ],
    };
    int count(String text, String heading) =>
        RegExp('^$heading\$', multiLine: true).allMatches(text).length;

    test('the prompt asks for the Plano section', () {
      expect(designPrompt, contains('seção Plano'));
      expect(designPrompt, isNot(contains('seção Design')));
    });

    test('Planejar writes ## Plano after the requirements and ## Etapas '
        'after it', () {
      final out = applyDesignAnswer(plain, answer);
      expect(count(out, '## Plano'), 1);
      expect(out.indexOf('## Requisitos'), lessThan(out.indexOf('## Plano')));
      expect(out.indexOf('## Plano'), lessThan(out.indexOf('## Etapas')));
      expect(out.indexOf('## Etapas'), lessThan(out.indexOf('## Critérios')));
      expect(out, isNot(contains('## Design')));
    });

    test('the new spec template brings ## Plano with the hint', () {
      final t = newSpecMarkdown(code: 'SPEC-001', title: 'A');
      expect(count(t, '## Plano'), 1);
      expect(t, contains('Use "Planejar"'));
      expect(t, isNot(contains('## Design')));
      expect(SpecDocument.parse(t).design, isNull);
    });

    test('a spec with only ## Design is read as having a plan', () {
      final legacy = plain.replaceFirst(
        '## Critérios',
        '## Design\n\nAntigo.\n\n## Critérios',
      );
      expect(SpecDocument.parse(legacy).design, 'Antigo.');
    });

    test('## Plano wins when the spec has both, and an empty one does not '
        'hide ## Design', () {
      final both = plain.replaceFirst(
        '## Critérios',
        '## Design\n\nAntigo.\n\n## Plano\n\nNovo.\n\n## Critérios',
      );
      expect(SpecDocument.parse(both).design, 'Novo.');
      final hint = plain.replaceFirst(
        '## Critérios',
        '## Plano\n\n<!-- dica -->\n\n## Design\n\nAntigo.\n\n## Critérios',
      );
      expect(SpecDocument.parse(hint).design, 'Antigo.');
    });

    test('## Plano de testes is not the plan', () {
      final other = plain.replaceFirst(
        '## Critérios',
        '## Plano de testes\n\nManual.\n\n## Critérios',
      );
      expect(SpecDocument.parse(other).design, isNull);
      final out = applyDesignAnswer(other, answer);
      expect(out, contains('## Plano de testes\n\nManual.'));
      expect(SpecDocument.parse(out).design, startsWith('### R1'));
    });

    test('Planejar on a spec with ## Design leaves only ## Plano, in the '
        'same place', () {
      final legacy = plain.replaceFirst(
        '## Critérios',
        '## Design\n\nAntigo.\n\n## Etapas\n\n- R1 → lib/old.dart\n\n'
            '## Critérios',
      );
      final out = applyDesignAnswer(legacy, answer);
      expect(out, isNot(contains('## Design')));
      expect(out, isNot(contains('Antigo.')));
      expect(count(out, '## Plano'), 1);
      expect(count(out, '## Etapas'), 1);
      expect(SpecDocument.parse(out).stepPlans['R1']!.files, ['lib/a.dart']);
    });

    test('Planejar on a spec with both sections removes ## Design', () {
      final both = plain.replaceFirst(
        '## Critérios',
        '## Plano\n\nVelho.\n\n## Design\n\nAntigo.\n\n## Critérios',
      );
      final out = applyDesignAnswer(both, answer);
      expect(out, isNot(contains('## Design')));
      expect(out, isNot(contains('Antigo.')));
      expect(out, isNot(contains('Velho.')));
      expect(count(out, '## Plano'), 1);
    });

    test('`design: dispensado` keeps working', () {
      final waived = SpecDocument.parse(plain).withMeta(designWaived: true);
      expect(SpecDocument.parse(waived).designWaived, isTrue);
    });

    test('withPrototype goes after ## Plano and after an old ## Design', () {
      final plan = plain.replaceFirst(
        '## Critérios',
        '## Plano\n\nNovo.\n\n## Critérios',
      );
      for (final (text, name) in [
        (plan, '## Plano'),
        (plan.replaceFirst('## Plano', '## Design'), '## Design'),
      ]) {
        final out = SpecDocument.parse(text).withPrototype('R1', 'x/R1.html');
        expect(out.indexOf(name), lessThan(out.indexOf('## Protótipo')));
        expect(out.indexOf('## Protótipo'), lessThan(out.indexOf('## Crit')));
      }
    });
  });

  test('SPEC-025 R5: completing "cancelled" stops the planner run and '
      'generate throws SpecActionCancelled', () async {
    final tmp = Directory.systemTemp.createTempSync('promptorium-design-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final cli = FakeCli();
    final c = ProviderContainer(
      overrides: [
        databaseOverride(memoryDatabase()),
        claudeProcessStarterProvider.overrideWithValue(cli.start),
        runSettingsDirProvider.overrideWithValue('${tmp.path}/run'),
      ],
    );
    addTearDown(c.dispose);
    await c.read(appSettingsProvider.notifier).load();
    final ws = Workspace(
      id: 1,
      path: tmp.path,
      name: 'ws',
      createdAt: DateTime(2026),
    );
    final cancel = Completer<void>();
    final run = c
        .read(specDesignerProvider)
        .generate(ws, '# Spec\n', cancelled: cancel.future);
    final rejected = expectLater(run, throwsA(isA<SpecActionCancelled>()));
    await until(() async => cli.processes.isNotEmpty);
    expect(cli.last.signals, isEmpty);
    cancel.complete();
    await rejected;
    // The agent was stopped, not left running.
    expect(cli.last.signals, isNotEmpty);
  });
}
