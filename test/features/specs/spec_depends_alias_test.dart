import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/specs/spec_file.dart';
import 'package:promptorium/features/specs/specs_screen.dart'
    show dependsOnAliasNotice;

import 'spec_action_lock_test.dart';
import 'specs_screen_test.dart' show settleIo;

String spec(String head) =>
    '---\nid: SPEC-002\nstatus: aprovada\ndesign: dispensado\n$head---\n\n'
    '# Pedidos\n\n## Requisitos\n\n- R1 · Quando pedir, o sistema deve guardar\n';

/// SPEC-063 t1: variations of `depende-de` are read and corrected.
void main() {
  group('SpecDocument', () {
    test('R1: every variation is read as depende-de, any case', () {
      for (final k in [
        'depende',
        'depends',
        'depends-on',
        'depends_on',
        'dependsOn',
        'depende_de',
        'dependencias',
        'dependências',
        'Depende',
        'DEPENDS-ON',
      ]) {
        final d = SpecDocument.parse(spec('$k: [SPEC-001]\n'));
        expect(d.dependsOn, ['SPEC-001'], reason: k);
        expect(d.hasDependsOn, isTrue, reason: k);
        expect(d.dependsOnAlias, k, reason: k);
      }
    });

    test('R1: depende-de alone has no alias; other keys are not read', () {
      final d = SpecDocument.parse(spec('depende-de: [SPEC-001]\n'));
      expect(d.dependsOnAlias, isNull);
      expect(d.dependsOn, ['SPEC-001']);
      for (final k in ['requer', 'apos', 'dep']) {
        final x = SpecDocument.parse(spec('$k: [SPEC-001]\n'));
        expect(x.dependsOn, isEmpty, reason: k);
        expect(x.hasDependsOn, isFalse, reason: k);
      }
    });

    test('R2: both keys: the lists together, without repeats', () {
      final d = SpecDocument.parse(
        spec('depende-de: [SPEC-001]\ndepende: SPEC-003, SPEC-001\n'),
      );
      expect(d.dependsOn, ['SPEC-001', 'SPEC-003']);
    });

    test('R2: withCanonicalDependsOn renames the line in place', () {
      final text = spec('depende: [SPEC-001]\n');
      final out = SpecDocument.parse(text).withCanonicalDependsOn();
      expect(out, spec('depende-de: [SPEC-001]\n'));
      expect(SpecDocument.parse(out).dependsOnAlias, isNull);
      // Nothing to do: the same text.
      expect(SpecDocument.parse(out).withCanonicalDependsOn(), out);
    });

    test(
      'R2: with depende-de too, the variation leaves and the lists join',
      () {
        final out = SpecDocument.parse(
          spec('depende-de: [SPEC-001]\ndependências: [SPEC-003]\n'),
        ).withCanonicalDependsOn();
        expect(out, spec('depende-de: [SPEC-001, SPEC-003]\n'));
      },
    );

    test('R2: the line of the variation', () {
      expect(
        SpecDocument.parse(spec('depende: [SPEC-001]\n')).dependsOnAliasLine,
        5,
      );
    });

    test('R2: the notice text', () {
      expect(
        dependsOnAliasNotice(
          SpecDocument.parse(spec('depende: [SPEC-001, SPEC-003]\n')),
          'SPEC-002',
        ),
        'A chave "depende" foi lida como "depende-de": SPEC-002 espera a '
        'SPEC-001 e a SPEC-003. Ao salvar, o nome fica certo no arquivo.',
      );
      expect(
        dependsOnAliasNotice(
          SpecDocument.parse(spec('depende-de: [SPEC-001]\n')),
          'SPEC-002',
        ),
        isNull,
      );
    });
  });

  group('Specs screen', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('promptorium-depends-');
      Directory('${tmp.path}/specs').createSync();
      File(specPath(tmp)).writeAsStringSync(spec('depende: [SPEC-001]\n'));
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    testWidgets('R2: the notice, "Trocar agora" changes the editor without '
        'saving, and saving writes depende-de', (tester) async {
      await pumpSpecs(tester, tmp, designer: FakeDesigner.new);
      expect(key('spec-depends-alias'), findsOneWidget);
      expect(
        tester.widget<Text>(key('spec-depends-alias-text')).data,
        contains('"depende" foi lida como "depende-de"'),
      );
      await tester.tap(key('spec-depends-alias-fix'));
      await tester.pump();
      expect(
        editorOf(tester).controller!.text,
        contains('depende-de: [SPEC-001]'),
      );
      expect(key('spec-depends-alias'), findsNothing);
      // Not saved.
      expect(File(specPath(tmp)).readAsStringSync(), contains('depende: '));
      await tester.tap(key('spec-save'));
      await settleIo(
        tester,
        until: () =>
            File(specPath(tmp)).readAsStringSync().contains('depende-de'),
      );
      expect(
        File(specPath(tmp)).readAsStringSync(),
        spec('depende-de: [SPEC-001]\n'),
      );
    });

    testWidgets('R2: saving with the variation writes depende-de', (
      tester,
    ) async {
      await pumpSpecs(tester, tmp, designer: FakeDesigner.new);
      final c = editorOf(tester).controller!;
      c.text = c.text.replaceFirst('# Pedidos', '# Pedidos do cliente');
      await tester.pump();
      await tester.tap(key('spec-save'));
      await settleIo(
        tester,
        until: () =>
            File(specPath(tmp)).readAsStringSync().contains('depende-de'),
      );
      final disk = File(specPath(tmp)).readAsStringSync();
      expect(disk, contains('depende-de: [SPEC-001]'));
      expect(disk, isNot(contains('depende: ')));
      expect(c.text, disk);
      expect(key('spec-depends-alias'), findsNothing);
    });
  });
}
