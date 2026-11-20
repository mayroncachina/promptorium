import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/features/prompt/compare/compare_controller.dart';
import 'package:promptorium/features/prompt/compare/compare_run.dart';

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
      'B pesou 4,0× o A   ·   levou 2,9× o tempo',
    );
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
        RegExp(r'^Resposta A, Sonnet, Perguntar, pronta em 38 segundos'),
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
}
