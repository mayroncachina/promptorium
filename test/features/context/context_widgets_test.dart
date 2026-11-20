import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/claude/claude_event.dart';
import 'package:promptorium/core/claude/context_usage.dart';
import 'package:promptorium/features/context/context_snapshot.dart';
import 'package:promptorium/features/context/context_tracker.dart';
import 'package:promptorium/features/context/widgets/context_chart.dart';
import 'package:promptorium/features/context/widgets/context_indicator.dart';
import 'package:promptorium/features/context/widgets/context_panel.dart';
import 'package:promptorium/features/sessions/timeline.dart';

final t0 = DateTime(2026, 11, 20, 14, 32);

AgentEvent assistant(
  int tokens, {
  String id = 'a',
  String model = 'claude-opus-5-5',
  List<Map<String, dynamic>> content = const [],
}) => AgentEvent.fromJson({
  'type': 'assistant',
  'message': {
    'id': id,
    'model': model,
    'content': content,
    'usage': {
      'input_tokens': 3100,
      'cache_creation_input_tokens': 9400,
      'cache_read_input_tokens': tokens - 12500,
      'output_tokens': 10,
    },
  },
});

AgentEvent result({int window = 1000000}) => AgentEvent.fromJson({
  'type': 'result',
  'subtype': 'success',
  'num_turns': 1,
  'modelUsage': {
    'claude-opus-5-5': {'contextWindow': window},
  },
});

AgentEvent usage(int threshold) => UnknownEvent(
  contextUsageEvent({
    'totalTokens': 1,
    'maxTokens': threshold + 33000,
    'autoCompactThreshold': threshold,
    'isAutoCompactEnabled': true,
    'model': 'claude-opus-5-5',
    'apiUsage': {},
  })!,
);

AgentEvent boundary() => AgentEvent.fromJson({
  'type': 'system',
  'subtype': 'compact_boundary',
  'uuid': 'b',
  'compact_metadata': {'trigger': 'auto', 'pre_tokens': 171000},
});

ContextTracker feed(List<AgentEvent> es, {bool live = true}) {
  final t = ContextTracker();
  var i = 0;
  for (final e in es) {
    t.apply(e, at: t0, itemIndex: i++, live: live);
  }
  return t;
}

String spans(ContextSnapshot s, {bool alive = true}) =>
    TextSpan(children: contextIndicatorParts(s, alive: alive)).toPlainText();

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 560, height: 760, child: child)),
);

