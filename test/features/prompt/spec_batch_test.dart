import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/db/app_database.dart';
import 'package:promptorium/data/repos/specs_repo.dart';
import 'package:promptorium/features/prompt/spec_batch.dart';
import 'package:promptorium/features/prompt/spec_from_answer.dart';
import 'package:promptorium/features/specs/spec_service.dart';

import '../../helpers/test_db.dart';

String specText(
  String id,
  String title, {
  List<String> deps = const [],
  int reqs = 2,
  String depsKey = 'depende-de',
}) =>
    '---\nid: $id\nstatus: rascunho\n'
    '${deps.isEmpty ? '' : '$depsKey: ${deps.join(', ')}\n'}'
    '---\n\n# $title\n\n## Requisitos\n\n'
    '${[for (var i = 1; i <= reqs; i++) '- R$i · Item $i.'].join('\n')}\n';

/// The answer of the mockup: three specs, B and C depend on A.
String threeSpecs({bool fenced = true}) {
  final specs = [
    specText('SPEC-A', 'Carrinho guarda os itens', reqs: 4),
    specText(
      'SPEC-B',
      'Cupom de desconto no carrinho',
      deps: ['SPEC-A'],
      reqs: 3,
    ),
    specText('SPEC-C', 'Pagamento com Pix', deps: ['SPEC-A'], reqs: 5),
  ];
  final body = fenced
      ? specs.map((s) => '```markdown\n$s```').join('\n\n')
      : specs.join('\n');
  return 'Dividi em três specs. O carrinho vem primeiro.\n\n$body\n';
}

List<SpecBatchEntry> entriesOf(String answer) =>
    batchEntries(batchItemsOf(answer), const [], null);

