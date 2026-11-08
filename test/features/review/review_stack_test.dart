import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/board/step_gate.dart';
import 'package:promptorium/features/review/conflict_resolution.dart';
import 'package:promptorium/features/review/review_logic.dart';
import 'package:promptorium/features/review/review_stack.dart';
import 'package:promptorium/features/review/widgets/conflict_resolution_panel.dart';
import 'package:promptorium/features/review/widgets/merge_status_view.dart';
import 'package:promptorium/ui/theme/tokens.dart';

import '../board/board_rules_test.dart' show spec;
import 'review_logic_test.dart' show session;

ReviewItem item(
  String id, {
  String? code,
  int? specId,
  String? base = 'main',
  DateTime? at,
}) {
  final branch = 'pr/$id';
  return ReviewItem(
    session: session(
      id: id,
      startedAt: at,
    ).copyWith(branch: branch, baseBranch: Value(base), specId: Value(specId)),
    spec: code == null ? null : spec(specId!, code),
  );
}

List<List<String>> ids(List<ReviewStack> s) => [
  for (final g in s) [for (final i in g.items) i.session.id],
];

void main() {
  group('orderQueue (R1, R2)', () {
    test('a stack of three goes from the base to the top, before the loose '
        'specs; tasks go last', () {
      final items = [
        item('t1', at: DateTime(2026)),
        item('c', code: 'SPEC-033', specId: 3, base: 'pr/b'),
        item('x', code: 'SPEC-030', specId: 9),
        item('b', code: 'SPEC-031', specId: 2, base: 'pr/a'),
        item('a', code: 'SPEC-029', specId: 1),
      ];
      expect(ids(orderQueue(items)), [
        ['a', 'b', 'c'],
        ['x'],
        ['t1'],
      ]);
    });

    test('two stacks keep their own order; waves decide between loose '
        'specs, then the code', () {
      final items = [
        item('d2', code: 'SPEC-041', specId: 6, base: 'pr/d1'),
        item('d1', code: 'SPEC-040', specId: 5),
        item('b', code: 'SPEC-031', specId: 2, base: 'pr/a'),
        item('a', code: 'SPEC-029', specId: 1),
        item('z', code: 'SPEC-001', specId: 7),
        item('y', code: 'SPEC-050', specId: 8),
      ];
      expect(ids(orderQueue(items, waves: {7: 2, 8: 0})), [
        ['a', 'b'],
        ['d1', 'd2'],
        ['y'],
        ['z'],
      ]);
    });

    test('a cycle (should not happen) is broken by the spec code', () {
      final items = [
        item('b', code: 'SPEC-002', specId: 2, base: 'pr/a'),
        item('a', code: 'SPEC-001', specId: 1, base: 'pr/b'),
      ];
      expect(ids(orderQueue(items)), [
        ['a', 'b'],
      ]);
    });
  });

  test('nextAfterMerge (R5): the child, else the next, else the previous', () {
    final items = [
      item('b', code: 'SPEC-031', specId: 2, base: 'pr/a'),
      item('a', code: 'SPEC-029', specId: 1),
      item('x', code: 'SPEC-030', specId: 9),
    ];
    expect(nextAfterMerge(items, 'a')?.session.id, 'b');
    expect(nextAfterMerge(items, 'b')?.session.id, 'x');
    expect(nextAfterMerge(items, 'x')?.session.id, 'b');
    expect(nextAfterMerge([items[2]], 'x'), isNull);
  });

  group('state and primary action (R3, R8)', () {
    test('precedence of the states', () {
      expect(
        mergeStatusOf(reviewing: true, motherCode: 'SPEC-029').state,
        MergeState.revisando,
      );
      expect(
        mergeStatusOf(motherCode: 'SPEC-029', conflictFiles: ['a']).text,
        'Espera SPEC-029',
      );
      expect(
        mergeStatusOf(conflictFiles: ['lib/a.dart'], pending: true).text,
        'Conflito em lib/a.dart',
      );
      expect(
        mergeStatusOf(conflictFiles: ['a', 'b', 'c']).text,
        'Conflito em a +2',
      );
      expect(
        mergeStatusOf(restackConflict: true).text,
        'Conflito ao refazer a base',
      );
      expect(
        mergeStatusOf(conflictFiles: [], pending: true).text,
        'Pendências',
      );
      expect(mergeStatusOf().text, 'Verificando…');
      expect(
        mergeStatusOf(rebaseStep: '1 de 2', reviewing: true).text,
        'Rebase em andamento · 1 de 2',
      );
      expect(mergeStatusOf(conflictFiles: []).text, 'Pronto para merge');
    });

    test('one primary action per state', () {
      PrimaryAction of(MergeState s, {bool pr = false}) =>
          primaryActionOf(MergeStatus(s), hasPr: pr);
      expect(of(MergeState.pronto), PrimaryAction.fazerMerge);
      expect(of(MergeState.pronto, pr: true), PrimaryAction.mergearPr);
      expect(of(MergeState.verificando), PrimaryAction.fazerMerge);
      expect(of(MergeState.esperaMae), PrimaryAction.irParaMae);
      expect(of(MergeState.conflito), PrimaryAction.resolverConflito);
      expect(of(MergeState.conflitoBase), PrimaryAction.resolverConflito);
      expect(of(MergeState.baseDesatualizada), PrimaryAction.refazerBase);
      expect(of(MergeState.pendencias), PrimaryAction.pedirAjustes);
      expect(of(MergeState.revisando), PrimaryAction.nenhuma);
      expect(of(MergeState.rebaseManual), PrimaryAction.abrirEditor);
      const wait = MergeStatus(MergeState.esperaMae, detail: 'SPEC-029');
      expect(
        primaryLabel(primaryActionOf(wait, hasPr: false), wait),
        'Ir para SPEC-029',
      );
    });

    test('SPEC-043 R2: the card shows the states of the resolution with icon '
        'and text', () {
      MergeStatus of(ResolutionState r, {String? detail}) => mergeStatusOf(
        resolution: r,
        resolutionDetail: detail,
        conflictFiles: const [],
      );
      expect(
        of(ResolutionState.resolvendo).text,
        'Agente resolvendo o conflito…',
      );
      expect(
        of(ResolutionState.conferindo, detail: 'testes').text,
        'Conferindo a resolução · testes',
      );
      expect(
        of(ResolutionState.aprovada).text,
        'Conflito resolvido · gate aprovado',
      );
      expect(
        of(ResolutionState.reprovada, detail: 'testes').text,
        'Resolução reprovada no gate · testes',
      );
      expect(
        of(ResolutionState.desatualizada).text,
        'A base mudou · resolver de novo',
      );
      final looks = {
        for (final s in [
          MergeState.resolvendo,
          MergeState.conferindo,
          MergeState.resolvida,
          MergeState.reprovada,
          MergeState.resolucaoDesatualizada,
        ])
          s: mergeStateLook(s),
      };
      expect(looks[MergeState.resolvida]!.$2, AppColors.teal);
      expect(looks[MergeState.reprovada]!.$2, AppColors.red);
      expect(looks.values.map((l) => l.$1).toSet(), hasLength(5));
      // The resolution in progress comes before the reviewer and the
      // forecast; an approved one replaces "ready", not the pendencies.
      expect(
        mergeStatusOf(
          resolution: ResolutionState.resolvendo,
          reviewing: true,
          conflictFiles: const ['a'],
        ).state,
        MergeState.resolvendo,
      );
      expect(
        mergeStatusOf(
          resolution: ResolutionState.aprovada,
          conflictFiles: const [],
          pending: true,
        ).state,
        MergeState.pendencias,
      );
      // A manual rebase ("Resolver eu mesmo") wins over a failed one.
      expect(
        mergeStatusOf(
          resolution: ResolutionState.reprovada,
          rebaseStep: '1 de 1',
        ).state,
        MergeState.rebaseManual,
      );
      PrimaryAction primary(MergeState s) =>
          primaryActionOf(MergeStatus(s), hasPr: false);
      expect(primary(MergeState.reprovada), PrimaryAction.corrigirVerificar);
      expect(
        primary(MergeState.resolucaoDesatualizada),
        PrimaryAction.resolverDeNovo,
      );
      expect(primary(MergeState.conferindo), PrimaryAction.fazerMerge);
      expect(primary(MergeState.resolvida), PrimaryAction.fazerMerge);
    });

    testWidgets('SPEC-043 R2, R3: header pill, gate running and the three ways '
        'out of a failed resolution', (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final running = ConflictResolution(
        state: ResolutionState.conferindo,
        workspaceId: 1,
        files: const ['a.txt'],
        running: 'testes',
        plan: const ['arvore', 'marcadores', 'base', 'testes', 'lint'],
        report: GateReport(
          at: DateTime(2026),
          checks: const [
            GateCheck(name: 'arvore', ok: true),
            GateCheck(name: 'marcadores', ok: true, output: '1 arquivo(s)'),
            GateCheck(name: 'base', ok: true, output: 'a408a2e1'),
          ],
        ),
      );
      final settings = _Settings({resolutionKey('s1'): running.encode()});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appSettingsProvider.overrideWith(() => settings)],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    const ResolutionChip(sessionId: 's1'),
                    ConflictResolutionPanel(
                      sessionId: 's1',
                      specCode: 'SPEC-042',
                      busy: false,
                      run: (_, job) => job(),
                      toast: (_) {},
                      refresh: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Conferindo a resolução'), findsOneWidget);
      expect(find.text('Gate da resolução'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('review-resolution-running-testes')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('review-resolution-queued-lint')),
        findsOneWidget,
      );
      expect(find.textContaining('não tem build:'), findsOneWidget);

      settings.state = {
        resolutionKey('s1'): running
            .copyWith(
              state: ResolutionState.reprovada,
              running: () => null,
              checkedSha: () => '4e1b7a2aa',
              gates: 2,
              report: () => GateReport(
                at: DateTime(2026),
                checks: const [
                  GateCheck(name: 'arvore', ok: true),
                  GateCheck(name: 'marcadores', ok: true),
                  GateCheck(name: 'base', ok: true),
                  GateCheck(
                    name: 'testes',
                    ok: false,
                    command: 'flutter test',
                    output: 'Expected: <3>\n  Actual: <2>',
                  ),
                ],
              ),
            )
            .encode(),
      };
      await tester.pump();
      expect(find.text('Resolução reprovada no gate'), findsOneWidget);
      expect(find.textContaining('Expected: <3>'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('review-resolution-not-run')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('review-resolution-fix')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('review-resolution-undo')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('review-resolution-myself')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('SPEC-043 R4: "O que a resolução decidiu" shows both sides, '
        'the result and the explanation', (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final approved = ConflictResolution(
        state: ResolutionState.aprovada,
        workspaceId: 1,
        files: const ['lib/a.dart'],
        checkedSha: '4e1b7a2aa',
        report: GateReport(
          at: DateTime(2026),
          checks: const [GateCheck(name: 'marcadores', ok: true)],
        ),
      );
      Widget app(ResolutionDecisions d) => ProviderScope(
        key: UniqueKey(),
        overrides: [
          appSettingsProvider.overrideWith(
            () => _Settings({resolutionKey('s1'): approved.encode()}),
          ),
          resolutionDecisionsProvider('s1').overrideWith((ref) async => d),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConflictResolutionPanel(
                sessionId: 's1',
                specCode: 'SPEC-042',
                busy: false,
                run: (_, job) => job(),
                toast: (_) {},
                refresh: () {},
              ),
            ),
          ),
        ),
      );
      const hunks = [
        ResolutionHunk(
          path: 'lib/a.dart',
          line: 41,
          base: ['main()'],
          spec: ['spec()'],
          result: ['main();', '// spec'],
        ),
        ResolutionHunk(
          path: 'lib/a.dart',
          line: 80,
          base: ['x'],
          spec: ['y'],
          result: ['y'],
        ),
      ];
      await tester.pumpWidget(
        app(
          ResolutionDecisions(
            hunks: hunks,
            how: parseHowResolved('## Como resolvi\na.dart: mantive a main'),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('O que a resolução decidiu'), findsOneWidget);
      expect(find.text('1 arquivo · 2 trechos'), findsOneWidget);
      expect(find.text('Na main'), findsOneWidget);
      expect(find.text('Nesta spec (SPEC-042)'), findsOneWidget);
      expect(find.text('Resultado do agente'), findsOneWidget);
      expect(find.text('main();\n// spec'), findsOneWidget);
      expect(find.text('mantive a main'), findsOneWidget);
      expect(find.text('Como resolvi · resposta do agente'), findsOneWidget);
      expect(find.textContaining('Trecho 1 de 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('review-resolution-next')));
      await tester.pump();
      expect(find.textContaining('Trecho 2 de 2'), findsOneWidget);

      // Without ## Como resolvi: the whole answer.
      await tester.pumpWidget(
        app(
          const ResolutionDecisions(
            hunks: hunks,
            answer: 'Fiquei com a main em tudo.',
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Fiquei com a main em tudo.'), findsOneWidget);
      expect(
        find.textContaining('sem a seção ## Como resolvi'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    test('accessible label of a card (R14)', () {
      expect(
        queueSemanticLabel(
          title: 'SPEC-031',
          position: 2,
          stackSize: 2,
          status: const MergeStatus(MergeState.esperaMae, detail: 'SPEC-029'),
        ),
        'SPEC-031, 2 de 2 na pilha, espera SPEC-029',
      );
      expect(
        queueSemanticLabel(
          title: 'SPEC-030',
          position: 1,
          stackSize: 1,
          status: const MergeStatus(MergeState.pronto),
        ),
        'SPEC-030, pronto para merge',
      );
    });
  });
}

class _Settings extends AppSettingsController {
  _Settings(this.initial);

  final Map<String, String> initial;

  @override
  Map<String, String> build() => initial;
}
