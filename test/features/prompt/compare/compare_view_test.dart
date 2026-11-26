import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/prompt/compare/compare_controller.dart';
import 'package:promptorium/core/providers/agent_provider.dart' show PromptMode;
import 'package:promptorium/data/providers.dart';
import 'package:promptorium/features/prompt/compare/compare_run.dart';
import 'package:promptorium/features/prompt/compare/widgets/compare_card.dart';
import 'package:promptorium/ui/providers/provider_logos.dart';

import '../../../core/codex/fake_codex.dart';
import '../prompt_screen_test.dart' show field, fieldText, pumpFor;
import '../prompt_test_utils.dart';
import 'compare_controller_test.dart' show resultOf, toolLine;
import 'compare_test_utils.dart';

/// Lets the controller's real work (processes, database) run, then pumps.
Future<void> drain(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await pumpFor(tester, 5);
  }
}

Future<void> startByComposer(WidgetTester tester, String text) async {
  await tester.enterText(field, text);
  await tester.tap(key('prompt-compare'));
  await pumpFor(tester);
  await tester.tap(key('prompt-send'));
  await pumpFor(tester, 20);
}

void main() {
  testWidgets('two columns with the timeline, state and metrics of each '
      'side, never US\$; choosing B folds A in a card (R6, R7, R11)', (
    tester,
  ) async {
    final p = CompareFakeProvider();
    final (db, c) = await pumpCompare(
      tester,
      provider: p,
      usages: [usageText(38, 61), usageText(45, 62)],
    );
    await startByComposer(tester, 'por que o cupom passa?');
    expect(p.runs, hasLength(2));
    expect(key('compare-panel-1'), findsOneWidget);
    expect(key('compare-column-A'), findsOneWidget);
    expect(key('compare-column-B'), findsOneWidget);
    expect(key('compare-tabs'), findsNothing);
    expect(find.text('Comparando'), findsOneWidget);
    // P7: the side panel folds.
    expect(key('prompt-side-strip'), findsOneWidget);

    final a = p.runs[0], b = p.runs[1];
    a.emit(initLine(a.options.sessionId!));
    a.emit(toolLine('t1', 'Read'));
    a.emit(textLine('Só conta pedidos pagos.'));
    a.emit(resultOf(cost: 0.1, ms: 38000));
    b.emit(initLine(b.options.sessionId!));
    b.emit(toolLine('t2', 'Read'));
    await pumpFor(tester, 20);
    expect(find.textContaining('pronta · 38 s'), findsOneWidget);
    expect(find.textContaining('rodando · '), findsOneWidget);
    expect(find.text('medindo…'), findsNWidgets(2));
    expect(
      find.textContaining('o peso aparece quando os dois terminarem'),
      findsOneWidget,
    );
    // A running side is stopped, not chosen.
    expect(key('compare-choose-B'), findsNothing);
    expect(key('compare-stop-B'), findsOneWidget);

    b.emit(textLine('São duas causas.', id: 'mb'));
    b.emit(resultOf(cost: 0.4, ms: 112000, input: 31000, output: 2400));
    await pumpFor(tester, 30);
    expect(find.textContaining('pronta · 1 min 52 s'), findsOneWidget);
    expect(find.text('38 s'), findsOneWidget);
    expect(find.text('14,2 mil → 900'), findsOneWidget);
    expect(find.text('1 leitura'), findsNWidgets(2));
    // 7 points of the window: 1/5 for A, 4/5 for B.
    expect(find.text('≈ 1,4%'), findsOneWidget);
    expect(find.text('≈ 5,6%'), findsOneWidget);
    expect(key('compare-ratio-B'), findsOneWidget);
    expect(
      tester.widget<Text>(key('compare-ratio-B')).data,
      'B pesou 4,0× o A',
    );
    // SPEC-108 R7: time and tokens between the sides; same provider, so no
    // notice of tokenizers or quotas.
    expect(
      tester.widget<Text>(key('compare-time-tokens')).data,
      'B levou 2,9× o tempo · usou 2,2× os tokens',
    );
    expect(key('compare-no-ratio'), findsNothing);
    expect(key('compare-tokenizers'), findsNothing);
    // P2: no US\$ anywhere in the comparison.
    expect(
      find.descendant(
        of: key('compare-panel-1'),
        matching: find.textContaining('\$'),
      ),
      findsNothing,
    );
    // R15: the region of each column.
    expect(
      find.bySemanticsLabel(
        RegExp(
          r'^Resposta A, Claude, Sonnet, Perguntar, pronta em 38 segundos',
        ),
      ),
      findsOneWidget,
    );

    await tester.tap(key('compare-choose-B'));
    await drain(tester);
    expect(c.read(compareControllerProvider), isEmpty);
    expect(key('compare-panel-1'), findsNothing);
    expect(key('compare-card'), findsOneWidget);
    expect(
      find.textContaining('escolhida B · Opus · Perguntar'),
      findsOneWidget,
    );
    expect(find.text('escolhida entre 2 · Opus · Perguntar'), findsOneWidget);
    expect(find.text('São duas causas.'), findsOneWidget);
    expect(find.text('Só conta pedidos pagos.'), findsNothing);
    // The composer is back, on Opus.
    expect(key('prompt-compare'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: key('prompt-model'),
              matching: find.byType(Text),
            ),
          )
          .data,
      'Opus',
    );
    await tester.tap(key('compare-card-toggle'));
    await pumpFor(tester);
    expect(key('compare-card-answer'), findsOneWidget);
    expect(find.text('Só conta pedidos pagos.'), findsOneWidget);
    expect(db, isNotNull);
  });

  testWidgets('a narrow window shows tabs A/B with the metrics on top (R6)', (
    tester,
  ) async {
    final p = CompareFakeProvider();
    await pumpCompare(tester, provider: p, size: const Size(1300, 900));
    await startByComposer(tester, 'por quê?');
    expect(key('compare-tabs'), findsOneWidget);
    expect(find.text('A · Sonnet'), findsOneWidget);
    expect(find.text('B · Opus'), findsOneWidget);
    expect(key('compare-metrics-A'), findsOneWidget);
    expect(key('compare-metrics-B'), findsOneWidget);
    await tester.tap(key('compare-stop-both'));
    await drain(tester);
  });

  testWidgets('Parar of one column; Descartar os dois asks and gives the '
      'prompt back (R10, R12)', (tester) async {
    final p = CompareFakeProvider();
    final (_, c) = await pumpCompare(tester, provider: p);
    await startByComposer(tester, 'por que o cupom passa?');
    expect(fieldText(tester), isEmpty);
    await tester.tap(key('compare-stop-A'));
    await drain(tester);
    expect(p.runs[0].stopped, isTrue);
    expect(p.runs[1].stopped, isFalse);
    expect(find.text('interrompida'), findsOneWidget);
    expect(key('compare-resume-A'), findsOneWidget);
    expect(key('compare-choose-A'), findsOneWidget);
    expect(c.read(compareProvider(1))!.run.a.state, CompareSideState.stopped);

    await tester.tap(key('compare-discard'));
    await pumpFor(tester);
    await tester.tap(key('compare-discard-confirm'));
    await drain(tester);
    expect(p.runs[1].stopped, isTrue);
    expect(key('compare-panel-1'), findsNothing);
    expect(fieldText(tester), 'por que o cupom passa?');
    expect(c.read(compareControllerProvider), isEmpty);
  });

  testWidgets('SPEC-087 R11: cada lado com o seu medidor, sem somar; o '
      'subagente fica separado', (tester) async {
    final p = CompareFakeProvider();
    await pumpCompare(
      tester,
      provider: p,
      usages: [usageText(38, 61), usageText(45, 62)],
    );
    await startByComposer(tester, 'índice em clientes.email');
    final a = p.runs[0], b = p.runs[1];
    Map<String, dynamic> said(
      String id,
      String model,
      int tokens, {
      List<Map<String, dynamic>> content = const [],
    }) => {
      'type': 'assistant',
      'message': {
        'id': id,
        'model': model,
        'role': 'assistant',
        'content': content,
        'usage': {
          'input_tokens': 2,
          'cache_creation_input_tokens': 0,
          'cache_read_input_tokens': tokens - 2,
          'output_tokens': 10,
        },
      },
      'parent_tool_use_id': null,
      'session_id': 's',
    };
    a.emit(initLine(a.options.sessionId!));
    a.emit(
      said(
        'ma',
        'claude-opus-5-5',
        96000,
        content: [
          {
            'type': 'tool_use',
            'id': 'task1',
            'name': 'Task',
            'input': {'subagent_type': 'Explore', 'prompt': 'procure'},
          },
        ],
      ),
    );
    // The subagent's own usage never enters side A.
    a.emit({
      ...said('sub', 'claude-haiku-5-5', 500000),
      'parent_tool_use_id': 'task1',
    });
    a.emit({
      ...resultOf(),
      'modelUsage': {
        'claude-opus-5-5': {'contextWindow': 1000000},
      },
    });
    b.emit(initLine(b.options.sessionId!));
    b.emit(said('mb', 'claude-sonnet-5-5', 88000));
    b.emit({
      ...resultOf(),
      'modelUsage': {
        'claude-sonnet-5-5': {'contextWindow': 200000},
      },
    });
    await pumpFor(tester, 30);
    String meter(String letter) => tester
        .widgetList<RichText>(
          find.descendant(
            of: key('compare-context-$letter'),
            matching: find.byType(RichText),
          ),
        )
        .map((r) => r.text.toPlainText())
        .join(' ');
    expect(meter('A'), contains('96 mil / 1 milhão'));
    expect(meter('A'), contains('10%'));
    expect(meter('A'), isNot(contains('500 mil')));
    expect(meter('B'), contains('88 mil / 200 mil'));
    expect(meter('B'), contains('44%'));
    // Nothing sums the two windows.
    expect(find.textContaining('184 mil'), findsNothing);
    expect(
      find.descendant(
        of: key('compare-context-A'),
        matching: find.textContaining(
          'contexto separado · medição indisponível',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: key('compare-context-B'),
        matching: find.textContaining('contexto separado'),
      ),
      findsNothing,
    );
    // The CLI was asked for each side's threshold before closing.
    expect(tester.takeException(), isNull);
  });

  testWidgets('SPEC-108 R6–R9, R12: Opus × Codex, with the badges, the reads '
      'of the Codex as reads, metrics, the weight in each quota and the '
      'conversation moving to the Codex', (tester) async {
    final servers = <FakeCodex>[];
    final p = CompareFakeProvider();
    final (_, c) = await pumpCompare(
      tester,
      provider: p,
      codex: servers,
      usages: [usageText(38, 61), usageText(44, 62)],
      codexUsages: [codexLimits(12, 30), codexLimits(15, 31)],
    );
    await tester.enterText(field, 'por que o cupom passa?');
    await tester.tap(key('prompt-compare'));
    await pumpFor(tester);
    await tester.tap(key('compare-claude-codex'));
    await pumpFor(tester);
    await tester.tap(key('prompt-send'));
    await drain(tester);
    final a = p.runs.single, f = servers.single;
    expect(find.text('Comparando · Claude × Codex'), findsOneWidget);
    expect(
      tester.widget<ProviderChip>(key('compare-chip-B')).provider,
      'codex',
    );
    expect(
      find.descendant(of: key('compare-chip-B'), matching: find.text('Codex')),
      findsOneWidget,
    );
    codexCommandItem(f, 'c1', 'sed -n 1,80p lib/cupom.dart', [
      {'type': 'read', 'command': 'sed', 'path': '/work/repo/lib/cupom.dart'},
    ]);
    codexCommandItem(f, 'c2', 'rg primeiraCompra lib', [
      {'type': 'search', 'command': 'rg', 'query': 'primeira', 'path': 'lib'},
    ]);
    // A question of the Codex shows only in its column.
    f.emit(
      jsonEncode({
        'id': 77,
        'method': 'item/tool/requestUserInput',
        'params': {
          'threadId': f.threadId,
          'turnId': 'turn-1',
          'itemId': 'q1',
          'questions': [
            {
              'id': 'q',
              'header': 'Qual',
              'question': 'Qual regra?',
              'options': [
                {'label': 'Uma', 'description': ''},
              ],
            },
          ],
        },
      }),
    );
    await drain(tester);
    final live = c.read(compareProvider(1))!;
    expect(live.liveOf('A').approvals, isEmpty);
    expect(live.liveOf('B').approvals.single.requestId, 'codex-77');
    expect(key('compare-approval-B-codex-77'), findsOneWidget);
    await tester.runAsync(
      () => c.read(compareControllerProvider.notifier).deny(1, 'B', 'codex-77'),
    );
    // R6: what the commands did, not a generic command.
    expect(find.text('Ler'), findsOneWidget);
    expect(find.text('lib/cupom.dart · sed -n'), findsOneWidget);
    expect(find.text('Buscar'), findsOneWidget);
    expect(find.text('"primeira" lib · rg'), findsOneWidget);

    codexFinish(f, 'O filtro compara com pago.');
    a.emit(initLine(a.options.sessionId!));
    a.emit(textLine('São duas causas.'));
    a.emit(resultOf(cost: 9, ms: 112000, input: 31400, output: 2400));
    await drain(tester);
    // R7.
    expect(find.text('18,4 mil → 1,6 mil'), findsOneWidget);
    expect(find.text('raciocínio 2,1 mil'), findsOneWidget);
    expect(find.text('1 leitura · 1 busca'), findsOneWidget);
    expect(find.text('1 min 8 s'), findsOneWidget);
    expect(
      tester.widget<Text>(key('compare-time-tokens')).data,
      'B levou 0,6× o tempo · usou 0,7× os tokens',
    );
    expect(
      tester.widget<Text>(key('compare-tokenizers')).data,
      'tokenizadores diferentes: os tokens servem de ordem de grandeza',
    );
    // R8: each weight in its own quota, without a ratio nor US$.
    expect(find.text('Claude · janela de 5 h'), findsOneWidget);
    expect(find.text('≈ 6,0%'), findsOneWidget);
    expect(find.text('Codex · janela de 5 h'), findsOneWidget);
    expect(find.text('≈ 3,0%'), findsOneWidget);
    expect(
      tester.widget<Text>(key('compare-no-ratio')).data,
      'cotas diferentes · sem razão de peso',
    );
    expect(key('compare-ratio-A'), findsNothing);
    expect(key('compare-ratio-B'), findsNothing);
    expect(
      find.descendant(
        of: key('compare-panel-1'),
        matching: find.textContaining('\$'),
      ),
      findsNothing,
    );
    // R12.
    expect(
      find.bySemanticsLabel(
        RegExp(
          r'^Resposta B, Codex, Padrão, Perguntar, pronta em 1 minuto e 8 '
          r'segundos',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        RegExp(r'peso na janela de 5 horas do Codex, cerca de 3,0 por cento'),
      ),
      findsOneWidget,
    );

    // R9.
    await tester.tap(key('compare-choose-B'));
    await drain(tester);
    expect(key('compare-card'), findsOneWidget);
    expect(
      find.text(
        'A conversa passou para o Codex · Padrão · Perguntar (escolhida '
        'entre 2)',
      ),
      findsOneWidget,
    );
    expect(key('compare-card-terminal'), findsOneWidget);
    final conv = (await tester.runAsync(
      () => c.read(conversationsRepoProvider).getById(1),
    ))!;
    expect(conv.provider, 'codex');
    // The composer is on the Codex.
    expect(
      find.descendant(of: key('prompt-provider'), matching: find.text('Codex')),
      findsOneWidget,
    );
    // The answer of before keeps its author.
    expect(find.textContaining('Claude Code · Sonnet'), findsWidgets);
    for (final s in servers) {
      await tester.runAsync(s.finish);
    }
  });

  test('SPEC-108 R9: the terminal command of the side that was not chosen', () {
    const a = CompareSide(
      letter: 'A',
      model: 'opus',
      mode: PromptMode.ask,
      sessionId: 'sid',
      started: true,
    );
    expect(
      compareTerminalCommand(a, claude: '/bin/claude', codex: 'codex'),
      "'/bin/claude' '--resume' 'sid'",
    );
    const b = CompareSide(
      letter: 'B',
      provider: 'codex',
      model: 'gpt-6.2-sol',
      mode: PromptMode.ask,
      sessionId: 'thr',
      started: true,
    );
    expect(
      compareTerminalCommand(b, claude: 'claude', codex: 'codex'),
      allOf(startsWith("'codex' 'resume' 'thr'"), contains("'read-only'")),
    );
    expect(
      compareTerminalCommand(
        const CompareSide(letter: 'A', model: 'opus', mode: PromptMode.ask),
        claude: 'claude',
        codex: 'codex',
      ),
      isNull,
    );
  });
}