void main() {
  group('detectAnswerSpecs', () {
    test('three fenced specs, in order, with provisional codes', () {
      final specs = detectAnswerSpecs(threeSpecs());
      expect(specs.map((s) => s.alias), ['SPEC-A', 'SPEC-B', 'SPEC-C']);
      expect(specs.map((s) => s.title), [
        'Carrinho guarda os itens',
        'Cupom de desconto no carrinho',
        'Pagamento com Pix',
      ]);
      expect(specs[1].rawDependsOn, ['SPEC-A']);
      expect(specs.every((s) => s.leftover), isTrue);
      expect(specs.first.id, isNull, reason: 'SPEC-A is not a real code');
      expect(detectAnswerSpec(threeSpecs())!.alias, 'SPEC-C');
    });

    test('three loose specs, split by their frontmatter', () {
      final specs = detectAnswerSpecs(threeSpecs(fenced: false));
      expect(specs, hasLength(3));
      expect(specs.map((s) => s.alias), ['SPEC-A', 'SPEC-B', 'SPEC-C']);
      expect(specs[0].markdown, startsWith('---\nid: SPEC-A'));
      expect(specs[0].markdown, isNot(contains('SPEC-B')));
      expect(specs[2].requirements, 5);
    });

    test('one spec and none', () {
      final one = detectAnswerSpecs(
        '```markdown\n${specText('SPEC-A', 'Só uma')}```',
      );
      expect(one, hasLength(1));
      expect(one.single.title, 'Só uma');
      expect(detectAnswerSpecs('Nada aqui.\n\n---\n\nSó texto.'), isEmpty);
    });

    test('a variation of depende-de is read with provisional codes', () {
      final s = detectAnswerSpecs(
        specText('SPEC-B', 'B', deps: ['[SPEC-A]'], depsKey: 'depende'),
      ).single;
      expect(s.rawDependsOn, ['SPEC-A']);
    });
  });

  group('planBatch', () {
    test('numbers in list order, depende-de rewritten', () {
      final plan = planBatch(
        entriesOf(threeSpecs()),
        existing: const {},
        nextNumber: 21,
      );
      expect(plan.codes, {0: 'SPEC-021', 1: 'SPEC-022', 2: 'SPEC-023'});
      expect(plan.deps, {
        0: <String>[],
        1: ['SPEC-021'],
        2: ['SPEC-021'],
      });
      expect(plan.warnings, isEmpty);
      expect(plan.range, 'SPEC-021 a SPEC-023');
      expect(plan.hasCycle, isFalse);
    });

    test('an existing code stays; an unknown one warns', () {
      final answer = [
        specText('SPEC-A', 'A', deps: ['SPEC-012']),
        specText('SPEC-B', 'B', deps: ['SPEC-A', 'SPEC-Z', 'SPEC-099']),
      ].map((s) => '```md\n$s```').join('\n');
      final plan = planBatch(
        entriesOf(answer),
        existing: const {'SPEC-012'},
        nextNumber: 21,
      );
      expect(plan.deps[0], ['SPEC-012']);
      expect(plan.deps[1], ['SPEC-021', 'SPEC-099']);
      expect(plan.warnings[1]!.map((w) => (w.kind, w.code)), [
        (BatchWarningKind.unknown, 'SPEC-Z'),
        (BatchWarningKind.unknown, 'SPEC-099'),
      ]);
      expect(plan.hasCycle, isFalse);
    });

    test('an unchecked dependency warns and the numbers close up', () {
      final e = entriesOf(threeSpecs());
      final plan = planBatch(
        [e[0].copyWith(checked: false), e[1], e[2]],
        existing: const {},
        nextNumber: 21,
      );
      expect(plan.codes, {1: 'SPEC-021', 2: 'SPEC-022'});
      expect(plan.warnings[1], [
        const BatchWarning(BatchWarningKind.unchecked, 'SPEC-A'),
      ]);
      expect(
        plan.warnings[1]!.single.message,
        'Depende da SPEC-A, que você desmarcou. Ela não vai existir.',
      );
      expect(plan.deps[1], isEmpty);
      expect(plan.toCreate, [1, 2]);
    });

    test('a cycle blocks creating', () {
      final answer = [
        specText('SPEC-A', 'A', deps: ['SPEC-B']),
        specText('SPEC-B', 'B', deps: ['SPEC-A']),
        specText('SPEC-C', 'C'),
      ].map((s) => '```md\n$s```').join('\n');
      final e = entriesOf(answer);
      final plan = planBatch(e, existing: const {}, nextNumber: 1);
      expect(plan.hasCycle, isTrue);
      expect(plan.warnings[0]!.single.path, ['SPEC-A', 'SPEC-B', 'SPEC-A']);
      expect(plan.warnings[2], isNull);
      // Removing one dependency breaks it.
      final fixed = planBatch(
        [e[0].copyWith(dependsOn: const []), e[1], e[2]],
        existing: const {},
        nextNumber: 1,
      );
      expect(fixed.hasCycle, isFalse);
      expect(fixed.deps[1], ['SPEC-001']);
    });

    test('rows already created keep their code and are not created', () {
      final items = batchItemsOf(threeSpecs());
      final done = Spec(
        id: 9,
        workspaceId: 1,
        code: 'SPEC-021',
        title: 'Carrinho guarda os itens',
        status: SpecStatus.draft,
        path: 'specs/SPEC-021.md',
        stage: SpecStage.backlog,
        requirements: const [],
        dependsOn: const [],
        hasPlan: false,
        inTray: false,
        kind: SpecKind.spec,
        autoAdvance: true,
        reviewRounds: 0,
        gateResends: 0,
        rejectedHunks: 0,
        originConversationId: 7,
        originAnswer: 0,
        originItem: 0,
        originAlias: 'SPEC-A',
        originTitle: 'Carrinho guarda os itens',
      );
      final entries = batchEntries(
        items,
        [done],
        (conversationId: 7, answer: 0),
      );
      expect(entries[0].created, done);
      final plan = planBatch(entries, existing: {'SPEC-021'}, nextNumber: 22);
      expect(plan.toCreate, [1, 2]);
      expect(plan.codes[1], 'SPEC-022');
      expect(plan.deps[1], ['SPEC-021']);
      expect(plan.existingDeps.first, (
        row: 1,
        alias: 'SPEC-A',
        code: 'SPEC-021',
      ));

      // A regenerated answer: same pair (code, title) counts as created.
      final again = batchEntries(items, [done], (conversationId: 7, answer: 3));
      expect(again[0].created, done);
      expect(again[1].created, isNull);
      // Another conversation does not.
      final other = batchEntries(items, [done], (conversationId: 8, answer: 0));
      expect(other[0].created, isNull);
    });
  });

  group('createSpecBatch', () {
    late Directory tmp;
    late AppDatabase db;
    late Workspace ws;
    late SpecsRepo repo;
    late SpecService service;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('promptorium-spec-batch-');
      db = memoryDatabase();
      ws = await db
          .into(db.workspaces)
          .insertReturning(
            WorkspacesCompanion.insert(path: tmp.path, name: 'ws'),
          );
      repo = SpecsRepo(db);
      service = SpecService(repo);
      Directory('${tmp.path}/specs').createSync();
      File('${tmp.path}/specs/SPEC-020-x.md').writeAsStringSync('# X\n');
    });

    tearDown(() async {
      await db.close();
      tmp.deleteSync(recursive: true);
    });

    test('writes the specs in order, drafts, with the origin', () async {
      final entries = entriesOf(threeSpecs());
      final edited = [
        entries[0].copyWith(title: 'Carrinho persistente'),
        entries[1],
        entries[2],
      ];
      final plan = planBatch(
        edited,
        existing: const {},
        nextNumber: await nextSpecNumber(repo, ws),
      );
      final created = await createSpecBatch(
        service,
        repo,
        ws,
        edited,
        plan,
        origin: (conversationId: 4, answer: 1),
      );
      expect(created.map((s) => s.code), ['SPEC-021', 'SPEC-022', 'SPEC-023']);
      expect(created.every((s) => s.status == SpecStatus.draft), isTrue);
      expect(created[0].title, 'Carrinho persistente');
      expect(created[0].originTitle, 'Carrinho guarda os itens');
      expect(created[1].originAlias, 'SPEC-B');
      expect(created[1].originItem, 1);
      expect(created[2].originConversationId, 4);
      expect(created[2].originAnswer, 1);
      expect(created[2].dependsOn, ['SPEC-021']);
      final text = File('${tmp.path}/${created[1].path}').readAsStringSync();
      expect(text, startsWith('---\nid: SPEC-022\nstatus: rascunho\n'));
      expect(text, contains('depende-de: [SPEC-021]'));
      expect(text, isNot(contains('SPEC-A')));
    });

    test('a number taken meanwhile moves to the next one, with the '
        'references adjusted', () async {
      final entries = entriesOf(threeSpecs());
      // Planned with an old view of the folder: 020 is the next.
      final plan = planBatch(entries, existing: const {}, nextNumber: 20);
      expect(plan.codes[0], 'SPEC-020');
      final created = await createSpecBatch(service, repo, ws, entries, plan);
      expect(created.map((s) => s.code), ['SPEC-021', 'SPEC-022', 'SPEC-023']);
      expect(created[1].dependsOn, ['SPEC-021']);
      expect(created[2].dependsOn, ['SPEC-021']);
    });

    test(
      'a forward reference is rewritten when the later spec moves',
      () async {
        final answer = [
          specText('SPEC-A', 'A', deps: ['SPEC-B']),
          specText('SPEC-B', 'B'),
        ].map((s) => '```md\n$s```').join('\n');
        final entries = entriesOf(answer);
        final plan = planBatch(entries, existing: const {}, nextNumber: 21);
        expect(plan.deps[0], ['SPEC-022']);
        // Someone takes 021 after the plan: A becomes 022 and B 023.
        File('${tmp.path}/specs/SPEC-021-y.md').writeAsStringSync('# Y\n');
        final created = await createSpecBatch(service, repo, ws, entries, plan);
        expect(created.map((s) => s.code), ['SPEC-022', 'SPEC-023']);
        expect(created[0].dependsOn, ['SPEC-023']);
        expect(
          File('${tmp.path}/${created[0].path}').readAsStringSync(),
          contains('depende-de: [SPEC-023]'),
        );
      },
    );
  });
}
