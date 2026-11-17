import 'package:flutter_test/flutter_test.dart';
import 'package:promptorium/core/providers/agent_provider.dart';
import 'package:promptorium/features/prompt/compare/compare_run.dart';
import 'package:promptorium/features/prompt/compare/compare_weight.dart';

void main() {
  final resets = DateTime.utc(2026, 11, 17, 14);

  group('compareWeights (R8)', () {
    test('splits the rise of the window and of the week by the share of '
        'the cost', () {
      final w = compareWeights(
        costs: {'A': 0.10, 'B': 0.40},
        before: UsageReading(five: 0.38, week: 0.61, fiveResetsAt: resets),
        after: UsageReading(five: 0.48, week: 0.63, fiveResetsAt: resets),
      );
      expect(w.measured, isTrue);
      expect(w.weights['A']!.five, closeTo(0.02, 1e-9));
      expect(w.weights['B']!.five, closeTo(0.08, 1e-9));
      expect(w.weights['A']!.week, closeTo(0.004, 1e-9));
      expect(w.weights['B']!.week, closeTo(0.016, 1e-9));
    });

    test('without cost, the rise is split in half', () {
      final w = compareWeights(
        costs: {'A': 0, 'B': 0},
        before: const UsageReading(five: 0.10, week: 0.20),
        after: const UsageReading(five: 0.12, week: 0.20),
      );
      expect(w.weights['A']!.five, closeTo(0.01, 1e-9));
      expect(w.weights['B']!.five, closeTo(0.01, 1e-9));
    });

    test('without the two readings, falls back to the Atividades rule on '
        'the last one', () {
      final w = compareWeights(
        costs: {'A': 0.10, 'B': 0.30},
        before: null,
        after: null,
        last: const UsageReading(five: 0.40, week: 0.60),
        windowCosts: {'session:x': 0.60},
      );
      expect(w.measured, isFalse);
      // share of the cost of the window (0,10 of 1,00) × use of the window.
      expect(w.weights['A']!.five, closeTo(0.04, 1e-9));
      expect(w.weights['B']!.five, closeTo(0.12, 1e-9));
      expect(w.weights['B']!.week, closeTo(0.18, 1e-9));
    });

    test('a window that renewed in between also falls back', () {
      final w = compareWeights(
        costs: {'A': 0.10, 'B': 0.10},
        before: UsageReading(five: 0.90, week: 0.5, fiveResetsAt: resets),
        after: UsageReading(
          five: 0.02,
          week: 0.5,
          fiveResetsAt: resets.add(const Duration(hours: 5)),
        ),
        last: const UsageReading(five: 0.02, week: 0.5),
      );
      expect(w.measured, isFalse);
      expect(w.weights['A']!.five, closeTo(0.01, 1e-9));
    });

    test('no reading at all: no weight', () {
      final w = compareWeights(costs: {'A': 0.1, 'B': 0.2});
      expect(w.weights, isEmpty);
    });
  });

  group('labels (R7, R15)', () {
    test('time, tokens, calls and weight, never US\$', () {
      expect(compareDuration(38000), '38 s');
      expect(compareDuration(112000), '1 min 52 s');
      expect(compareDuration(120000), '2 min');
      expect(compareDurationSpoken(112000), '1 minuto e 52 segundos');
      expect(compareClock(const Duration(seconds: 64)), '1:04');
      expect(compareTokens(950), '950');
      expect(compareTokens(14200), '14,2 mil');
      expect(
        compareTokensLine(
          const CompareMetrics(tokensIn: 14200, tokensOut: 1100),
        ),
        '14,2 mil → 1,1 mil',
      );
      expect(
        compareCalls({'Read': 9, 'Grep': 1, 'Glob': 1}),
        '9 leituras · 2 buscas',
      );
      expect(compareCalls({'Read': 1, 'Bash': 1}), '1 leitura · 1 outra');
      expect(compareCalls({}), 'nenhuma');
      expect(compareWeightLabel(0.012), '≈ 1,2%');
      expect(compareWeightSpoken(0.012), 'cerca de 1,2 por cento');
    });

    test('compareRatio: the heavier side over the lighter', () {
      const a = CompareSide(
        letter: 'A',
        model: 'sonnet',
        mode: PromptMode.ask,
        metrics: CompareMetrics(durationMs: 38000, costUsd: 0.1),
        weight: (five: 0.012, week: 0.002),
      );
      const b = CompareSide(
        letter: 'B',
        model: 'opus',
        mode: PromptMode.ask,
        metrics: CompareMetrics(durationMs: 112000, costUsd: 0.5),
        weight: (five: 0.0576, week: 0.009),
      );
      final r = compareRatio(a, b);
      expect(r.weight, 'B pesou 4,8× o A');
      expect(r.time, 'B levou 2,9× o tempo');
      // Without weights, the cost is the proportion.
      final r2 = compareRatio(
        a.copyWith(clearWeight: true),
        b.copyWith(clearWeight: true),
      );
      expect(r2.weight, 'B pesou 5,0× o A');
      // The order of the arguments does not matter.
      expect(compareRatio(b, a).time, 'B levou 2,9× o tempo');
    });
  });

  group('sides (R1–R3, P8)', () {
    test('B is the other model in the same mode; Editar becomes Perguntar', () {
      expect(defaultCompareSides('sonnet', PromptMode.plan), (
        (model: 'sonnet', mode: PromptMode.plan),
        (model: 'opus', mode: PromptMode.plan),
      ));
      expect(defaultCompareSides('opus', PromptMode.ask).$2.model, 'sonnet');
      expect(defaultCompareSides('haiku', PromptMode.ask).$2.model, 'sonnet');
      expect(defaultCompareSides('inherit', PromptMode.edit), (
        (model: 'sonnet', mode: PromptMode.ask),
        (model: 'opus', mode: PromptMode.ask),
      ));
    });

    test('equal sides and Editar cannot be sent', () {
      const ask = (model: 'sonnet', mode: PromptMode.ask);
      expect(compareSidesProblem(ask, ask), compareSameSidesMessage);
      expect(
        compareSidesProblem(ask, (model: 'opus', mode: PromptMode.edit)),
        compareEditHint,
      );
      expect(
        compareSidesProblem(ask, (model: 'sonnet', mode: PromptMode.plan)),
        isNull,
      );
    });

    test('the last pair round-trips; an invalid one is ignored', () {
      const a = (model: 'sonnet', mode: PromptMode.plan);
      const b = (model: 'sonnet', mode: PromptMode.ask);
      expect(decodeCompareSides(encodeCompareSides(a, b)), (a, b));
      expect(decodeCompareSides(encodeCompareSides(a, a)), isNull);
      expect(decodeCompareSides('x'), isNull);
    });

    test('CompareRun round-trips through its JSON', () {
      final run = CompareRun(
        conversationId: 1,
        prompt: 'por quê?',
        at: DateTime(2026, 11, 17, 10, 6),
        sides: const [
          CompareSide(
            letter: 'A',
            model: 'sonnet',
            mode: PromptMode.ask,
            sessionId: 's-a',
            started: true,
            state: CompareSideState.done,
            metrics: CompareMetrics(durationMs: 38000, tools: {'Read': 2}),
            weight: (five: 0.012, week: 0.002),
            events: ['{"type":"result"}'],
          ),
          CompareSide(
            letter: 'B',
            model: 'opus',
            mode: PromptMode.plan,
            plan: '1. x',
            state: CompareSideState.planReady,
          ),
        ],
        originalSessionId: 'orig',
        originalModel: 'sonnet',
        originalMode: PromptMode.ask,
        before: const UsageReading(five: 0.38, week: 0.61),
      );
      final back = CompareRun.fromJson(run.toJson(), conversationId: 1)!;
      expect(back.prompt, 'por quê?');
      expect(back.a.metrics!.tools, {'Read': 2});
      expect(back.a.weight, (five: 0.012, week: 0.002));
      expect(back.a.events, ['{"type":"result"}']);
      expect(back.b.mode, PromptMode.plan);
      expect(back.b.plan, '1. x');
      expect(back.b.state, CompareSideState.planReady);
      expect(back.originalSessionId, 'orig');
      expect(back.before!.five, 0.38);
      expect(run.toJson().toString(), isNot(contains('US\$')));
    });
  });
}
