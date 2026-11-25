import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/debts/debt_files.dart';
import 'package:promptorium/features/debts/debt_item.dart';
import 'package:promptorium/features/debts/debt_table.dart';
import 'package:promptorium/features/project/project_config.dart';

/// SPEC-112 R1, R2, R4, R5: the files on disk.
void main() {
  late Directory dir;
  final fixture = File('test/fixtures/debts/debitos.md').readAsStringSync();

  setUp(() => dir = Directory.systemTemp.createTempSync('debts_'));
  tearDown(() => dir.deleteSync(recursive: true));

  String read(String rel) => File('${dir.path}/$rel').readAsStringSync();

  test('the first item creates the file with a header and the table', () async {
    final doc = await DebtFiles.apply(
      dir.path,
      'DEBITO_TECNICO.md',
      DebtKind.debt,
      AppendDebtRow(
        DebtItem.newCells(code: 'DT-01', since: '2026-11-24', title: 'x'),
      ),
    );
    expect(doc.debts.single.code, 'DT-01');
    final text = read('DEBITO_TECNICO.md');
    expect(text, startsWith('# Débito técnico\n'));
    expect(
      text,
      endsWith(
        '| ID | Desde | O quê | Onde | Para resolver |\n'
        '|---|---|---|---|---|\n'
        '| DT-01 | 2026-11-24 | **x**. | — | — |\n',
      ),
    );
  });

  test('the write reads the file again: an outside change is kept', () async {
    File('${dir.path}/DEBITO_TECNICO.md').writeAsStringSync(fixture);
    final before = await DebtFiles.read(
      dir.path,
      'DEBITO_TECNICO.md',
      DebtKind.debt,
    );
    // Someone edits the text around the table after the screen read it.
    File('${dir.path}/DEBITO_TECNICO.md')
        .writeAsStringSync('$fixture\nNota depois da tabela.\n');
    await DebtFiles.apply(
      dir.path,
      'DEBITO_TECNICO.md',
      DebtKind.debt,
      ReplaceDebtRow(
        'DT-05',
        before.debts[4].struckCells(label: 'spec 9'),
        expectedRaw: before.debts[4].raw,
      ),
    );
    final text = read('DEBITO_TECNICO.md');
    expect(text, endsWith('\nNota depois da tabela.\n'));
    expect(text, contains('| ~~DT-05~~ |'));
  });

  test('a changed row gives up and leaves the file as it is', () async {
    File('${dir.path}/DEBITO_TECNICO.md').writeAsStringSync(fixture);
    final before = await DebtFiles.read(
      dir.path,
      'DEBITO_TECNICO.md',
      DebtKind.debt,
    );
    final edited = fixture.replaceFirst('PagarView.vue', 'Pagar.vue');
    File('${dir.path}/DEBITO_TECNICO.md').writeAsStringSync(edited);
    await expectLater(
      DebtFiles.apply(
        dir.path,
        'DEBITO_TECNICO.md',
        DebtKind.debt,
        ReplaceDebtRow(
          'DT-05',
          before.debts[4].struckCells(label: 'spec 9'),
          expectedRaw: before.debts[4].raw,
        ),
      ),
      throwsA(isA<DebtRowChanged>()),
    );
    expect(read('DEBITO_TECNICO.md'), edited);
  });

  test('the old files of docs/ are offered only when the configured one '
      'is missing (R2)', () async {
    Directory('${dir.path}/docs').createSync();
    File('${dir.path}/docs/debitos-tecnicos.md').writeAsStringSync(fixture);
    var s = await DebtSnapshot.load(dir.path);
    expect(s.legacyDebts, 'docs/debitos-tecnicos.md');
    expect(s.legacyDecisions, isNull);
    expect(s.debts.debts, isEmpty, reason: 'nothing is read without a choice');
    File('${dir.path}/DEBITO_TECNICO.md').writeAsStringSync('');
    s = await DebtSnapshot.load(dir.path);
    expect(s.legacyDebts, isNull);
  });

  test('the configured paths come from .promptorium/config.yml', () async {
    Directory('${dir.path}/.promptorium').createSync();
    File('${dir.path}/.promptorium/config.yml').writeAsStringSync(
      'debitos:\n  arquivo: docs/debitos-tecnicos.md\n'
      '  lembrar_na_execucao: false\n',
    );
    Directory('${dir.path}/docs').createSync();
    File('${dir.path}/docs/debitos-tecnicos.md').writeAsStringSync(fixture);
    final s = await DebtSnapshot.load(dir.path);
    expect(s.config.debtsPath, 'docs/debitos-tecnicos.md');
    expect(s.config.remindOnRun, isFalse);
    expect(s.legacyDebts, isNull);
    expect(s.debts.debts, hasLength(8));
    expect(s.openDebts.map((d) => d.code), isNot(contains('DT-02')));
  });

  test('editing the file outside the app emits a new snapshot (R5)', () async {
    File('${dir.path}/DEBITO_TECNICO.md').writeAsStringSync(fixture);
    final seen = <int>[];
    final done = Completer<void>();
    final sub =
        DebtSnapshot.watch(
          dir.path,
          debounce: const Duration(milliseconds: 20),
        ).listen((s) {
          seen.add(s.debts.debts.length);
          if (seen.length == 2 && !done.isCompleted) done.complete();
        });
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final added = DebtTable.parse(
      fixture,
      DebtKind.debt,
    ).append(['DT-09', 'x', '**y**', '—', '—']);
    File('${dir.path}/DEBITO_TECNICO.md').writeAsStringSync(added);
    await done.future.timeout(const Duration(seconds: 5));
    await sub.cancel();
    expect(seen, [8, 9]);
  });

  test('the highest number among several roots (R3)', () async {
    final other = Directory.systemTemp.createTempSync('debts_wt_');
    addTearDown(() => other.deleteSync(recursive: true));
    File('${dir.path}/DEBITO_TECNICO.md').writeAsStringSync(fixture);
    File('${other.path}/DEBITO_TECNICO.md').writeAsStringSync(
      DebtTable.parse(
        fixture,
        DebtKind.debt,
      ).append(['DT-11', 'x', '**y**', '—', '—']),
    );
    expect(
      await DebtFiles.maxNumberIn(
        [dir.path, other.path, '/nao/existe'],
        'DEBITO_TECNICO.md',
        DebtKind.debt,
      ),
      11,
    );
  });

  test('DebtsConfig round-trips through the YAML', () {
    const c = ProjectConfig(
      debts: DebtsConfig(
        debtsPath: 'docs/debitos-tecnicos.md',
        remindOnRun: false,
      ),
    );
    final back = ProjectConfig.parse(c.toYaml());
    expect(back.debts, c.debts);
    expect(const ProjectConfig().toYaml(), isNot(contains('debitos')));
    expect(
      ProjectConfig.parse('debitos:\n  arquivo: ../fora.md\n').debts.debtsPath,
      DebtsConfig.defaultDebtsPath,
    );
  });
}