void main() {
  group('indicador (R2, R3)', () {
    test('sem medição: "Aguardando medição", nunca 0%', () {
      final s = feed([
        UnknownEvent(ContextEventTypes.runEvent(autocompact: '200k')),
      ]).snapshot;
      final text = spans(s);
      expect(text, contains('Aguardando medição'));
      expect(text, isNot(contains('%')));
      expect(text, contains('auto compactar: 200 mil'));
    });

    test('medição com limite, limiar e turno', () {
      final s = feed([assistant(182000), result(), usage(200000)]).snapshot;
      expect(
        spans(s),
        allOf(
          contains('182 mil / 1 milhão'),
          contains('18%'),
          contains('compacta em 200 mil, faltam 18 mil'),
          contains('medido no turno 1'),
        ),
      );
    });

    test('limite desconhecido: total sem porcentagem', () {
      final s = feed([assistant(64000)]).snapshot;
      final text = spans(s);
      expect(text, contains('64 mil medidos'));
      expect(text, contains('limite desconhecido'));
      expect(text, isNot(contains('%')));
    });

    test('compactado: aguardando medição e o valor só no histórico', () {
      final s = feed([assistant(171000), result(), boundary()]).snapshot;
      expect(spans(s), contains('Contexto compactado · aguardando medição'));
      expect(spans(s), contains('171 mil fica só no histórico'));
    });

    test('leitura antiga ao reabrir: não é ao vivo', () {
      final s = feed([assistant(96000), result()], live: false).snapshot;
      expect(spans(s, alive: false), contains('não é ao vivo'));
      expect(spans(s, alive: false), isNot(contains('medido no turno')));
    });

    testWidgets('resumo em texto e Enter abre o painel (R12)', (tester) async {
      var opened = 0;
      final s = feed([assistant(182000), result(), usage(200000)]).snapshot;
      await tester.pumpWidget(
        host(ContextIndicator(snapshot: s, onOpen: () => opened++)),
      );
      expect(
        find.bySemanticsLabel(RegExp('Contexto: 182 mil tokens de 1 milhão')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(opened, 1);
    });
  });

  group('painel (R2, R4–R6)', () {
    testWidgets('Uso: limiar distinto da capacidade e composição medida', (
      tester,
    ) async {
      final t = feed([assistant(182000), result(), usage(200000)]);
      await tester.pumpWidget(
        host(
          ContextPanel(
            snapshot: t.snapshot,
            sources: t.sources,
            onClose: () {},
          ),
        ),
      );
      expect(find.text('182 mil'), findsWidgets);
      expect(find.textContaining('compacta em 200 mil'), findsOneWidget);
      expect(
        find.textContaining('capacidade da janela · 1 milhão'),
        findsOneWidget,
      );
      expect(find.textContaining('leitura de cache'), findsOneWidget);
      expect(find.text('818 mil'), findsOneWidget); // livre
      expect(find.text('18 mil'), findsOneWidget); // até compactar
    });

    testWidgets('Fontes: evidência e peso indisponível', (tester) async {
      final t = feed([
        UnknownEvent(AppEventTypes.userMessage('veja @lib/a.dart', t0)),
        assistant(
          30000,
          content: [
            {
              'type': 'tool_use',
              'id': 'r',
              'name': 'Read',
              'input': {'file_path': 'lib/features/x/run_prefs.dart'},
            },
          ],
        ),
        result(),
      ]);
      await tester.pumpWidget(
        host(
          ContextPanel(
            snapshot: t.snapshot,
            sources: t.sources,
            onClose: () {},
            initialTab: ContextTab.sources,
          ),
        ),
      );
      expect(find.text('leitura observada · t1'), findsOneWidget);
      expect(find.text('peso indisponível'), findsWidgets);
      expect(find.textContaining('as fontes não somam a ele'), findsOneWidget);
    });

    testWidgets('Evolução: setas mudam o ponto e Enter vai ao turno', (
      tester,
    ) async {
      final t = feed([
        assistant(40000, id: 'a'),
        result(),
        assistant(80000, id: 'b'),
        result(),
        assistant(120000, id: 'c'),
        result(),
      ]);
      ContextReading? jumped;
      await tester.pumpWidget(
        host(ContextEvolution(snapshot: t.snapshot, onJump: (r) => jumped = r)),
      );
      expect(find.text('Turno 3 · 120 mil'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('context-evolution-chart')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(find.text('Turno 1 · 40 mil'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(jumped!.turn, 1);
      expect(jumped!.tokens, 40000);
    });

    test('antes/depois só com duas leituras válidas (R6)', () {
      final pending = feed([assistant(171000), result(), boundary()]);
      expect(
        markerLines(pending.snapshot).single,
        contains('aguardando medição'),
      );
      final both = feed([
        assistant(171000),
        result(),
        boundary(),
        assistant(46000, id: 'z'),
      ]);
      expect(markerLines(both.snapshot).single, contains('171 mil → 46 mil'));
    });

    test('um ponto por turno, sem interpolar a compactação', () {
      final t = feed([
        assistant(40000, id: 'a'),
        assistant(42000, id: 'b'),
        result(),
        assistant(171000, id: 'c'),
        boundary(),
        assistant(46000, id: 'd'),
        result(),
      ]);
      expect(contextPoints(t.snapshot).map((p) => p.reading.tokens), [
        42000,
        171000,
        46000,
      ]);
    });
  });
}
